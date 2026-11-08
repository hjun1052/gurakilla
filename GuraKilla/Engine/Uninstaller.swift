import Foundation

struct RemovalItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case installLocation = "Install location", launchdPlist = "Launchd plist", receiptFile = "Package file"
        case extraFile = "Installed file", receipt = "Package receipt", certificate = "Trusted certificate"
    }
    let path: String          // filesystem path, receipt ID, or certificate description
    let kind: Kind
    var certificate: InstalledCertificate? = nil
    /// Another detected product also claims this item.
    var sharedWith: [String] = []
    var requiresAdmin: Bool
    var id: String { kind.rawValue + ":" + path }
}

struct ExcludedItem: Identifiable, Hashable, Sendable {
    let path: String
    let reason: String
    var id: String { path }
}

struct RemovalPlan: Sendable {
    let product: DetectedProduct
    var items: [RemovalItem]
    var excluded: [ExcludedItem]
    /// Items selected by default: everything not shared with another product.
    var defaultSelection: Set<String> { Set(items.filter { $0.sharedWith.isEmpty }.map(\.id)) }
}

/// Result of running the parts that need no elevation; `privilegedLines`
/// still have to be authorized by the user.
struct RemovalExecution: Sendable {
    var log: [String] = []
    var privilegedLines: [String] = []
    var completed: [ChangeRecord] = []
    var pendingPrivileged: [ChangeRecord] = []
}

enum Uninstaller {
    /// Reasons shown for items left out of a plan. English here (CLI); the UI looks them up in Localizable.
    static let kextReason = "Kernel extension — use the vendor uninstaller. GuraKilla never removes kernel extensions."
    static let systemExtensionReason = "System extension — only the app that installed it can remove it. Use the vendor uninstaller, or System Settings › General › Login Items & Extensions."
    static let protectedReason = "Protected system location"
    static let excludedReasons = [kextReason, systemExtensionReason, protectedReason]

    /// Generic folders where a package drops individual items that belong to it.
    /// Items are taken one level below these, never the folder itself.
    static let fileContainers = [
        "/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools",
        "/Library/Frameworks", "/Library/Internet Plug-Ins",
        "/Library/Google/Chrome/NativeMessagingHosts",
        "/Library/Application Support/Google/Chrome/NativeMessagingHosts",
        "/Library/Application Support/Mozilla/NativeMessagingHosts",
    ]

    static let protectedPrefixes = [
        "/System", "/bin", "/sbin", "/usr", "/private/var/db", "/private/etc", "/etc", "/var",
        "/Library/Apple", "/Library/Extensions", "/Library/SystemExtensions", "/Library/Security",
        "/Library/Keychains", "/Library/StagedExtensions", "/Applications/Utilities",
    ]

    static let neverRemove = Set([
        "/", "/Applications", "/Library", "/Users", "/Library/Application Support",
        "/Library/Google", "/Library/Google/Chrome", "/Library/Application Support/Google",
        "/Library/Application Support/Mozilla",
    ] + fileContainers)

    /// Last line of defence before anything is moved.
    static func isSafeToRemove(_ raw: String) -> Bool {
        guard raw.hasPrefix("/"), !raw.contains("/../"), !raw.hasSuffix("/..") else { return false }
        let path = (raw as NSString).standardizingPath
        if neverRemove.contains(path) { return false }
        if path == NSHomeDirectory() || Paths.isUnder(NSHomeDirectory(), path) { return false }
        if protectedPrefixes.contains(where: { Paths.isUnder(path, $0) }) { return false }
        if path.hasSuffix(".kext") || path.contains(".kext/") { return false }
        return path.split(separator: "/").count >= 2 // at least /Applications/Something
    }

    /// Absolute paths a product's receipts installed, resolved against the receipt location.
    private static let receiptLock = NSLock()
    nonisolated(unsafe) private static var receiptCache: [String: [String]] = [:]

    static func receiptFiles(_ receipt: String) -> [String] {
        receiptLock.lock()
        if let hit = receiptCache[receipt] { receiptLock.unlock(); return hit }
        receiptLock.unlock()
        let files = readReceiptFiles(receipt)
        receiptLock.lock(); receiptCache[receipt] = files; receiptLock.unlock()
        return files
    }

    private static func readReceiptFiles(_ receipt: String) -> [String] {
        let info = Shell.run("/usr/sbin/pkgutil", ["--pkg-info", receipt]).stdout
        var volume = "/", location = ""
        for line in info.split(separator: "\n") {
            if line.hasPrefix("volume: ") { volume = String(line.dropFirst(8)) }
            if line.hasPrefix("location: ") { location = String(line.dropFirst(10)) }
        }
        let base = ((volume as NSString).appendingPathComponent(location) as NSString).standardizingPath
        return Shell.run("/usr/sbin/pkgutil", ["--files", receipt]).stdout
            .split(separator: "\n")
            .map { ((base as NSString).appendingPathComponent(String($0)) as NSString).standardizingPath }
    }

    /// Item one level below a generic container, e.g. `/Library/LaunchAgents/x.plist`.
    static func containerItem(for path: String) -> String? {
        for c in fileContainers.sorted(by: { $0.count > $1.count }) where path.hasPrefix(c + "/") {
            let rest = path.dropFirst(c.count + 1)
            guard let first = rest.split(separator: "/").first else { return nil }
            return c + "/" + first
        }
        return nil
    }

    /// Paths a product exclusively claims (install roots, launchd plists, receipt items).
    struct Claims { var paths = Set<String>(); var kexts = Set<String>(); var receiptFiles: [String] = [] }

    /// Paths a product claims (install roots, launchd plists, receipt items),
    /// plus every raw file its receipts installed (used to detect sharing).
    static func claims(_ p: DetectedProduct) -> Claims {
        var c = Claims()
        c.paths = Set(p.installPaths).union(p.launchJobs.map(\.plistPath)).union(p.extraPaths)
        for r in p.receipts {
            for f in receiptFiles(r) {
                if let k = f.range(of: ".kext") { c.kexts.insert(String(f[..<k.upperBound])); continue }
                c.receiptFiles.append(f)
                if let item = containerItem(for: f) { c.paths.insert(item) }
            }
        }
        return c
    }

    /// Names of other products that also use `path`: they claim it, install files into it, or live
    /// inside it. A path inside another product's folder is still ours when our own receipt installed
    /// it (CrossWeb EX puts .../iniLINE/CrossEX/crosswebex inside CrossEX's folder).
    static func sharedWith(_ path: String, ourReceiptFiles: [String],
                           others: [(name: String, claims: Claims, roots: [String])]) -> [String] {
        let ourReceiptInstalledIt = ourReceiptFiles.contains { Paths.isUnder($0, path) }
        return others.filter { other in
            other.claims.paths.contains(path)
            || other.roots.contains { Paths.isUnder($0, path) || (!ourReceiptInstalledIt && Paths.isUnder(path, $0)) }
            || other.claims.receiptFiles.contains { Paths.isUnder($0, path) }
        }.map(\.name)
    }

    static func plan(for product: DetectedProduct, among all: [DetectedProduct]) -> RemovalPlan {
        let fm = FileManager.default
        let mine = claims(product)
        let others = all.filter { $0.id != product.id }.map { (name: $0.definition.name, claims: claims($0), roots: $0.definition.expandedInstallPaths) }

        var items: [RemovalItem] = []
        let kexts = mine.kexts.filter { fm.fileExists(atPath: $0) }.union(product.kernelExtensions)
        var excluded: [ExcludedItem] = kexts.sorted().map {
            ExcludedItem(path: $0, reason: kextReason)
        }
        excluded += product.systemExtensions.map {
            ExcludedItem(path: "\($0.bundleID) (\($0.teamID)) — \($0.state)",
                         reason: systemExtensionReason)
        }

        for path in mine.paths.sorted() {
            guard fm.fileExists(atPath: path) || isSymlink(path) else { continue }
            guard isSafeToRemove(path) else {
                excluded.append(ExcludedItem(path: path, reason: protectedReason))
                continue
            }
            // Skip items nested inside another item we already remove.
            if mine.paths.contains(where: { $0 != path && Paths.isUnder(path, $0) }) { continue }
            let shared = sharedWith(path, ourReceiptFiles: mine.receiptFiles, others: others)
            let kind: RemovalItem.Kind = product.launchJobs.contains { $0.plistPath == path } ? .launchdPlist
                : product.installPaths.contains(path) ? .installLocation
                : product.extraPaths.contains(path) ? .extraFile : .receiptFile
            items.append(RemovalItem(path: path, kind: kind, sharedWith: shared, requiresAdmin: !canMoveWithoutAdmin(path)))
        }
        for r in product.receipts {
            items.append(RemovalItem(path: r, kind: .receipt, requiresAdmin: true))
        }
        // Certificates: shared only if another product's CA list also names it.
        for c in product.certificates {
            let shared = all.filter { $0.id != product.id && $0.certificates.contains(c) }.map(\.definition.name)
            let where_ = c.inSystemKeychain ? "System keychain" : "login keychain"
            items.append(RemovalItem(path: "\(c.commonName) — \(where_), \(c.trustLabelEnglish.lowercased())", kind: .certificate,
                                     certificate: c, sharedWith: shared, requiresAdmin: c.inSystemKeychain || c.adminTrusted))
        }
        return RemovalPlan(product: product, items: items, excluded: excluded)
    }

    static func isSymlink(_ path: String) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
    }

    static func canMoveWithoutAdmin(_ path: String) -> Bool {
        let parent = (path as NSString).deletingLastPathComponent
        return FileManager.default.isWritableFile(atPath: parent)
    }

    static func trashBase(date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return Paths.expand("~/.Trash/GuraKilla \(f.string(from: date))")
    }

    /// Stops jobs and processes, moves user-writable items to the Trash, and
    /// returns root-only steps as script lines for the user to authorize.
    static func performUnprivileged(_ plan: RemovalPlan, selected: Set<String>) -> RemovalExecution {
        var ex = RemovalExecution()
        let product = plan.product
        let name = product.definition.name

        // 1. Unload launchd jobs (prevents KeepAlive respawn while removing).
        for job in product.launchJobs where job.isLoaded {
            let cmd = StartupManager.unloadCommand(job)
            if !job.domain.requiresAdmin, Shell.run(cmd[0], Array(cmd.dropFirst())).ok {
                ex.log.append("Unloaded \(job.serviceTarget)")
                AuditLog.record("UNLOAD", job.serviceTarget)
            } else {
                ex.privilegedLines.append(Shell.commandLine(cmd))
            }
        }

        // 2. Terminate remaining processes.
        let term = ProcessController.terminate(product.processes)
        ex.log += term.signalled.map { "Sent SIGTERM to \($0.name) (\($0.pid))" }
        term.signalled.forEach { AuditLog.record("TERMINATE", "\(name): \($0.path) pid \($0.pid)") }
        ex.privilegedLines += ProcessController.privilegedSignalLines(term.needsPrivilege, signal: "TERM")

        // 3. Move files to the Trash (restorable from Restore Settings or Finder).
        let base = trashBase()
        let chosen = plan.items.filter { selected.contains($0.id) }
        for item in chosen where item.kind != .receipt && item.kind != .certificate {
            guard isSafeToRemove(item.path) else { ex.log.append("Refused protected path \(item.path)"); continue }
            let dest = base + item.path
            let record = ChangeRecord(product: name, kind: .moved(original: item.path, destination: dest))
            if !item.requiresAdmin {
                do {
                    try FileManager.default.createDirectory(atPath: (dest as NSString).deletingLastPathComponent,
                                                            withIntermediateDirectories: true)
                    try FileManager.default.moveItem(atPath: item.path, toPath: dest)
                    ex.completed.append(record)
                    ex.log.append("Moved to Trash: \(item.path)")
                    AuditLog.record("MOVE_TO_TRASH", "\(item.path) -> \(dest)")
                    continue
                } catch {
                    // Fall through to the privileged path.
                }
            }
            let parent = (dest as NSString).deletingLastPathComponent
            ex.privilegedLines.append("/bin/mkdir -p \(Shell.quote(parent)) && /bin/mv \(Shell.quote(item.path)) \(Shell.quote(dest))")
            ex.pendingPrivileged.append(record)
        }
        if ex.pendingPrivileged.contains(where: { if case .moved = $0.kind { return true }; return false }) {
            ex.privilegedLines.append("/usr/sbin/chown -R \(getuid()):\(getgid()) \(Shell.quote(base))")
        }

        // 4. Untrust and delete certificates. Each is backed up first so it can be restored.
        for item in chosen where item.kind == .certificate {
            guard let c = item.certificate else { continue }
            guard let backup = try? CertificateInspector.backup(c) else {
                ex.log.append("Could not back up certificate \(c.commonName); left untouched.")
                continue
            }
            let record = ChangeRecord(product: name, kind: .certificateRemoved(
                sha256: c.sha256, commonName: c.commonName, keychain: c.keychain, backupPath: backup,
                wasAdminTrusted: c.adminTrusted, wasUserTrusted: c.userTrusted, selfSigned: c.isSelfSigned))
            let lines = CertificateInspector.removalLines(c, backupPath: backup)
            let userOK = lines.user.allSatisfy { Shell.run($0[0], Array($0.dropFirst())).ok }
            if lines.privileged.isEmpty {
                if userOK {
                    ex.completed.append(record)
                    ex.log.append("Removed certificate \(c.commonName)")
                    AuditLog.record("CERT_REMOVE", "\(c.commonName) sha256=\(c.sha256) backup=\(backup)")
                } else {
                    ex.log.append("Could not remove certificate \(c.commonName) from the login keychain.")
                }
            } else {
                ex.privilegedLines += lines.privileged
                ex.pendingPrivileged.append(record)
            }
        }

        // 5. Forget package receipts (root only, not reversible).
        for item in chosen where item.kind == .receipt {
            ex.privilegedLines.append("/usr/sbin/pkgutil --forget \(Shell.quote(item.path))")
            ex.pendingPrivileged.append(ChangeRecord(product: name, kind: .receiptForgotten(id: item.path)))
        }
        return ex
    }

    /// Moves a trashed item back. Returns a root script line if needed.
    static func restoreMove(original: String, destination: String) -> (ok: Bool, privilegedLine: String?) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: destination) || isSymlink(destination) else { return (false, nil) }
        guard !fm.fileExists(atPath: original) else { return (false, nil) }
        let parent = (original as NSString).deletingLastPathComponent
        if fm.isWritableFile(atPath: parent) || !fm.fileExists(atPath: parent) && fm.isWritableFile(atPath: (parent as NSString).deletingLastPathComponent) {
            do {
                try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
                try fm.moveItem(atPath: destination, toPath: original)
                return (true, nil)
            } catch {}
        }
        // Restore root ownership for system locations.
        let line = "/bin/mkdir -p \(Shell.quote(parent)) && /bin/mv \(Shell.quote(destination)) \(Shell.quote(original)) && /usr/sbin/chown -R root:wheel \(Shell.quote(original))"
        return (false, line)
    }
}

import Foundation

/// Machine-readable detection output for `GuraKilla --scan-json`.
/// Used by research/tools/inventory.py so baseline and cleanup snapshots
/// record exactly what the app itself would show.
enum ScanReport {
    static func json(_ products: [DetectedProduct]) -> String {
        let rows: [[String: Any]] = products.map { p in
            [
                "id": p.id,
                "name": p.definition.name,
                "publisher": p.definition.publisher,
                "installPaths": p.installPaths,
                "bundles": p.bundles.map { b -> [String: Any] in
                    ["path": b.path, "bundleID": b.bundleID ?? "", "version": b.version ?? "", "signing": b.signing.label]
                },
                "launchJobs": p.launchJobs.map { j -> [String: Any] in
                    ["target": j.serviceTarget, "plist": j.plistPath, "loaded": j.isLoaded,
                     "disabled": j.isDisabled, "autoStarts": j.autoStarts, "keepAlive": j.keepAlive,
                     "pid": j.pid.map { Int($0) } ?? NSNull()]
                },
                "receipts": p.receipts,
                "processes": p.processes.map { q -> [String: Any] in
                    ["pid": Int(q.pid), "path": q.path, "owner": q.owner, "cpu": q.cpu, "rssKB": q.rssKB]
                },
                "uninstallers": p.uninstallers,
                "certificates": p.certificates.map { c -> [String: Any] in
                    ["commonName": c.commonName, "subject": c.subject, "issuer": c.issuer, "sha256": c.sha256,
                     "keychain": c.keychain, "adminTrusted": c.adminTrusted, "userTrusted": c.userTrusted]
                },
                "systemExtensions": p.systemExtensions.map { ["bundleID": $0.bundleID, "teamID": $0.teamID, "state": $0.state] },
                "kernelExtensions": p.kernelExtensions,
                "extraPaths": p.extraPaths,
            ]
        }
        let data = (try? JSONSerialization.data(withJSONObject: ["products": rows], options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Handles `--scan-json` before any UI is created. Read-only.
    static func runIfRequested() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--remove"), i + 1 < args.count {
            exit(removeCommand(args[i + 1], apply: args.contains("--yes"), useSudo: args.contains("--sudo")))
        }
        guard args.contains("--scan-json") else { return }
        print(json(DetectionEngine.scan(ProductRegistry.load())))
        exit(0)
    }

    /// `--remove <id>`: prints the same plan the Uninstall sheet shows (default
    /// selection). Dry run unless `--yes`. Admin steps go through the macOS
    /// password dialog, or `sudo -n` when `--sudo` is given (fails, never
    /// prompts, if sudo is not already authorized).
    static func removeCommand(_ id: String, apply: Bool, useSudo: Bool) -> Int32 {
        let all = DetectionEngine.scan(ProductRegistry.load())
        guard let product = all.first(where: { $0.id == id }) else {
            print("\(id): not detected on this Mac"); return 2
        }
        let plan = Uninstaller.plan(for: product, among: all)
        let selected = plan.defaultSelection
        print("Removal plan for \(product.definition.name):")
        for item in plan.items {
            let shared = item.sharedWith.isEmpty ? "" : "  (shared with \(item.sharedWith.joined(separator: ", ")); skipped)"
            print("  [\(selected.contains(item.id) ? "x" : " ")] \(item.kind.rawValue): \(item.path)\(item.requiresAdmin ? "  (admin)" : "")\(shared)")
        }
        for ex in plan.excluded { print("  [-] not touched: \(ex.path) (\(ex.reason))") }
        guard apply else { print("Dry run. Add --yes to remove the checked items."); return 0 }

        let name = product.definition.name
        AuditLog.record("REMOVAL_START", "\(name): \(selected.count) item(s) [cli]")
        let ex = Uninstaller.performUnprivileged(plan, selected: selected)
        ex.log.forEach { print($0) }
        var changes = ChangeStore.load() + ex.completed
        var failure: String?
        if !ex.privilegedLines.isEmpty {
            print("Administrator steps:")
            ex.privilegedLines.forEach { print("  " + $0) }
            let script = PrivilegedRunner.script(ex.privilegedLines)
            let outcome: PrivilegedOutcome
            if useSudo {
                let r = Shell.run("/usr/bin/sudo", ["-n", "/bin/sh", "-c", script])
                outcome = r.ok ? .success(r.stdout) : .failed(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                outcome = PrivilegedRunner.run(script: script, prompt: "GuraKilla wants to remove \(name).")
            }
            switch outcome {
            case .success:
                changes += ex.pendingPrivileged
                ex.pendingPrivileged.forEach { AuditLog.record("REMOVE", $0.summary) }
            case .cancelled:
                failure = "administrator steps cancelled"
            case .failed(let msg):
                failure = msg.isEmpty ? "administrator steps failed" : msg
                changes += ex.pendingPrivileged.filter {
                    if case let .moved(_, dest) = $0.kind { return FileManager.default.fileExists(atPath: dest) }
                    return false
                }
            }
        }
        ChangeStore.save(changes)
        AuditLog.record("REMOVAL_END", "\(name)\(failure.map { ": \($0)" } ?? "")")
        print(failure.map { "Partly removed: \($0)" } ?? "Removed. Restore from the app's Restore Settings.")
        return failure == nil ? 0 : 1
    }
}

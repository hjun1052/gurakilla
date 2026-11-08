import Foundation
import AppKit

struct BundleInfo: Identifiable, Hashable, Sendable {
    let path: String
    let bundleID: String?
    let version: String?
    let signing: SigningInfo
    var id: String { path }
    var name: String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
}

enum StartupState: Hashable, Sendable {
    case none          // no launchd job found
    case enabled(Int)  // n jobs will auto-start
    case disabled      // jobs exist, all disabled
}

struct DetectedProduct: Identifiable, Hashable, Sendable {
    let definition: ProductDefinition
    var installPaths: [String]
    var bundles: [BundleInfo]
    var launchJobs: [LaunchJob]
    var receipts: [String]
    var processes: [ProcessSnapshot]
    var uninstallers: [String]
    var certificates: [InstalledCertificate] = []
    var systemExtensions: [SystemExtensionInfo] = []
    var kernelExtensions: [String] = []
    var extraPaths: [String] = []

    var id: String { definition.id }
    var isRunning: Bool { !processes.isEmpty }
    var totalCPU: Double { processes.reduce(0) { $0 + $1.cpu } }
    var totalMemoryKB: Int { processes.reduce(0) { $0 + $1.rssKB } }
    var trustedCertificates: [InstalledCertificate] { certificates.filter(\.isTrusted) }

    var startupState: StartupState {
        if launchJobs.isEmpty { return .none }
        let n = launchJobs.filter(\.autoStarts).count
        return n > 0 ? .enabled(n) : .disabled
    }

    /// The software itself is gone; only receipts, certificates or other traces remain.
    var isLeftover: Bool {
        installPaths.isEmpty && bundles.isEmpty && launchJobs.isEmpty && processes.isEmpty
    }

    var observedTeams: [String] {
        Array(Set(bundles.compactMap { $0.signing.valid ? $0.signing.teamID : nil })).sorted()
    }
}

/// Everything a scan reads from the system. Injectable so detection rules can
/// be regression-tested against recorded evidence without touching the Mac.
struct ScanInputs {
    var receipts: [String]
    var jobs: [LaunchJob]
    var processes: [ProcessSnapshot]
    var certificates: [InstalledCertificate]
    var systemExtensions: [SystemExtensionInfo]
    var fileExists: (String) -> Bool
    var jobStatus: (LaunchJob) -> LaunchJob
    var findBundles: (ProductDefinition, [String]) -> [BundleInfo]

    static func live() -> ScanInputs {
        let overrides = LaunchdInspector.disabledOverrides()
        return ScanInputs(
            receipts: Shell.run("/usr/sbin/pkgutil", ["--pkgs"]).stdout.split(separator: "\n").map(String.init),
            jobs: LaunchdInspector.definitions(),
            processes: ProcessInspector.snapshot(),
            certificates: CertificateInspector.all(),
            systemExtensions: CertificateInspector.systemExtensions(),
            fileExists: { FileManager.default.fileExists(atPath: $0) || Uninstaller.isSymlink($0) },
            jobStatus: { LaunchdInspector.withStatus($0, overrides: overrides) },
            findBundles: DetectionEngine.findBundles)
    }
}

enum DetectionEngine {
    /// True only for a directory that can be listed and holds nothing but .DS_Store.
    static func isEmptyDirectory(_ path: String) -> Bool {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: path) else { return false }
        return items.allSatisfy { $0 == ".DS_Store" }
    }

    /// Full scan: filesystem, launchd, receipts, processes, certificates and extensions.
    static func scan(_ definitions: [ProductDefinition], inputs: ScanInputs? = nil) -> [DetectedProduct] {
        let inputs = inputs ?? .live()
        var found: [DetectedProduct] = []
        for def in definitions {
            let roots = def.expandedInstallPaths
            // An empty folder is not an installation (e.g. iniLINE/CrossEX after CrossWeb EX is removed).
            let existing = roots.filter { inputs.fileExists($0) && !Self.isEmptyDirectory($0) }
            let jobs = inputs.jobs
                .filter { job in
                    def.launchdLabels.contains(job.label)
                    || (job.executable.map { Paths.isUnder($0, anyOf: roots) } ?? false)
                }
                .map(inputs.jobStatus)
            let recs = inputs.receipts.filter(def.matchesReceipt)
            let bundles = inputs.findBundles(def, existing)
            let certs = inputs.certificates.filter { def.matchesCertificate(subject: $0.subject, issuer: $0.issuer) }
            let sysext = inputs.systemExtensions.filter {
                def.systemExtensionIDs.contains($0.bundleID) && (def.teamIDs.isEmpty || def.teamIDs.contains($0.teamID))
            }
            let kexts = def.kernelExtensions.map(Paths.expand).filter(inputs.fileExists)
            let extras = def.expandedExtraPaths.filter(inputs.fileExists)

            guard !existing.isEmpty || !jobs.isEmpty || !recs.isEmpty || !bundles.isEmpty
                    || !certs.isEmpty || !sysext.isEmpty || !kexts.isEmpty || !extras.isEmpty else { continue }

            found.append(DetectedProduct(
                definition: def, installPaths: existing, bundles: bundles, launchJobs: jobs,
                receipts: recs,
                processes: matchProcesses(inputs.processes, definition: def, jobs: jobs, trustJobPIDs: true),
                uninstallers: def.expandedUninstallers.filter(inputs.fileExists),
                certificates: certs, systemExtensions: sysext, kernelExtensions: kexts, extraPaths: extras))
        }
        return found
    }

    /// Cheap periodic refresh of CPU / memory / running state only.
    /// Job PIDs from the last full scan may be stale, so they are not trusted here.
    static func refreshProcesses(_ products: [DetectedProduct]) -> [DetectedProduct] {
        let processes = ProcessInspector.snapshot()
        return products.map { p in
            var p = p
            p.processes = matchProcesses(processes, definition: p.definition, jobs: p.launchJobs, trustJobPIDs: false)
            return p
        }
    }

    /// A process belongs to a product only when it is linked by a verified
    /// identifier (its launchd job, a launchd program path, or an exclusive
    /// install location) AND, if it is code-signed, the signing team matches.
    static func matchProcesses(_ processes: [ProcessSnapshot], definition def: ProductDefinition,
                               jobs: [LaunchJob], trustJobPIDs: Bool) -> [ProcessSnapshot] {
        let roots = def.expandedInstallPaths
        let jobPIDs = trustJobPIDs ? Set(jobs.compactMap(\.pid)) : []
        let jobExecutables = Set(jobs.flatMap { [$0.program, $0.firstArgument].compactMap { $0 } })
        return processes.filter { p in
            let viaJob = jobPIDs.contains(p.pid)
            let linked = viaJob || jobExecutables.contains(p.path) || Paths.isUnder(p.path, anyOf: roots)
            guard linked else { return false }
            return signatureAllows(CodeSigning.info(path: p.path), definition: def, launchdVerified: viaJob)
        }
    }

    static func signatureAllows(_ sig: SigningInfo, definition def: ProductDefinition, launchdVerified: Bool) -> Bool {
        guard !def.teamIDs.isEmpty, sig.signed else { return true } // unsigned: path/launchd link is the evidence
        if let team = sig.teamID, sig.valid { return def.teamIDs.contains(team) }
        return launchdVerified // broken/teamless signature: only trust launchd's own PID
    }

    static func findBundles(_ def: ProductDefinition, existingRoots: [String]) -> [BundleInfo] {
        var paths = Set<String>()
        for id in def.bundleIDs {
            for url in NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id)
            where !url.path.contains("/.Trash/") {
                paths.insert(url.path)
            }
        }
        let fm = FileManager.default
        for root in existingRoots {
            if root.hasSuffix(".app") { paths.insert(root); continue }
            guard let e = fm.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil,
                                        options: [.skipsPackageDescendants, .skipsHiddenFiles]) else { continue }
            for case let url as URL in e {
                if e.level > 3 { e.skipDescendants(); continue }
                if url.pathExtension == "app" { paths.insert(url.path) }
            }
        }
        return paths.sorted().compactMap { path in
            let b = Bundle(path: path)
            let sig = CodeSigning.info(path: path)
            // Bundles found by ID must still be signed by the vendor when a team is known.
            if !Paths.isUnder(path, anyOf: existingRoots),
               !def.teamIDs.isEmpty, !(sig.teamID.map(def.teamIDs.contains) ?? false) { return nil }
            return BundleInfo(path: path, bundleID: b?.bundleIdentifier,
                              version: b?.infoDictionary?["CFBundleShortVersionString"] as? String,
                              signing: sig)
        }
    }
}

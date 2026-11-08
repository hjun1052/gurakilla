import Foundation
import AppKit
import Observation

/// A privileged script waiting for the user to review and approve it.
struct PendingAuthorization: Identifiable {
    let id = UUID()
    let title: String
    let explanation: String
    let script: String
    let onFinish: @MainActor (PrivilegedOutcome) -> Void
}

struct Notice: Identifiable {
    struct Action: Identifiable {
        let id = UUID()
        let title: String
        var destructive = false
        let run: @MainActor () -> Void
    }
    let id = UUID()
    let title: String
    let message: String
    var actions: [Action] = []
}

@MainActor
@Observable
final class AppModel {
    var products: [DetectedProduct] = []
    var selection = Set<String>()
    var isScanning = false
    var lastScan: Date?
    var changes: [ChangeRecord] = ChangeStore.load()

    var pendingAuthorization: PendingAuthorization?
    var notice: Notice?
    var showStartupManager = false
    var showRestore = false
    var showAuditLog = false
    var uninstallTarget: DetectedProduct?

    let definitions = ProductRegistry.load()
    private var refreshTask: Task<Void, Never>?

    var selectedProducts: [DetectedProduct] { products.filter { selection.contains($0.id) } }
    var runningCount: Int { products.filter(\.isRunning).count }
    var processCount: Int { products.reduce(0) { $0 + $1.processes.count } }
    var autoStartJobCount: Int { products.reduce(0) { $0 + $1.launchJobs.filter(\.autoStarts).count } }
    var totalCPU: Double { products.reduce(0) { $0 + $1.totalCPU } }
    var totalMemoryKB: Int { products.reduce(0) { $0 + $1.totalMemoryKB } }
    var trustedCertificateCount: Int { Set(products.flatMap { $0.trustedCertificates.map(\.id) }).count }
    var pendingRestores: [ChangeRecord] { changes.filter { $0.restoredAt == nil && $0.isReversible } }

    // MARK: Scanning

    func start() {
        guard refreshTask == nil else { return }
        Task { await scan() }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await self?.refreshProcesses()
            }
        }
    }

    func scan() async {
        isScanning = true
        let defs = definitions
        let result = await Task.detached { DetectionEngine.scan(defs) }.value
        products = result
        selection = selection.intersection(result.map(\.id))
        lastScan = Date()
        isScanning = false
    }

    private func refreshProcesses() async {
        guard !isScanning, !products.isEmpty else { return }
        let current = products
        let refreshed = await Task.detached { DetectionEngine.refreshProcesses(current) }.value
        // Only apply if no full scan replaced the list meanwhile.
        if products.map(\.id) == refreshed.map(\.id), !isScanning { products = refreshed }
    }

    // MARK: Authorization

    /// Shows the exact script, then (on approval) runs it through the macOS admin prompt.
    func authorize(title: String, explanation: String, lines: [String], onFinish: @escaping @MainActor (PrivilegedOutcome) -> Void) {
        pendingAuthorization = PendingAuthorization(
            title: title, explanation: explanation,
            script: PrivilegedRunner.script(lines), onFinish: onFinish)
    }

    func runPendingAuthorization() {
        guard let pending = pendingAuthorization else { return }
        pendingAuthorization = nil
        let prompt = "GuraKilla: \(pending.title)"
        AuditLog.record("AUTH_REQUEST", pending.title)
        Task {
            let outcome = await Task.detached { PrivilegedRunner.run(script: pending.script, prompt: prompt) }.value
            switch outcome {
            case .success: AuditLog.record("AUTH_OK", pending.title)
            case .cancelled: AuditLog.record("AUTH_CANCELLED", pending.title)
            case .failed(let e): AuditLog.record("AUTH_FAILED", "\(pending.title): \(e)")
            }
            pending.onFinish(outcome)
        }
    }

    func cancelPendingAuthorization() {
        guard let pending = pendingAuthorization else { return }
        pendingAuthorization = nil
        AuditLog.record("AUTH_DECLINED", pending.title)
        pending.onFinish(.cancelled)
    }

    // MARK: Quit

    func quitSelected() { quit(selectedProducts) }
    func quitAll() { quit(products) }

    func quit(_ targets: [DetectedProduct]) {
        let procs = targets.flatMap(\.processes)
        guard !procs.isEmpty else {
            notice = Notice(title: String(localized: "Nothing to quit"), message: String(localized: "None of the selected software is running."))
            return
        }
        let names = Dictionary(targets.flatMap { p in p.processes.map { ($0.pid, p.definition.name) } }, uniquingKeysWith: { a, _ in a })
        Task {
            let report = await Task.detached { ProcessController.terminate(procs) }.value
            for p in report.signalled { AuditLog.record("TERMINATE", "\(names[p.pid] ?? "?"): \(p.path) pid \(p.pid)") }
            if report.needsPrivilege.isEmpty {
                await finishQuit(procs)
            } else {
                let list = report.needsPrivilege.map { String(localized: "• \($0.name) (PID \($0.pid), owner \($0.owner))") }.joined(separator: "\n")
                authorize(title: String(localized: "Quit processes owned by another user"),
                          explanation: String(localized: "These processes run as another user (usually root) and can only be asked to quit with administrator rights:\n\(list)"),
                          lines: ProcessController.privilegedSignalLines(report.needsPrivilege, signal: "TERM")) { _ in
                    Task { await self.finishQuit(procs) }
                }
            }
        }
    }

    private func finishQuit(_ procs: [ProcessSnapshot]) async {
        let alive = await ProcessController.waitForExit(procs, timeout: 4)
        await scan()
        let ids = Set(procs.map(\.pid))
        let affected = products.filter { p in p.launchJobs.contains { $0.isLoaded } && !p.processes.isEmpty }
        let respawned = affected.filter { p in p.processes.contains { !ids.contains($0.pid) } }
        let keepAliveJobs = respawned.flatMap { p in p.launchJobs.filter { $0.isLoaded && $0.keepAlive } }

        var lines: [String] = []
        var actions: [Notice.Action] = []
        if !alive.isEmpty {
            let names = alive.map(\.name).joined(separator: ", ")
            lines.append(String(localized: "\(alive.count) process(es) did not respond to a graceful quit request: \(names)."))
            actions.append(.init(title: String(localized: "Force Quit"), destructive: true) { self.forceQuit(alive) })
        }
        if !keepAliveJobs.isEmpty {
            let names = respawned.map(\.definition.name).joined(separator: ", ")
            lines.append(String(localized: "launchd restarted \(names) because its job is configured to stay alive (KeepAlive). Quitting only stops the current instance.\n\nTo stop it until the next login, unload the launchd job. To stop it permanently, also disable auto-start in Manage Startup."))
            actions.append(.init(title: String(localized: "Unload Job Now")) { self.unload(keepAliveJobs) })
            actions.append(.init(title: String(localized: "Manage Startup…")) { self.showStartupManager = true })
        }
        if lines.isEmpty {
            notice = Notice(title: String(localized: "Quit complete"), message: String(localized: "\(procs.count) process(es) quit. Software set to start automatically will launch again at next login or restart."))
        } else {
            notice = Notice(title: String(localized: "Some software is still running"), message: lines.joined(separator: "\n\n"), actions: actions)
        }
    }

    func forceQuit(_ procs: [ProcessSnapshot]) {
        Task {
            let report = await Task.detached { ProcessController.forceKill(procs) }.value
            report.signalled.forEach { AuditLog.record("FORCE_QUIT", "\($0.path) pid \($0.pid)") }
            if report.needsPrivilege.isEmpty { await scan(); return }
            authorize(title: String(localized: "Force quit processes"),
                      explanation: String(localized: "Force quitting (SIGKILL) stops the process immediately without letting it save state. These processes belong to another user and need administrator rights."),
                      lines: ProcessController.privilegedSignalLines(report.needsPrivilege, signal: "KILL")) { _ in
                Task { await self.scan() }
            }
        }
    }

    // MARK: Launchd

    func unload(_ jobs: [LaunchJob]) {
        runLaunchctl(jobs.map { ($0, [StartupManager.unloadCommand($0)]) },
                     title: String(localized: "Unload launchd jobs"),
                     explanation: String(localized: "Unloading stops these jobs now. They will start again at next login or restart unless auto-start is disabled."),
                     auditAction: "UNLOAD") { _ in }
    }

    /// Applies auto-start changes. `changes` maps job id → desired auto-start state.
    func applyStartup(_ desired: [String: Bool], unloadNow: Bool) {
        let all = products.flatMap { p in p.launchJobs.map { (p, $0) } }
        var steps: [(LaunchJob, [[String]])] = []
        var newRecords: [String: ChangeRecord] = [:]
        for (product, job) in all {
            guard let want = desired[job.id], want != job.autoStarts else { continue }
            if want {
                steps.append((job, StartupManager.enableCommands(job, loadNow: true)))
            } else {
                steps.append((job, StartupManager.disableCommands(job, unloadNow: unloadNow)))
                newRecords[job.id] = ChangeRecord(product: product.definition.name, kind: .startupDisabled(
                    label: job.label, domain: job.domain, plistPath: job.plistPath,
                    wasDisabled: job.isDisabled, wasLoaded: job.isLoaded))
            }
        }
        guard !steps.isEmpty else { return }
        runLaunchctl(steps, title: String(localized: "Change automatic startup"),
                     explanation: String(localized: "launchd keeps its own enable/disable list; vendor files are not modified. Every change can be undone from Restore Settings."),
                     auditAction: "STARTUP") { succeeded in
            let recs = succeeded.compactMap { newRecords[$0] }
            if !recs.isEmpty { self.changes.append(contentsOf: recs); ChangeStore.save(self.changes) }
        }
    }

    /// Runs per-job launchctl commands: user-domain jobs directly, system-domain
    /// (or failed) ones in a single reviewed admin script. Reports succeeded job ids.
    private func runLaunchctl(_ steps: [(LaunchJob, [[String]])], title: String, explanation: String,
                              auditAction: String, completion: @escaping @MainActor ([String]) -> Void) {
        Task {
            let (done, escalate) = await Task.detached { () -> ([String], [(LaunchJob, [[String]])]) in
                var done: [String] = [], escalate: [(LaunchJob, [[String]])] = []
                for (job, cmds) in steps {
                    if job.domain.requiresAdmin { escalate.append((job, cmds)); continue }
                    let ok = cmds.allSatisfy { Shell.run($0[0], Array($0.dropFirst())).ok }
                    if ok { done.append(job.id) } else { escalate.append((job, cmds)) }
                }
                return (done, escalate)
            }.value
            for id in done {
                let cmds = steps.first { $0.0.id == id }?.1 ?? []
                cmds.forEach { AuditLog.record(auditAction, Shell.commandLine($0)) }
            }
            guard !escalate.isEmpty else { completion(done); await scan(); return }
            let lines = escalate.flatMap { $0.1.map(Shell.commandLine) }
            authorize(title: title,
                      explanation: explanation + "\n\n" + String(localized: "These jobs belong to the system domain and need administrator rights."),
                      lines: lines) { outcome in
                var all = done
                if case .success = outcome {
                    all += escalate.map(\.0.id)
                    lines.forEach { AuditLog.record(auditAction, $0) }
                } else if case .failed(let msg) = outcome {
                    self.notice = Notice(title: String(localized: "Could not change all jobs"), message: msg)
                }
                completion(all)
                Task { await self.scan() }
            }
        }
    }

    // MARK: Restore

    func restore(_ records: [ChangeRecord]) {
        Task {
            var privileged: [String] = []
            var privilegedIDs: [UUID] = []
            var restored: [UUID] = []
            var problems: [String] = []
            for r in records where r.restoredAt == nil {
                switch r.kind {
                case .startupDisabled:
                    let (cmds, admin) = StartupManager.restoreCommands(r.kind)
                    if cmds.isEmpty { restored.append(r.id); continue }
                    let ok = !admin && cmds.allSatisfy { Shell.run($0[0], Array($0.dropFirst())).ok }
                    if ok { restored.append(r.id); cmds.forEach { AuditLog.record("RESTORE", Shell.commandLine($0)) } }
                    else { privileged += cmds.map(Shell.commandLine); privilegedIDs.append(r.id) }
                case let .moved(original, destination):
                    let res = Uninstaller.restoreMove(original: original, destination: destination)
                    if res.ok { restored.append(r.id); AuditLog.record("RESTORE", "\(destination) -> \(original)") }
                    else if let line = res.privilegedLine { privileged.append(line); privilegedIDs.append(r.id) }
                    else { problems.append(String(localized: "\(original): item is no longer in the Trash, or the original location is occupied.")) }
                case let .certificateRemoved(_, cn, keychain, backup, wasAdmin, wasUser, selfSigned):
                    guard FileManager.default.fileExists(atPath: backup) else {
                        problems.append(String(localized: "\(cn): certificate backup is missing (\(backup)).")) ; continue
                    }
                    let (argv, admin) = CertificateInspector.restoreCommand(
                        backupPath: backup, keychain: keychain, adminTrusted: wasAdmin, userTrusted: wasUser, selfSigned: selfSigned)
                    if !admin, Shell.run(argv[0], Array(argv.dropFirst())).ok {
                        restored.append(r.id); AuditLog.record("RESTORE", Shell.commandLine(argv))
                    } else {
                        privileged.append(Shell.commandLine(argv)); privilegedIDs.append(r.id)
                    }
                case .receiptForgotten:
                    continue
                }
            }
            markRestored(restored)
            if privileged.isEmpty {
                finishRestore(problems)
            } else {
                authorize(title: String(localized: "Restore previous settings"),
                          explanation: String(localized: "Some changes were made in system locations and need administrator rights to undo."),
                          lines: privileged) { outcome in
                    if case .success = outcome {
                        self.markRestored(privilegedIDs)
                        privileged.forEach { AuditLog.record("RESTORE", $0) }
                    }
                    self.finishRestore(problems)
                }
            }
        }
    }

    private func markRestored(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        for i in changes.indices where ids.contains(changes[i].id) { changes[i].restoredAt = Date() }
        ChangeStore.save(changes)
    }

    private func finishRestore(_ problems: [String]) {
        if !problems.isEmpty {
            notice = Notice(title: String(localized: "Some items could not be restored"), message: problems.joined(separator: "\n"))
        }
        Task { await scan() }
    }

    // MARK: Uninstall

    func openVendorUninstaller(_ path: String, product: String) {
        AuditLog.record("VENDOR_UNINSTALL", "\(product): \(path)")
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init()) { _, error in
            if let error {
                Task { @MainActor in self.notice = Notice(title: String(localized: "Could not open uninstaller"), message: error.localizedDescription) }
            }
        }
        uninstallTarget = nil
    }

    func executeRemoval(_ plan: RemovalPlan, selected: Set<String>) {
        uninstallTarget = nil
        let name = plan.product.definition.name
        AuditLog.record("REMOVAL_START", "\(name): \(selected.count) item(s)")
        Task {
            let ex = await Task.detached { Uninstaller.performUnprivileged(plan, selected: selected) }.value
            if !ex.completed.isEmpty { changes += ex.completed; ChangeStore.save(changes) }
            guard !ex.privilegedLines.isEmpty else { finishRemoval(name, log: ex.log, failed: nil); return }
            let trustNote = ex.privilegedLines.contains { $0.contains("remove-trusted-cert") }
                ? " " + String(localized: "Clearing certificate trust is guarded by macOS, which may ask for your password once more; the certificate is already deleted by then.")
                : ""
            authorize(title: String(localized: "Remove \(name)"),
                      explanation: String(localized: "The remaining steps touch files or processes owned by the system. Files are moved to your Trash (in a “GuraKilla …” folder), not deleted, and can be put back from Restore Settings.") + trustNote,
                      lines: ex.privilegedLines) { outcome in
                switch outcome {
                case .success:
                    self.changes += ex.pendingPrivileged
                    ChangeStore.save(self.changes)
                    ex.pendingPrivileged.forEach { AuditLog.record("REMOVE", $0.summary) }
                    self.finishRemoval(name, log: ex.log, failed: nil)
                case .cancelled:
                    self.finishRemoval(name, log: ex.log, failed: String(localized: "Administrator steps were cancelled; only user-owned items were handled."))
                case .failed(let msg):
                    // Record moves that actually happened so they stay restorable.
                    let done = ex.pendingPrivileged.filter {
                        if case let .moved(_, dest) = $0.kind { return FileManager.default.fileExists(atPath: dest) }
                        return false
                    }
                    self.changes += done
                    ChangeStore.save(self.changes)
                    self.finishRemoval(name, log: ex.log, failed: msg)
                }
            }
        }
    }

    private func finishRemoval(_ name: String, log: [String], failed: String?) {
        AuditLog.record("REMOVAL_END", "\(name)\(failed.map { ": \($0)" } ?? "")")
        notice = Notice(title: failed == nil ? String(localized: "\(name) removed") : String(localized: "\(name) partly removed"),
                        message: (failed.map { $0 + "\n\n" } ?? "") + String(localized: "Removed items are in your Trash and can be restored from Restore Settings. Restart your Mac to clear anything still loaded in memory."))
        Task { await scan() }
    }
}

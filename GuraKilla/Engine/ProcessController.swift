import Foundation
import AppKit

struct TerminationReport: Sendable {
    var signalled: [ProcessSnapshot] = []
    /// Owned by another user (usually root): needs administrator authorization.
    var needsPrivilege: [ProcessSnapshot] = []
    /// Already gone, or the PID now belongs to a different process (left alone).
    var skipped: [ProcessSnapshot] = []
}

enum ProcessController {
    /// Graceful termination. Each PID is re-verified right before signalling
    /// so a reused PID is never touched.
    static func terminate(_ processes: [ProcessSnapshot]) -> TerminationReport {
        var report = TerminationReport()
        for p in processes {
            guard ProcessInspector.isSameInstance(p) else { report.skipped.append(p); continue }
            if let app = NSRunningApplication(processIdentifier: p.pid), app.terminate() {
                report.signalled.append(p)
            } else if kill(p.pid, SIGTERM) == 0 {
                report.signalled.append(p)
            } else if errno == EPERM {
                report.needsPrivilege.append(p)
            } else {
                report.skipped.append(p)
            }
        }
        return report
    }

    /// Unprivileged SIGKILL for processes we own; returns those that need admin.
    static func forceKill(_ processes: [ProcessSnapshot]) -> TerminationReport {
        var report = TerminationReport()
        for p in processes {
            guard ProcessInspector.isSameInstance(p) else { report.skipped.append(p); continue }
            if kill(p.pid, SIGKILL) == 0 { report.signalled.append(p) }
            else if errno == EPERM { report.needsPrivilege.append(p) }
            else { report.skipped.append(p) }
        }
        return report
    }

    /// Shell lines for root. Each signal is guarded by the process start time,
    /// so if the PID was recycled in the meantime nothing happens.
    static func privilegedSignalLines(_ processes: [ProcessSnapshot], signal: String) -> [String] {
        processes.map { p in
            "if /bin/ps -p \(p.pid) -o lstart= | /usr/bin/grep -qF \(Shell.quote(p.startTime)); then /bin/kill -\(signal) \(p.pid); fi"
        }
    }

    /// Waits until the processes exit; returns the ones still alive.
    static func waitForExit(_ processes: [ProcessSnapshot], timeout: TimeInterval) async -> [ProcessSnapshot] {
        let deadline = Date().addingTimeInterval(timeout)
        var alive = processes
        while !alive.isEmpty, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(300))
            alive = alive.filter(ProcessInspector.isSameInstance)
        }
        return alive
    }
}

/// Builds launchd commands. Uses only documented `launchctl` subcommands and
/// launchd's own override database — vendor plist files are never edited.
enum StartupManager {
    /// Prevents future automatic launches. Persistent and reversible.
    static func disableCommands(_ job: LaunchJob, unloadNow: Bool) -> [[String]] {
        var cmds = [["/bin/launchctl", "disable", job.serviceTarget]]
        if unloadNow, job.isLoaded { cmds.append(unloadCommand(job)) }
        return cmds
    }

    static func enableCommands(_ job: LaunchJob, loadNow: Bool) -> [[String]] {
        var cmds = [["/bin/launchctl", "enable", job.serviceTarget]]
        if loadNow, !job.isLoaded, FileManager.default.fileExists(atPath: job.plistPath) {
            cmds.append(["/bin/launchctl", "bootstrap", job.domain.target, job.plistPath])
        }
        return cmds
    }

    /// Stops the job now (and its process); it comes back at next login/boot unless disabled.
    static func unloadCommand(_ job: LaunchJob) -> [String] {
        ["/bin/launchctl", "bootout", job.serviceTarget]
    }

    static func restoreCommands(_ kind: ChangeRecord.Kind) -> (cmds: [[String]], admin: Bool) {
        guard case let .startupDisabled(label, domain, plistPath, wasDisabled, wasLoaded) = kind else { return ([], false) }
        let target = "\(domain.target)/\(label)"
        var cmds: [[String]] = []
        if !wasDisabled { cmds.append(["/bin/launchctl", "enable", target]) }
        let loadedNow = Shell.run("/bin/launchctl", ["print", target]).ok
        if wasLoaded, !loadedNow, FileManager.default.fileExists(atPath: plistPath) {
            cmds.append(["/bin/launchctl", "bootstrap", domain.target, plistPath])
        }
        return (cmds, domain.requiresAdmin)
    }
}

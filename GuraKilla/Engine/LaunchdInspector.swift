import Foundation

enum LaunchDomain: Codable, Hashable, Sendable {
    case gui(uid: UInt32)
    case system

    var target: String {
        switch self {
        case let .gui(uid): return "gui/\(uid)"
        case .system: return "system"
        }
    }

    /// Changing the system domain always needs administrator rights.
    var requiresAdmin: Bool { self == .system }
    var displayName: String { self == .system ? String(localized: "System daemon") : String(localized: "User agent") }
}

struct LaunchJob: Identifiable, Hashable, Sendable {
    let label: String
    let plistPath: String
    let domain: LaunchDomain
    let program: String?
    let firstArgument: String?
    let runAtLoad: Bool
    let keepAlive: Bool
    let disabledInPlist: Bool

    // Live status (filled by `withStatus`).
    var isLoaded = false
    var isDisabled = false
    var state: String?
    var pid: Int32?

    var id: String { serviceTarget }
    var serviceTarget: String { "\(domain.target)/\(label)" }
    var executable: String? { program ?? firstArgument }
    /// launchd will start this job at login/boot.
    var autoStarts: Bool { !isDisabled && (runAtLoad || keepAlive) }
    var isRunning: Bool { pid != nil }
}

enum LaunchdInspector {
    static var searchLocations: [(String, LaunchDomain)] {
        let uid = getuid()
        return [
            ("/Library/LaunchAgents", .gui(uid: uid)),
            ("/Library/LaunchDaemons", .system),
            (Paths.expand("~/Library/LaunchAgents"), .gui(uid: uid)),
        ]
    }

    /// Parses every launchd plist in the standard locations (no status yet).
    static func definitions() -> [LaunchJob] {
        var jobs: [LaunchJob] = []
        let fm = FileManager.default
        for (dir, domain) in searchLocations {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names where name.hasSuffix(".plist") {
                let path = (dir as NSString).appendingPathComponent(name)
                if let job = parse(path: path, domain: domain) { jobs.append(job) }
            }
        }
        return jobs
    }

    static func parse(path: String, domain: LaunchDomain) -> LaunchJob? {
        guard let data = FileManager.default.contents(atPath: path),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = dict["Label"] as? String else { return nil }
        let keepAlive: Bool = {
            if let b = dict["KeepAlive"] as? Bool { return b }
            return dict["KeepAlive"] is [String: Any] // conditional KeepAlive still relaunches
        }()
        return LaunchJob(
            label: label, plistPath: path, domain: domain,
            program: dict["Program"] as? String,
            firstArgument: (dict["ProgramArguments"] as? [String])?.first,
            runAtLoad: dict["RunAtLoad"] as? Bool ?? false,
            keepAlive: keepAlive,
            disabledInPlist: dict["Disabled"] as? Bool ?? false)
    }

    /// launchd's persistent enable/disable overrides for both domains we manage.
    static func disabledOverrides() -> [String: Bool] {
        var map: [String: Bool] = [:]
        for domain in [LaunchDomain.gui(uid: getuid()), .system] {
            let out = Shell.run("/bin/launchctl", ["print-disabled", domain.target]).stdout
            for (label, disabled) in parseDisabled(out) { map["\(domain.target)/\(label)"] = disabled }
        }
        return map
    }

    /// Parses lines like `"com.example" => disabled` (or `=> true` on older systems).
    static func parseDisabled(_ output: String) -> [String: Bool] {
        var map: [String: Bool] = [:]
        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("\""), let arrow = line.range(of: "\" => ") else { continue }
            let label = String(line[line.index(after: line.startIndex)..<arrow.lowerBound])
            let value = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
            map[label] = (value == "disabled" || value == "true")
        }
        return map
    }

    /// Top-level `state` and `pid` from `launchctl print <target>`.
    static func parsePrint(_ output: String) -> (state: String?, pid: Int32?) {
        var state: String?, pid: Int32?
        for raw in output.split(separator: "\n") {
            guard raw.hasPrefix("\t"), !raw.hasPrefix("\t\t") else { continue }
            let line = raw.trimmingCharacters(in: .whitespaces)
            if state == nil, line.hasPrefix("state = ") { state = String(line.dropFirst(8)) }
            if pid == nil, line.hasPrefix("pid = ") { pid = Int32(line.dropFirst(6)) }
        }
        return (state, pid)
    }

    static func withStatus(_ job: LaunchJob, overrides: [String: Bool]) -> LaunchJob {
        var j = job
        let r = Shell.run("/bin/launchctl", ["print", job.serviceTarget])
        j.isLoaded = r.ok
        if r.ok {
            let parsed = parsePrint(r.stdout)
            j.state = parsed.state
            j.pid = parsed.pid
        }
        j.isDisabled = overrides[job.serviceTarget] ?? job.disabledInPlist
        return j
    }
}

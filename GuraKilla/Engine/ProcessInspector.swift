import Foundation
import Darwin
import Security

struct ProcessSnapshot: Identifiable, Hashable, Sendable {
    let pid: Int32
    let uid: UInt32
    let path: String
    let cpu: Double
    let rssKB: Int
    /// `ps -o lstart` in the C locale. Together with the PID it identifies
    /// one specific process instance, guarding against PID reuse.
    let startTime: String

    var id: Int32 { pid }
    var name: String { (path as NSString).lastPathComponent }
    var ownedByCurrentUser: Bool { uid == getuid() }
    var owner: String {
        if uid == 0 { return "root" }
        if let pw = getpwuid(uid) { return String(cString: pw.pointee.pw_name) }
        return String(uid)
    }
}

enum ProcessInspector {
    static func executablePath(pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : nil
    }

    /// All processes with CPU / memory. `ps` is used for stats because it can
    /// read them for processes owned by other users, which libproc cannot without root.
    static func snapshot() -> [ProcessSnapshot] {
        let r = Shell.run("/bin/ps", ["-axo", "pid=,uid=,pcpu=,rss=,lstart="])
        let selfPID = getpid()
        var result: [ProcessSnapshot] = []
        for line in r.stdout.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard parts.count == 5, let pid = Int32(parts[0]), pid > 1, pid != selfPID,
                  let uid = UInt32(parts[1]),
                  let path = executablePath(pid: pid) else { continue }
            let cpu = Double(parts[2].replacingOccurrences(of: ",", with: ".")) ?? 0
            let rss = Int(parts[3]) ?? 0
            let start = parts[4].trimmingCharacters(in: .whitespaces)
            result.append(ProcessSnapshot(pid: pid, uid: uid, path: path, cpu: cpu, rssKB: rss, startTime: start))
        }
        return result
    }

    static func startTime(pid: Int32) -> String? {
        let r = Shell.run("/bin/ps", ["-p", String(pid), "-o", "lstart="])
        let t = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// True when the PID still refers to the exact process instance we inspected.
    static func isSameInstance(_ p: ProcessSnapshot) -> Bool {
        startTime(pid: p.pid) == p.startTime && executablePath(pid: p.pid) == p.path
    }
}

struct SigningInfo: Hashable, Sendable {
    var teamID: String?
    var signed: Bool
    var valid: Bool

    static let unsigned = SigningInfo(teamID: nil, signed: false, valid: false)

    var label: String {
        if !signed { return "Unsigned" }
        guard let teamID else { return valid ? "Signed (no team)" : "Invalid signature" }
        return valid ? "Team \(teamID)" : "Team \(teamID) — invalid"
    }
}

/// Reads and validates code signatures. Results are cached per path.
enum CodeSigning {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: SigningInfo] = [:]

    // Raw SecCSFlags values (CSCommon.h); named constants aren't reliably bridged.
    private static let signingInformation = SecCSFlags(rawValue: 1 << 1)
    private static let doNotValidateResources = SecCSFlags(rawValue: 1 << 2)

    static func info(path: String) -> SigningInfo {
        lock.lock()
        if let hit = cache[path] { lock.unlock(); return hit }
        lock.unlock()

        let result = compute(path: path)
        lock.lock(); cache[path] = result; lock.unlock()
        return result
    }

    private static func compute(path: String) -> SigningInfo {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code else { return .unsigned }
        var cfInfo: CFDictionary?
        guard SecCodeCopySigningInformation(code, signingInformation, &cfInfo) == errSecSuccess,
              let dict = cfInfo as? [String: Any],
              dict[kSecCodeInfoIdentifier as String] != nil else { return .unsigned }
        let team = dict[kSecCodeInfoTeamIdentifier as String] as? String
        // Validate the executable and signature; skip deep resource hashing for speed.
        let valid = SecStaticCodeCheckValidity(code, doNotValidateResources, nil) == errSecSuccess
        return SigningInfo(teamID: team, signed: true, valid: valid)
    }
}

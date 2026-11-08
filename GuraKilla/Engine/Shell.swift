import Foundation

struct ShellResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
    var ok: Bool { status == 0 }
}

enum Shell {
    /// Runs a tool directly (no shell interpolation). Locale is pinned to C so
    /// output formats (e.g. `ps -o lstart`) are stable and comparable.
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) -> ShellResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["LC_ALL"] = "C"; env["LANG"] = "C"
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch {
            return ShellResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }
        // Drain stderr concurrently so a chatty tool can't fill the pipe and deadlock.
        final class Box: @unchecked Sendable { var data = Data() }
        let errBox = Box()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errBox.data = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        return ShellResult(status: p.terminationStatus,
                           stdout: String(decoding: outData, as: UTF8.self),
                           stderr: String(decoding: errBox.data, as: UTF8.self))
    }

    /// POSIX single-quote escaping.
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func commandLine(_ argv: [String]) -> String {
        argv.map(quote).joined(separator: " ")
    }
}

enum PrivilegedOutcome: Sendable {
    case success(String)
    case cancelled
    case failed(String)
}

/// Runs a reviewed shell script as root through the standard macOS
/// administrator authorization dialog (`do shell script … with administrator
/// privileges`, Authorization Services). GuraKilla never sees the password,
/// and the caller must have shown the exact script to the user beforehand.
enum PrivilegedRunner {
    static func escapeForAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func appleScriptSource(script: String, prompt: String) -> String {
        "do shell script \"\(escapeForAppleScript(script))\" with prompt \"\(escapeForAppleScript(prompt))\" with administrator privileges"
    }

    /// Wraps command lines so every line runs, failures are counted, and the
    /// script's exit status reports whether anything failed.
    static func script(_ lines: [String]) -> String {
        (["export LC_ALL=C", "failed=0"]
         + lines.map { "( \($0) ) || failed=1" }
         + ["exit $failed"]).joined(separator: "\n")
    }

    static func run(script: String, prompt: String) -> PrivilegedOutcome {
        let r = Shell.run("/usr/bin/osascript", ["-e", appleScriptSource(script: script, prompt: prompt)])
        if r.ok { return .success(r.stdout) }
        if r.stderr.contains("-128") { return .cancelled }
        return .failed(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

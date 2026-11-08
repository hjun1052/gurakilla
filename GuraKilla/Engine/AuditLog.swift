import Foundation

/// Append-only, human-readable log of every change GuraKilla makes.
/// Lives at ~/Library/Logs/GuraKilla/audit.log (also visible in Console.app).
enum AuditLog {
    static let url = Paths.logs.appendingPathComponent("audit.log")
    private static let lock = NSLock()

    static func record(_ action: String, _ detail: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp)  \(action.padding(toLength: 18, withPad: " ", startingAt: 0))  \(detail)\n"
        lock.lock(); defer { lock.unlock() }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: Data(line.utf8))
    }

    static func read() -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}

/// A reversible (or at least recorded) change, kept so "Restore Settings" can undo it.
struct ChangeRecord: Codable, Identifiable, Hashable, Sendable {
    enum Kind: Codable, Hashable, Sendable {
        case startupDisabled(label: String, domain: LaunchDomain, plistPath: String, wasDisabled: Bool, wasLoaded: Bool)
        case moved(original: String, destination: String)
        case receiptForgotten(id: String)
        case certificateRemoved(sha256: String, commonName: String, keychain: String, backupPath: String,
                                wasAdminTrusted: Bool, wasUserTrusted: Bool, selfSigned: Bool)
    }

    var id = UUID()
    var date = Date()
    var product: String
    var kind: Kind
    var restoredAt: Date?

    var isReversible: Bool {
        if case .receiptForgotten = kind { return false }
        return true
    }

    var summary: String {
        switch kind {
        case let .startupDisabled(label, domain, _, _, _): return "Auto-start disabled: \(domain.target)/\(label)"
        case let .moved(original, _): return "Moved to Trash: \(original)"
        case let .receiptForgotten(id): return "Package receipt forgotten: \(id)"
        case let .certificateRemoved(_, cn, keychain, _, _, _, _):
            return "Certificate removed: \(cn) (\((keychain as NSString).lastPathComponent))"
        }
    }
}

enum ChangeStore {
    static let url = Paths.support.appendingPathComponent("changes.json")

    static func load() -> [ChangeRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ChangeRecord].self, from: data)) ?? []
    }

    static func save(_ records: [ChangeRecord]) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(records) { try? data.write(to: url, options: .atomic) }
    }
}

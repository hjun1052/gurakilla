import AppKit
import CryptoKit
import Foundation

/// A GitHub release newer than the running app.
struct AppRelease: Equatable, Sendable {
    let version: String
    let pageURL: URL
    /// Signed zip and its signature; nil when the release has no signed update.
    let zipURL: URL?
    let signatureURL: URL?
    var canInstall: Bool { zipURL != nil && signatureURL != nil }
}

enum UpdateError: LocalizedError {
    case notSigned, badSignature, notWritable, badBundle, unzipFailed

    var errorDescription: String? {
        switch self {
        case .notSigned: String(localized: "This release has no signed update file.")
        case .badSignature: String(localized: "The update's signature is not valid, so it was not installed.")
        case .notWritable: String(localized: "GuraKilla can't replace itself in this location. Move it to the Applications folder, or download the update from the release page.")
        case .badBundle, .unzipFailed: String(localized: "The downloaded update is not a valid GuraKilla build.")
        }
    }
}

/// Checks GitHub for a newer release and installs it in place.
/// Each release zip is signed with an Ed25519 key kept in the maintainer's Keychain
/// (scripts/update-key.swift); updates without a valid signature are refused.
enum Updater {
    static let publicKey = "1m+7MXOFSW5JEnUs1BNtuko37g7dc7qg78W5lGgAq1o="
    static let latestURL = URL(string: "https://api.github.com/repos/hjun1052/gurakilla/releases/latest")!

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Numeric dotted-version comparison ("1.0.10" > "1.0.9"); a leading "v" is ignored.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Parses the GitHub "latest release" JSON.
    static func parse(_ data: Data) -> AppRelease? {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Release: Decodable { let tag_name: String; let html_url: URL; let assets: [Asset] }
        guard let r = try? JSONDecoder().decode(Release.self, from: data) else { return nil }
        let zip = r.assets.first { $0.name.hasSuffix(".zip") }
        let sig = zip.flatMap { z in r.assets.first { $0.name == z.name + ".sig" } }
        return AppRelease(version: r.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
                          pageURL: r.html_url, zipURL: zip?.browser_download_url, signatureURL: sig?.browser_download_url)
    }

    /// The latest release if it is newer than the running app, otherwise nil.
    static func latest() async throws -> AppRelease? {
        var request = URLRequest(url: latestURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let release = parse(data), isNewer(release.version, than: currentVersion) else { return nil }
        return release
    }

    static func verify(_ data: Data, signature: Data, publicKey: String = publicKey) -> Bool {
        guard let raw = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
              let sig = Data(base64Encoded: String(decoding: signature, as: UTF8.self)
                                .trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return key.isValidSignature(sig, for: data)
    }

    /// Downloads, verifies and installs the release over `target`. Returns the installed app's URL.
    static func install(_ release: AppRelease, replacing target: URL = Bundle.main.bundleURL) async throws -> URL {
        guard let zipURL = release.zipURL, let sigURL = release.signatureURL else { throw UpdateError.notSigned }
        guard canReplace(target) else { throw UpdateError.notWritable }
        async let zip = URLSession.shared.data(from: zipURL).0
        async let sig = URLSession.shared.data(from: sigURL).0
        let (zipData, sigData) = try await (zip, sig)
        try installArchive(zipData, signature: sigData, expectedVersion: release.version, replacing: target)
        return target
    }

    /// Can we swap the bundle at `target`? Not when macOS runs it from a read-only translocated copy.
    static func canReplace(_ target: URL) -> Bool {
        !target.path.contains("/AppTranslocation/")
            && FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path)
            && FileManager.default.isWritableFile(atPath: target.path)
    }

    static func installArchive(_ zip: Data, signature: Data, expectedVersion: String, replacing target: URL,
                               bundleID: String? = Bundle.main.bundleIdentifier,
                               publicKey: String = publicKey) throws {
        guard verify(zip, signature: signature, publicKey: publicKey) else { throw UpdateError.badSignature }

        let fm = FileManager.default
        // Same volume as the target so the final swap is a rename.
        let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)
        defer { try? fm.removeItem(at: work) }
        let archive = work.appendingPathComponent("update.zip")
        try zip.write(to: archive)
        let unpacked = work.appendingPathComponent("unpacked")
        guard Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path]).ok else { throw UpdateError.unzipFailed }

        guard let app = try fm.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }),
              let info = Bundle(url: app)?.infoDictionary,
              info["CFBundleIdentifier"] as? String == bundleID,
              info["CFBundleShortVersionString"] as? String == expectedVersion else { throw UpdateError.badBundle }

        _ = try fm.replaceItemAt(target, withItemAt: app)
        Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", target.path])
    }

    /// Opens the app at `url` once this process has exited.
    static func relaunch(_ url: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
                       url.path, String(ProcessInfo.processInfo.processIdentifier)]
        try? p.run()
    }
}

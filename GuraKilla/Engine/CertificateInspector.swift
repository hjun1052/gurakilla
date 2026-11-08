import Foundation
import Security
import CryptoKit

/// A certificate in the System or login keychain, with its trust settings.
/// Korean banking modules install their own root CAs (for localhost TLS) and
/// mark them trusted system-wide; vendor uninstallers often leave them behind.
struct InstalledCertificate: Identifiable, Hashable, Sendable {
    let sha256: String
    let sha1: String
    /// RFC 2253 subject / issuer exactly as `openssl x509 -nameopt RFC2253` prints them.
    let subject: String
    let issuer: String
    let commonName: String
    let notAfter: String
    let keychain: String
    let pem: String
    let adminTrusted: Bool
    let userTrusted: Bool

    var id: String { keychain + ":" + sha256 }
    var isSelfSigned: Bool { subject == issuer }
    var inSystemKeychain: Bool { keychain == CertificateInspector.systemKeychain }
    var isTrusted: Bool { adminTrusted || userTrusted }
    var trustLabel: String {
        switch (adminTrusted, userTrusted) {
        case (true, true): return "Trusted (system + user)"
        case (true, false): return "Trusted system-wide"
        case (false, true): return "Trusted for this user"
        default: return "Not explicitly trusted"
        }
    }
}

struct SystemExtensionInfo: Identifiable, Hashable, Sendable {
    let teamID: String
    let bundleID: String
    let version: String
    let name: String
    let state: String
    var id: String { teamID + "/" + bundleID + "/" + version }
}

enum CertificateInspector {
    static let systemKeychain = "/Library/Keychains/System.keychain"
    static var loginKeychain: String { Paths.expand("~/Library/Keychains/login.keychain-db") }

    static func all() -> [InstalledCertificate] {
        [systemKeychain, loginKeychain].flatMap { kc in
            splitPEM(Shell.run("/usr/bin/security", ["find-certificate", "-a", "-p", kc]).stdout)
                .compactMap { parse(pem: $0, keychain: kc) }
        }
    }

    static func splitPEM(_ text: String) -> [String] {
        text.components(separatedBy: "-----END CERTIFICATE-----")
            .compactMap { chunk in
                guard let start = chunk.range(of: "-----BEGIN CERTIFICATE-----") else { return nil }
                return String(chunk[start.lowerBound...]) + "-----END CERTIFICATE-----\n"
            }
    }

    static func der(fromPEM pem: String) -> Data? {
        let body = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        return Data(base64Encoded: body)
    }

    static func parse(pem: String, keychain: String) -> InstalledCertificate? {
        guard let der = der(fromPEM: pem),
              let cert = SecCertificateCreateWithData(nil, der as CFData) else { return nil }
        let fields = opensslFields(pem)
        guard let subject = fields["subject"] else { return nil }
        return InstalledCertificate(
            sha256: SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined(),
            sha1: Insecure.SHA1.hash(data: der).map { String(format: "%02X", $0) }.joined(),
            subject: subject, issuer: fields["issuer"] ?? "",
            commonName: (SecCertificateCopySubjectSummary(cert) as String?) ?? subject,
            notAfter: fields["notAfter"] ?? "",
            keychain: keychain, pem: pem,
            adminTrusted: hasTrustSettings(cert, domain: .admin),
            userTrusted: hasTrustSettings(cert, domain: .user))
    }

    /// Subject/issuer via the system LibreSSL so strings match research data exactly.
    static func opensslFields(_ pem: String) -> [String: String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        p.arguments = ["x509", "-noout", "-subject", "-issuer", "-enddate", "-nameopt", "RFC2253"]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [:] }
        inPipe.fileHandleForWriting.write(Data(pem.utf8))
        try? inPipe.fileHandleForWriting.close()
        let out = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        return parseOpenSSL(out)
    }

    static func parseOpenSSL(_ out: String) -> [String: String] {
        var f: [String: String] = [:]
        for line in out.split(separator: "\n") {
            for key in ["subject", "issuer", "notAfter"] where line.hasPrefix(key + "=") {
                f[key] = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
            }
        }
        return f
    }

    static func hasTrustSettings(_ cert: SecCertificate, domain: SecTrustSettingsDomain) -> Bool {
        var settings: CFArray?
        return SecTrustSettingsCopyTrustSettings(cert, domain, &settings) == errSecSuccess
    }

    // MARK: System extensions

    static func systemExtensions() -> [SystemExtensionInfo] {
        parseSystemExtensions(Shell.run("/usr/bin/systemextensionsctl", ["list"]).stdout)
    }

    /// Parses rows like `\t*\tR2PBZJ465V\tcom.nprotect.nosfw (1.0/1)\tnosfw\t[activated waiting for user]`.
    static func parseSystemExtensions(_ out: String) -> [SystemExtensionInfo] {
        out.split(separator: "\n").compactMap { line in
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 6, cols[2].count == 10,
                  let open = cols[3].firstIndex(of: "("), cols[5].hasPrefix("[") else { return nil }
            return SystemExtensionInfo(
                teamID: cols[2],
                bundleID: cols[3][..<open].trimmingCharacters(in: .whitespaces),
                version: cols[3][cols[3].index(after: open)...].trimmingCharacters(in: CharacterSet(charactersIn: ") ")),
                name: cols[4],
                state: cols[5].trimmingCharacters(in: CharacterSet(charactersIn: "[]")))
        }
    }

    // MARK: Removal / restore commands

    /// Root-script lines that untrust and delete a certificate. The PEM must
    /// already be backed up at `backupPath` (used to identify the trust entry).
    static func removalLines(_ c: InstalledCertificate, backupPath: String) -> (privileged: [String], user: [[String]]) {
        // Delete first: root can do that without further prompts, and it removes the trust anchor.
        // Clearing the trust setting afterwards needs macOS's own admin authentication
        // (rule com.apple.trust-settings.admin = entitled or authenticate-admin, even for root),
        // which may show one more system dialog; if it is cancelled the cert is already gone.
        var priv: [String] = [], user: [[String]] = []
        if c.inSystemKeychain {
            priv.append("/usr/bin/security delete-certificate -Z \(c.sha1) \(Shell.quote(systemKeychain))")
        } else {
            user.append(["/usr/bin/security", "delete-certificate", "-Z", c.sha1, c.keychain])
        }
        if c.adminTrusted { priv.append("/usr/bin/security remove-trusted-cert -d \(Shell.quote(backupPath))") }
        if c.userTrusted { user.append(["/usr/bin/security", "remove-trusted-cert", backupPath]) }
        return (priv, user)
    }

    /// Re-adds a backed-up certificate. CAs get `trustRoot`, leaf certs `trustAsRoot`
    /// (what the vendor installers use); custom policy constraints are not reproduced.
    static func restoreCommand(backupPath: String, keychain: String, adminTrusted: Bool,
                               userTrusted: Bool, selfSigned: Bool) -> (argv: [String], admin: Bool) {
        let result = selfSigned ? "trustRoot" : "trustAsRoot"
        if keychain == systemKeychain {
            return adminTrusted
                ? (["/usr/bin/security", "add-trusted-cert", "-d", "-r", result, "-k", keychain, backupPath], true)
                : (["/usr/bin/security", "add-certificates", "-k", keychain, backupPath], true)
        }
        return userTrusted
            ? (["/usr/bin/security", "add-trusted-cert", "-r", result, "-k", keychain, backupPath], false)
            : (["/usr/bin/security", "add-certificates", "-k", keychain, backupPath], false)
    }

    static var backupDirectory: URL {
        let url = Paths.support.appendingPathComponent("certificate-backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func backup(_ c: InstalledCertificate) throws -> String {
        let url = backupDirectory.appendingPathComponent("\(c.sha256).pem")
        try c.pem.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }
}

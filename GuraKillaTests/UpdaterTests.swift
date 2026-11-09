import CryptoKit
import XCTest
@testable import GuraKilla

final class UpdaterTests: XCTestCase {
    func testVersionCompare() {
        XCTAssertTrue(Updater.isNewer("1.0.2", than: "1.0.1"))
        XCTAssertTrue(Updater.isNewer("v1.0.10", than: "1.0.9"))
        XCTAssertTrue(Updater.isNewer("1.1", than: "1.0.9"))
        XCTAssertFalse(Updater.isNewer("1.0.1", than: "1.0.1"))
        XCTAssertFalse(Updater.isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(Updater.isNewer("0.9", than: "1.0.1"))
    }

    func testParseRelease() throws {
        let json = """
        {"tag_name":"v1.0.2","html_url":"https://github.com/hjun1052/gurakilla/releases/tag/v1.0.2","assets":[
          {"name":"GuraKilla-1.0.2.dmg","browser_download_url":"https://example.com/a.dmg"},
          {"name":"GuraKilla-1.0.2.zip","browser_download_url":"https://example.com/a.zip"},
          {"name":"GuraKilla-1.0.2.zip.sig","browser_download_url":"https://example.com/a.zip.sig"}]}
        """
        let r = try XCTUnwrap(Updater.parse(Data(json.utf8)))
        XCTAssertEqual(r.version, "1.0.2")
        XCTAssertEqual(r.zipURL?.absoluteString, "https://example.com/a.zip")
        XCTAssertEqual(r.signatureURL?.absoluteString, "https://example.com/a.zip.sig")
        XCTAssertTrue(r.canInstall)

        let unsigned = json.replacingOccurrences(of: "GuraKilla-1.0.2.zip.sig", with: "other.txt")
        XCTAssertFalse(try XCTUnwrap(Updater.parse(Data(unsigned.utf8))).canInstall)
    }

    func testBundledPublicKeyIsValid() {
        XCTAssertNotNil(Data(base64Encoded: Updater.publicKey).flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) })
    }

    // MARK: Install

    private var dir: URL!
    private let key = Curve25519.Signing.PrivateKey()
    private let bundleID = "dev.hjun.GuraKilla.test"

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("UpdaterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func makeApp(at url: URL, version: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version,
                                    "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
    }

    /// A zipped GuraKilla.app at `version`, as the release script produces it.
    private func makeArchive(version: String) throws -> Data {
        let staging = dir.appendingPathComponent("staging-\(version)")
        let app = staging.appendingPathComponent("GuraKilla.app")
        try makeApp(at: app, version: version)
        let zip = dir.appendingPathComponent("GuraKilla-\(version).zip")
        XCTAssertTrue(Shell.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path]).ok)
        return try Data(contentsOf: zip)
    }

    private func sign(_ data: Data) throws -> Data {
        Data(try key.signature(for: data).base64EncodedString().utf8)
    }

    private func installedVersion(_ target: URL) -> String? {
        NSDictionary(contentsOf: target.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
    }

    private var publicKey: String { key.publicKey.rawRepresentation.base64EncodedString() }

    func testSignedUpdateReplacesApp() throws {
        let target = dir.appendingPathComponent("Applications/GuraKilla.app")
        try makeApp(at: target, version: "1.0.0")
        let zip = try makeArchive(version: "9.9.9")

        try Updater.installArchive(zip, signature: try sign(zip), expectedVersion: "9.9.9", replacing: target,
                                   bundleID: bundleID, publicKey: publicKey)
        XCTAssertEqual(installedVersion(target), "9.9.9")
    }

    func testTamperedUpdateIsRefused() throws {
        let target = dir.appendingPathComponent("Applications/GuraKilla.app")
        try makeApp(at: target, version: "1.0.0")
        let zip = try makeArchive(version: "9.9.9")
        let signature = try sign(zip)
        var tampered = zip
        tampered.append(0)

        XCTAssertThrowsError(try Updater.installArchive(tampered, signature: signature, expectedVersion: "9.9.9",
                                                        replacing: target, bundleID: bundleID, publicKey: publicKey)) {
            guard case UpdateError.badSignature = $0 else { return XCTFail("\($0)") }
        }
        // Signed by a different key.
        let other = Data(try Curve25519.Signing.PrivateKey().signature(for: zip).base64EncodedString().utf8)
        XCTAssertThrowsError(try Updater.installArchive(zip, signature: other, expectedVersion: "9.9.9",
                                                        replacing: target, bundleID: bundleID, publicKey: publicKey))
        XCTAssertEqual(installedVersion(target), "1.0.0")
    }

    func testWrongVersionOrBundleIsRefused() throws {
        let target = dir.appendingPathComponent("Applications/GuraKilla.app")
        try makeApp(at: target, version: "1.0.0")
        let zip = try makeArchive(version: "9.9.9")
        let signature = try sign(zip)

        XCTAssertThrowsError(try Updater.installArchive(zip, signature: signature, expectedVersion: "2.0.0",
                                                        replacing: target, bundleID: bundleID, publicKey: publicKey))
        XCTAssertThrowsError(try Updater.installArchive(zip, signature: signature, expectedVersion: "9.9.9",
                                                        replacing: target, bundleID: "com.example.other", publicKey: publicKey))
        XCTAssertEqual(installedVersion(target), "1.0.0")
    }

    func testTranslocatedAppCannotBeReplaced() {
        XCTAssertFalse(Updater.canReplace(URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/GuraKilla.app")))
    }
}

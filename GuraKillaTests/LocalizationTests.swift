import XCTest
@testable import GuraKilla

/// Korean must cover every UI string and every built-in product text.
final class LocalizationTests: XCTestCase {
    private func koTable(_ name: String) throws -> [String: String] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "strings", subdirectory: nil, localization: "ko"),
                                "ko.lproj/\(name).strings missing from the app bundle")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    }

    func testEveryCatalogStringHasKorean() throws {
        let src = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("GuraKilla/Resources/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: src)) as! [String: Any]
        let strings = json["strings"] as! [String: [String: Any]]
        let untranslated = strings.filter { _, entry in
            let ko = (entry["localizations"] as? [String: Any])?["ko"] as? [String: Any]
            let unit = ko?["stringUnit"] as? [String: Any]
            return (unit?["value"] as? String)?.isEmpty ?? true
        }.keys.sorted()
        XCTAssertEqual(untranslated, [], "Strings without a Korean translation")
    }

    func testBuiltInProductTextIsTranslated() throws {
        let table = try koTable("Products")
        for def in ProductRegistry.builtIn {
            for text in [def.publisher, def.category, def.notes].compactMap({ $0 }) {
                XCTAssertNotNil(table[text], "\(def.id): no Korean for “\(text)”")
            }
        }
    }

    func testRemovalReasonsAreTranslated() throws {
        let table = try koTable("Localizable")
        for reason in Uninstaller.excludedReasons {
            XCTAssertNotNil(table[reason], "No Korean for “\(reason)”")
        }
    }
}

final class FormatTests: XCTestCase {
    func testCertificateDateParsesOpenSSLFormat() {
        XCTAssertNotEqual(Format.certificateDate("Dec 31 00:00:00 2099 GMT"), "Dec 31 00:00:00 2099 GMT")
        XCTAssertNotEqual(Format.certificateDate("Jan  1 12:00:00 2038 GMT"), "Jan  1 12:00:00 2038 GMT")
        XCTAssertEqual(Format.certificateDate("garbage"), "garbage")
    }
}

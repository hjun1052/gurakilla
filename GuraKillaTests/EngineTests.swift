import XCTest
@testable import GuraKilla

final class EngineTests: XCTestCase {
    func testRegistryIDsAreUnique() {
        let ids = ProductRegistry.builtIn.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testReceiptPatterns() {
        XCTAssertTrue(ProductRegistry.receipt("com.wizvera.delfino", matches: "com.wizvera.delfino"))
        XCTAssertFalse(ProductRegistry.receipt("com.wizvera.delfino2", matches: "com.wizvera.delfino"))
        XCTAssertTrue(ProductRegistry.receipt("com.nprotect.nprotectOnlineSecurityV1.kernel.pkg", matches: "com.nprotect.nprotectOnlineSecurityV1.*"))
        XCTAssertFalse(ProductRegistry.receipt("com.nprotect.other", matches: "com.nprotect.nprotectOnlineSecurityV1.*"))
    }

    func testPathContainmentIsComponentWise() {
        XCTAssertTrue(Paths.isUnder("/Applications/Veraport/veraport.app", "/Applications/Veraport"))
        XCTAssertTrue(Paths.isUnder("/Applications/Veraport", "/Applications/Veraport"))
        XCTAssertFalse(Paths.isUnder("/Applications/Veraport2/x", "/Applications/Veraport"))
    }

    func testRemovalSafetyGuard() {
        for bad in ["/", "/Applications", "/System/Library/Foo", "/usr/bin/kill", "/Library/LaunchAgents",
                    "/Applications/../System", "/Library/Extensions/TKVHD.kext", "relative/path", NSHomeDirectory()] {
            XCTAssertFalse(Uninstaller.isSafeToRemove(bad), bad)
        }
        for ok in ["/Applications/IPinside.app", "/Library/LaunchAgents/com.wizvera.veraport.plist",
                   "/Library/Application Support/raonsecure/TouchEn nxKey"] {
            XCTAssertTrue(Uninstaller.isSafeToRemove(ok), ok)
        }
    }

    func testContainerItem() {
        XCTAssertEqual(Uninstaller.containerItem(for: "/Library/Frameworks/X.framework/Versions/A/X"), "/Library/Frameworks/X.framework")
        XCTAssertEqual(Uninstaller.containerItem(for: "/Library/Application Support/Mozilla/NativeMessagingHosts/a.json"),
                       "/Library/Application Support/Mozilla/NativeMessagingHosts/a.json")
        XCTAssertNil(Uninstaller.containerItem(for: "/Applications/AhnLab/V3.app"))
    }

    func testShellQuotingRoundTrips() {
        let tricky = "it's a \"test\" $HOME `x`"
        let r = Shell.run("/bin/sh", ["-c", "printf %s " + Shell.quote(tricky)])
        XCTAssertEqual(r.stdout, tricky)
    }

    func testAppleScriptEscaping() {
        let src = PrivilegedRunner.appleScriptSource(script: #"echo "a\b""#, prompt: "p")
        XCTAssertTrue(src.hasPrefix(#"do shell script "echo \"a\\b\"""#))
    }

    func testLaunchctlParsing() {
        let disabled = "\tdisabled services = {\n\t\t\"com.a\" => disabled\n\t\t\"com.b\" => enabled\n\t\t\"com.c\" => true\n\t}\n"
        XCTAssertEqual(LaunchdInspector.parseDisabled(disabled), ["com.a": true, "com.b": false, "com.c": true])

        let print = "gui/501/com.x = {\n\tactive count = 1\n\tstate = running\n\tpid = 1082\n\tendpoints = {\n\t\tpid = 9\n\t}\n}\n"
        let parsed = LaunchdInspector.parsePrint(print)
        XCTAssertEqual(parsed.state, "running")
        XCTAssertEqual(parsed.pid, 1082)
    }

    func testSignatureGate() {
        let def = ProductRegistry.builtIn.first { $0.id == "wizvera-veraport" }!
        XCTAssertTrue(DetectionEngine.signatureAllows(.init(teamID: "C86MGS2A3T", signed: true, valid: true), definition: def, launchdVerified: false))
        XCTAssertFalse(DetectionEngine.signatureAllows(.init(teamID: "OTHERTEAM1", signed: true, valid: true), definition: def, launchdVerified: true))
        XCTAssertTrue(DetectionEngine.signatureAllows(.unsigned, definition: def, launchdVerified: false))
    }

    /// Read-only smoke test against the real machine: the scan must not crash.
    func testLiveScanIsReadOnlyAndSucceeds() {
        let products = DetectionEngine.scan(ProductRegistry.load())
        for p in products {
            for proc in p.processes {
                XCTAssertTrue(Paths.isUnder(proc.path, anyOf: p.definition.expandedInstallPaths)
                              || p.launchJobs.contains { $0.pid == proc.pid || $0.executable == proc.path })
            }
        }
    }
}

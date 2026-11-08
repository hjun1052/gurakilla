import XCTest
@testable import GuraKilla

/// One regression case per supported product, built from identifiers observed
/// on a real Mac (research/baseline.json) or documented by the vendor's own
/// uninstaller. Detection runs on injected inputs, so nothing on this Mac is read.
final class ProductRegressionTests: XCTestCase {
    let sys = CertificateInspector.systemKeychain
    let uid = getuid()

    // MARK: Fixture helpers

    func cert(_ subject: String, issuer: String? = nil, cn: String, keychain: String? = nil,
              admin: Bool = true, user: Bool = false) -> InstalledCertificate {
        InstalledCertificate(sha256: String(repeating: "A", count: 64) + cn, sha1: "00" + cn, subject: subject,
                             issuer: issuer ?? subject, commonName: cn, notAfter: "Dec 31 00:00:00 2099 GMT",
                             keychain: keychain ?? sys, pem: "", adminTrusted: admin, userTrusted: user)
    }

    func job(_ label: String, _ plist: String, system: Bool = false, program: String? = nil, keepAlive: Bool = true) -> LaunchJob {
        LaunchJob(label: label, plistPath: plist, domain: system ? .system : .gui(uid: uid), program: nil,
                  firstArgument: program, runAtLoad: true, keepAlive: keepAlive, disabledInPlist: false)
    }

    func proc(_ pid: Int32, _ path: String, uid: UInt32 = 501) -> ProcessSnapshot {
        ProcessSnapshot(pid: pid, uid: uid, path: path, cpu: 0.1, rssKB: 1000, startTime: "Sun Nov  8 00:00:00 2026")
    }

    func scan(receipts: [String] = [], jobs: [LaunchJob] = [], processes: [ProcessSnapshot] = [],
              certs: [InstalledCertificate] = [], sysext: [SystemExtensionInfo] = [], files: Set<String> = []) -> [String: DetectedProduct] {
        let inputs = ScanInputs(receipts: receipts, jobs: jobs, processes: processes, certificates: certs,
                                systemExtensions: sysext, fileExists: { files.contains($0) },
                                jobStatus: { $0 }, findBundles: { _, _ in [] })
        return Dictionary(uniqueKeysWithValues: DetectionEngine.scan(ProductRegistry.builtIn, inputs: inputs).map { ($0.id, $0) })
    }

    // MARK: Products

    func testTouchEnNxKey() {
        let r = scan(receipts: ["com.raonsecure.pkg.nxkey"],
                     jobs: [job("com.raon.agent.touchen.nxkey", "/Library/LaunchAgents/com.raon.agent.touchen.nxkey.plist"),
                            job("com.raon.touchen.UserAgent", "/Library/LaunchAgents/com.raon.touchen.UserAgent.plist"),
                            job("com.raon.touchen.nxkey", "/Library/LaunchDaemons/com.raon.touchen.nxkey.plist", system: true)],
                     files: ["/Library/Extensions/TKVHD.kext", "/Library/Internet Plug-Ins/npraontouchenex.plugin",
                             "/Applications/TouchEn nxKey"])
        let p = try! XCTUnwrap(r["touchen-nxkey"])
        XCTAssertEqual(p.launchJobs.count, 3)
        XCTAssertEqual(p.kernelExtensions, ["/Library/Extensions/TKVHD.kext"])
        XCTAssertEqual(p.extraPaths, ["/Library/Internet Plug-Ins/npraontouchenex.plugin"])
    }

    func testVeraportCAAndLeaf() {
        let ca = "CN=VERAPORT-CA,O=WIZVERA,C=KR"
        let r = scan(receipts: ["com.wizvera.vp20handler"],
                     jobs: [job("com.wizvera.veraport", "/Library/LaunchAgents/com.wizvera.veraport.plist",
                                program: "/Applications/Veraport/veraport.app/Contents/MacOS/veraport")],
                     processes: [proc(1082, "/Applications/Veraport/veraport.app/Contents/MacOS/veraport")],
                     certs: [cert(ca, cn: "VERAPORT-CA"), cert("CN=127.0.0.1", issuer: ca, cn: "127.0.0.1"),
                             cert("CN=VERAPORT-CA,O=WIZVERA,C=KR2", cn: "lookalike")])
        let p = try! XCTUnwrap(r["wizvera-veraport"])
        XCTAssertEqual(Set(p.certificates.map(\.commonName)), ["VERAPORT-CA", "127.0.0.1"])
        XCTAssertEqual(p.processes.map(\.pid), [1082])
        XCTAssertNil(r["wizvera-delfino"], "Veraport evidence must not detect Delfino")
    }

    func testDelfino() {
        let ca = "CN=DELFINO-CA,O=WIZVERA,C=KR"
        let r = scan(receipts: ["com.wizvera.delfino"],
                     jobs: [job("com.wizvera.delfino", "/Library/LaunchAgents/com.wizvera.delfino.plist")],
                     certs: [cert(ca, cn: "DELFINO-CA"), cert("CN=127.0.0.1", issuer: ca, cn: "127.0.0.1")])
        XCTAssertEqual(r["wizvera-delfino"]?.certificates.count, 2)
        XCTAssertNil(r["wizvera-veraport"])
    }

    func testKeySharpNXBizDocumentedLabel() {
        let r = scan(jobs: [job("com.wizvera.keysharpbiz", "/Library/LaunchAgents/com.wizvera.keysharpbiz.plist")])
        XCTAssertNotNil(r["wizvera-keysharpbiz"])
    }

    func testCrossWebEX() {
        let ca = "CN=Initech Root Authority - CrossWeb EX,OU=PKI_DEV,O=INITECH,C=kr"
        let r = scan(receipts: ["kr.co.initech.pkg.CrossWebEX"],
                     jobs: [job("com.initech.INISAFECrossWebEXSvc", "/Library/LaunchAgents/com.initech.INISAFECrossWebEXSvc.plist")],
                     certs: [cert(ca, cn: "Initech Root Authority - CrossWeb EX"), cert("CN=localhost", issuer: ca, cn: "localhost")])
        XCTAssertEqual(r["initech-crosswebex"]?.certificates.count, 2)
    }

    func testCrossEXEscapedSubject() {
        let r = scan(receipts: ["kr.co.iniline.pkg.CrossEXServicePackage"],
                     jobs: [job("kr.co.iniline.crossex-service", Paths.expand("~/Library/LaunchAgents/kr.co.iniline.crossex-service.plist"), keepAlive: false)],
                     certs: [cert("CN=iniLINE CrossEX RootCA2,O=iniLINE Co.\\, Ltd.,L=Seoul,ST=Some-State,C=KR", cn: "iniLINE CrossEX RootCA2")])
        XCTAssertEqual(r["iniline-crossex"]?.certificates.count, 1)
    }

    func testAhnLabSafeTransactionAndV3IsIgnored() {
        let r = scan(receipts: ["com.ahnlab.astxd.pkg"],
                     jobs: [job("com.astx.firewall.Daemon", "/Library/LaunchDaemons/com.ahnlab.astxd.plist", system: true, program: "/tmp/astxd")],
                     processes: [proc(29514, "/Applications/AhnLab/ASTx/astxd", uid: 0),
                                 proc(4000, "/Applications/AhnLab/V3.app/Contents/MacOS/V3")],
                     certs: [cert("O=ASTxRoot2", cn: "ASTxRoot2")])
        let p = try! XCTUnwrap(r["ahnlab-astx"])
        XCTAssertEqual(p.processes.map(\.pid), [29514], "only the ASTx daemon, never other AhnLab products")
        XCTAssertEqual(p.certificates.count, 1)
    }

    func testIPinside() {
        let r = scan(receipts: ["com.interezen.IPinside"],
                     jobs: [job("com.interezen.nwsdaemon", "/Library/LaunchDaemons/com.interezen.nwsdaemon.plist", system: true)],
                     certs: [cert("C=KR,ST=SEOUL,L=SEOUL,O=INTEREZEN,OU=INTEREZEN,CN=INTEREZEN CA,emailAddress=HJKIM@INTEREZEN.CO.KR", cn: "INTEREZEN CA")])
        let p = try! XCTUnwrap(r["interezen-ipinside"])
        XCTAssertEqual(p.launchJobs.first?.domain, .system)
        XCTAssertEqual(p.certificates.count, 1)
    }

    func testMagicLineBothLabels() {
        let r = scan(jobs: [job("com.dreamsecurity.MagicLine4NX", "/Library/LaunchAgents/com.dreamsecurity.MagicLine4NX.plist"),
                            job("com.dreamsecurity.NTSMagicLineNP", "/Library/LaunchAgents/com.dreamsecurity.NTSMagicLineNP.plist")],
                     certs: [cert("CN=Dreamsecurity ROOT CA,O=Dreamsecurity Inc.,C=KR", cn: "Dreamsecurity ROOT CA")])
        XCTAssertEqual(r["dreamsecurity-magicline"]?.launchJobs.count, 2)
    }

    func testNProtectSystemExtensionRequiresTeam() {
        let good = SystemExtensionInfo(teamID: "R2PBZJ465V", bundleID: "com.nprotect.nosfw", version: "1.0/1", name: "nosfw", state: "activated waiting for user")
        let forged = SystemExtensionInfo(teamID: "AAAAAAAAAA", bundleID: "com.nprotect.nosfw", version: "1.0/1", name: "nosfw", state: "activated enabled")
        let r = scan(receipts: ["com.nprotect.nprotectOnlineSecurityV1.kernel.pkg"], sysext: [good, forged])
        XCTAssertEqual(r["inca-nprotect"]?.systemExtensions, [good])
    }

    func testAnySign4PCOldAndNewRoots() {
        let r = scan(receipts: ["com.softforum.anysign4pc"],
                     jobs: [job("com.softforum.anysign", "/Library/LaunchDaemons/com.softforum.anysign.plist", system: true)],
                     certs: [cert("CN=Hancom Secure Root Authority,OU=Research and development office,O=Hancom Secure Inc.,C=KR", cn: "Hancom Secure Root Authority"),
                             cert("CN=Hancom With Root Authority,OU=Research and development office,O=Hancom With Inc.,C=KR", cn: "Hancom With Root Authority")])
        XCTAssertEqual(r["softforum-anysign4pc"]?.certificates.count, 2)
    }

    func testInnorixLeftoverOnly() {
        let r = scan(receipts: ["com.innorix.innorixexagent.ca.pkg", "com.innorix.innorixexagent.register.pkg"],
                     certs: [cert("CN=INNORIX.CA,O=INNORIX,C=KR", cn: "INNORIX.CA")])
        let p = try! XCTUnwrap(r["innorix-ex"])
        XCTAssertTrue(p.isLeftover)
        XCTAssertEqual(p.receipts.count, 2)
    }

    func testCertificateOnlyProducts() {
        let login = CertificateInspector.loginKeychain
        let r = scan(certs: [cert("CN=RAON K CA,OU=Research and Development Division,O=RAONWIZ Inc.,C=KR", cn: "RAON K CA"),
                             cert("CN=Root,OU=SignKorea NA,O=Personal,C=KR", cn: "Root", keychain: login, admin: false, user: true),
                             cert("CN=Root,OU=MangoWire,O=Personal,C=KR", cn: "Root", keychain: login, admin: false, user: true),
                             cert("CN=Root,OU=Someone Else,O=Personal,C=KR", cn: "Root", keychain: login, admin: false, user: true)])
        XCTAssertNotNil(r["raonwiz-raonk"])
        XCTAssertEqual(r["signkorea-root"]?.certificates.count, 1)
        XCTAssertEqual(r["mangowire-root"]?.certificates.count, 1)
        XCTAssertEqual(r.count, 3, "an unknown 'Root' certificate must not be attributed to anyone")
    }

    func testNothingDetectedOnCleanInputs() {
        XCTAssertTrue(scan(processes: [proc(1, "/sbin/launchd", uid: 0)], files: ["/Applications/Safari.app"]).isEmpty)
    }

    // MARK: Uninstall plan for certificates and extensions

    func testPlanIncludesCertificatesAndExcludesExtensions() {
        let sysext = SystemExtensionInfo(teamID: "R2PBZJ465V", bundleID: "com.nprotect.nosfw", version: "1.0/1", name: "nosfw", state: "activated")
        let r = scan(certs: [cert("CN=RAON K CA,OU=Research and Development Division,O=RAONWIZ Inc.,C=KR", cn: "RAON K CA")],
                     sysext: [sysext])
        let raon = try! XCTUnwrap(r["raonwiz-raonk"])
        let plan = Uninstaller.plan(for: raon, among: Array(r.values))
        XCTAssertEqual(plan.items.map(\.kind), [.certificate])
        XCTAssertTrue(plan.items[0].requiresAdmin)
        XCTAssertEqual(plan.defaultSelection.count, 1)

        let nprotect = try! XCTUnwrap(r["inca-nprotect"])
        let nplan = Uninstaller.plan(for: nprotect, among: Array(r.values))
        XCTAssertTrue(nplan.items.isEmpty)
        XCTAssertEqual(nplan.excluded.count, 1, "system extensions are reported, never removed")
    }

    // MARK: Findings from the VM install → remove test (2026-11-08)

    func testOwnReceiptPathInsideAnotherProductsFolderIsNotShared() {
        let crossex = (name: "CrossEX Service", claims: Uninstaller.Claims(), roots: ["/Library/Application Support/iniLINE/CrossEX"])
        let sub = "/Library/Application Support/iniLINE/CrossEX/crosswebex"
        XCTAssertEqual(Uninstaller.sharedWith(sub, ourReceiptFiles: [sub + "/CrossExChrome.app"], others: [crossex]), [],
                       "CrossWeb EX's own subfolder is removable")
        XCTAssertEqual(Uninstaller.sharedWith(sub, ourReceiptFiles: [], others: [crossex]), ["CrossEX Service"],
                       "without receipt evidence it stays shared")
        XCTAssertEqual(Uninstaller.sharedWith("/Library/Application Support/iniLINE", ourReceiptFiles: [sub + "/x"], others: [crossex]),
                       ["CrossEX Service"], "a folder containing another product is always shared")
    }

    func testEmptyInstallFolderIsNotAnInstallation() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gk-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(DetectionEngine.isEmptyDirectory(dir.path))
        try Data().write(to: dir.appendingPathComponent("file"))
        XCTAssertFalse(DetectionEngine.isEmptyDirectory(dir.path))
        XCTAssertFalse(DetectionEngine.isEmptyDirectory("/nonexistent/gurakilla"))
    }

    func testLeftoversFoundInVMAreClaimed() {
        let def = Dictionary(uniqueKeysWithValues: ProductRegistry.builtIn.map { ($0.id, $0) })
        XCTAssertTrue(def["ahnlab-astx"]!.extraPaths.contains("/Library/Application Support/ahnlab/.{0D02314D-EC55-4D53-95FD-41183118B518}"))
        XCTAssertTrue(def["initech-crosswebex"]!.extraPaths.contains("/Library/Application Support/iniLINE/CrossEX/crosswebex"))
        XCTAssertTrue(def["softforum-anysign4pc"]!.extraPaths.contains("/Applications/SoftForum/Uninstaller_AnySign4PC.app"))
    }

    func testCertificateCommands() {
        let admin = cert("CN=X", cn: "X")
        let lines = CertificateInspector.removalLines(admin, backupPath: "/tmp/x.pem")
        XCTAssertEqual(lines.privileged.count, 2)
        // Delete before untrusting: the trust change can need a second macOS dialog (found in VM test).
        XCTAssertTrue(lines.privileged[0].contains("delete-certificate -Z 00X"))
        XCTAssertTrue(lines.privileged[1].contains("remove-trusted-cert -d"))
        XCTAssertTrue(lines.user.isEmpty)

        let user = cert("CN=Y", cn: "Y", keychain: CertificateInspector.loginKeychain, admin: false, user: true)
        let ul = CertificateInspector.removalLines(user, backupPath: "/tmp/y.pem")
        XCTAssertTrue(ul.privileged.isEmpty)
        XCTAssertEqual(ul.user.count, 2)
        XCTAssertEqual(ul.user[0][1], "delete-certificate")

        let restoreRoot = CertificateInspector.restoreCommand(backupPath: "/b.pem", keychain: sys, adminTrusted: true, userTrusted: false, selfSigned: true)
        XCTAssertEqual(restoreRoot.argv, ["/usr/bin/security", "add-trusted-cert", "-d", "-r", "trustRoot", "-k", sys, "/b.pem"])
        XCTAssertTrue(restoreRoot.admin)
        let restoreLeaf = CertificateInspector.restoreCommand(backupPath: "/b.pem", keychain: sys, adminTrusted: true, userTrusted: false, selfSigned: false)
        XCTAssertEqual(restoreLeaf.argv[4], "trustAsRoot")
    }

    // MARK: Parsers

    func testSystemExtensionParsing() {
        let out = """
        7 extension(s)
        --- com.apple.system_extension.network_extension
        enabled\tactive\tteamID\tbundleID (version)\tname\t[state]
        \t*\tR2PBZJ465V\tcom.nprotect.nosfw (1.0/1)\tnosfw\t[activated waiting for user]
        *\t*\tW5364U7YZB\tio.tailscale.ipn.macsys.network-extension (1.104.2/101.104.2)\tTailscale Network Extension\t[activated enabled]
        """
        let parsed = CertificateInspector.parseSystemExtensions(out)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].bundleID, "com.nprotect.nosfw")
        XCTAssertEqual(parsed[0].teamID, "R2PBZJ465V")
        XCTAssertEqual(parsed[0].state, "activated waiting for user")
    }

    func testOpenSSLAndPEMParsing() {
        let f = CertificateInspector.parseOpenSSL("subject= CN=INNORIX.CA,O=INNORIX,C=KR\nissuer= CN=INNORIX.CA,O=INNORIX,C=KR\nnotAfter=Jul  7 09:06:37 2028 GMT\n")
        XCTAssertEqual(f["subject"], "CN=INNORIX.CA,O=INNORIX,C=KR")
        XCTAssertEqual(f["notAfter"], "Jul  7 09:06:37 2028 GMT")
        let two = "-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----\nBBBB\n-----END CERTIFICATE-----\n"
        XCTAssertEqual(CertificateInspector.splitPEM(two).count, 2)
    }

    func testEveryBuiltInProductHasARegressionCase() {
        // Keep this list in sync when adding products: each needs a test above.
        let covered: Set = ["touchen-nxkey", "wizvera-veraport", "wizvera-delfino", "wizvera-keysharpbiz",
                            "initech-crosswebex", "iniline-crossex", "ahnlab-astx", "interezen-ipinside",
                            "dreamsecurity-magicline", "inca-nprotect", "softforum-anysign4pc", "innorix-ex",
                            "raonwiz-raonk", "signkorea-root", "mangowire-root"]
        XCTAssertEqual(Set(ProductRegistry.builtIn.map(\.id)), covered)
    }
}

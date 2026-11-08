import Foundation

/// Describes one product GuraKilla knows how to recognise.
/// Every field is an exact identifier — nothing here is substring-matched.
struct ProductDefinition: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var publisher: String
    var category: String?
    /// Apple Developer Team IDs the vendor signs with. When set, a signed
    /// binary from any other team is never attributed to this product.
    var teamIDs: [String]
    var bundleIDs: [String]
    var launchdLabels: [String]
    /// Package receipt IDs. A trailing `*` means "prefix", e.g. `com.vendor.pkg.*`.
    var receiptPatterns: [String]
    /// Directories or bundles that belong exclusively to this product.
    var installPaths: [String]
    /// Vendor-supplied uninstaller apps, in order of preference.
    var uninstallers: [String]
    /// RFC 2253 subjects of the vendor's root CAs. A certificate matches when its
    /// subject (the CA itself) or issuer (a leaf it signed) equals one of these.
    var certificateSubjects: [String]
    /// Kernel extensions the product installs. Reported, never removed.
    var kernelExtensions: [String]
    /// System extension bundle IDs. Reported, never removed (only the owning app can).
    var systemExtensionIDs: [String]
    /// Other files exclusively created by the product (e.g. symlinks made by install scripts).
    var extraPaths: [String]
    var notes: String?

    init(id: String, name: String, publisher: String, category: String? = nil,
         teamIDs: [String] = [], bundleIDs: [String] = [], launchdLabels: [String] = [],
         receiptPatterns: [String] = [], installPaths: [String] = [], uninstallers: [String] = [],
         certificateSubjects: [String] = [], kernelExtensions: [String] = [], systemExtensionIDs: [String] = [],
         extraPaths: [String] = [], notes: String? = nil) {
        self.id = id; self.name = name; self.publisher = publisher; self.category = category
        self.teamIDs = teamIDs; self.bundleIDs = bundleIDs; self.launchdLabels = launchdLabels
        self.receiptPatterns = receiptPatterns; self.installPaths = installPaths
        self.uninstallers = uninstallers; self.certificateSubjects = certificateSubjects
        self.kernelExtensions = kernelExtensions; self.systemExtensionIDs = systemExtensionIDs
        self.extraPaths = extraPaths; self.notes = notes
    }

    // Lenient decoding so user registry files may omit empty lists.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        publisher = try c.decode(String.self, forKey: .publisher)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        teamIDs = try c.decodeIfPresent([String].self, forKey: .teamIDs) ?? []
        bundleIDs = try c.decodeIfPresent([String].self, forKey: .bundleIDs) ?? []
        launchdLabels = try c.decodeIfPresent([String].self, forKey: .launchdLabels) ?? []
        receiptPatterns = try c.decodeIfPresent([String].self, forKey: .receiptPatterns) ?? []
        installPaths = try c.decodeIfPresent([String].self, forKey: .installPaths) ?? []
        uninstallers = try c.decodeIfPresent([String].self, forKey: .uninstallers) ?? []
        certificateSubjects = try c.decodeIfPresent([String].self, forKey: .certificateSubjects) ?? []
        kernelExtensions = try c.decodeIfPresent([String].self, forKey: .kernelExtensions) ?? []
        systemExtensionIDs = try c.decodeIfPresent([String].self, forKey: .systemExtensionIDs) ?? []
        extraPaths = try c.decodeIfPresent([String].self, forKey: .extraPaths) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    var expandedInstallPaths: [String] { installPaths.map(Paths.expand) }
    var expandedUninstallers: [String] { uninstallers.map(Paths.expand) }
    var expandedExtraPaths: [String] { extraPaths.map(Paths.expand) }

    func matchesCertificate(subject: String, issuer: String) -> Bool {
        certificateSubjects.contains(subject) || certificateSubjects.contains(issuer)
    }

    func matchesReceipt(_ receipt: String) -> Bool {
        receiptPatterns.contains { ProductRegistry.receipt(receipt, matches: $0) }
    }
}

enum ProductRegistry {
    /// Built-in definitions. Identifiers were taken from real installations
    /// (code signatures, launchd plists and package receipts).
    static let builtIn: [ProductDefinition] = [
        ProductDefinition(
            id: "touchen-nxkey", name: "TouchEn nxKey", publisher: "RaonSecure",
            category: "Keyboard protection",
            teamIDs: ["9TKT2BJHQF"],
            bundleIDs: ["com.raonsecure.TKAgent", "com.raonsecure.TKPref", "com.raon.touchen.UserAgent", "com.raonsecure.TKUninstall"],
            launchdLabels: ["com.raon.agent.touchen.nxkey", "com.raon.touchen.UserAgent", "com.raon.touchen.nxkey"],
            receiptPatterns: ["com.raonsecure.pkg.nxkey"],
            installPaths: ["/Applications/TouchEn nxKey", "/Library/Application Support/raonsecure/TouchEn nxKey"],
            uninstallers: ["/Applications/TouchEn nxKey/TKUninstall.app"],
            kernelExtensions: ["/Library/Extensions/TKVHD.kext", "/Library/Extensions/TKUKMD.kext"],
            extraPaths: ["/Library/Internet Plug-Ins/npraontouchenex.plugin"],
            notes: "Installs kernel extensions (TKVHD/TKUKMD) and runs the nested CrossEX installers, so CrossEX Service arrives with it. GuraKilla never unloads or deletes kernel extensions — use the vendor uninstaller for those."),
        ProductDefinition(
            id: "wizvera-veraport", name: "Veraport", publisher: "Wizvera",
            category: "Security module installer",
            teamIDs: ["C86MGS2A3T"],
            bundleIDs: ["com.wizvera.vp20handler"],
            launchdLabels: ["com.wizvera.veraport"],
            receiptPatterns: ["com.wizvera.vp20handler"],
            installPaths: ["/Applications/Veraport", "/Library/Application Support/wizvera/veraport"],
            uninstallers: ["/Applications/Veraport/Uninstaller.app", "/Applications/Veraport/VeraportUninstaller.app"],
            certificateSubjects: ["CN=VERAPORT-CA,O=WIZVERA,C=KR"],
            notes: "The installer adds a per-install VERAPORT-CA root and a 127.0.0.1 certificate to the System keychain as trusted. The vendor uninstaller script only removes the launchd plist; the app folder, receipt and certificates stay behind."),
        ProductDefinition(
            id: "wizvera-delfino", name: "Delfino", publisher: "Wizvera",
            category: "Digital certificate signing",
            teamIDs: ["C86MGS2A3T"],
            bundleIDs: ["com.wizvera.delfino"],
            launchdLabels: ["com.wizvera.delfino"],
            receiptPatterns: ["com.wizvera.delfino"],
            installPaths: ["/Applications/Delfino", "/Library/Application Support/wizvera/delfino"],
            uninstallers: ["/Applications/Delfino/DelfinoUninstaller.app"],
            certificateSubjects: ["CN=DELFINO-CA,O=WIZVERA,C=KR"],
            notes: "The installer adds a DELFINO-CA root and a 127.0.0.1 certificate as trusted, and quits Firefox (killall firefox) to update its certificate store."),
        ProductDefinition(
            id: "wizvera-keysharpbiz", name: "KeySharp NX Biz", publisher: "Wizvera",
            category: "Digital certificate signing",
            teamIDs: ["C86MGS2A3T"],
            launchdLabels: ["com.wizvera.keysharpbiz"],
            installPaths: ["/Applications/keysharpnxbiz"],
            notes: "Known from Wizvera's own uninstaller script (keysharpnxbiz.sh). Not observed on a test Mac yet."),
        ProductDefinition(
            id: "initech-crosswebex", name: "INISAFE CrossWeb EX", publisher: "Initech",
            category: "Digital certificate signing",
            teamIDs: ["BN4D26VM76"],
            bundleIDs: ["com.initech.INISAFECrossWebEXSvc"],
            launchdLabels: ["com.initech.INISAFECrossWebEXSvc"],
            receiptPatterns: ["kr.co.initech.pkg.CrossWebEX"],
            installPaths: ["/Applications/CrossWebEX", "/Library/Application Support/iniLINE/CrossWebEX",
                           "/Library/Frameworks/CrossWebEXFramework.framework"],
            uninstallers: ["/Applications/CrossWebEX/UnInstallCrossEX.app"],
            certificateSubjects: ["CN=Initech Root Authority - CrossWeb EX,OU=PKI_DEV,O=INITECH,C=kr"],
            // Installed by CrossWeb EX's own package inside CrossEX's folder (VM install/remove test, 2026-11-08).
            extraPaths: ["/Library/Application Support/iniLINE/CrossEX/crosswebex"],
            notes: "Adds the Initech root and a localhost certificate as trusted. The vendor script misspells NativeMessagingHosts, so its Firefox host manifest is never removed by the vendor uninstaller."),
        ProductDefinition(
            id: "iniline-crossex", name: "CrossEX Service", publisher: "iniLINE",
            category: "Browser extension bridge",
            teamIDs: ["W77CBPNBYQ"],
            launchdLabels: ["kr.co.iniline.crossex-service"],
            receiptPatterns: ["kr.co.iniline.pkg.CrossEXPackage", "kr.co.iniline.pkg.CrossEXServicePackage"],
            installPaths: ["/Applications/CrossEX", "/Library/Application Support/iniLINE/CrossEX"],
            uninstallers: ["/Applications/CrossEX/crossex/UnInstallCrossEXService.app",
                           "/Applications/CrossEX/touchenex/UnInstallCrossEX.app"],
            certificateSubjects: ["CN=iniLINE CrossEX RootCA2,O=iniLINE Co.\\, Ltd.,L=Seoul,ST=Some-State,C=KR"],
            notes: "Installed as a dependency of TouchEn nxKey and CrossWeb EX. Removing it may break those products."),
        ProductDefinition(
            id: "ahnlab-astx", name: "AhnLab Safe Transaction", publisher: "AhnLab",
            category: "Transaction protection",
            teamIDs: ["G99MLRF664"],
            bundleIDs: ["com.ahnlab.safetransaction.Agent", "com.ahnlab.safetransaction.Status"],
            launchdLabels: ["com.astx.firewall.Agent", "com.astx.firewall.Daemon"],
            receiptPatterns: ["com.ahnlab.astxagent.pkg", "com.ahnlab.astxd.pkg", "com.ahnlab.astx.AhnLab.pkg"],
            installPaths: ["/Applications/AhnLab/ASTx"],
            uninstallers: ["/Applications/AhnLab/ASTx/Uninstaller.app"],
            certificateSubjects: ["O=ASTxRoot2"],
            // Hidden state folder created by the installer; left behind otherwise (VM install/remove test, 2026-11-08).
            extraPaths: ["/Library/Application Support/ahnlab/.{0D02314D-EC55-4D53-95FD-41183118B518}"],
            notes: "The root daemon's launchd plist sets argv[0] to /tmp/astxd, so ps and Activity Monitor show a path that does not exist; the real executable is /Applications/AhnLab/ASTx/astxd. Other AhnLab products (such as V3) are never touched."),
        ProductDefinition(
            id: "interezen-ipinside", name: "IPinside LWS Agent", publisher: "Interezen",
            category: "Device fingerprinting",
            teamIDs: ["BQNTQCRV77"],
            bundleIDs: ["com.interezen.ipinside"],
            launchdLabels: ["com.interezen.nwsdaemon"],
            receiptPatterns: ["com.interezen.IPinside"],
            installPaths: ["/Applications/IPinside.app"],
            uninstallers: ["/Applications/IPinside.app"],
            certificateSubjects: ["C=KR,ST=SEOUL,L=SEOUL,O=INTEREZEN,OU=INTEREZEN,CN=INTEREZEN CA,emailAddress=HJKIM@INTEREZEN.CO.KR"],
            notes: "Runs as a root LaunchDaemon with KeepAlive. There is no separate uninstaller: per Woori Bank's official Mac removal guide, opening IPinside from Applications offers to remove it."),
        ProductDefinition(
            id: "dreamsecurity-magicline", name: "MagicLine4NX", publisher: "DreamSecurity",
            category: "Digital certificate signing",
            teamIDs: ["PVRBEFNNC6"],
            bundleIDs: ["com.dreamsecurity.NTSMagicLineNP"],
            launchdLabels: ["com.dreamsecurity.MagicLine4NX", "com.dreamsecurity.NTSMagicLineNP"],
            receiptPatterns: ["com.dreamsecurity.MagicLine4NX"],
            installPaths: ["/Applications/MagicLine4NX", "/Applications/NTSMagicLineNP", "/Applications/NTSMagicLineNP.app"],
            uninstallers: ["/Applications/MagicLine4NX/Uninstaller.app"],
            certificateSubjects: ["CN=Dreamsecurity ROOT CA,O=Dreamsecurity Inc.,C=KR"],
            notes: "The vendor uninstaller removes the app and launchd plists but not the package receipt or the Dreamsecurity root certificate."),
        ProductDefinition(
            id: "inca-nprotect", name: "nProtect Online Security", publisher: "INCA Internet",
            category: "Anti-keylogging / firewall",
            teamIDs: ["R2PBZJ465V"],
            bundleIDs: ["com.nprotect.nosmain", "com.nprotect.nosuiagt"],
            launchdLabels: ["com.nprotect.nosintgdmn"],
            receiptPatterns: ["com.nprotect.nprotectOnlineSecurityV1.*"],
            installPaths: ["/Applications/nProtect/nProtect Online Security V1"],
            uninstallers: ["/Applications/nProtect/nProtect Online Security V1/NOS/nosuninst.app"],
            certificateSubjects: ["CN=INCA Internet Co.\\, Ltd. G3,OU=INCA Internet Co.\\, Ltd. - For Authorized use only,O=INCA Internet Co.\\, Ltd.,C=KR"],
            systemExtensionIDs: ["com.nprotect.nosfw"],
            notes: "Installs a network system extension (com.nprotect.nosfw) and a kernel-extension package. GuraKilla reports these but never removes them — use the vendor uninstaller."),
        ProductDefinition(
            id: "softforum-anysign4pc", name: "AnySign4PC", publisher: "Hancom WITH (SoftForum)",
            category: "Digital certificate signing",
            teamIDs: ["5R777FVMKA"],
            bundleIDs: ["com.softforum.anysign4pc"],
            launchdLabels: ["com.softforum.anysign"],
            receiptPatterns: ["com.softforum.anysign4pc"],
            installPaths: ["/Applications/SoftForum/AnySign4PC.app", "/Applications/SoftForum/AnySignFirefox"],
            uninstallers: ["/Applications/SoftForum/Uninstaller_AnySign4PC.app"],
            certificateSubjects: ["CN=Hancom Secure Root Authority,OU=Research and development office,O=Hancom Secure Inc.,C=KR",
                                  "CN=Hancom With Root Authority,OU=Research and development office,O=Hancom With Inc.,C=KR"],
            // Created by postinstall, not in the receipt; left behind otherwise (VM install/remove test, 2026-11-08).
            extraPaths: ["/Applications/SoftForum/Uninstaller_AnySign4PC.app"],
            notes: "Runs a root LaunchDaemon (KeepAlive). The installer also sets security.enterprise_roots.enabled in every user's Firefox prefs.js; GuraKilla does not edit browser preferences."),
        ProductDefinition(
            id: "innorix-ex", name: "INNORIX EX Agent", publisher: "INNORIX",
            category: "File transfer agent",
            receiptPatterns: ["com.innorix.innorixexagent.*"],
            certificateSubjects: ["CN=INNORIX.CA,O=INNORIX,C=KR"],
            notes: "Installs into /tmp/INNORIX-EX, which macOS clears on restart. What usually remains is package receipts and a trusted INNORIX.CA root."),
        ProductDefinition(
            id: "raonwiz-raonk", name: "RAON K (certificate)", publisher: "RAONWIZ",
            category: "Web upload/editor component",
            certificateSubjects: ["CN=RAON K CA,OU=Research and Development Division,O=RAONWIZ Inc.,C=KR"],
            notes: "Only the trusted RAON K root CA was found. The component that installed it is not present."),
        ProductDefinition(
            id: "signkorea-root", name: "SignKorea local root", publisher: "SignKorea (KOSCOM)",
            category: "Certificate relay",
            certificateSubjects: ["CN=Root,OU=SignKorea NA,O=Personal,C=KR"],
            notes: "A per-user trusted root named \"Root\" (OU=SignKorea NA). The installing component is not identified yet."),
        ProductDefinition(
            id: "mangowire-root", name: "MangoWire local root", publisher: "MangoWire",
            category: "Security module",
            certificateSubjects: ["CN=Root,OU=MangoWire,O=Personal,C=KR"],
            notes: "A per-user trusted root named \"Root\" (OU=MangoWire). The installing component is not identified yet."),
    ]

    static var userRegistryURL: URL { Paths.support.appendingPathComponent("registry.json") }

    /// Built-ins plus optional user definitions from
    /// `~/Library/Application Support/GuraKilla/registry.json` (same schema, a JSON array).
    /// A user entry with the same `id` replaces the built-in one.
    static func load() -> [ProductDefinition] {
        var byID = Dictionary(uniqueKeysWithValues: builtIn.map { ($0.id, $0) })
        var order = builtIn.map(\.id)
        if let data = try? Data(contentsOf: userRegistryURL),
           let extra = try? JSONDecoder().decode([ProductDefinition].self, from: data) {
            for def in extra {
                if byID[def.id] == nil { order.append(def.id) }
                byID[def.id] = def
            }
        }
        return order.compactMap { byID[$0] }
    }

    static func receipt(_ receipt: String, matches pattern: String) -> Bool {
        if pattern.hasSuffix("*") { return receipt.hasPrefix(String(pattern.dropLast())) }
        return receipt == pattern
    }
}

enum Paths {
    static func expand(_ p: String) -> String { (p as NSString).expandingTildeInPath }

    static let support: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GuraKilla", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let logs: URL = {
        let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/GuraKilla", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// `path` equals `root` or lives inside it. Avoids `/Applications/Foo2` matching `/Applications/Foo`.
    static func isUnder(_ path: String, _ root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    static func isUnder(_ path: String, anyOf roots: [String]) -> Bool {
        roots.contains { isUnder(path, $0) }
    }
}

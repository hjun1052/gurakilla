# Compatibility matrix

Host: macOS 26.6.2 (25G83), Apple silicon (arm64), SIP enabled, Gatekeeper assessments disabled.

**V** = Verified on this Mac · **D** = Documented by an official bank/vendor source · **U** = Unverified

## Products × facts

| Product | Vendor / team | Arch | Min macOS | Installed here | Root process | Auto-start | Restarts on quit | Trusted root CA | Kext / sysext | Vendor uninstaller | GuraKilla support |
|---|---|---|---|---|---|---|---|---|---|---|---|
| TouchEn nxKey | RaonSecure / 9TKT2BJHQF | x86_64 (V) | — | yes, startup disabled (V) | TEK_Daemon (V, not running) | disabled (V) | n/a | no | TKVHD.kext present, not loaded (V) | yes (V) | detect, quit, startup, plan; kext reported only |
| Veraport G3 | Wizvera / C86MGS2A3T | x86_64 (V) | — | 3,8,6,6 (V) | no | yes (V) | **yes** (V) | VERAPORT-CA ×2 (V) | — | yes, plist only (V) | full + certificates |
| Delfino G3 | Wizvera / C86MGS2A3T | x86_64 (V) | — | 5.0.0.3 (V) | no | yes (V) | **yes** (V) | DELFINO-CA (V) | — | yes, plist only (V) | full + certificates |
| KeySharp NX Biz | Wizvera / C86MGS2A3T | U | U | no (V) | U | U | U | U | U | referenced (D) | detect by label/path (regression-tested) |
| INISAFE CrossWeb EX | Initech / BN4D26VM76 | x86_64 (V) | 10.11 (V) | 1.0.1 (V) | no | yes (V) | **yes** (V) | Initech root + localhost (V) | — | yes (V) | full + certificates |
| CrossEX Service | iniLINE / W77CBPNBYQ | U | U | yes (V) | no | at login (V) | no (V) | iniLINE RootCA2, valid to 2099 (V) | — | yes, two apps (V) | full; folders marked shared |
| AhnLab Safe Transaction | AhnLab / G99MLRF664 | universal (V) | 12.0 (V) | 152.0.39 (V) | astxd (V) | yes (V) | agent no (V), daemon U | ASTxRoot2 (V) | — | yes, removes its CA (V) | full; real path despite argv[0] spoof |
| IPinside LWS Agent | Interezen / BQNTQCRV77 | universal (V) | 10.11 (V) | 3.0.0.21 (V) | NWSDaemon (V) | yes (V) | U (root) | INTEREZEN CA (V) | — | the app itself (D, Woori guide) | full + certificates |
| MagicLine4NX | DreamSecurity / PVRBEFNNC6 | x86_64 (V) | 10.13 (V) | 1.0.0.20 (V) | no | yes (V) | **yes** (V) | Dreamsecurity ROOT CA (V) | — | yes (V) | full + certificates |
| nProtect Online Security | INCA / R2PBZJ465V | x86_64 (V) | 10.15 (V) | yes, 32 receipts (V) | nosintgdmn (V, not running) | yes (V) | n/a | INCA G3 (user) (V) | sysext com.nprotect.nosfw (V) | yes (V) | detect, plan; sysext reported only |
| AnySign4PC | Hancom WITH / 5R777FVMKA | universal (V) | — | leftover only (V) | AnySign.ex when installed (V, script) | daemon KeepAlive (V, script) | U | Hancom Secure (old, V) / Hancom With (new, V script) | — | yes (V, payload) | leftover cleanup + certificates |
| INNORIX EX Agent | INNORIX / — | U | U | leftover only (V) | U | U | U | INNORIX.CA (V) | — | gone (in /tmp) | leftover cleanup + certificate |
| RAON K | RAONWIZ / — | U | U | certificate only (V) | — | — | — | RAON K CA (V) | — | — | certificate cleanup |
| SignKorea local root | SignKorea | U | U | certificate only (V) | — | — | — | user-trusted (V) | — | — | certificate cleanup |
| MangoWire local root | MangoWire | U | U | certificate only (V) | — | — | — | user-trusted (V) | — | — | certificate cleanup |

Apple silicon note: the Intel-only products (TouchEn, Veraport, Delfino, CrossWeb EX, MagicLine4NX, nProtect) need
Rosetta 2. Their future after Apple's announced reduction of Rosetta support is **U** (not checked against Apple's
current documentation during this run).

## VM install → remove test

Fresh macOS 26.6.2 VM per product, official package, removed with GuraKilla (`vm-test/README.md`):

| Product | Installs on macOS 26 (arm64 + Rosetta) | Own root CA | Residue after GuraKilla |
|---|---|---|---|
| Veraport G3 (KB) | yes (V) | generated at install (V) | none (V) |
| Delfino G3 (KB) | yes (V) | generated at install (V) | none (V) |
| AhnLab Safe Transaction | yes (V) | shipped, ASTxRoot2 (V) | none (V) |
| INISAFE CrossWeb EX 3.3.3.3 | yes (V) | generated at install, 10-year (V) | empty folder + inert launchd override (V) |
| AnySign4PC 1.1.5.3 | yes (V) | shipped, Hancom With (V) | none (V) |
| TouchEn nxKey 1.0.0.18 | yes, also installs CrossEX Service (V) | CrossEX's RootCA2, shipped (V) | TKVHD.kext only (V) |

## Banks / services × products

From official bank pages and the JavaScript they load (fetched 2026-11-08). "Package" means a macOS download URL was
resolved and the file downloaded and verified.

| Site | Products referenced | macOS packages resolved |
|---|---|---|
| KB Kookmin Bank | Delfino G3, ASTx, Veraport (D) | veraport-g3.pkg, delfino-g3.pkg, astx.dmg (V) |
| Shinhan Bank (bizbank) | Veraport, TouchEn nxKey, CrossWeb EX (D); Delfino, KeySharp, nProtect, ASTx (U) | veraport-g3.pkg, TouchEn_nxKey_Installer.pkg, CrossWebEX_3.3.3.3.pkg (V) |
| Hana Bank | Veraport, Delfino G3, TouchEn nxKey (D); IPinside, CrossWeb EX, KSign, ASTx (U) | veraport-g3.pkg, delfino-g3.pkg, TouchEn_nxKey_Installer.pkg (V) |
| Woori Bank | AnySign4PC (Mac pkg), IPinside "security log collector" 3.0.0.3 (Mac guide), official Mac **removal** guide for IPinside (D); Veraport, ASTx, nProtect listed for Windows only (D) | anysign4pc_mac_universal.pkg — identical to SoftForum's (V); IPinside Mac link not published |
| NH Nonghyup Bank | ASTx (D, `astx2_run.js`); TouchEn nxKey, CrossWeb EX (U) | TouchEn path returned 404 |
| IBK Industrial Bank | TouchEn nxKey, Delfino G3, nProtect pluginfree (`nppfs`) (D) | TouchEn_nxKey_Installer.pkg (**no stapled notarization ticket**, V), delfino-g3.pkg (= Hana's, V) |
| KDB Korea Development Bank | required on Mac: **AhnLab Safe Transaction** and **AnySign** (D, rendered `www.kdb.co.kr/COSCSS17N10.act`); XecureKeypad (Hancom) referenced in scripts (D) | `astx.dmg` from safetx.ahnlab.com (= KB/NH, V); `anysign4pc_mac_universal.pkg` self-hosted, identical to SoftForum's (V); fallback `astx_offline.dmg`: 2018 build, Developer ID–signed, **not notarized** (V); XecureKeypad's `xk_install_mac_universal.pkg` URL returns an HTML error page |
| Korea Post Banking | AnySign4PC, EDotXPress, nProtect pluginfree `nppfs` (D, script includes) | AnySign package via SoftForum (V) |
| Hometax (NTS) | Veraport install guide (D); TouchEn, IPinside, MagicLine, nProtect (U) | not resolved: distributed through Veraport list |
| yessign / yeskey | TouchEn nx framework, KSCertRelay nx (D) | KSCertRelay_nx_Installer.pkg returned 404 |
| Government 24 (gov.kr → plus.gov.kr) | Mac page lists **AnySign4PC** (application encryption, signing), **ezCertForClient** (print anti-forgery), **ezPDFReader** (document viewer), **CertShareXFree** (certificate transfer) (D, rendered `plus.gov.kr/portal/scrtycntr/scrtyprgrm`) | AnySign: `anysign4pc_mac_universal.pkg` from its `anySignOld4PCInterface.js`, same package as SoftForum/Woori (D); the other three buttons download **Windows installers only**, even on Mac (`EzCertForClientNonV-5.0.0.5.exe`, `ezPDFReader_setup.exe`, `CertShare_Installer.exe` via `plus.gov.kr/api/portal/v1.0/rpstr/rpstrDwnld`) (V) |
| RaonSecure (vendor) | TouchEn nxKey download page (D) | — |
| cros.or.kr | AnySign4PC install page (D) | anysign4pc_mac_universal.pkg (V) |

## Method limits

- The ego-browser task space was held by the user during the run, so pages were fetched with ego-browser's Node
  `fetch()` instead of a rendered browser page. Woori and IBK were resolved from their static pages; KDB (blocks non-browser requests) and Gov24 (unreachable) still need a rendered browser. Rendering them in ego-browser is the next step.
- Bing and DuckDuckGo HTML results were used only to find official URLs. Every URL used as evidence is on a bank,
  government or vendor domain.
- Products were installed only in throwaway VMs, never on this Mac (see `vm-test/README.md`).

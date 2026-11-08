# Installations

How each macOS banking-security installer behaves, based on official installers
downloaded on 2026-11-08 and inspected **without installing them**, plus the
state of copies that were already installed on this Mac.

Evidence labels: **Verified** = observed on this Mac (installed files, or the
downloaded package's own contents and scripts) · **Documented** = official
vendor/bank page or script · **Unverified** = needs more testing.

## What was and wasn't done

| Step | Status |
|---|---|
| Official installers downloaded (13 files, SHA-256 in `downloads/manifest.json`) | Done |
| Developer ID signature + notarization checked (`pkgutil --check-signature`) | Done — all 13 validly signed; 12 carry a stapled notarization ticket, IBK's TouchEn package does not |
| Package metadata, payload file lists and install scripts read (`pkgutil --expand`, `lsbom`) | Done (`installers.json`) |
| Compared with what's already installed | Done (every product was already present, so a fresh install would have been an upgrade, not a clean test) |
| Installing a product | **Done in throwaway macOS VMs** (6 products, one fresh VM each), never on this Mac. Results and evidence: `vm-test/README.md`. |

Gatekeeper assessments are disabled on this Mac (`spctl --status` →
`assessments disabled`), so `spctl -a` cannot be used as a signature check here;
`pkgutil --check-signature` and `codesign` were used instead. **Verified**

## Common pattern (all Wizvera, Initech, AhnLab and Hancom installers)

Every one of these postinstall scripts runs, as root:

```sh
security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain <vendor CA>
```

Wizvera and Initech also add a `127.0.0.1` / `localhost` leaf certificate with `-r trustAsRoot`
and import the CA into Firefox's NSS databases with `certutil`. **Verified (scripts)**

This matches the baseline. **10 vendor root CAs are trusted system-wide** on this Mac, and two
more are trusted in the user domain. **Verified**

| CA (subject CN) | Installed by | Trust | Expires |
|---|---|---|---|
| VERAPORT-CA (×2, one per install) | Veraport | System | 2045, 2046 |
| DELFINO-CA | Delfino | System | 2046 |
| Initech Root Authority - CrossWeb EX | CrossWeb EX | System | 2036 |
| iniLINE CrossEX RootCA2 | CrossEX Service | System | **2099** |
| ASTxRoot2 | AhnLab Safe Transaction | System | 2038 |
| INTEREZEN CA | IPinside | System | 2029 |
| Dreamsecurity ROOT CA | MagicLine4NX | System | 2035 |
| Hancom Secure Root Authority | AnySign4PC (older version; app is gone) | System | 2036 |
| INNORIX.CA | INNORIX EX Agent (app is gone) | System | 2028 |
| RAON K CA | RAONWIZ RAON K (component not present) | System | 2027 |
| Root (OU=SignKorea NA) | unidentified SignKorea component | User | 2027 |
| Root (OU=MangoWire) | unidentified MangoWire component | User | 2027 |

A trusted root makes anything signed with its private key look secure to Safari and Chrome. The
Wizvera installers generate a new CA on every install, which is why two VERAPORT-CA roots exist.
In the VM test, VERAPORT-CA and DELFINO-CA started at the install minute and the Initech root expired exactly
10 years after install day, so **Wizvera and Initech generate their CA on the device at install**. ASTxRoot2,
Hancom With Root Authority and iniLINE CrossEX RootCA2 have fixed dates and ship inside the package. **Verified (VM)**

Adding Admin-domain trust needs macOS's own admin authentication even for root (`com.apple.trust-settings.admin`
= entitled or authenticate-admin). In the VM a repeat Veraport install hung in postinstall on `add-trusted-cert`
waiting for that dialog. **Verified (VM)**

## Per product

### Veraport G3 — Wizvera (team C86MGS2A3T)
- Sources: KB `download.kbstar.com/security/wizvera/veraport/g3/veraport-g3.pkg`, Hana
  `kebhana.com/wizvera/veraport/down/veraport-g3.pkg` (byte-identical, SHA-256 `41e14609…`),
  Shinhan `bizbank.shinhan.com/sw/wizvera/veraport/down/veraport-g3.pkg` (different build). **Documented** (bank JS) / **Verified** (download)
- Package `com.wizvera.vp20handler` → `/Applications/Veraport` (29 files). **Verified**
- preinstall: removes `/Library/Launch*/com.wizvera.veraport.plist`. postinstall: symlinks the
  plist into `/Library/LaunchAgents`, `launchctl load`, trusts VERAPORT-CA and a 127.0.0.1 cert,
  imports into Firefox NSS. **Verified (scripts)**
- Running: user agent `com.wizvera.veraport`, KeepAlive. **Verified**
- Binary is x86_64-only. **Verified**

### Delfino G3 — Wizvera (team C86MGS2A3T)
- Sources: KB `…/delfino/g3/delfino-g3.pkg` (version_g3 3,6,9,5), Hana `…/wizvera/delfino/down/g3/delfino-g3.pkg`. **Documented**
- Package `com.wizvera.delfino` → `/Applications/Delfino`. Same CA/leaf pattern as Veraport (DELFINO-CA).
  postinstall also runs **`killall firefox`**. **Verified (scripts)**
- Running: user agent `com.wizvera.delfino`, KeepAlive. **Verified**

### TouchEn nxKey — RaonSecure (team 9TKT2BJHQF)
- Sources: Shinhan `bizbank.shinhan.com/sw/TouchEn/raonnx/nxKey/module/TouchEn_nxKey_Installer.pkg`
  (exMacVer 1.0.0.18), Hana `sab.hanabank.com/raonnx/nxKey/module/TouchEn_nxKey_Installer.pkg` (1.0.0.13).
  NH's equivalent path returned 404. **Documented** / **Verified**
- The preinstall/postinstall are **compiled x86_64 programs**, not readable scripts. Their embedded strings include: **Verified (static strings; whether each runs is Unverified)**
  - `installer -pkg /Library/CrossEXService_Install.pkg` and `installer -pkg /Library/raon_touchenex_Install.pkg`:
    nested installers. This is why CrossEX Service arrives with TouchEn.
  - `cp -r /Library/TKVHD.kext /Library/Extensions/`, also `/System/Library/Extensions/`, and `kextload -b com.raon.touchen.VirtualHIDDevice`.
  - `sudo mount -uw /`: an attempt to make the system volume writable. That is blocked on any Mac with SIP and the sealed system volume (macOS 11+).
  - `launchctl bootstrap/enable gui/%s …touchen…`, creating the `npraontouchenex.plugin` symlink in `/Library/Internet Plug-Ins`.
- VM install confirmed the nested install: TouchEn's package also added CrossEX Service (2 receipts, user LaunchAgent,
  `/Applications/CrossEX`, browser host manifests, iniLINE CrossEX RootCA2 trusted until 2099) and copied TKVHD.kext into
  `/Library/Extensions`. **Verified (VM)**
- On this Mac: `/Library/Extensions/TKVHD.kext` exists (signed by team **Z4BS3F3UYR**, a different team from the app) but **is not loaded**.
  The staging copies in `/Library` (TEK_Daemon*, *.pkg, *.kext) were cleaned up. All three TouchEn launchd jobs are present but disabled/not loaded. **Verified**

### INISAFE CrossWeb EX — Initech (team BN4D26VM76)
- Source: Shinhan `bizbank.shinhan.com/sw/initech/extension/down/CrossWebEX_3.3.3.3.pkg`. **Documented**
- Package `kr.co.initech.pkg.CrossWebEX` (139 files, `hostArchitectures=x86_64`). Installs into `/Applications/CrossWebEX`,
  `/Library/Application Support/iniLINE/{CrossEX,CrossWebEX}`, `/Library/Frameworks/CrossWebEXFramework.framework`,
  NPAPI plug-ins in `/Library/Internet Plug-Ins`, and Chrome + Firefox native-messaging manifests. **Verified**
- postinstall `launchctl load -w` the agent, trusts the Initech root and a localhost cert, imports into Firefox. **Verified (scripts)**
- preinstall misspells `NaviteMessagingHosts`, so its cleanup of the Firefox manifest never matches. **Verified (scripts)**

### AhnLab Safe Transaction — AhnLab (team G99MLRF664)
- Source: `safetx.ahnlab.com/master/mac/astx.dmg` (used by KB and NH). KB states that on Mac only the
  personal firewall and device-information collection are supported. **Documented**
- DMG signed (Developer ID Application); inner `ASTx.pkg` notarized. Three packages: LaunchAgent plist,
  LaunchDaemon plist, `/Applications/AhnLab/ASTx` (197 files). postinstall loads both and trusts `cacert2.crt` (ASTxRoot2). **Verified**
- The root daemon's launchd plist sets `Program=/Applications/AhnLab/ASTx/astxd` but `ProgramArguments[0]=/tmp/astxd`.
  `ps` and Activity Monitor therefore show `/tmp/astxd`, a file that does not exist. The kernel (`proc_pidpath`) reports the real path. **Verified**
- Universal (x86_64 + arm64), macOS 12+. **Verified**

### AnySign4PC — Hancom WITH (team 5R777FVMKA)
- Source: `download.softforum.com/Published/AnySign/v1.1.5.0/anysign4pc_mac_universal.pkg`
  (from cros.or.kr's install page; Korea Post Banking loads the same interface script). **Documented**
- Package `com.softforum.anysign4pc` 1.1.5.3, x86_64 + arm64. postinstall moves `com.softforum.anysign.plist`
  into `/Library/LaunchDaemons` (root daemon, KeepAlive), trusts **"Hancom With Root Authority"**, imports it into every
  user's Firefox `cert8.db`, and **appends `security.enterprise_roots.enabled=true` to every user's Firefox `prefs.js`**. **Verified (scripts)**
- On this Mac the app is gone, but an older receipt (7.0.0) and the older "Hancom Secure Root Authority" remain. No Firefox profile has the pref. **Verified**

### Woori Bank and IBK (resolved in a second pass)
- Woori's security pages list **AnySign4PC** for Mac (`spot.wooribank.com/pot/jcc?...fileName=anysign4pc_mac_universal.pkg`), byte-identical
  to SoftForum's package, and **IPinside 3.0.0.3** as its "security log collector", with an official Mac install guide and an official
  **Mac removal guide** (open IPinside from Applications and confirm). Veraport, ASTx and nProtect are offered for Windows only there. **Documented** / **Verified** (download)
- IBK loads TouchEn nxKey, Delfino and INCA nProtect (`nppfs`). Its `TouchEn_nxKey_Installer.pkg` is Developer ID–signed (2023-02-27)
  but **has no stapled notarization ticket**, unlike every other package downloaded. Whether Apple holds an online ticket is **Unverified**.
  Its `delfino-g3.pkg` is identical to Hana's. **Verified**

### Products installed here but whose installer URL was not resolved
IPinside (Interezen), MagicLine4NX (DreamSecurity), nProtect Online Security (INCA), CrossEX Service (iniLINE; bundled inside
TouchEn). Bank pages fetch these through Veraport's server-side distribution list, which isn't visible in static page
code. Their behaviour is documented from the installed copies (`processes.json`, `launchd.json`). **Verified** (installed) / **Unverified** (installer)

## Behaviour summary (installed copies, observed 2026-11-08)

| Product | Processes (user) | Root processes | launchd | Starts automatically | Restarts after normal quit (SIGTERM) |
|---|---|---|---|---|---|
| Veraport | veraport | — | gui agent, KeepAlive | yes | **yes** (new PID within 5 s) |
| Delfino | delfino | — | gui agent, KeepAlive | yes | **yes** |
| CrossWeb EX | INISAFECrossWebEXSvc | — | gui agent, KeepAlive | yes | **yes** |
| MagicLine4NX | MagicLine4NX | — | gui agent, KeepAlive, Aqua only | yes | **yes** |
| CrossEX Service | CrossEXService (parent + child) | — | user `~/Library/LaunchAgents`, RunAtLoad | at login | no |
| AhnLab ASTx | astxAgent | astxd | gui agent + system daemon, RunAtLoad | yes | agent: no (exit 0) · daemon: not tested (root) |
| IPinside | — | NWSDaemon | system daemon, KeepAlive | yes | not tested (root) |
| nProtect | — (not running) | — | system daemon, RunAtLoad | yes | not running |
| TouchEn nxKey | — | — | 2 agents + 1 daemon, **all disabled** | no | n/a |

All rows **Verified**. Both agents that stayed down after the test were restarted with
`launchctl kickstart` to leave the Mac as it was.

Browser extensions: native-messaging host manifests for CrossWeb EX and TouchEn EX are registered for
Chrome and Firefox, but **no matching browser extension is installed** in any Chrome, Arc, Brave, Edge or
Firefox profile. **Verified**

Privileged helpers (`/Library/PrivilegedHelperTools`): none from these vendors. **Verified**

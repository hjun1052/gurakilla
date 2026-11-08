# Uninstallation

What each vendor provides for removal, what it actually removes (read from the
uninstaller's script or the commands embedded in its binary), and what should
be gone after a complete removal.

No vendor uninstaller was run: they are GUI apps that ask for a password in a
system dialog. "Removes" below means the uninstaller **contains** those commands.
GuraKilla's own removal **was** run after a fresh install of six products in
throwaway VMs; the expected end states below were checked against those runs
(`vm-test/README.md`).

Labels: **Verified** = observed on this Mac (file present, script read, hash
matched) · **Documented** = official vendor material · **Unverified** = predicted, not yet tested.

## Summary

| Product | Vendor uninstaller | Type | Removes receipt | Removes its root CA | Known gaps |
|---|---|---|---|---|---|
| TouchEn nxKey | `/Applications/TouchEn nxKey/TKUninstall.app` | compiled | no | no | Removes kexts only from `/System/Library/Extensions`. `/Library/Extensions/TKVHD.kext` (present here) is probably left behind. CrossEX is not removed. |
| Veraport | `/Applications/Veraport/Uninstaller.app` (KB/Hana) or `VeraportUninstaller.app` (Shinhan) | app + shell (`veraport.sh`) | no | no | Script only unloads and deletes the launchd plist. `/Applications/Veraport`, both VERAPORT-CA roots and the 127.0.0.1 certs stay. Script also references a wrong path (`/Applications/Delfino/veraport.app`). |
| Delfino | `/Applications/Delfino/DelfinoUninstaller.app` | app + shell (`delfino.sh`) | no | no | Same as Veraport: plist only. The same uninstaller app (identical scripts) ships with both products. |
| CrossWeb EX | `/Applications/CrossWebEX/UnInstallCrossEX.app` | app + shell | no | tries (`delete_certificate.sh`) | Firefox manifest path misspelled (`NaviteMessagingHosts`), so it stays. Certificate deletion runs as the user, so a System-keychain cert may not be removable without root (Unverified). |
| CrossEX Service | `/Applications/CrossEX/crossex/UnInstallCrossEXService.app` + `/Applications/CrossEX/touchenex/UnInstallCrossEX.app` | app + shell | no | no | Two separate uninstallers. Neither removes `kr.co.raon.touchenex.firefox.json`/`kr.co.iniline.crosswebex.firefox.json` or iniLINE CrossEX RootCA2. |
| AhnLab Safe Transaction | `/Applications/AhnLab/ASTx/Uninstaller.app` → `astxUninstall` | compiled | no | **yes**: `security delete-certificate -Z E6E5C1EB…`, matching the installed ASTxRoot2 exactly | Receipts remain. |
| IPinside LWS Agent | the app itself: open `/Applications/IPinside.app` → confirm → password (Woori Bank official Mac removal guide, **Documented**) | app | not checked | not checked | No separate uninstaller app; the daemon plist and INTEREZEN CA removal not verified. |
| MagicLine4NX | `/Applications/MagicLine4NX/Uninstaller.app` | AppleScript | no | no | Removes app, plists and both MagicLine processes; leaves receipt and Dreamsecurity ROOT CA. |
| nProtect Online Security | `…/NOS/nosuninst.app` | compiled | no | **yes**, by name (`security delete-certificate -c`) in System + login keychains | Has kext and system-extension handling. Effect on `com.nprotect.nosfw` not verified. |
| AnySign4PC | `/Applications/SoftForum/Uninstaller_AnySign4PC.app` | app | not checked | not checked | Firefox `prefs.js` change (`security.enterprise_roots.enabled`) is not reverted by anything we found. |
| INNORIX EX | `/tmp/INNORIX-EX/uninstall.app` (in `/tmp`, so gone after restart) | — | — | — | Here: 11 receipts and INNORIX.CA left; uninstaller no longer exists. |

Sources: script text / embedded strings read on this Mac (**Verified** as content, **Unverified** as runtime effect).

## GuraKilla removal, VM-verified (2026-11-08)

| Product | Residue after GuraKilla removal |
|---|---|
| Veraport, Delfino, AhnLab Safe Transaction, AnySign4PC | none **Verified (VM)** |
| INISAFE CrossWeb EX | empty `iniLINE/CrossEX` folder; inert launchd override entry **Verified (VM)** |
| TouchEn nxKey, then CrossEX Service | `TKVHD.kext` only (never removed by GuraKilla) **Verified (VM)** |

## Expected end state per product

After a complete removal, these should all be absent. Each line is what GuraKilla checks after a
removal (by rescanning) and what `tools/diff_inventory.py` compares.

### TouchEn nxKey
- Processes: TEK_Daemon (root), TEK_UserAgent, TKAgent
- launchd: `gui/<uid>/com.raon.agent.touchen.nxkey`, `gui/<uid>/com.raon.touchen.UserAgent`, `system/com.raon.touchen.nxkey`
- Files: `/Applications/TouchEn nxKey`, `/Library/Application Support/raonsecure/TouchEn nxKey`, the three plists,
  `/Library/Internet Plug-Ins/npraontouchenex.plugin`
- Kernel extensions: `/Library/Extensions/TKVHD.kext`, `TKUKMD.kext` (GuraKilla never removes these; vendor uninstaller or manual `kmutil` by the user)
- Receipt: `com.raonsecure.pkg.nxkey`
- **The installer also installs CrossEX Service** (see below). Remove it too unless CrossWeb EX needs it. **Verified (VM)**
- Shared, keep unless CrossEX is also removed: `/Library/Application Support/iniLINE/CrossEX/touchenex`, `/Applications/CrossEX/touchenex`

### Veraport / Delfino
- Processes: `veraport` / `delfino` (user)
- launchd: `gui/<uid>/com.wizvera.veraport` / `com.wizvera.delfino` (also check `/Library/LaunchDaemons` variant the scripts remove)
- Files: `/Applications/Veraport` / `/Applications/Delfino`, `/Library/Application Support/wizvera/{veraport,delfino}`
- Certificates: VERAPORT-CA (all copies) + `127.0.0.1` leafs issued by it / DELFINO-CA + its `127.0.0.1` leaf
- Receipts: `com.wizvera.vp20handler` / `com.wizvera.delfino`
- Firefox NSS entries for the CA (per profile). Not removed by GuraKilla (Unverified whether present)

### INISAFE CrossWeb EX
- Process: INISAFECrossWebEXSvc; launchd `gui/<uid>/com.initech.INISAFECrossWebEXSvc`
- Files: `/Applications/CrossWebEX`, `/Library/Application Support/iniLINE/CrossWebEX`, `/Library/Frameworks/CrossWebEXFramework.framework`,
  `/Library/Internet Plug-Ins/npCrossWebEXPlugin.plugin`, `npinilinecrosswebex.plugin`,
  `/Library/Google/Chrome/NativeMessagingHosts/kr.co.iniline.crosswebex.json`,
  `/Library/Application Support/Mozilla/NativeMessagingHosts/kr.co.iniline.crosswebex.firefox.json`
- Certificates: Initech Root Authority - CrossWeb EX + `localhost` leaf
- Receipt: `kr.co.initech.pkg.CrossWebEX`
- `/Library/Application Support/iniLINE/CrossEX/crosswebex`: inside CrossEX's folder but installed by this receipt, so removed with it **Verified (VM)**

### CrossEX Service
- Processes: CrossEXService (parent + forked child); launchd `gui/<uid>/kr.co.iniline.crossex-service` (in `~/Library/LaunchAgents`)
- Files: `/Applications/CrossEX`, `/Library/Application Support/iniLINE/CrossEX`, the two `kr.co.raon.touchenex*.json` manifests
- Certificate: iniLINE CrossEX RootCA2 (expires 2099)
- Receipts: `kr.co.iniline.pkg.CrossEXPackage`, `kr.co.iniline.pkg.CrossEXServicePackage`
- **Only remove after TouchEn nxKey and CrossWeb EX**, which depend on it. GuraKilla marks these folders as shared and leaves them unchecked.

### AhnLab Safe Transaction
- Processes: astxAgent (user), astxd (root, shown as `/tmp/astxd`)
- launchd: `gui/<uid>/com.astx.firewall.Agent`, `system/com.astx.firewall.Daemon` (plists `com.ahnlab.astxagent.plist`, `com.ahnlab.astxd.plist`)
- Files: `/Applications/AhnLab/ASTx` only (never the parent `/Applications/AhnLab`), and the hidden
  `/Library/Application Support/ahnlab/.{0D02314D-EC55-4D53-95FD-41183118B518}` the installer creates **Verified (VM)**
- Certificate: ASTxRoot2 (SHA-1 `E6E5C1EB1E19E4F89A0C37DDCDA50C8B6EDDDD8F`)
- Receipts: `com.ahnlab.astxagent.pkg`, `com.ahnlab.astxd.pkg`, `com.ahnlab.astx.AhnLab.pkg`

### IPinside LWS Agent
- Process: NWSDaemon (root); launchd `system/com.interezen.nwsdaemon`
- Files: `/Applications/IPinside.app`, `/Library/LaunchDaemons/com.interezen.nwsdaemon.plist`
- Certificate: INTEREZEN CA · Receipt: `com.interezen.IPinside`

### MagicLine4NX
- Process: MagicLine4NX (and NTSMagicLineNP on older installs)
- launchd: `gui/<uid>/com.dreamsecurity.MagicLine4NX`, `com.dreamsecurity.NTSMagicLineNP`
- Files: `/Applications/MagicLine4NX`, `/Applications/NTSMagicLineNP(.app)`
- Certificate: Dreamsecurity ROOT CA · Receipt: `com.dreamsecurity.MagicLine4NX`

### nProtect Online Security
- launchd: `system/com.nprotect.nosintgdmn`
- Files: `/Applications/nProtect/nProtect Online Security V1`
- System extension: `com.nprotect.nosfw` (team R2PBZJ465V). Only the vendor app can deactivate it.
- Certificates: INCA Internet G3 (user-trusted), PFS V2 (login keychain)
- Receipts: 32 × `com.nprotect.nprotectOnlineSecurityV1.*`

### AnySign4PC
- Process: AnySign.ex (root); launchd `system/com.softforum.anysign`
- Files: `/Applications/SoftForum/AnySign4PC.app`, `AnySignFirefox`, `Uninstaller_AnySign4PC.app` (created by postinstall, not in the receipt) **Verified (VM)**
- Certificates: Hancom With Root Authority (current), Hancom Secure Root Authority (older)
- Receipt: `com.softforum.anysign4pc`
- Not restored by anyone: `user_pref("security.enterprise_roots.enabled", true);` in Firefox `prefs.js`

## How GuraKilla removes things (after this research)

1. Recommends the vendor uninstaller when one exists.
2. Otherwise, or afterwards for leftovers, it builds a reviewable plan:
   - launchd jobs are unloaded, then processes asked to quit (root ones through one reviewed admin script)
   - files are **moved** into `~/.Trash/GuraKilla <date>/` with their original paths, never deleted
   - vendor certificates: the PEM is backed up to `~/Library/Application Support/GuraKilla/certificate-backups/`,
     then `security delete-certificate -Z <sha1>` runs, then `security remove-trusted-cert`. Deleting first matters:
     clearing Admin-domain trust needs macOS's own admin authentication even as root, which can show one more
     dialog; if that is cancelled the certificate is already gone. **Verified (VM)**
   - receipts are forgotten with `pkgutil --forget` (the only irreversible step, and labelled as such)
   - kernel and system extensions are listed under "Not touched", with the reason
   - anything another installed product also uses is unchecked by default
3. Every change goes to the audit log, and everything except receipts can be undone from Restore Settings.
   Certificates are re-added as `trustRoot` (CAs) or `trustAsRoot` (leaf certs), the same settings the vendor installers use.
   Custom per-policy trust constraints, if a vendor ever set them, are not reproduced. **Verified (code + tests)**

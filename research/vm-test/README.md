# VM install → remove test (2026-11-08)

Each product was installed from its official package into a **fresh, throwaway macOS VM**, then removed
with GuraKilla. A read-only inventory was taken before install, after install and after removal. Nothing
ran on the host Mac. Every result here is **Verified** (observed in the VM).

## Setup

| | |
|---|---|
| Host | macOS 26.6.2, Apple silicon |
| VM | `ghcr.io/cirruslabs/macos-tahoe-base:latest` (macOS 26.6.2 25G83, arm64, Rosetta 2 present) via [tart](https://github.com/cirruslabs/tart) 2.41.1 (Developer ID: Cirrus Labs, 9M2P8L4D89) |
| Isolation | one APFS clone of the base VM per product, deleted afterwards; repo shared read-only |
| Install | `sudo installer -pkg <official package> -target /` (ASTx: the pkg inside the official DMG) |
| Remove | `GuraKilla --remove <id> --yes --sudo`: same plan and executor as the Uninstall sheet, default selection |
| Inventory | `research/tools/inventory.py` at each step, compared with `research/tools/diff_inventory.py` |
| Scripts | `tools/vmrun.sh` (host) and `tools/guest_test.sh` (guest) |

`run1/` is the first pass. `run2/` repeats the products whose GuraKilla definition changed because of run1.
Each product folder has `diff-install.md` (what the installer added) and `diff-residue.md` (before
install vs after removal; empty = nothing left).

## Results

| Product (package) | Installer added | Left after GuraKilla removal, run1 | After fix, run2 |
|---|---|---|---|
| Veraport G3 (KB) | app, gui agent (KeepAlive), receipt, **VERAPORT-CA + 127.0.0.1** (system trust) | nothing | — |
| Delfino G3 (KB) | app, `/Library/Application Support/wizvera/delfino`, gui agent, receipt, **DELFINO-CA + 127.0.0.1** | nothing | — |
| AhnLab Safe Transaction (`astx.dmg`) | app, gui agent + root daemon (`/tmp/astxd` argv[0]), 3 receipts, **ASTxRoot2**, hidden `/Library/Application Support/ahnlab/.{0D02314D-…}` | the hidden folder | nothing |
| INISAFE CrossWeb EX 3.3.3.3 (Shinhan) | app, framework, 2 NPAPI plug-ins, Chrome + Firefox host manifests, gui agent, receipt, **Initech root + localhost**, `iniLINE/CrossEX/crosswebex` | `iniLINE/CrossEX/crosswebex` (was hidden as "shared with CrossEX"), launchd override entry | empty `iniLINE/CrossEX` folder, launchd override entry |
| AnySign4PC 1.1.5.3 (SoftForum) | app, root daemon (KeepAlive), receipt, **Hancom With Root Authority**, uninstaller app (not in receipt) | `Uninstaller_AnySign4PC.app` | nothing |
| TouchEn nxKey 1.0.0.18 (Shinhan) | app, 2 gui agents + root daemon, receipt, `npraontouchenex.plugin`, `/Library/Extensions/TKVHD.kext`, **and a whole second product: CrossEX Service** (2 receipts, user agent, `/Applications/CrossEX`, host manifests, **iniLINE CrossEX RootCA2**) | CrossEX Service (separate product, kept as shared), TKVHD.kext | after also removing CrossEX: **TKVHD.kext only** (by design; see below) |

Admin trust settings (`security dump-trust-settings -d`) were empty after every removal.

### What is left, and why

- **TKVHD.kext**: GuraKilla never removes kernel extensions (spec rule). It is not loaded, is signed by a
  different team (Z4BS3F3UYR), and should be removed with the vendor's `TKUninstall.app` or by the user.
- **launchd override `com.initech.INISAFECrossWebEXSvc = enabled`**: written by the vendor's `launchctl load -w`.
  launchctl can only flip it, not delete it; with the plist gone it has no effect.
- **Empty `/Library/Application Support/iniLINE/CrossEX`**: parent of the CrossWeb EX subfolder. GuraKilla
  leaves empty folders other products may share. It no longer reports an empty folder as an installed product.

## Findings

1. **Changing Admin-domain certificate trust needs a GUI admin authentication, even as root.** The
   authorization rule `com.apple.trust-settings.admin` is `entitled` or `authenticate-admin`. In the VM, the
   first trust changes after login went through (cached login credential), later ones opened a SecurityAgent
   dialog and waited. This hits the vendors' own installers too: a second Veraport install hung in its
   postinstall on `security add-trusted-cert -d`. **GuraKilla change:** certificates are now deleted from the
   System keychain *before* their trust setting is cleared. Deleting needs only root and removes the trust
   anchor, so if the extra macOS dialog is cancelled the certificate is already gone. In every run the trust
   settings still ended up empty. In the app this can mean one more macOS password dialog after GuraKilla's own.
2. **Wizvera and Initech generate their root CA on the device during install.** VERAPORT-CA and DELFINO-CA
   start at the install minute (valid about 20 years); the Initech root expires exactly 10 years after install day.
   Every install trusts a new CA, which explains the duplicate VERAPORT-CA on the host. ASTxRoot2 (2038),
   Hancom With (2045) and iniLINE CrossEX RootCA2 (2099) have fixed dates, so they ship inside the package.
3. **TouchEn nxKey silently installs CrossEX Service**, including a root CA trusted until 2099, a user
   LaunchAgent and browser host manifests. Removing TouchEn alone leaves all of that. GuraKilla shows CrossEX as
   its own product; remove both.
4. **Installed files outside the receipt**: ASTx's hidden state folder and AnySign's uninstaller app are created by
   scripts, so receipt-based cleanup misses them. Both are now in the registry.
5. **Vendor launchd plists without an XML header** (Wizvera): launchd accepts them, Python's plistlib does not.
   The research inventory script now falls back to `plutil`.
6. **LibreSSL prints `SHA256 Fingerprint=`** (uppercase), so the inventory script's certificate hashes were empty
   on stock macOS. Fixed; the diff tool now keys certificates by subject + expiry, which also works for older snapshots.

## Vendor uninstallers, then GuraKilla (`vendor/`)

The vendor uninstaller apps confirm with an `NSAlert` and elevate through `AuthorizationExecuteWithPrivileges`
(a password dialog), so they cannot run unattended. Instead, the **commands each uninstaller contains** were run
as root in a fresh VM right after install (`tools/guest_vendor.sh`): Wizvera's bundled `veraport.sh` / `delfino.sh`,
CrossWeb EX's embedded `launchctl unload` + `rm -r` line and its `delete_certificate.sh`, AhnLab's `astxUninstall`.
Then GuraKilla removed whatever was left. `diff-after-vendor.md` = vendor leftovers, `diff-final.md` = after GuraKilla.

| Product | Left by the vendor's uninstall logic | Left after GuraKilla |
|---|---|---|
| Veraport | app, receipt, **VERAPORT-CA + 127.0.0.1 still trusted system-wide** (script only unloads and deletes the launchd plist; its `chmod` points at a wrong path under `/Applications/Delfino`) | nothing |
| Delfino | app, `wizvera/delfino` folder, receipt, **DELFINO-CA + 127.0.0.1 still trusted** | nothing |
| CrossWeb EX | receipt, **localhost certificate still trusted** (its lookup feeds an empty hash to `security delete-certificate`), Firefox host manifest (misspelled `NaviteMessagingHosts`), launchd override. The Initech root itself was removed. | inert launchd override, empty `iniLINE/CrossEX` |
| AhnLab ASTx | everything: `astxUninstall` run as root without its GUI wrapper exited 0 and removed nothing (it likely needs arguments from `Uninstaller.app`) — **inconclusive** for the vendor tool | nothing |
| AnySign4PC | everything: its uninstaller is one compiled binary with no script to run — **not testable** headless | nothing |

Every predicted vendor gap in `../uninstallation.md` that could be exercised was confirmed: no Wizvera or Initech
uninstall logic forgets its receipt, and the Wizvera scripts leave both trusted roots. **Verified (VM)**

## Not covered

- The vendor GUI apps themselves (password dialog), TouchEn's compiled `TKUninstall` and AhnLab's/AnySign's GUI flows.
- IPinside, MagicLine4NX and nProtect: no official package URL was found (see `../installations.md`).
- Browsers were not installed in the VM, so Firefox NSS imports and AnySign's `prefs.js` change were not exercised.
- The GUI removal path (osascript administrator prompt) was not driven; the CLI uses the same plan and executor
  and differs only in how the admin script is authorized.

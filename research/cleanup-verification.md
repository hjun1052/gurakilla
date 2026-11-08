# Cleanup verification

**This Mac is not clean of banking security software, and nothing here claims
it is.** 11 products are installed or partly installed. 4 more exist only as
leftover certificates or receipts.

## 1. This research changed nothing on the Mac

`baseline.json` (01:04) and `post-research.json` (13:56, after all VM work) were captured with
`tools/inventory.py` and compared with `tools/diff_inventory.py`:

#### Inventory diff: `baseline-2026-11-08` (2026-11-08T01:04:39+0900) → `post-research-2026-11-08` (2026-11-08T13:56:18+0900)

### Package receipts

No change.

### launchd jobs

- **added** gui/501/com.example.unrelated-agent
- **added** gui/501/com.wizvera.delfino
- **added** gui/501/com.wizvera.veraport

### Certificates (by subject + expiry)

No change.

Trust changed:

- mkcert user@host (name): [] → ['admin']

### Non-system process executables

- **added** /Applications/Arc.app/Contents/Frameworks/ArcCore.framework/Helpers/Browser Helper (Aperitif Renderer).app/Contents/MacOS/Browser Helper (Aperitif Renderer)
- **added** /Applications/Arc.app/Contents/Frameworks/ArcCore.framework/Helpers/Browser Helper (Aperitif).app/Contents/MacOS/Browser Helper (Aperitif)
- **added** /Applications/Arc.app/Contents/MacOS/Arc
- **added** /Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/bin/swift-plugin-server
- **removed** /Applications/ego lite.app/Contents/Frameworks/ego Framework.framework/Versions/0.6.2.9/Helpers/ego Helper (Node).app/Contents/MacOS/ego Helper (Node)

### System extensions

No change.

### /Library/Extensions

No change.

### Vendor directories

No change.

### Browser native-messaging hosts

No change.

### GuraKilla detections

- **added** innorix-ex
- **added** mangowire-root
- **added** raonwiz-raonk
- **added** signkorea-root



Reading the diff: receipts, certificates, system and kernel extensions, vendor folders and browser hosts are
**identical**. **Verified** The rest is not a change:

- The two Wizvera launchd jobs and the certificate-trust line were already there; the baseline script could not read
  Wizvera's header-less plists and decoded a Korean certificate name differently (both script bugs, fixed).
- `com.example.unrelated-agent` and the process differences (Arc, Xcode, ego-browser) are unrelated to banking software.
- The GuraKilla rows are detection rules added during the research finding leftovers that were already there.

An earlier version of this check (01:32) reported "no certificate change" while certificate hashes were empty on
stock macOS (LibreSSL prints `SHA256 Fingerprint=`). The diff now keys certificates by subject + expiry, and the
result above was re-run with the fixed scripts.

During the research, six user-owned vendor agents were sent SIGTERM to test restart behaviour.
The four KeepAlive agents were restarted by launchd. The two that were not (CrossEX Service and the
ASTx agent) were restarted with `launchctl kickstart`. **Verified**

## 2. Install → remove cycles (throwaway VMs)

Six products were installed from official packages in fresh macOS 26.6.2 VMs and removed with GuraKilla
(`vm-test/README.md`, evidence in `vm-test/run1`, `vm-test/run2`). Residue = diff between "before install" and
"after removal":

| Product | Residue |
|---|---|
| Veraport, Delfino, AhnLab Safe Transaction, AnySign4PC | **none** |
| INISAFE CrossWeb EX | empty `/Library/Application Support/iniLINE/CrossEX`; launchd override entry `enabled` (inert, cannot be deleted with launchctl) |
| TouchEn nxKey + the CrossEX Service it installs | `/Library/Extensions/TKVHD.kext` (GuraKilla never removes kernel extensions) |

Three leftovers found in the first pass (ASTx hidden folder, CrossWeb EX's subfolder inside CrossEX's folder,
AnySign's uninstaller app) were fixed in GuraKilla and are gone in the second pass. **Verified (VM)**

Not covered: vendor uninstallers (GUI password dialogs), IPinside / MagicLine4NX / nProtect (no official package
found), Firefox profile changes (no browser in the VM). Those stay **Unverified**; predictions are in `uninstallation.md`.

## 3. Evidence of incomplete earlier cleanups (already on this Mac)

These artifacts belong to software whose app is gone. The install dates come from receipts.

| Leftover | Product | Since | Evidence | Risk |
|---|---|---|---|---|
| Trusted root `INNORIX.CA` + 11 receipts pointing at `/tmp/INNORIX-EX` | INNORIX EX Agent | 2024-10-15 / 2025-08-27 | Verified | System-trusted root with no owning app |
| Trusted root `Hancom Secure Root Authority` + receipt `com.softforum.anysign4pc` 7.0.0 | AnySign4PC (older) | 2026-02-11 | Verified | System-trusted root with no owning app |
| Trusted root `RAON K CA` | RAONWIZ RAON K | unknown | Verified | System-trusted root with no owning app |
| User-trusted `Root` (OU=SignKorea NA) | SignKorea component | unknown | Verified | Trusted for this user |
| User-trusted `Root` (OU=MangoWire) | MangoWire component | unknown | Verified | Trusted for this user |
| Second `VERAPORT-CA` + `127.0.0.1` | Veraport reinstall | ≈2025-12 / 2026-02 (20-year validity → issue dates) | Verified (dates inferred) | Each reinstall adds another trusted root; old ones are never removed |
| Native-messaging manifests (Chrome + Firefox) for CrossWeb EX and TouchEn EX | CrossEX / CrossWeb EX | — | Verified | Registered with no browser extension installed |
| NPAPI plug-ins `npraontouchenex`, `npCrossWebEXPlugin`, `npinilinecrosswebex` | TouchEn / CrossWeb EX | 2026-08 / 2026-10 | Verified | Dead technology; no current browser loads them |
| `/Library/Extensions/TKVHD.kext` (team Z4BS3F3UYR) | TouchEn nxKey | 2026-02-17 | Verified | Not loaded; would remain after the vendor uninstaller (Unverified) |
| ~40 self-signed `my-mac*.local` certificates in System keychain | **not attributed** | 2025–2026 | Verified | Not trusted; origin unknown (not linked to any vendor here) |
| Self-signed `localhost` (expires 2027-07-11), system-trusted | **not attributed** | — | Verified | Trusted; issuer is itself, no vendor marker, so GuraKilla does not claim it |

Shared items that must be kept while their dependants remain:
`/Library/Application Support/iniLINE/CrossEX` (TouchEn nxKey and CrossWeb EX install into it) and
`/Applications/CrossEX` (TouchEn). GuraKilla flags both as shared. CrossWeb EX's own `CrossEX/crosswebex` subfolder is not shared (its receipt installed it). **Verified (regression tests + VM)**

## 4. Recovery plan for leftovers

With GuraKilla (each step is reviewed, logged and, except receipts, reversible):

1. Open GuraKilla. Leftover products show as **Leftover** with a count under *Trusted CAs*.
2. Select one (for example *INNORIX EX Agent*) → **Uninstall…**. The plan lists its certificate and receipts.
3. **Move to Trash…** → review the admin script → authorize. Each certificate is backed up first.
4. To undo: **Restore Settings** → *Restore*. The certificate is re-added with its original trust kind.

Manual equivalent for one certificate (shown so the effect is clear, run only if you mean to):

```sh
security find-certificate -c "INNORIX.CA" -p /Library/Keychains/System.keychain > ~/innorix-ca-backup.pem
sudo security delete-certificate -Z <SHA-1> /Library/Keychains/System.keychain
sudo security remove-trusted-cert -d ~/innorix-ca-backup.pem   # macOS may ask for an admin password again
# undo: sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/innorix-ca-backup.pem
```

Kernel/system extensions: use the vendor uninstaller first. For a leftover kext, macOS only loads it if it was
approved, and removing it from `/Library/Extensions` needs admin rights and a restart. GuraKilla deliberately
does not do this.

## 5. How to repeat the cleanup verification

Automated, in throwaway VMs: `vm-test/tools/vmrun.sh` (needs tart). Manually, on a disposable machine:

```sh
cd research
python3 -I tools/inventory.py before.json --label before-<product>
# install one product from downloads/ (installer -pkg … -target /), then use it once
python3 -I tools/inventory.py installed.json --label installed-<product>
# run the vendor uninstaller, restart, then
python3 -I tools/inventory.py after.json --label after-<product>
python3 -I tools/diff_inventory.py before.json after.json   # everything listed here is a leftover
python3 -I tools/diff_inventory.py before.json installed.json # what the installer added
```

Only a diff that is empty, apart from unrelated processes, supports calling the product removed.

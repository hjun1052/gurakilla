# GuraKilla research — Korean banking security software on macOS

Captured 2026-11-08 on macOS 26.6.2 (Apple silicon). Every finding is labelled
**Verified** (observed on this Mac), **Documented** (official bank/vendor source)
or **Unverified** (needs more testing).

## Files

| File | What it is |
|---|---|
| `baseline.json` | Full read-only inventory before any work: processes + Team IDs, launchd jobs and state, overrides, receipts, bundles, system/kernel extensions, vendor folders, browser native-messaging hosts, certificates + trust, GuraKilla's scan |
| `post-research.json` | Same inventory after the research (for comparison) |
| `products.json` | Per-product facts: versions, official download URLs + SHA-256, signer, notarization, supported macOS, which banks use it |
| `processes.json` | Vendor processes with real executable path, argv[0], Team ID, root or not, managing launchd job |
| `launchd.json` | Vendor launchd jobs: plist, domain, program, RunAtLoad/KeepAlive, overrides, live state |
| `installers.json` | Static inspection of each downloaded installer: signature, packages, payload, script actions |
| `installations.md` | What each installer does; behaviour of installed copies (auto-start, restarts, root, extensions) |
| `uninstallation.md` | Vendor uninstallers, what they remove, gaps, and the expected end state per product |
| `cleanup-verification.md` | Before/after diff of this run, leftovers from earlier uninstalls, recovery plan, procedure for a real test |
| `compatibility-matrix.md` | Products × facts and banks × products |
| `vm-test/` | Install → GuraKilla removal of 6 products in throwaway macOS VMs: per-step inventories, diffs, logs, scripts |
| `raw/` | Bank pages and JavaScript as fetched (evidence for every Documented URL) |
| `downloads/` | Official installers (git-ignored; hashes in `downloads/manifest.json`) |
| `tools/` | Scripts to reproduce everything |

## Reproduce

```sh
# read-only inventory (needs the GuraKilla Debug build for the scan section)
python3 -I research/tools/inventory.py research/snapshot.json --label my-snapshot
python3 -I research/tools/diff_inventory.py research/baseline.json research/snapshot.json
python3 -I research/tools/extract.py research/snapshot.json research/

# bank pages → macOS package URLs (runs inside ego-browser's Node runtime)
ego-browser nodejs < research/tools/crawl.mjs

# static installer inspection (downloads/manifest.json must exist)
python3 -I research/tools/inspect_installers.py
```

## Headline findings

1. **Trusted root certificates are the biggest leftover.** Wizvera, Initech, AhnLab and Hancom installers all run
   `security add-trusted-cert -d -r trustRoot` into the System keychain. 10 vendor roots are trusted system-wide here,
   3 of them from software that is already gone, plus 2 user-trusted roots from unidentified components. Only the
   AhnLab and nProtect uninstallers try to remove their CA. GuraKilla now detects, removes (after backup) and restores them.
2. **No vendor uninstaller forgets its package receipt**, and the Wizvera uninstallers only remove the launchd plist.
3. **Four products are restarted by launchd within seconds of a normal quit** (Veraport, Delfino, CrossWeb EX, MagicLine4NX).
   Quitting alone does not stop them; disabling auto-start does.
4. **AhnLab's root daemon shows a fake path** (`/tmp/astxd`) in `ps` because its plist overrides argv[0].
5. **TouchEn nxKey's installer is a compiled program** that runs nested installers (CrossEX), copies kernel extensions
   and tries `mount -uw /`. A TKVHD.kext from it sits in `/Library/Extensions` (not loaded).
6. Six of the products are **Intel-only** and rely on Rosetta 2.
7. All 13 downloaded installers are Developer ID–signed and their Team IDs match the installed products. 12 are notarized; IBK's TouchEn package has no stapled ticket.
8. Woori publishes an official Mac removal procedure for IPinside: the app uninstalls itself when opened.
9. **VM test (6 products):** after GuraKilla's removal, Veraport, Delfino, ASTx and AnySign4PC leave nothing; CrossWeb EX leaves an
   empty folder and an inert launchd override; TouchEn leaves only its kernel extension (never removed by design). See `vm-test/`.
10. **Changing system certificate trust needs a GUI admin authentication even as root** (`com.apple.trust-settings.admin`).
    GuraKilla now deletes the certificate before clearing its trust, so a cancelled extra dialog leaves no trusted root behind.
11. **Wizvera and Initech create a new root CA on the device at every install.** TouchEn nxKey silently installs a second product
    (CrossEX Service) with a root CA trusted until 2099.

## Not done (and why)

- **Nothing was installed or uninstalled on this Mac.** Install → remove tests ran only in throwaway VMs (approved on 2026-11-08),
  so pre-existing software here was not touched. Vendor uninstallers were not run (they need a password typed into a system dialog).
- **Gov24** (resolved 2026-11-08, rendered in ego-browser): its Mac page lists AnySign4PC, ezCertForClient, ezPDFReader and
  CertShareXFree, but only AnySign4PC has a Mac package (already analysed and VM-tested); the other three download Windows `.exe` files.
- KDB's XecureKeypad is not in GuraKilla's registry: its Mac package URL returns an error page, so no identifiers could be verified.
- **KDB** (resolved 2026-11-08): requires AhnLab Safe Transaction and AnySign on Mac (both packages already analysed). It also
  hosts a 2018, non-notarized `astx_offline.dmg` fallback. XecureKeypad's Mac package URL returns an error page.
- **nProtect's Mac installer URL** is not in any bank's static scripts (likely returned by the server at runtime).

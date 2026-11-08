<img src="Design/logo.png" width="160" alt="GuraKilla logo">

# GuraKilla (구라킬라)

[한국어](README.md) | **English**

A native macOS utility for finding, inspecting, quitting, disabling and removing
Korean banking and government security software (TouchEn nxKey, Veraport,
Delfino, INISAFE CrossWeb EX, CrossEX, AhnLab Safe Transaction, IPinside,
MagicLine4NX, nProtect, AnySign4PC, and their leftovers) on your own Mac.

Swift + SwiftUI, macOS 26, Apple silicon and Intel. No dependencies.

## Download

Get the latest `.dmg` from [Releases](https://github.com/hjun1052/gurakilla/releases/latest). Requires macOS 26 or later
(universal). The app is ad-hoc signed and not notarized: open it the first time with right-click → Open, or
System Settings → Privacy & Security → Open Anyway.

## Build

```sh
xcodegen generate            # project.yml → GuraKilla.xcodeproj
xcodebuild -project GuraKilla.xcodeproj -scheme GuraKilla -configuration Release -derivedDataPath build build
open build/Build/Products/Release/GuraKilla.app
```

Tests (unit + one regression case per supported product):

```sh
xcodebuild -project GuraKilla.xcodeproj -scheme GuraKilla -destination 'platform=macOS,arch=arm64' -derivedDataPath build test
```

Read-only scan from the command line (JSON):

```sh
build/Build/Products/Release/GuraKilla.app/Contents/MacOS/GuraKilla --scan-json
```

Removal from the command line. It prints the same plan the Uninstall sheet shows and is a dry run unless you add `--yes`.
Admin steps use the macOS password dialog, or `sudo -n` with `--sudo` (fails instead of prompting if sudo isn't already authorized):

```sh
build/Build/Products/Release/GuraKilla.app/Contents/MacOS/GuraKilla --remove wizvera-veraport          # show plan
build/Build/Products/Release/GuraKilla.app/Contents/MacOS/GuraKilla --remove wizvera-veraport --yes    # do it
```

## What it does

- **Detects** products only by exact, verified identifiers: code-signing Team IDs, vendor install folders,
  launchd labels, package receipts, certificate subjects and system-extension IDs. No name guessing.
- **Shows** running processes (CPU, memory, PID, owner, real executable path), launchd jobs, auto-start state,
  trusted root certificates, kernel/system extensions, files and receipts.
- **Quit**: graceful first, PID re-verified to avoid touching the wrong process. Root-owned processes go through a
  reviewed admin prompt. It explains when launchd relaunches a KeepAlive job.
- **Manage Startup**: `launchctl disable/enable` (launchd's own override list; vendor files untouched). Separate from quitting.
- **Uninstall**: recommends the vendor uninstaller, or builds a reviewable plan. Files move to the Trash, vendor
  certificates are backed up before removal, shared items are unchecked, and kernel/system extensions are never touched.
- **Restore Settings**: undoes startup changes, moved files and removed certificates.
- **Audit log** at `~/Library/Logs/GuraKilla/audit.log`.

Admin actions always show the exact commands first, then use the standard macOS password prompt. Clearing a
certificate's system-wide trust is guarded by macOS itself, so it may ask once more; the certificate is deleted
before that step, so cancelling it leaves no trusted root behind.
GuraKilla never sees your password, and never touches SIP, Endpoint Security, MDM or Apple components.

## Languages

English and Korean (한국어). The app follows the macOS language order; to force Korean for GuraKilla only, use
System Settings › General › Language & Region › Applications. UI strings live in
`GuraKilla/Resources/Localizable.xcstrings`; publishers, categories and notes in `Products.xcstrings`. Product names
stay as the vendors write them (the same names Korean banks show). `--scan-json` and the `--remove` plan output stay in English;
audit log action codes are English, with details in the language the app was running in. `LocalizationTests` fails if a string has no Korean translation.

## Extending the registry

Add products without rebuilding: `~/Library/Application Support/GuraKilla/registry.json`, a JSON array with the
same fields as `ProductDefinition` in `GuraKilla/Engine/Registry.swift` (an entry with an existing `id` replaces it).

## Research

`research/` holds the evidence behind the registry: system baseline, official installer analysis, uninstaller
behaviour, cleanup verification, a compatibility matrix and install → remove tests of six products in throwaway
macOS VMs (`research/vm-test/`). Start with `research/README.md`.

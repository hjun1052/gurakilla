#!/bin/bash
# Host driver: fresh APFS clone of the base VM per product, run guest_test.sh, discard the clone.
# Needs tart (github.com/cirruslabs/tart) and a base VM: tart clone ghcr.io/cirruslabs/macos-tahoe-base:latest gk-test
# Build first: xcodebuild ... -configuration Debug -derivedDataPath build build
T=${TART:-tart}
REPO=$(cd "$(dirname "$0")/../../.." && pwd)
S=${OUT:-$REPO/research/vm-test/out}; mkdir -p "$S/vmout"; cp "$(dirname "$0")/guest_test.sh" "$S/vmout/"
while read -r ID PKG EXTRA; do
  [[ -z $ID ]] && continue
  echo "=== $ID start $(date +%T)"
  $T delete gk-run 2>/dev/null; $T clone gk-test gk-run
  $T run gk-run --no-graphics --dir=repo:$REPO:ro --dir=out:$S/vmout > $S/run-$ID.log 2>&1 &
  for i in $(seq 1 60); do $T exec gk-run true 2>/dev/null && break; sleep 5; done
  rm -rf "$S/vmout/$ID"
  $T exec gk-run /bin/bash "/Volumes/My Shared Files/out/guest_test.sh" "$ID" "$PKG" $EXTRA > $S/exec-$ID.log 2>&1
  echo "=== $ID end $(date +%T): $(tail -1 $S/vmout/$ID/steps.log 2>/dev/null)"
  $T stop gk-run; wait; $T delete gk-run
done <<LIST
ahnlab-astx ahnlab-astx/astx.dmg
initech-crosswebex shinhan-crosswebex/CrossWebEX_3.3.3.3.pkg
softforum-anysign4pc softforum-anysign4pc/anysign4pc_mac_universal.pkg
touchen-nxkey shinhan-touchen-nxkey/TouchEn_nxKey_Installer.pkg iniline-crossex
LIST
echo ALL_DONE

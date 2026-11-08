#!/bin/bash
# Runs inside the throwaway VM: install one product, snapshot, remove with GuraKilla, snapshot.
# usage: guest_test.sh <productID> <installer path relative to research/downloads>
set -u
ID=$1; PKG=$2
R="/Volumes/My Shared Files/repo"; O="/Volumes/My Shared Files/out/$ID"; mkdir -p "$O"
GK="$R/build/Build/Products/Debug/GuraKilla.app/Contents/MacOS/GuraKilla"
inv() { python3 -I "$R/research/tools/inventory.py" "$O/$1.json" --label "$ID-$1" > "$O/$1.inv.log" 2>&1; }
log() { echo "[$(date +%T)] $*" | tee -a "$O/steps.log"; }

trust() { sudo security dump-trust-settings -d > "$O/$1.trust-admin.txt" 2>&1; }
# Watchdog: macOS asks for admin authentication (SecurityAgent) for trust-setting changes even as root.
# Nobody can answer that dialog here, so cancel any such command stuck >60s and record it.
( while true; do
    ps -axo pid=,etime=,command= | awk '$3 == "/usr/bin/security" && ($4 == "add-trusted-cert" || $4 == "remove-trusted-cert")' | while read -r pid et cmd; do
      [[ $et == *:* ]] && secs=$(( 10#${et%%:*}*60 + 10#${et##*:} )) || secs=0
      [[ $et == *-* || $et == *:*:* ]] && secs=999
      if (( secs > 60 )); then echo "[$(date +%T)] cancelled stuck (needs admin auth dialog): $cmd" >> "$O/prompts.log"; sudo kill $pid; fi
    done; sleep 10; done ) &
WD=$!
log "snapshot before"; inv 0-before; trust 0-before
SRC="$R/research/downloads/$PKG"
if [[ $SRC == *.dmg ]]; then
  MNT=$(hdiutil attach -nobrowse -readonly "$SRC" | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)
  SRC=$(find "$MNT" -maxdepth 2 -name '*.pkg' | head -1)
fi
log "install $SRC"
sudo installer -pkg "$SRC" -target / > "$O/install.log" 2>&1; log "installer exit $?"
[[ -n ${MNT:-} ]] && hdiutil detach "$MNT" -quiet
sleep 30
log "snapshot installed"; inv 1-installed; trust 1-installed
"$GK" --scan-json > "$O/scan-installed.json" 2>&1
"$GK" --remove "$ID" > "$O/plan.txt" 2>&1
log "remove via GuraKilla"
"$GK" --remove "$ID" --yes --sudo > "$O/remove.log" 2>&1; log "remove exit $?"
for EXTRA in "${@:3}"; do  # products the installer brought along (TouchEn -> CrossEX)
  "$GK" --remove "$EXTRA" --yes --sudo > "$O/remove-$EXTRA.log" 2>&1; log "remove $EXTRA exit $?"
done
sleep 15
log "snapshot removed"; inv 2-removed; trust 2-removed
"$GK" --scan-json > "$O/scan-removed.json" 2>&1
cp ~/Library/Logs/GuraKilla/audit.log "$O/audit.log" 2>/dev/null
kill $WD; log done

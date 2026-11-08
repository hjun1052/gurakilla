#!/bin/bash
# Runs inside the throwaway VM: install one product, run the commands its vendor uninstaller
# contains (as root, without the vendor GUI), snapshot, then let GuraKilla clean up what is left.
# usage: guest_vendor.sh <productID> <installer path relative to research/downloads>
set -u
ID=$1; PKG=$2
R="/Volumes/My Shared Files/repo"; O="/Volumes/My Shared Files/out/vendor-$ID"; mkdir -p "$O"
GK="$R/build/Build/Products/Debug/GuraKilla.app/Contents/MacOS/GuraKilla"
inv() { python3 -I "$R/research/tools/inventory.py" "$O/$1.json" --label "vendor-$ID-$1" > "$O/$1.inv.log" 2>&1; }
trust() { sudo security dump-trust-settings -d > "$O/$1.trust-admin.txt" 2>&1; }
log() { echo "[$(date +%T)] $*" | tee -a "$O/steps.log"; }
to() { perl -e 'alarm 180; exec @ARGV' "$@"; }   # vendor tools may wait for GUI input
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
log "install $SRC"; sudo installer -pkg "$SRC" -target / > "$O/install.log" 2>&1; log "installer exit $?"
[[ -n ${MNT:-} ]] && hdiutil detach "$MNT" -quiet
sleep 30; log "snapshot installed"; inv 1-installed; trust 1-installed

log "vendor uninstall logic"
{
case $ID in
  wizvera-veraport) to sudo sh /Applications/Veraport/Uninstaller.app/Contents/Resources/veraport.sh ;;
  wizvera-delfino)  to sudo sh /Applications/Delfino/DelfinoUninstaller.app/Contents/Resources/delfino.sh ;;
  initech-crosswebex)
    launchctl unload /Library/LaunchAgents/com.initech.INISAFECrossWebEXSvc.plist
    to sudo sh /Applications/CrossWebEX/UnInstallCrossEX.app/Contents/Resources/delete_certificate.sh
    sudo /bin/rm -r /Library/Internet\ Plug-Ins/npinilinecrosswebex.plugin /Library/Google/Chrome/NativeMessagingHosts/kr.co.iniline.crosswebex.json /Library/Application\ Support/iniLINE/CrossEX/crosswebex /Library/Application\ Support/iniLINE/CrossWebEX /Library/Frameworks/CrossWebEXFramework.framework /Applications/CrossWebEX /Library/LaunchAgents/com.initech.INISAFECrossWebEXSvc.plist /Library/Internet\ Plug-Ins/npCrossWebEXPlugin.plugin ;;
  ahnlab-astx) to sudo /Applications/AhnLab/ASTx/astxUninstall ;;
  softforum-anysign4pc)
    U=/Applications/SoftForum/Uninstaller_AnySign4PC.app
    find "$U" -maxdepth 4 -type f \( -name '*.sh' -o -name '*.scpt' -o -path '*/MacOS/*' \) -print
    for s in $(find "$U" -maxdepth 4 -type f -name '*.sh'); do echo "running $s"; to sudo sh "$s"; done ;;
esac
echo "vendor exit $?"
} > "$O/vendor.log" 2>&1
log "vendor done: $(tail -1 "$O/vendor.log")"
sleep 15; log "snapshot after vendor"; inv 2-vendor; trust 2-vendor
"$GK" --scan-json > "$O/scan-after-vendor.json" 2>&1
if python3 -c "import json,sys; sys.exit(0 if any(p['id']=='$ID' for p in json.load(open('$O/scan-after-vendor.json'))['products']) else 1)"; then
  "$GK" --remove "$ID" > "$O/plan-leftovers.txt" 2>&1
  log "GuraKilla cleans leftovers"; "$GK" --remove "$ID" --yes --sudo > "$O/remove-leftovers.log" 2>&1; log "remove exit $?"
else log "GuraKilla: nothing left to remove"; fi
sleep 10; log "snapshot final"; inv 3-final; trust 3-final
kill $WD; log done

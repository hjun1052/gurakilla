#!/bin/zsh
# Build a drag-to-install DMG with a background image and fixed icon layout.
#
#   scripts/make-dmg.sh path/to/GuraKilla.app out.dmg
#
# Uses Finder (AppleScript) to save the window layout, so the first run asks
# for permission to control Finder.
set -euo pipefail

app=${1:?usage: make-dmg.sh <app> <out.dmg>}
dmg=${2:?usage: make-dmg.sh <app> <out.dmg>}
app=${app:A}; dmg=${dmg:A}
root=${0:A:h:h}

work=$(mktemp -d)
trap 'hdiutil detach -quiet "$mnt" 2>/dev/null || true; rm -rf "$work"' EXIT
mnt=""

mkdir -p "$work/src/.background"
cp -R "$app" "$work/src/"
ln -s /Applications "$work/src/Applications"
swift "$root/scripts/dmg-background.swift" "$work" >/dev/null
tiffutil -cathidpicheck "$work/background.png" "$work/background@2x.png" -out "$work/src/.background/background.tiff" >/dev/null 2>&1

hdiutil create -quiet -volname GuraKilla -srcfolder "$work/src" -fs HFS+ -format UDRW -size 100m "$work/rw.dmg"
mnt=$(hdiutil attach -readwrite -noverify -noautoopen "$work/rw.dmg" | awk -F'\t' '/\/Volumes\//{print $NF}')

osascript <<EOF
tell application "Finder"
  -- By path: the user may have other "GuraKilla" volumes mounted.
  set d to item (POSIX file "$mnt" as alias)
  open d
  set w to container window of d
  set current view of w to icon view
  set toolbar visible of w to false
  set statusbar visible of w to false
  set bounds of w to {200, 120, 840, 578}
  set o to icon view options of w
  set arrangement of o to not arranged
  set icon size of o to 112
  set text size of o to 13
  set background picture of o to file ".background:background.tiff" of d
  set position of item "GuraKilla.app" of d to {160, 150}
  set position of item "Applications" of d to {480, 150}
  update d without registering applications
  delay 1
  close w
end tell
EOF

chflags hidden "$mnt/.background"
sync
hdiutil detach -quiet "$mnt"; mnt=""
rm -f "$dmg"
hdiutil convert -quiet "$work/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$dmg"
echo "$dmg"

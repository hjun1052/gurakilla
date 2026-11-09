#!/bin/zsh
# Build, package, sign and publish a release.
#
#   scripts/release.sh 1.0.2 notes.md
#
# Needs: xcodegen, gh (logged in), and the signing key in the Keychain (scripts/update-key.swift genkey).
# MARKETING_VERSION in project.yml must already be set to the version being released.
set -euo pipefail

version=${1:?usage: release.sh <version> <notes.md>}
: ${2:?usage: release.sh <version> <notes.md>}
notes=${2:A}
root=${0:A:h:h}
cd "$root"

grep -q "MARKETING_VERSION: \"$version\"" project.yml || { echo "project.yml is not at $version" >&2; exit 1; }
[[ -z $(git status --porcelain) ]] || { echo "working tree not clean" >&2; exit 1; }

out=$(mktemp -d)/release
mkdir -p "$out/dmgroot"
xcodegen generate >/dev/null
xcodebuild -project GuraKilla.xcodeproj -scheme GuraKilla -configuration Release \
  -derivedDataPath "$out/dd" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build -quiet
app="$out/dd/Build/Products/Release/GuraKilla.app"
codesign -v --strict "$app"

cd "$out"
zip="GuraKilla-$version.zip"; dmg="GuraKilla-$version.dmg"
ditto -c -k --keepParent "$app" "$zip"
cp -R "$app" dmgroot/ && ln -s /Applications dmgroot/Applications
hdiutil create -quiet -volname GuraKilla -srcfolder dmgroot -format UDZO "$dmg"
swift "$root/scripts/update-key.swift" sign "$zip" >/dev/null
shasum -a 256 "$dmg" "$zip" > SHA256SUMS.txt

gh release create "v$version" --repo hjun1052/gurakilla --title "GuraKilla $version" --notes-file "$notes" \
  "$dmg" "$zip" "$zip.sig" SHA256SUMS.txt
echo "released v$version from $out"

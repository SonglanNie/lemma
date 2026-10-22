#!/bin/zsh
# make-dmg.sh: packs build/Lemma.app into build/Lemma-<version>.dmg with an Applications shortcut and a note on opening
# an app that is not notarized. Signs the disk image when LEMMA_SIGN_IDENTITY is a Developer ID (then notarize it
# with scripts/notarize.sh). Run scripts/build-app.sh --universal first.
set -eu
cd "${0:A:h:h}"
app=build/Lemma.app
[[ -d $app ]] || { echo "Build the app first: scripts/build-app.sh --universal"; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/Lemma"
ditto "$app" "$staging/Lemma/Lemma.app"
ln -s /Applications "$staging/Lemma/Applications"
if [[ ${LEMMA_SIGN_IDENTITY:-} != "Developer ID Application:"* ]]; then
  cp scripts/dmg/Opening-Lemma.txt "$staging/Lemma/If macOS says it cannot verify Lemma.txt"
fi
output="build/Lemma-$version.dmg"
rm -f "$output"
hdiutil create -volname "Lemma $version" -srcfolder "$staging/Lemma" -ov -format UDZO -imagekey zlib-level=9 "$output" >/dev/null
if [[ ${LEMMA_SIGN_IDENTITY:-} == "Developer ID Application:"* ]]; then
  codesign --force --timestamp --sign "$LEMMA_SIGN_IDENTITY" "$output"
fi
# The same image under a fixed name, for the README's download link (releases/latest/download/Lemma.dmg).
cp "$output" build/Lemma.dmg
shasum -a 256 "$output"
echo "Made $output (and build/Lemma.dmg)"

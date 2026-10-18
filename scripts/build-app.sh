#!/bin/zsh
# build-app.sh [--universal]: builds build/Lemma.app (optimized: simulations and page analysis run far faster than in
# debug builds).
#   --universal               Apple silicon and Intel in one binary (what public releases ship).
#   LEMMA_SIGN_IDENTITY=…     a "Developer ID Application: …" identity: hardened runtime and a secure timestamp, ready
#                             for notarization (scripts/notarize.sh). Another name is a self-signed certificate trusted
#                             for code signing, which keeps one identity across releases. Without it the app is signed
#                             ad hoc, which runs on this Mac and, after "Open Anyway", on others.
set -eu
cd "${0:A:h:h}"
universal=0
for argument in "$@"; do
  case $argument in
    --universal) universal=1 ;;
    *) echo "unknown option $argument"; exit 2 ;;
  esac
done
mkdir -p Sources/Lemma/Resources/Assistant
cp browser/dom.js browser/content.js Sources/Lemma/Resources/Assistant/
arch_flags=()
(( universal )) && arch_flags=(--arch arm64 --arch x86_64)
swift build -c release $arch_flags
bin_dir="$(swift build -c release $arch_flags --show-bin-path)"
bundle_path="$PWD/build/Lemma.app"
# LemmaIndexer gets a background-only bundle of its own (Info.plist from package-app.py): PDFKit registers it with the
# window server, and from Contents/MacOS it would register as Lemma and get a second Lemma icon in the Dock.
helper_path="$bundle_path/Contents/Helpers/LemmaIndexer.app"
mkdir -p "$bundle_path/Contents/MacOS" "$bundle_path/Contents/Resources/Chrome Companion" "$helper_path/Contents/MacOS"
# Replace executables by rename, so a running Lemma, browser host or indexer keeps its own copy.
for name in Lemma LemmaBrowserHost; do
  cp "$bin_dir/$name" "$bundle_path/Contents/MacOS/.$name.new"
  mv -f "$bundle_path/Contents/MacOS/.$name.new" "$bundle_path/Contents/MacOS/$name"
done
cp "$bin_dir/LemmaIndexer" "$helper_path/Contents/MacOS/.LemmaIndexer.new"
mv -f "$helper_path/Contents/MacOS/.LemmaIndexer.new" "$helper_path/Contents/MacOS/LemmaIndexer"
rm -f "$bundle_path/Contents/MacOS/LemmaIndexer"
# Sparkle (in-app updates) in Contents/Frameworks, without the XPC services only a sandboxed app needs.
framework="$bundle_path/Contents/Frameworks/Sparkle.framework"
rm -rf "$framework"; mkdir -p "$bundle_path/Contents/Frameworks"
ditto "$bin_dir/Sparkle.framework" "$framework"
rm -rf "$framework/Versions/B/XPCServices" "$framework/XPCServices"
swift scripts/generate-icon.swift build/Lemma.iconset
iconutil -c icns build/Lemma.iconset -o "$bundle_path/Contents/Resources/Lemma.icns"
python3 scripts/package-app.py "$bundle_path"
identity=${LEMMA_SIGN_IDENTITY:--}
if [[ $identity == "Developer ID Application:"* ]]; then
  # Inside out, without --deep: Sparkle's helpers and framework, each helper, then the app, all with the hardened runtime
  # and a timestamp, as notarization requires.
  for code in "$framework/Versions/B/Autoupdate" "$framework/Versions/B/Updater.app" "$framework"; do
    codesign --force --options runtime --timestamp --sign "$identity" "$code"
  done
  for code in "$helper_path" "$bundle_path/Contents/MacOS/LemmaBrowserHost"; do
    codesign --force --options runtime --timestamp --entitlements scripts/Lemma.entitlements --sign "$identity" "$code"
  done
  codesign --force --options runtime --timestamp --entitlements scripts/Lemma.entitlements --sign "$identity" "$bundle_path"
else
  # Ad hoc ("-"), or a self-signed certificate, which keeps the same identity from one release to the next (macOS then
  # keeps the Keychain and folder permissions it gave the previous version).
  codesign --force --deep --sign "$identity" "$bundle_path"
fi
codesign --verify --deep --strict "$bundle_path"
# Notify macOS that the reused app bundle has new contents, including its icon.
touch "$bundle_path"
echo "Built $bundle_path ($(lipo -archs "$bundle_path/Contents/MacOS/Lemma"), signed: $identity)"

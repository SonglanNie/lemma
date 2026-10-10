#!/bin/zsh
# build-app.sh [--universal]: builds build/Lemma.app (optimized: simulations and page analysis run far faster than in
# debug builds).
#   --universal               Apple silicon and Intel in one binary (what public releases ship).
#   LEMMA_SIGN_IDENTITY=…     a "Developer ID Application: …" identity: hardened runtime and a secure timestamp, ready
#                             for notarization (scripts/notarize.sh). Without it the app is signed ad hoc, which runs on
#                             this Mac and, after "Open Anyway", on others.
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
mkdir -p "$bundle_path/Contents/MacOS" "$bundle_path/Contents/Resources/Chrome Companion"
# Replace executables by rename, so a running Lemma or browser host keeps its own copy.
for name in Lemma LemmaBrowserHost LemmaIndexer; do
  cp "$bin_dir/$name" "$bundle_path/Contents/MacOS/.$name.new"
  mv -f "$bundle_path/Contents/MacOS/.$name.new" "$bundle_path/Contents/MacOS/$name"
done
swift scripts/generate-icon.swift build/Lemma.iconset
iconutil -c icns build/Lemma.iconset -o "$bundle_path/Contents/Resources/Lemma.icns"
python3 scripts/package-app.py "$bundle_path"
identity=${LEMMA_SIGN_IDENTITY:--}
if [[ $identity == - ]]; then
  codesign --force --deep --sign - "$bundle_path"
else
  # Inside out, without --deep: each helper, then the app, all with the hardened runtime and a timestamp.
  for name in LemmaIndexer LemmaBrowserHost; do
    codesign --force --options runtime --timestamp --entitlements scripts/Lemma.entitlements --sign "$identity" "$bundle_path/Contents/MacOS/$name"
  done
  codesign --force --options runtime --timestamp --entitlements scripts/Lemma.entitlements --sign "$identity" "$bundle_path"
fi
codesign --verify --deep --strict "$bundle_path"
# Notify macOS that the reused app bundle has new contents, including its icon.
touch "$bundle_path"
echo "Built $bundle_path ($(lipo -archs "$bundle_path/Contents/MacOS/Lemma"), signed: $identity)"

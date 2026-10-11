#!/bin/zsh
# make-appcast.sh: writes build/appcast.xml for the disk image made by scripts/make-dmg.sh, signed with the project's
# EdDSA key, so that the Lemmas already installed offer the update (Sparkle). Publish it beside the disk image:
#   gh release create v<version> build/Lemma-<version>.dmg build/appcast.xml --notes-file …
# Installed copies read https://github.com/fus3r/lemma/releases/latest/download/appcast.xml, so only the latest release
# needs one. The update window shows this version's section of CHANGELOG.md.
#   SPARKLE_KEY_FILE   the private key exported with Sparkle's `generate_keys -x` (default:
#                      ~/.config/lemma-release/sparkle-ed25519.key). Keep it, and a copy of it, private.
set -eu
cd "${0:A:h:h}"
app=build/Lemma.app
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
dmg=build/Lemma-$version.dmg
[[ -f $dmg ]] || { echo "Make the disk image first: scripts/make-dmg.sh"; exit 1; }
key=${SPARKLE_KEY_FILE:-$HOME/.config/lemma-release/sparkle-ed25519.key}
[[ -f $key ]] || { echo "No Sparkle private key at $key (see docs/RELEASING.md)"; exit 1; }
tools=.build/artifacts/sparkle/Sparkle/bin
[[ -x $tools/generate_appcast ]] || swift package resolve
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
cp "$dmg" "$staging/"
# Release notes beside the archive, under its name, become the item's description.
python3 - "$version" "$staging/Lemma-$version.html" <<'PY'
import html, pathlib, re, sys
version, output = sys.argv[1], pathlib.Path(sys.argv[2])
changelog = pathlib.Path("CHANGELOG.md").read_text()
match = re.search(r"^## " + re.escape(version) + r"\b.*?\n(.*?)(?=^## )", changelog, re.S | re.M)
if not match:
    sys.exit(f"CHANGELOG.md has no section for {version}")
def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
    return re.sub(r"\[(.+?)\]\((.+?)\)", r'<a href="\2">\1</a>', text)
parts, items = [], []
for block in match.group(1).strip().split("\n\n"):
    lines = block.strip().splitlines()
    bullets = [line[2:] for line in lines if line.startswith("- ")]
    heading = [line for line in lines if not line.startswith("- ")]
    if heading:
        parts.append("<p>" + inline(" ".join(heading)) + "</p>")
    if bullets:
        parts.append("<ul>" + "".join("<li>" + inline(item) + "</li>" for item in bullets) + "</ul>")
output.write_text("<body>" + "\n".join(parts) + "</body>\n")
PY
"$tools/generate_appcast" --ed-key-file "$key" --download-url-prefix "https://github.com/fus3r/lemma/releases/download/v$version/" \
  --embed-release-notes --link "https://github.com/fus3r/lemma" -o build/appcast.xml "$staging"
echo "Wrote build/appcast.xml for Lemma $version"

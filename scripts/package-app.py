"""package-app.py <bundle> [--release]: package locally built native executables; no signing identity or publication.

Without --release the bundle is Lemma Dev (com.lemma.app.dev), with a support folder of its own: macOS never mistakes a
local build for the installed Lemma, and the two can run side by side without writing the same library."""
import json
import plistlib
import shutil
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
bundle = Path(sys.argv[1])
options = sys.argv[2:]
if options not in ([], ["--release"]):
    raise SystemExit(f"unknown options {options}")
release = options == ["--release"]
app_name = "Lemma" if release else "Lemma Dev"
identifier = "com.lemma.app" if release else "com.lemma.app.dev"
companion = bundle / "Contents/Resources/Chrome Companion"
identity = json.loads((root / "browser/identity.json").read_text())
manifest = json.loads((root / "browser/manifest.json").read_text())
manifest["key"] = identity["key"]
for name in ("background.js", "arxiv.js", "dom.js", "content.js", "identity.json"):
    shutil.copy2(root / "browser" / name, companion / name)
(companion / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
# Chrome's folder picker does not expose app bundle contents like ordinary folders.
visible_companion = bundle.parent / "Chrome Companion"
shutil.copytree(companion, visible_companion, dirs_exist_ok=True)
shutil.copytree(root / "Sources/Lemma/Resources/Math", bundle / "Contents/Resources/Math", dirs_exist_ok=True)
# 2.0: VS Code colour themes (with their licences) and the codicon font (CC BY 4.0).
for folder in ("Themes", "Codicons", "Assistant", "Sample", "Licenses"):
    shutil.copytree(root / "Sources/Lemma/Resources" / folder, bundle / "Contents/Resources" / folder, dirs_exist_ok=True)
shutil.copy2(root / "LICENSE", bundle / "Contents/Resources/LICENSE.txt")
info = {
    "CFBundleName": app_name, "CFBundleDisplayName": app_name,
    "CFBundleIdentifier": identifier, "CFBundleExecutable": "Lemma",
    # The folder in Application Support that holds the library (WorkspaceRepository.defaultRoot).
    "LemmaSupportFolder": app_name,
    "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "3.5.0-fork.2",
    "CFBundleVersion": "55", "LSMinimumSystemVersion": "15.0",
    "LSApplicationCategoryType": "public.app-category.education",
    "NSHighResolutionCapable": True,
    "CFBundleIconFile": "Lemma.icns",
    # 3.0: Lemma is offered in Finder's Open With menu for PDFs and accepts PDFs dropped on its Dock icon.
    "CFBundleDocumentTypes": [{"CFBundleTypeName": "PDF Document", "CFBundleTypeRole": "Viewer", "LSHandlerRank": "Alternate",
                               "LSItemContentTypes": ["com.adobe.pdf"]}],
    "NSHumanReadableCopyright": "Copyright © 2026 the Lemma contributors. Free software under the GNU GPL v3.",
    # 2.4: rows dragged inside the Library tree (between libraries, folders and sections).
    "UTExportedTypeDeclarations": [{"UTTypeIdentifier": "com.lemma.library-items", "UTTypeDescription": "Lemma Library items",
                                    "UTTypeConformsTo": ["public.data"], "UTTypeTagSpecification": {}}],
    # This fork publishes no Sparkle feed: without SUFeedURL, Sparkle stays off (Updates.isEnabled), so upstream releases,
    # which carry upstream's valid signature, cannot install over this build. Check for Updates… then only reports a newer
    # release of this fork (UpdateChecker) and opens its page.
    # Two free books of the catalog are served over plain HTTP by their authors (their HTTPS certificates are self-signed).
    "NSAppTransportSecurity": {"NSExceptionDomains": {
        "incompleteideas.net": {"NSExceptionAllowsInsecureHTTPLoads": True, "NSIncludesSubdomains": True},
        "web4.cs.ucl.ac.uk": {"NSExceptionAllowsInsecureHTTPLoads": True, "NSIncludesSubdomains": False},
    }},
}
# lemma://open?book=<fingerprint>&ref=Theorem%202.3 (or &page=<pdf page>) opens a place in a book from other apps. Only a
# release claims the scheme, so links always open the reader's library.
if release:
    info["CFBundleURLTypes"] = [{"CFBundleURLName": "com.lemma.app.link", "CFBundleURLSchemes": ["lemma"]}]
with (bundle / "Contents/Info.plist").open("wb") as file:
    plistlib.dump(info, file)
# 3.2.2: the helper that reads books has a bundle of its own (scripts/build-app.sh), background-only, so the Dock never
# shows it. In Contents/MacOS it took Lemma's identity and showed up as another Lemma.
helper = {
    "CFBundleName": "LemmaIndexer", "CFBundleIdentifier": f"{identifier}.indexer", "CFBundleExecutable": "LemmaIndexer",
    "CFBundlePackageType": "APPL", "CFBundleShortVersionString": info["CFBundleShortVersionString"],
    "CFBundleVersion": info["CFBundleVersion"], "LSMinimumSystemVersion": info["LSMinimumSystemVersion"],
    "LSBackgroundOnly": True,
}
with (bundle / "Contents/Helpers/LemmaIndexer.app/Contents/Info.plist").open("wb") as file:
    plistlib.dump(helper, file)

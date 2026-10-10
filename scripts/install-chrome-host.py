"""Register only Lemma's local native-messaging host for its fixed Chrome ID."""
import json
import os
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
app = Path(sys.argv[1]).expanduser().resolve() if len(sys.argv) > 1 else root / "build/Lemma.app"
host = app / "Contents/MacOS/LemmaBrowserHost"
companion = app / "Contents/Resources/Chrome Companion"
if not host.is_file() or not os.access(host, os.X_OK):
    raise SystemExit("Build Lemma.app first, then prepare the Chrome connection.")
identity = json.loads((companion / "identity.json").read_text())
manifest = {
    "name": "com.lemma.browser", "description": "Lemma study questions",
    "path": str(host), "type": "stdio",
    "allowed_origins": [f"chrome-extension://{identity['extensionID']}/"],
}
directory = Path.home() / "Library/Application Support/Google/Chrome/NativeMessagingHosts"
directory.mkdir(parents=True, exist_ok=True)
destination = directory / "com.lemma.browser.json"
temporary = destination.with_suffix(".json.tmp")
temporary.write_text(json.dumps(manifest, indent=2) + "\n")
temporary.chmod(0o600)
temporary.replace(destination)
print(f"Local host registered: {destination}")
visible_companion = app.parent / "Chrome Companion"
print(f"Load this unpacked extension folder once in Chrome: {visible_companion if visible_companion.is_dir() else companion}")

"""Refresh the offline renderer from the exact npm lockfile versions."""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parent.parent
target = root / "Sources/Lemma/Resources/Math"
target.mkdir(parents=True, exist_ok=True)
for source, name in [
    ("katex/dist/katex.min.js", "katex.min.js"),
    ("katex/dist/katex.min.css", "katex.min.css"),
    ("marked/lib/marked.umd.js", "marked.js"),
    ("dompurify/dist/purify.min.js", "purify.min.js"),
    ("katex/LICENSE", "KaTeX-LICENSE.txt"),
    ("marked/LICENSE", "Marked-LICENSE.txt"),
    ("dompurify/LICENSE", "DOMPurify-LICENSE.txt"),
]:
    shutil.copy2(root / "node_modules" / source, target / name)
shutil.copytree(root / "node_modules/katex/dist/fonts", target / "fonts", dirs_exist_ok=True)
print("Offline Markdown and math assets refreshed.")

"""Compares Lemma's detected definitions with labels read independently by Poppler.

Ground truth (an approximation): equation labels ending a laid-out line, and captions or
algorithm titles beginning one. Usage, after building the probe (see reference_probe.swift):
    python3 research/reference_coverage.py <pdf> <probe> [first last]
"""
import re
import subprocess
import sys

pdf, probe = sys.argv[1], sys.argv[2]
first, last = (sys.argv[3], sys.argv[4]) if len(sys.argv) > 4 else ("1", "100000")
layout = subprocess.run(["pdftotext", "-f", first, "-l", last, "-layout", pdf, "-"], capture_output=True, text=True).stdout
expected = {
    "Equation": set(re.findall(r"\(([1-9]\d?\.\d{1,3}[a-z]?)\)\s*$", layout, re.M)),
    "Figure": set(re.findall(r"^\s*FIGURE\s+([1-9]\d?\.\d{1,3}[a-z]?)\.", layout, re.M)),
    "Table": set(re.findall(r"^\s*TABLE\s+([1-9]\d?\.\d{1,3}[a-z]?)\.", layout, re.M)),
    "Algorithm": set(re.findall(r"^\s*Algorithm\s+([1-9]\d?\.\d{1,3}[a-z]?)\s+[A-Z]", layout, re.M)),
}
output = subprocess.run([probe, pdf, first, last], capture_output=True, text=True).stdout
found = {kind: set() for kind in expected}
for kind, number in re.findall(r"DEF (Equation|Figure|Table|Algorithm) \(?([0-9.]+[a-z]?)\)?", output):
    found[kind].add(number)
for kind in expected:
    missing = sorted(expected[kind] - found[kind], key=lambda s: [int(p) if p.isdigit() else p for p in re.split(r"[.]", s)])
    extra = sorted(found[kind] - expected[kind])
    print(f"{kind}: {len(expected[kind] & found[kind])} of {len(expected[kind])} found; missing {missing[:12]}{'…' if len(missing) > 12 else ''}; not in reference set {extra[:12]}")

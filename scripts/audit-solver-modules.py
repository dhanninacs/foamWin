#!/usr/bin/env python3
"""Compare source solver modules with a built Windows library directory."""
import argparse
from pathlib import Path
import re
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("libdir", type=Path, help="Windows runtime lib directory")
parser.add_argument(
    "--source", type=Path, default=Path(__file__).resolve().parents[1] / "OpenFOAM-14"
)
args = parser.parse_args()
modules = args.source / "applications" / "modules"
if not modules.is_dir() or not args.libdir.is_dir():
    parser.error("source modules and runtime lib directory must both exist")

pattern = re.compile(r"^LIB\s*=.*?/lib(\w+Solver)\s*$", re.MULTILINE)
expected = set()
for makefile in modules.glob("*/Make/files"):
    match = pattern.search(makefile.read_text(encoding="utf-8"))
    if match:
        expected.add("lib" + match.group(1) + ".dll")
if not expected:
    sys.exit("No solver modules found in the source tree")
present = {p.name.lower() for p in args.libdir.glob("*.dll")}
missing = sorted(name for name in expected if name.lower() not in present)
print(f"Solver modules present: {len(expected) - len(missing)}/{len(expected)}")
for name in missing:
    print(f"Missing: {name}")
sys.exit(bool(missing))

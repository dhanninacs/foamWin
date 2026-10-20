#!/bin/bash
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
SRC=${OF14_SOURCE:-$REPO/OpenFOAM-14}
OUT=${OF14_OUTPUT:-$REPO}
OPTIONS=linuxmingw-w64GccDPInt32Opt
CXX=${CXX:-x86_64-w64-mingw32-g++}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
STAGE=$(mktemp -d)
trap 'rm -rf -- "$STAGE"' EXIT
mkdir -p "$STAGE/OpenFOAM-14/platforms/$OPTIONS"
cp -a "$SRC/etc" "$SRC/COPYING" "$STAGE/OpenFOAM-14/"
# Ship runtime files only, preserving the dummy subdirectory.
(cd "$SRC/platforms/$OPTIONS" && find bin lib -type f \( -name '*.exe' -o -name '*.dll' \) -print0 | tar --null -T - -cf -) | tar -xf - -C "$STAGE/OpenFOAM-14/platforms/$OPTIONS"
BIN="$STAGE/OpenFOAM-14/platforms/$OPTIONS/bin"
# Resolve runtimes from the actual compiler, never silently omit them.
for dll in libgcc_s_seh-1.dll libstdc++-6.dll; do
    if [ -n "${WIN_RUNTIME_DIR:-}" ]; then runtime="$WIN_RUNTIME_DIR/$dll"
    else runtime=$("$CXX" -print-file-name="$dll"); fi
    test -f "$runtime" || { echo "Missing compiler runtime: $dll" >&2; exit 1; }
    cp "$runtime" "$BIN/"
done
EXT=${OF14_EXT_LIBBIN:-$REPO/platforms/linuxmingw-w64GccDPInt32/lib}
if [ ! -f "$BIN/libstack_trace.dll" ]; then cp "$EXT/libstack_trace.dll" "$BIN/"; fi
for dll in libgnurx-0.dll zlib1.dll; do
    test -f "$BIN/$dll" || { echo "Missing runtime: $dll" >&2; exit 1; }
done
FIXTURE=tutorials/legacy/incompressible/icoFoam/cavity/cavity
mkdir -p "$STAGE/OpenFOAM-14/$(dirname "$FIXTURE")"
cp -a "$SRC/$FIXTURE" "$STAGE/OpenFOAM-14/$FIXTURE"
cp "$REPO/installer/"{of14-shell.bat,of14-shell.ps1,of14-smoke-test.ps1,setup-openfoam14.ps1,LICENSE.txt,OF14-installer.nsi} "$STAGE/"
cp "$REPO/packaging/WINDOWS-README.md" "$STAGE/README.md"
mkdir -p "$STAGE/runtime-licenses"
cp /usr/share/doc/gcc-mingw-w64-x86-64-win32-runtime/copyright "$STAGE/runtime-licenses/gcc-mingw-w64.txt"
cp -a "$STAGE/runtime-licenses" "$STAGE/OpenFOAM-14/"
python3 "$REPO/scripts/verify-windows-imports.py" "$STAGE/OpenFOAM-14/platforms/$OPTIONS"
(cd "$STAGE" && makensis -V2 OF14-installer.nsi)
cp "$STAGE/OF14-win-setup.exe" "$OUT/"
(cd "$STAGE" && zip -qr "$STAGE/OF14-win.zip" OpenFOAM-14 of14-shell.bat of14-shell.ps1 of14-smoke-test.ps1 setup-openfoam14.ps1 README.md LICENSE.txt runtime-licenses)
cp "$STAGE/OF14-win.zip" "$OUT/"
echo "Created $OUT/OF14-win-setup.exe and $OUT/OF14-win.zip"

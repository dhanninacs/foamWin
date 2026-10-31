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
# A real partitioner supersedes the same-named dummy stub.  Remove only the
# staged stub so Windows has a single unambiguous DLL name; leave the build
# tree and its serial fallback untouched.
for name in libmetisDecomp.dll libscotchDecomp.dll; do
    if [ -f "$STAGE/OpenFOAM-14/platforms/$OPTIONS/lib/$name" ]; then
        rm -f -- "$STAGE/OpenFOAM-14/platforms/$OPTIONS/lib/dummy/$name"
    fi
done
BIN="$STAGE/OpenFOAM-14/platforms/$OPTIONS/bin"
# Resolve runtimes from the actual compiler, never silently omit them.
RUNTIMES="libgcc_s_seh-1.dll libstdc++-6.dll"
# cfMesh uses OpenMP, whose runtime needs winpthreads
[ -f "$BIN/cartesianMesh.exe" ] && RUNTIMES="$RUNTIMES libgomp-1.dll libwinpthread-1.dll"
for dll in $RUNTIMES; do
    if [ -n "${WIN_RUNTIME_DIR:-}" ]; then runtime="$WIN_RUNTIME_DIR/$dll"
    else runtime=$("$CXX" -print-file-name="$dll"); fi
    test -f "$runtime" || { echo "Missing compiler runtime: $dll" >&2; exit 1; }
    cp "$runtime" "$BIN/"
done
EXT=${OF14_EXT_LIBBIN:-$REPO/platforms/linuxmingw-w64GccDPInt32/lib}
if [ ! -f "$BIN/libstack_trace.dll" ] && [ -f "$EXT/libstack_trace.dll" ]; then cp "$EXT/libstack_trace.dll" "$BIN/"; fi
[ -f "$BIN/zlib1.dll" ] || cp "$EXT/zlib1.dll" "$BIN/"
for dll in zlib1.dll; do
    test -f "$BIN/$dll" || { echo "Missing runtime: $dll" >&2; exit 1; }
done
FIXTURE=tutorials/legacy/incompressible/icoFoam/cavity/cavity
mkdir -p "$STAGE/OpenFOAM-14/$(dirname "$FIXTURE")"
cp -a "$SRC/$FIXTURE" "$STAGE/OpenFOAM-14/$FIXTURE"
cp "$REPO/installer/"{of14-shell.bat,of14-shell.ps1,of14-smoke-test.ps1,of14-mesh-test.ps1,of14-cfmesh-test.ps1,of14-env.ps1,of14-runtime-test.ps1,setup-openfoam14.ps1,LICENSE.txt,OF14-installer.nsi} "$STAGE/"
mkdir -p "$STAGE/OpenFOAM-14/examples"
cp -a "$REPO/installer/parallel-mesh" "$STAGE/OpenFOAM-14/examples/parallelMesh"
cp -a "$REPO/installer/runtime-support" "$STAGE/OpenFOAM-14/examples/runtimeSupport"
cp -a "$REPO/installer/cfmesh-box" "$STAGE/OpenFOAM-14/examples/cfMeshBox"
mkdir -p "$STAGE/OpenFOAM-14/tutorials/incompressibleFluid"
cp -a "$SRC/tutorials/incompressibleFluid/cavity" "$STAGE/OpenFOAM-14/tutorials/incompressibleFluid/cavity"
cp "$REPO/packaging/WINDOWS-README.md" "$STAGE/README.md"
mkdir -p "$STAGE/runtime-licenses"
cp /usr/share/doc/gcc-mingw-w64-x86-64-win32-runtime/copyright "$STAGE/runtime-licenses/gcc-mingw-w64.txt"
# Real partitioners are linked from separately supplied third-party builds.
# Do not silently package them without the corresponding license notices.
if [ -f "$STAGE/OpenFOAM-14/platforms/$OPTIONS/lib/libscotchDecomp.dll" ] \
    || [ -f "$STAGE/OpenFOAM-14/platforms/$OPTIONS/lib/msmpi/libptscotchDecomp.dll" ]; then
    : "${SCOTCH_LICENSE_FILE:?Set SCOTCH_LICENSE_FILE to the Scotch license text}"
    test -f "$SCOTCH_LICENSE_FILE"
    mkdir -p "$STAGE/runtime-licenses/scotch"
    cp "$SCOTCH_LICENSE_FILE" "$STAGE/runtime-licenses/scotch/"
fi
if [ -f "$STAGE/OpenFOAM-14/platforms/$OPTIONS/lib/libmetisDecomp.dll" ]; then
    : "${METIS_LICENSE_FILE:?Set METIS_LICENSE_FILE to the METIS license text}"
    : "${GKLIB_NOTICES_DIR:?Set GKLIB_NOTICES_DIR to the GKlib license files}"
    test -f "$METIS_LICENSE_FILE"
    test -f "$GKLIB_NOTICES_DIR/LICENSE.txt"
    test -f "$GKLIB_NOTICES_DIR/LICENSES.md"
    test -d "$GKLIB_NOTICES_DIR/LICENSES"
    mkdir -p "$STAGE/runtime-licenses/metis" "$STAGE/runtime-licenses/gklib"
    cp "$METIS_LICENSE_FILE" "$STAGE/runtime-licenses/metis/"
    cp -a "$GKLIB_NOTICES_DIR/LICENSE.txt" "$GKLIB_NOTICES_DIR/LICENSES.md" \
        "$GKLIB_NOTICES_DIR/LICENSES" "$STAGE/runtime-licenses/gklib/"
fi
if [ -f "$STAGE/OpenFOAM-14/platforms/$OPTIONS/lib/msmpi/libzoltanDecomp.dll" ]; then
    : "${ZOLTAN_LICENSE_FILE:?Set ZOLTAN_LICENSE_FILE to the Zoltan license text}"
    test -f "$ZOLTAN_LICENSE_FILE"
    mkdir -p "$STAGE/runtime-licenses/zoltan"
    cp "$ZOLTAN_LICENSE_FILE" "$STAGE/runtime-licenses/zoltan/"
fi
cp -a "$STAGE/runtime-licenses" "$STAGE/OpenFOAM-14/"
python3 "$REPO/scripts/verify-windows-imports.py" "$STAGE/OpenFOAM-14/platforms/$OPTIONS"
python3 "$REPO/scripts/stage-gmsh.py" "$STAGE" --cache "${FOAMWIN_DOWNLOAD_CACHE:-$OUT/download-cache}"
(cd "$STAGE" && makensis -V2 OF14-installer.nsi)
cp "$STAGE/OF14-win-setup.exe" "$OUT/"
(cd "$STAGE" && zip -qr "$STAGE/OF14-win.zip" OpenFOAM-14 of14-shell.bat of14-shell.ps1 of14-smoke-test.ps1 of14-mesh-test.ps1 of14-cfmesh-test.ps1 of14-env.ps1 of14-runtime-test.ps1 setup-openfoam14.ps1 README.md LICENSE.txt runtime-licenses gmsh)
cp "$STAGE/OF14-win.zip" "$OUT/"
echo "Created $OUT/OF14-win-setup.exe and $OUT/OF14-win.zip"

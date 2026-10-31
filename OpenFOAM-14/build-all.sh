#!/bin/bash
# =============================================================================
# build-all.sh — Full cross-compile of OpenFOAM 14 for Windows (MinGW-w64)
# Reproduces the blueCFD-style build from a clean tree.
# Run from: .../OF14_windows/build/of14-win/OpenFOAM-14
# =============================================================================
set -e
cd "${0%/*}"

source etc/pre-bashrc-mingw_w64.sh
export WM_THIRD_PARTY_DIR=$(cd .. && pwd)
export FOAM_EXT_LIBBIN=$WM_THIRD_PARTY_DIR/platforms/linuxmingw-w64GccDPInt32/lib
mkdir -p "$FOAM_EXT_LIBBIN"

# ---- Host tools (native Linux) -------------------------------------------
(cd wmake/src && make cc="gcc")

# ---- Third-party ----------------------------------------------------------
mkdir -p "$WM_THIRD_PARTY_DIR/stack_trace/lnInclude"
cp "$WM_THIRD_PARTY_DIR/third-party/stack_trace/stack_trace.h" "$WM_THIRD_PARTY_DIR/stack_trace/lnInclude/"
(cd "$WM_THIRD_PARTY_DIR/third-party/stack_trace" && wmake lib)

# ---- Core: Pstream static -> OSspecific -> OpenFOAM -> Pstream dll -------
(cd src/Pstream/dummy && wmake lib)
(cd src/OSspecific/MSwindows && wmake lib)
cp /usr/include/FlexLexer.h src/OpenFOAM/lnInclude/ 2>/dev/null || true
(cd src && wmake libso OpenFOAM)
(cd src/Pstream/dummy && wmake libso)
rm -f "$FOAM_LIBBIN"/libOpenFOAM.*
(cd src && wmake libso OpenFOAM)
(cd src/OSspecific/MSwindows/stubLibrary && wmake libso)

# ---- Remaining libraries, in upstream src/Allwmake order ------------------
# wmake is incremental, so the core libraries above are not rebuilt. Some
# upstream libraries do not build on MinGW yet, so Allwmake continues past a
# failure and the required-library check below decides the result.
# A Windows DLL must resolve every symbol at link time, but upstream orders
# some libraries before their dependencies (dummyThirdParty before
# decompositionMethods), so a second pass links what the first could not.
for pass in 1 2; do
    (cd src && WM_CONTINUE_ON_ERROR=1 ./Allwmake -j "${WM_NCOMPPROCS:-$(nproc)}") || true
done

# ---- Check ------------------------------------------------------------------
# build-required-libs.txt lists every src library the Windows packages need.
missing=()
while read -r lib; do
    [ -f "$FOAM_LIBBIN/$lib.dll" ] || [ -f "$FOAM_LIBBIN/dummy/$lib.dll" ] \
        || missing+=("$lib")
done < build-required-libs.txt

echo "=== Library build complete: $(ls "$FOAM_LIBBIN"/*.dll | wc -l) libraries ==="
if [ "${#missing[@]}" -gt 0 ]; then
    echo "=== Required libraries that did not build ==="
    printf '  %s\n' "${missing[@]}"
    exit 1
fi

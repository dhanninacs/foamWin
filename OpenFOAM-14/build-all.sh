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

build() {
    local lib="$1"; shift
    echo "=== Building $lib ==="
    if ! wmake "$@" "$lib" 2>&1 | grep -E "error:|undefined reference"; then
        echo "--- $lib OK"
    fi
}

# ---- Host tools (native Linux) -------------------------------------------
(cd wmake/src && make cc="gcc")

# ---- Third-party ----------------------------------------------------------
mkdir -p "$WM_THIRD_PARTY_DIR/stack_trace/lnInclude"
cp "$WM_THIRD_PARTY_DIR/third-party/stack_trace/stack_trace.h" "$WM_THIRD_PARTY_DIR/stack_trace/lnInclude/"
(cd "$WM_THIRD_PARTY_DIR/third-party/stack_trace" && wmake libso)

# ---- Core: Pstream static -> OSspecific -> OpenFOAM -> Pstream dll -------
(cd src/Pstream/dummy && wmake lib)
(cd src/OSspecific/MSwindows && wmake lib)
cp /usr/include/FlexLexer.h src/OpenFOAM/lnInclude/ 2>/dev/null || true
(cd src && wmake libso OpenFOAM)
(cd src/Pstream/dummy && wmake libso)
rm -f "$FOAM_LIBBIN"/libOpenFOAM.*
(cd src && wmake libso OpenFOAM)
(cd src/OSspecific/MSwindows/stubLibrary && wmake libso)

# ---- Core libraries -------------------------------------------------------
cd src
for lib in fileFormats surfMesh triSurface meshTools; do
    wmake libso "$lib"
done
for lib in finiteVolume mesh/extrudeModel lagrangian/basic sampling meshCheck \
           polyTopoChange parallel/decompose/decompositionMethods; do
    wmake libso "$lib"
done
(cd dummyThirdParty && ./Allwmake) || true

for lib in ODE physicalProperties generic conversion; do
    wmake libso "$lib"
done
wmake libso thermophysicalModels || true
wmake libso lagrangian/basic || true
wmake libso motionSolvers || true
wmake libso fvMeshStitchers fvMeshMovers fvMeshTopoChangers fvMeshDistributors || true
wmake libso randomProcesses || true
wmake libso twoPhaseModels multiphaseModels MomentumTransportModels \
        ThermophysicalTransportModels radiationModels combustionModels || true
wmake libso mesh || true

echo "=== Library build complete ==="
ls -la "$FOAM_LIBBIN"/*.dll | wc -l

#!/usr/bin/env bash
# Cross-build cfMesh into the MinGW OpenFOAM tree, after build-all.sh.
# CFMESH_SOURCE is a clone of https://github.com/Ultravis66/cfMesh-OpenFOAM13
# at the commit below; this script copies it to CFMESH_BUILD_ROOT, applies
# patches/cfmesh, and installs the library and tools into FOAM_LIBBIN and
# FOAM_APPBIN. It does not download anything.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
SOURCE=${OF14_SOURCE:-$REPO/OpenFOAM-14}
JOBS=${FOAM_BUILD_JOBS:-2}
CFMESH_COMMIT=2e36fe7359dd8bbe76ca126c008f884a40ff38fc
: "${CFMESH_SOURCE:?Set CFMESH_SOURCE to a cfMesh-OpenFOAM13 clone}"
: "${CFMESH_BUILD_ROOT:?Set CFMESH_BUILD_ROOT to a new directory}"
if [ -e "$CFMESH_BUILD_ROOT" ]; then
    echo "Build directory already exists: $CFMESH_BUILD_ROOT" >&2
    exit 1
fi
git -C "$CFMESH_SOURCE" cat-file -e "$CFMESH_COMMIT^{commit}"
git clone -q --no-checkout "$CFMESH_SOURCE" "$CFMESH_BUILD_ROOT"
git -C "$CFMESH_BUILD_ROOT" checkout -q "$CFMESH_COMMIT"
git -C "$CFMESH_BUILD_ROOT" apply "$REPO"/patches/cfmesh/*.patch

cd "$SOURCE"
set +u
source etc/pre-bashrc-mingw_w64.sh
set -u
export WM_THIRD_PARTY_DIR=$(cd .. && pwd)
export FOAM_EXT_LIBBIN=$WM_THIRD_PARTY_DIR/platforms/linuxmingw-w64GccDPInt32/lib
# Install beside OpenFOAM's own libraries and tools so the packages ship them
export FOAM_USER_LIBBIN=$FOAM_LIBBIN FOAM_USER_APPBIN=$FOAM_APPBIN
cd "$CFMESH_BUILD_ROOT"
wmake -j "$JOBS" libso meshLibrary
wmake -all -j "$JOBS" executables
wmake -all -j "$JOBS" utilities
test -f "$FOAM_LIBBIN/libmeshLibrary.dll"
test -f "$FOAM_APPBIN/cartesianMesh.exe"

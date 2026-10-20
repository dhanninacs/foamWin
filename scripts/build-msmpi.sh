#!/usr/bin/env bash
# Run after the serial Windows build. Argument: extracted Microsoft MPI SDK.
set -euo pipefail
SDK=$(realpath "${1:?Usage: build-msmpi.sh <extracted-sdk-directory>}")
SOURCE=${OF14_SOURCE:-$(cd "$(dirname "$0")/../OpenFOAM-14" && pwd)}
cd "$SOURCE"
HEADER=$(find "$SDK" -name mpi.h -print -quit)
IMPORT=$(find "$SDK" -name msmpi64.lib -print -quit)
test -n "$HEADER" && test -n "$IMPORT"
export MSMPI_ROOT="${MSMPI_ROOT:-$SOURCE/../ThirdParty-msmpi}"
mkdir -p "$MSMPI_ROOT/include" "$MSMPI_ROOT/lib"
cp "$(dirname "$HEADER")/"*.h "$MSMPI_ROOT/include/"
cp "$IMPORT" "$MSMPI_ROOT/lib/libmsmpi.a"
# OpenFOAM environment scripts reference optional unset variables.
set +u
source etc/pre-bashrc-mingw_w64.sh
export WM_MPLIB=MSMPI FOAM_MPI=msmpi MPI_ARCH_PATH="$MSMPI_ROOT"
wmake -j "${FOAM_BUILD_JOBS:-2}" libso src/Pstream/mpi
for library in src/generic/genericLagrangianPatches src/generic/genericLagrangianFields src/parallel/parallel; do
    wmake -j "${FOAM_BUILD_JOBS:-2}" libso "$library"
done
for application in decomposePar reconstructPar redistributePar; do
    wmake -j "${FOAM_BUILD_JOBS:-2}" "applications/utilities/parallelProcessing/$application"
done

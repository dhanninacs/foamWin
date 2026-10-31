#!/usr/bin/env bash
# Incrementally build the Windows partitioner adapters from separately built
# Scotch, METIS and GKlib, and, when PTSCOTCH_ARCH_PATH or ZOLTAN_ARCH_PATH is
# set, the MS-MPI adapters for PT-Scotch and Zoltan (run build-msmpi.sh first).
# This does not download third-party software; see build-thirdparty-partitioners.sh.
set -euo pipefail
SOURCE=${OF14_SOURCE:-$(cd "$(dirname "$0")/../OpenFOAM-14" && pwd)}
JOBS=${FOAM_BUILD_JOBS:-2}
: "${SCOTCH_ARCH_PATH:?Set SCOTCH_ARCH_PATH to the cross-built Scotch prefix}"
: "${METIS_INCLUDE_DIR:?Set METIS_INCLUDE_DIR to the cross-built METIS headers}"
: "${METIS_LIB_DIR:?Set METIS_LIB_DIR to the cross-built METIS library}"
: "${GKLIB_LIB_DIR:?Set GKLIB_LIB_DIR to the cross-built GKlib library}"
test -f "$SCOTCH_ARCH_PATH/include/scotch.h"
test -f "$SCOTCH_ARCH_PATH/lib/libscotch.a"
test -f "$METIS_INCLUDE_DIR/metis.h"
test -f "$METIS_LIB_DIR/libmetis.a"
test -f "$GKLIB_LIB_DIR/libGKlib.a"
export SCOTCH_ARCH_PATH METIS_INCLUDE_DIR METIS_LIB_DIR GKLIB_LIB_DIR
cd "$SOURCE"
set +u
source etc/pre-bashrc-mingw_w64.sh
set -u
wmake -j "$JOBS" libso src/parallel/decompose/decompositionMethods
wmake -j "$JOBS" libso src/parallel/decompose/metis
wmake -j "$JOBS" libso src/parallel/decompose/scotch

# ---- MS-MPI adapters, built into lib/msmpi beside the MPI Pstream ----------
[ -n "${PTSCOTCH_ARCH_PATH:-}${ZOLTAN_ARCH_PATH:-}" ] || exit 0
export MSMPI_ROOT="${MSMPI_ROOT:-$SOURCE/../ThirdParty-msmpi}"
test -f "$MSMPI_ROOT/include/mpi.h"
test -f "$FOAM_LIBBIN/msmpi/libPstream.dll"
export WM_MPLIB=MSMPI FOAM_MPI=msmpi MPI_ARCH_PATH="$MSMPI_ROOT"
if [ -n "${PTSCOTCH_ARCH_PATH:-}" ]; then
    test -f "$PTSCOTCH_ARCH_PATH/include/ptscotch.h"
    test -f "$PTSCOTCH_ARCH_PATH/lib/libptscotch.a"
    # The MPI build of Scotch supplies matching scotch.h and libscotch.a.
    SCOTCH_ARCH_PATH="$PTSCOTCH_ARCH_PATH" \
        wmake -j "$JOBS" libso src/parallel/decompose/ptscotch
fi
if [ -n "${ZOLTAN_ARCH_PATH:-}" ]; then
    test -f "$ZOLTAN_ARCH_PATH/include/zoltan.h"
    test -f "$ZOLTAN_ARCH_PATH/lib/libzoltan.a"
    export ZOLTAN_ARCH_PATH
    wmake -j "$JOBS" libso src/parallel/decompose/zoltan
fi

#!/usr/bin/env bash
# Incrementally build the Windows partitioner adapters from separately built
# Scotch, METIS and GKlib.  This does not download or redistribute them.
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

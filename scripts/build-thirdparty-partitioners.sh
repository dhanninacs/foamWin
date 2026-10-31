#!/usr/bin/env bash
# Cross-build separately supplied Scotch, METIS, and GKlib sources, and, when
# MSMPI_ROOT is set, PT-Scotch and (with ZOLTAN_SOURCE) Zoltan. This script
# copies sources into a new build directory; it does not download or install
# third-party software globally. Scotch executes a generated Windows helper, so
# the Linux host needs WSL Windows executable interop or an equivalent runner.
set -euo pipefail
: "${SCOTCH_SOURCE:?Set SCOTCH_SOURCE to the Scotch 7 source directory}"
: "${METIS_SOURCE:?Set METIS_SOURCE to the METIS source directory}"
: "${GKLIB_SOURCE:?Set GKLIB_SOURCE to the GKlib source directory}"
: "${PARTITIONER_BUILD_ROOT:?Set PARTITIONER_BUILD_ROOT to a new directory}"
JOBS=${FOAM_BUILD_JOBS:-2}
if [ -e "$PARTITIONER_BUILD_ROOT" ]; then
    echo "Build directory already exists: $PARTITIONER_BUILD_ROOT" >&2
    exit 1
fi
for source in "$SCOTCH_SOURCE" "$METIS_SOURCE" "$GKLIB_SOURCE"; do
    test -d "$source"
done
mkdir -p "$PARTITIONER_BUILD_ROOT"
BUILD=$(cd "$PARTITIONER_BUILD_ROOT" && pwd)
cp -a "$SCOTCH_SOURCE" "$BUILD/scotch"
cp -a "$METIS_SOURCE" "$BUILD/metis"
cp -a "$GKLIB_SOURCE" "$BUILD/gklib"

cmake -S "$BUILD/gklib" -B "$BUILD/gklib-build" \
    -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
    -DCMAKE_INSTALL_PREFIX="$BUILD/gklib-install" -DGKLIB_BUILD_APPS=OFF -DSHARED=OFF
cmake --build "$BUILD/gklib-build" --parallel "$JOBS"
cmake --install "$BUILD/gklib-build"

# METIS's own make config generates this header before invoking CMake.
mkdir -p "$BUILD/metis/build/xinclude"
printf '#define IDXTYPEWIDTH 32\n#define REALTYPEWIDTH 32\n' > "$BUILD/metis/build/xinclude/metis.h"
cat "$BUILD/metis/include/metis.h" >> "$BUILD/metis/build/xinclude/metis.h"
cp "$BUILD/metis/include/CMakeLists.txt" "$BUILD/metis/build/xinclude/"
cmake -S "$BUILD/metis" -B "$BUILD/metis-build" \
    -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
    -DCMAKE_INSTALL_PREFIX="$BUILD/metis-install" -DGKLIB_PATH="$BUILD/gklib-install"
cmake --build "$BUILD/metis-build" --target metis --parallel "$JOBS"

cat > "$BUILD/scotch/src/Makefile.inc" <<'EOF'
EXE = .exe
LIB = .a
OBJ = .o
MAKE = make
AR = x86_64-w64-mingw32-ar
ARFLAGS = -ruv
CAT = cat
CCS = x86_64-w64-mingw32-gcc
CCP = x86_64-w64-mingw32-gcc
CCD = x86_64-w64-mingw32-gcc
FCS = x86_64-w64-mingw32-gfortran
CFLAGS = -O2 -DCOMMON_RANDOM_FIXED_SEED -DCOMMON_STUB_FORK -DCOMMON_STUB_WAITPID -DCOMMON_WINDOWS -DHAVE_NOT_SYS_WAIT_H -DSCOTCH_RENAME
CCDFLAGS = $(CFLAGS)
CLIBFLAGS =
LDFLAGS = -lm
CP = cp
FLEX = flex
LN = ln
MKDIR = mkdir -p
MV = mv
RANLIB = x86_64-w64-mingw32-ranlib
BISON = bison
EOF
make -C "$BUILD/scotch/src" -j "$JOBS" libscotch

printf '\nSet these paths before running scripts/build-partitioners.sh:\n'
printf 'SCOTCH_ARCH_PATH=%s\n' "$BUILD/scotch"
printf 'METIS_INCLUDE_DIR=%s\n' "$BUILD/metis/build/xinclude"
printf 'METIS_LIB_DIR=%s\n' "$BUILD/metis-build/libmetis"
printf 'GKLIB_LIB_DIR=%s\n' "$BUILD/gklib-install/lib"

# ---- Optional MS-MPI partitioners: PT-Scotch and Zoltan ---------------------
# MSMPI_ROOT holds mpi.h and libmsmpi.a, as set up by build-msmpi.sh.
[ -n "${MSMPI_ROOT:-}" ] || exit 0
test -f "$MSMPI_ROOT/include/mpi.h"
test -f "$MSMPI_ROOT/lib/libmsmpi.a"
MPI_CFLAGS="-DMSMPI_NO_SAL -DMSMPI_NO_DEPRECATE_2012 -I$MSMPI_ROOT/include"

cp -a "$SCOTCH_SOURCE" "$BUILD/ptscotch"
sed -e "s#^CFLAGS = \(.*\)#CFLAGS = \1 $MPI_CFLAGS#" \
    -e "s#^LDFLAGS = .*#LDFLAGS = -L$MSMPI_ROOT/lib -lmsmpi -lm#" \
    "$BUILD/scotch/src/Makefile.inc" > "$BUILD/ptscotch/src/Makefile.inc"
make -C "$BUILD/ptscotch/src" -j "$JOBS" libptscotch
printf 'PTSCOTCH_ARCH_PATH=%s\n' "$BUILD/ptscotch"

if [ -n "${ZOLTAN_SOURCE:-}" ]; then
    test -d "$ZOLTAN_SOURCE"
    cp -a "$ZOLTAN_SOURCE" "$BUILD/zoltan"
    mkdir -p "$BUILD/zoltan-build"
    (
        cd "$BUILD/zoltan-build"
        ../zoltan/configure --host=x86_64-w64-mingw32 --prefix="$BUILD/zoltan-install" \
            --disable-fortran --disable-examples --disable-tests \
            --with-mpi-incdir="$MSMPI_ROOT/include" --with-mpi-libdir="$MSMPI_ROOT/lib" \
            --with-mpi-libs=-lmsmpi \
            CC=x86_64-w64-mingw32-gcc CXX=x86_64-w64-mingw32-g++ \
            CFLAGS="-O2 -DMSMPI_NO_SAL -DMSMPI_NO_DEPRECATE_2012" CXXFLAGS=-O2
        make -j "$JOBS"
        make install
    )
    printf 'ZOLTAN_ARCH_PATH=%s\n' "$BUILD/zoltan-install"
fi

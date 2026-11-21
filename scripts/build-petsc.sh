#!/usr/bin/env bash
# Cross-build PETSc for MinGW-w64 with Microsoft MPI, for coupledSimpleFoam's parallel backend.
#
#   scripts/build-petsc.sh <msmpisdk.msi> <petsc-X.tar.gz> <hypre-X.tar.gz> <f2cblaslapack-X.tar.gz>
#
# Builds, in PETSC_BUILD_ROOT (a new directory):
#   msmpi/include, msmpi/lib/libmsmpi.a   the MS-MPI SDK headers and x64 import library, unpacked
#                                         from the SDK installer with msiextract (msitools)
#   petsc-*/mingw-msmpi-opt               a static PETSc with hypre and the C BLAS/LAPACK
#                                         (f2cblaslapack, so no Fortran compiler is needed)
# then prints the PETSC_DIR, PETSC_ARCH and MSMPI_ROOT that scripts/build-coupled.sh takes.
#
# Measured with PETSc 3.22.2, hypre 2.32.0, f2cblaslapack 3.8.0.q2 and MS-MPI SDK 10.1.1
# (Ubuntu 24.04, mingw-w64 GCC 13): PETSc's KSP ex2 with BoomerAMG converges natively on two
# MS-MPI ranks. It does not download anything: the four files are its arguments.
#
# The build machine cannot run Windows test programs, so PETSc's configure runs in batch mode
# (--with-batch); everything it would have measured by running a program has a safe default for
# x86-64 Windows. PETSc finds winpthreads' pthread.h and uses POSIX mutexes in PCMPI, so a program
# linking it also needs -lpthread (scripts/build-coupled.sh links it statically).
set -euo pipefail
MSI=$(realpath "${1:?Usage: build-petsc.sh <msmpisdk.msi> <petsc.tar.gz> <hypre.tar.gz> <f2cblaslapack.tar.gz>}")
PETSC_TAR=$(realpath "${2:?missing PETSc tarball}")
HYPRE_TAR=$(realpath "${3:?missing hypre tarball}")
BLAS_TAR=$(realpath "${4:?missing f2cblaslapack tarball}")
ROOT=${PETSC_BUILD_ROOT:?Set PETSC_BUILD_ROOT to a new directory}
JOBS=${FOAM_BUILD_JOBS:-2}
ARCH=mingw-msmpi-opt
command -v msiextract > /dev/null || { echo "msiextract not found (Ubuntu: apt install msitools)" >&2; exit 1; }
command -v x86_64-w64-mingw32-gcc > /dev/null || { echo "MinGW-w64 GCC not found" >&2; exit 1; }
if [ -e "$ROOT" ]; then
    echo "Build directory already exists: $ROOT" >&2
    exit 1
fi
mkdir -p "$ROOT/sdk" "$ROOT/msmpi/include" "$ROOT/msmpi/lib"

# ---- MS-MPI SDK: headers and the x64 import library -----------------------------
(cd "$ROOT/sdk" && msiextract "$MSI" > /dev/null)
SDK=$(dirname "$(find "$ROOT/sdk" -name mpi.h -print -quit)")
cp "$SDK"/*.h "$ROOT/msmpi/include/"
cp "$SDK/x64/mpifptr.h" "$ROOT/msmpi/include/"
cp "$(find "$ROOT/sdk" -path '*x64*' -name msmpi.lib -print -quit)" "$ROOT/msmpi/lib/libmsmpi.a"

# ---- PETSc ---------------------------------------------------------------------
tar -xzf "$PETSC_TAR" -C "$ROOT"
PETSC_DIR=$(find "$ROOT" -maxdepth 1 -type d -name 'petsc-*' -print -quit)
cd "$PETSC_DIR"
python3 ./configure PETSC_ARCH=$ARCH \
    --with-batch=1 \
    --with-cc=x86_64-w64-mingw32-gcc --with-cxx=x86_64-w64-mingw32-g++ --with-fc=0 \
    --with-mpi-include="$ROOT/msmpi/include" --with-mpi-lib="$ROOT/msmpi/lib/libmsmpi.a" \
    --with-mpiexec=/bin/true \
    --with-shared-libraries=0 --with-debugging=0 \
    COPTFLAGS=-O2 CXXOPTFLAGS=-O2 \
    --with-x=0 --with-ssl=0 --with-pthread=0 \
    --download-f2cblaslapack="$BLAS_TAR" \
    --download-hypre="$HYPRE_TAR"
make PETSC_DIR="$PETSC_DIR" PETSC_ARCH=$ARCH MAKE_NP="$JOBS" all
test -f "$PETSC_DIR/$ARCH/lib/libpetsc.a"
test -f "$PETSC_DIR/$ARCH/lib/libHYPRE.a"

echo
echo "PETSC_DIR=$PETSC_DIR"
echo "PETSC_ARCH=$ARCH"
echo "MSMPI_ROOT=$ROOT/msmpi"

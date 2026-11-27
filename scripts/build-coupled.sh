#!/usr/bin/env bash
# Cross-build coupledSimpleFoam into the MinGW OpenFOAM tree, after build-all.sh.
# COUPLED_SOURCE is a clone of https://github.com/dhanninacs/coupledSimpleFoam
# holding the commit below (its feat/amgx-backend branch: the conjugate mode,
# -region and the AmgX backend); every build is made from that one commit, so
# the CPU builds run conjugate cases (conjugateSolver Eigen) without a GPU. It
# copies the source to COUPLED_BUILD_ROOT and installs
# its builds:
#   FOAM_APPBIN/coupledSimpleFoam.exe        serial, Eigen backend only
#                                            (COUPLED_NO_PETSC=1); needs no MPI
#   FOAM_APPBIN/msmpi/coupledSimpleFoam.exe  the PETSc backend over MS-MPI, built
#                                            only when PETSC_DIR is set (from
#                                            scripts/build-petsc.sh); it imports
#                                            msmpi.dll, so of14-shell.ps1 puts
#                                            bin/msmpi on PATH only when Microsoft
#                                            MPI is installed, as with lib/msmpi
#   FOAM_APPBIN/amgx/coupledSimpleFoam.exe   the NVIDIA GPU build (AmgX), built
#                                            only when AMGX_WINDOWS_BUILD is set
#                                            (from scripts/build-amgx.ps1); see
#                                            its section below
# EIGEN_INCLUDE is the Eigen 3 header directory (Ubuntu: /usr/include/eigen3,
# from libeigen3-dev); Eigen is header-only, so nothing extra ships. PETSc,
# hypre and BLAS/LAPACK are linked statically, so the PETSc build ships no DLL
# beyond MinGW's runtime and the system's msmpi.dll.
# It does not download anything.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
SOURCE=${OF14_SOURCE:-$REPO/OpenFOAM-14}
JOBS=${FOAM_BUILD_JOBS:-2}
COUPLED_COMMIT=5585c2ac31e65ceeae1485d23e30c1abf4d9a4f4
EIGEN_INCLUDE=${EIGEN_INCLUDE:-/usr/include/eigen3}
: "${COUPLED_SOURCE:?Set COUPLED_SOURCE to a coupledSimpleFoam clone}"
: "${COUPLED_BUILD_ROOT:?Set COUPLED_BUILD_ROOT to a new directory}"
if [ ! -f "$EIGEN_INCLUDE/Eigen/Sparse" ]; then
    echo "Eigen 3 headers not found in $EIGEN_INCLUDE (set EIGEN_INCLUDE)" >&2
    exit 1
fi
if [ -e "$COUPLED_BUILD_ROOT" ]; then
    echo "Build directory already exists: $COUPLED_BUILD_ROOT" >&2
    exit 1
fi
if [ -n "${PETSC_DIR:-}" ]; then
    PETSC_ARCH=${PETSC_ARCH:-mingw-msmpi-opt}
    : "${MSMPI_ROOT:?Set MSMPI_ROOT (scripts/build-petsc.sh prints it) with PETSC_DIR}"
    test -f "$PETSC_DIR/$PETSC_ARCH/lib/libpetsc.a"
    test -f "$MSMPI_ROOT/lib/libmsmpi.a"
fi
git -C "$COUPLED_SOURCE" cat-file -e "$COUPLED_COMMIT^{commit}"
git clone -q --no-checkout "$COUPLED_SOURCE" "$COUPLED_BUILD_ROOT"
git -C "$COUPLED_BUILD_ROOT" checkout -q "$COUPLED_COMMIT"

cd "$SOURCE"
set +u
source etc/pre-bashrc-mingw_w64.sh
set -u
export EIGEN_INC="-I$EIGEN_INCLUDE"
SOLVER="$COUPLED_BUILD_ROOT/src/coupledSimpleFoam"

# ---- serial (Eigen) build, beside OpenFOAM's own tools ------------------------
export FOAM_USER_APPBIN=$FOAM_APPBIN COUPLED_NO_PETSC=1
(cd "$SOLVER" && wmake -j "$JOBS")
test -f "$FOAM_APPBIN/coupledSimpleFoam.exe"

# ---- NVIDIA GPU (AmgX) build into bin/amgx ---------------------------------------
# Built when AMGX_WINDOWS_BUILD is set: scripts/build-amgx.ps1's Release folder
# (amgxsh.dll, amgxsh.lib, AmgX's license and NOTICES). AmgX is MSVC + CUDA; the
# solver calls only its C API, so MinGW links the MSVC import library. The GPU
# solver is coupledSimpleFoam's GPU build
# (linearSolver AmgX, scalar equations with `solver AmgX;`, conjugate heat
# transfer with COUPLED/solidRegions), built from the same COUPLED_COMMIT; it starts
# CUDA first thing in main (FoamWin issue #1). It installs as bin/amgx/coupledSimpleFoam.exe
# beside amgxsh.dll and MSVC's C++ runtime (MSVC_RUNTIME_DIR: the folder with
# msvcp140.dll, vcruntime140.dll and vcruntime140_1.dll, Visual Studio's
# redistributable Microsoft.VC143.CRT). cuBLAS, cuSPARSE and cuSOLVER are not
# shipped: they come from the user's CUDA Toolkit 12 (of14-shell.ps1 finds them).
if [ -n "${AMGX_WINDOWS_BUILD:-}" ]; then
    : "${AMGX_INCLUDE:?Set AMGX_INCLUDE to the AmgX 2.5.0 source include folder (amgx_c.h)}"
    : "${MSVC_RUNTIME_DIR:?Set MSVC_RUNTIME_DIR to Microsoft.VC143.CRT (msvcp140.dll)}"
    for f in amgxsh.dll amgxsh.lib BSD-3-Clause.txt NOTICES; do
        test -f "$AMGX_WINDOWS_BUILD/$f" || { echo "Missing $AMGX_WINDOWS_BUILD/$f" >&2; exit 1; }
    done
    test -f "$AMGX_INCLUDE/amgx_c.h"
    for f in msvcp140.dll vcruntime140.dll vcruntime140_1.dll; do
        test -f "$MSVC_RUNTIME_DIR/$f" || { echo "Missing $MSVC_RUNTIME_DIR/$f" >&2; exit 1; }
    done
    GPU_ROOT="$COUPLED_BUILD_ROOT/amgx"
    git clone -q --no-checkout "$COUPLED_SOURCE" "$GPU_ROOT/src"
    git -C "$GPU_ROOT/src" checkout -q "$COUPLED_COMMIT"
    # The prefix the solver's Make/options reads: include/amgx_c.h, lib/amgxsh.lib.
    mkdir -p "$GPU_ROOT/prefix/include" "$GPU_ROOT/prefix/lib"
    cp "$AMGX_INCLUDE"/*.h "$GPU_ROOT/prefix/include/"
    cp "$AMGX_WINDOWS_BUILD/amgxsh.lib" "$GPU_ROOT/prefix/lib/"
    mkdir -p "$FOAM_APPBIN/amgx"
    (
        export FOAM_USER_APPBIN=$FOAM_APPBIN/amgx COUPLED_NO_PETSC=1
        export AMGX_DIR="$GPU_ROOT/prefix" AMGX_RPATH=
        cd "$GPU_ROOT/src/src/coupledSimpleFoam" && wmake -j "$JOBS"
    )
    test -f "$FOAM_APPBIN/amgx/coupledSimpleFoam.exe"
    cp "$AMGX_WINDOWS_BUILD/amgxsh.dll" "$FOAM_APPBIN/amgx/"
    # Visual Studio installs these read-only: make them writable, so a rebuild can replace them.
    for f in msvcp140.dll vcruntime140.dll vcruntime140_1.dll; do
        chmod u+w "$FOAM_APPBIN/amgx/$f" 2> /dev/null || true
        rm -f "$FOAM_APPBIN/amgx/$f"
        cp "$MSVC_RUNTIME_DIR/$f" "$FOAM_APPBIN/amgx/"
        chmod u+w "$FOAM_APPBIN/amgx/$f"
    done
    x86_64-w64-mingw32-objdump -p "$FOAM_APPBIN/amgx/coupledSimpleFoam.exe" \
        | grep 'DLL Name: amgxsh.dll' > /dev/null
fi
[ -n "${PETSC_DIR:-}" ] || exit 0

# ---- PETSc build into bin/msmpi ------------------------------------------------
# The solver's Make/options asks pkg-config for PETSc and `mpicc --showme` for
# MPI. Two wrappers answer for the MinGW build: pkg-config with PETSc's static
# link line (hypre, BLAS/LAPACK) plus MS-MPI and static winpthreads, which
# PETSc's PCMPI needs; mpicc with the MS-MPI include path.
WRAP="$COUPLED_BUILD_ROOT/wrap"
mkdir -p "$WRAP"
cat > "$WRAP/pkg-config" <<EOF
#!/bin/bash
export PKG_CONFIG_PATH="$PETSC_DIR/$PETSC_ARCH/lib/pkgconfig"
if [[ " \$* " == *" --libs "* ]]; then
    echo "\$(/usr/bin/pkg-config --static "\$@") -L$MSMPI_ROOT/lib -lmsmpi -Wl,-Bstatic -lpthread -Wl,-Bdynamic"
else
    /usr/bin/pkg-config "\$@"
fi
EOF
cat > "$WRAP/mpicc" <<EOF
#!/bin/bash
case "\$1" in
    --showme:compile) echo "-I$MSMPI_ROOT/include" ;;
    --showme:link) echo "" ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$WRAP/pkg-config" "$WRAP/mpicc"
mkdir -p "$FOAM_APPBIN/msmpi"
unset COUPLED_NO_PETSC
export FOAM_USER_APPBIN=$FOAM_APPBIN/msmpi PATH="$WRAP:$PATH"
(cd "$SOLVER" && wclean > /dev/null && wmake -j "$JOBS")
test -f "$FOAM_APPBIN/msmpi/coupledSimpleFoam.exe"
# Not `grep -q`: it stops reading early, and under pipefail objdump's broken pipe fails the check.
x86_64-w64-mingw32-objdump -p "$FOAM_APPBIN/msmpi/coupledSimpleFoam.exe" | grep 'DLL Name: msmpi.dll' > /dev/null

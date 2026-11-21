#!/usr/bin/env bash
# Cross-build coupledSimpleFoam into the MinGW OpenFOAM tree, after build-all.sh.
# COUPLED_SOURCE is a clone of https://github.com/dhanninacs/coupledSimpleFoam
# at the commit below; this script copies it to COUPLED_BUILD_ROOT and installs
# two builds:
#   FOAM_APPBIN/coupledSimpleFoam.exe        serial, Eigen backend only
#                                            (COUPLED_NO_PETSC=1); needs no MPI
#   FOAM_APPBIN/msmpi/coupledSimpleFoam.exe  the PETSc backend over MS-MPI, built
#                                            only when PETSC_DIR is set (from
#                                            scripts/build-petsc.sh); it imports
#                                            msmpi.dll, so of14-shell.ps1 puts
#                                            bin/msmpi on PATH only when Microsoft
#                                            MPI is installed, as with lib/msmpi
# EIGEN_INCLUDE is the Eigen 3 header directory (Ubuntu: /usr/include/eigen3,
# from libeigen3-dev); Eigen is header-only, so nothing extra ships. PETSc,
# hypre and BLAS/LAPACK are linked statically, so the PETSc build ships no DLL
# beyond MinGW's runtime and the system's msmpi.dll.
# It does not download anything.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
SOURCE=${OF14_SOURCE:-$REPO/OpenFOAM-14}
JOBS=${FOAM_BUILD_JOBS:-2}
COUPLED_COMMIT=c2ca076434f5a43ec616a3e278589b565f4d6aa6
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

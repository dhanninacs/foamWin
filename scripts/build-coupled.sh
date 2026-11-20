#!/usr/bin/env bash
# Cross-build coupledSimpleFoam into the MinGW OpenFOAM tree, after build-all.sh.
# COUPLED_SOURCE is a clone of https://github.com/dhanninacs/coupledSimpleFoam
# at the commit below; this script copies it to COUPLED_BUILD_ROOT and installs
# coupledSimpleFoam.exe into FOAM_APPBIN. It builds the serial Eigen backend
# only (COUPLED_NO_PETSC=1): PETSc and hypre have no MinGW/MS-MPI build here.
# EIGEN_INCLUDE is the Eigen 3 header directory (Ubuntu: /usr/include/eigen3,
# from libeigen3-dev); Eigen is header-only, so nothing extra ships.
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
git -C "$COUPLED_SOURCE" cat-file -e "$COUPLED_COMMIT^{commit}"
git clone -q --no-checkout "$COUPLED_SOURCE" "$COUPLED_BUILD_ROOT"
git -C "$COUPLED_BUILD_ROOT" checkout -q "$COUPLED_COMMIT"

cd "$SOURCE"
set +u
source etc/pre-bashrc-mingw_w64.sh
set -u
# Install beside OpenFOAM's own tools so the packages ship it
export FOAM_USER_APPBIN=$FOAM_APPBIN
export COUPLED_NO_PETSC=1 EIGEN_INC="-I$EIGEN_INCLUDE"
cd "$COUPLED_BUILD_ROOT/src/coupledSimpleFoam"
wmake -j "$JOBS"
test -f "$FOAM_APPBIN/coupledSimpleFoam.exe"

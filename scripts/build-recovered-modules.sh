#!/usr/bin/env bash
# Incremental cross-build for the recovered Windows solver modules.
# Run against a case-sensitive Linux build tree with the normal FoamWin
# prerequisites and core libraries already built.
set -euo pipefail
SOURCE=${OF14_SOURCE:-$(cd "$(dirname "$0")/../OpenFOAM-14" && pwd)}
JOBS=${FOAM_BUILD_JOBS:-2}
cd "$SOURCE"
# OpenFOAM's environment scripts expect unset variables to be allowed.
set +u
source etc/pre-bashrc-mingw_w64.sh
set -u

for lib in \
    src/fvModels/general \
    src/fvConstraints \
    src/atmosphericModels \
    src/waves \
    src/rigidBodyMotion/rigidBodyDynamics \
    src/rigidBodyMotion/rigidBodyMotion_pointMeshMovers \
    src/rigidBodyMotion/rigidBodyState \
    src/rigidBodyMotion/rigidBodyForces \
    src/rigidBodyMotion/sixDoFRigidBodyMotion \
    src/rigidBodyMotion/sixDoFRigidBodyMotion_pointMeshMovers \
    src/rigidBodyMotion/sixDoFRigidBodyState \
    src/fvMeshMovers/fvMotionSolvers \
    src/fvMeshMovers/interpolator \
    src/fvMeshMovers/multiValveEngine \
    src/fvMeshMovers/inkJet \
    src/fvMeshTopoChangers/meshToMesh \
    src/fvModels/interRegion \
    src/fvModels/propellerDisk \
    src/fvModels/rigidBodyPropellerDisk \
    src/specieTransfer \
    applications/modules/solid \
    applications/modules/solidDisplacement/solidDisplacementThermo \
    applications/modules/solidDisplacement \
    applications/modules/incompressibleDenseParticleFluid \
    applications/modules/compressibleVoF \
    applications/modules/isothermalFilm/filmCompressibleMomentumTransportModels \
    applications/modules/isothermalFilm \
    applications/modules/isothermalFilm/fvModels/filmVoFTransfer \
    applications/modules/isothermalFilm/fvModels/filmCloudTransfer \
    applications/modules/film/filmThermophysicalTransportModels \
    applications/modules/film \
    src/ThermophysicalTransportModels/phaseSolid \
    applications/modules/multiphaseEuler/phaseSystem \
    applications/modules/multiphaseEuler/populationBalance \
    applications/modules/multiphaseEuler/momentumTransportModels \
    applications/modules/multiphaseEuler/thermophysicalTransportModels \
    applications/modules/multiphaseEuler/reactions \
    applications/modules/multiphaseEuler \
    applications/modules/multiphaseEuler/fvModels \
    applications/modules/multiphaseEuler/functionObjects
do
    wmake -j "$JOBS" libso "$lib"
done

for app in applications/solvers/foamRun applications/solvers/foamMultiRun \
    applications/utilities/mesh/generation/blockMesh; do
    wmake -j "$JOBS" "$app"
done

#!/usr/bin/env bash
# Incrementally build additional utilities; the core libraries must already exist.
set -euo pipefail
SOURCE=${OF14_SOURCE:-$(cd "$(dirname "$0")/../OpenFOAM-14" && pwd)}
JOBS=${FOAM_BUILD_JOBS:-2}
cd "$SOURCE"
set +u
source etc/pre-bashrc-mingw_w64.sh
set -u

for app in \
    applications/utilities/thermophysical/adiabaticFlameT \
    applications/utilities/thermophysical/chemkinToFoam \
    applications/utilities/thermophysical/equilibriumCO \
    applications/utilities/thermophysical/equilibriumFlameT \
    applications/utilities/thermophysical/mixtureAdiabaticFlameT \
    applications/utilities/surface/surfaceAdd \
    applications/utilities/surface/surfaceAutoPatch \
    applications/utilities/surface/surfaceBooleanFeatures \
    applications/utilities/surface/surfaceCheck \
    applications/utilities/surface/surfaceClean \
    applications/utilities/surface/surfaceCoarsen \
    applications/utilities/surface/surfaceConvert \
    applications/utilities/surface/surfaceFeatureConvert \
    applications/utilities/surface/surfaceFind \
    applications/utilities/surface/surfaceHookUp \
    applications/utilities/surface/surfaceInertia \
    applications/utilities/surface/surfaceLambdaMuSmooth \
    applications/utilities/surface/surfaceMeshConvert \
    applications/utilities/surface/surfaceMeshExport \
    applications/utilities/surface/surfaceMeshImport \
    applications/utilities/surface/surfaceMeshInfo \
    applications/utilities/surface/surfaceMeshTriangulate \
    applications/utilities/surface/surfaceOrient \
    applications/utilities/surface/surfacePointMerge \
    applications/utilities/surface/surfaceRedistributePar \
    applications/utilities/surface/surfaceRefineRedGreen \
    applications/utilities/surface/surfaceRenamePatch \
    applications/utilities/surface/surfaceSplitByPatch \
    applications/utilities/surface/surfaceSplitByTopology \
    applications/utilities/surface/surfaceSplitNonManifolds \
    applications/utilities/surface/surfaceSubset \
    applications/utilities/surface/surfaceToPatch \
    applications/utilities/surface/surfaceTransformPoints \
    applications/utilities/preProcessing/applyBoundaryLayer \
    applications/utilities/preProcessing/boxTurb \
    applications/utilities/preProcessing/createExternalCoupledPatchGeometry \
    applications/utilities/preProcessing/dsmcInitialise \
    applications/utilities/preProcessing/engineSwirl \
    applications/utilities/preProcessing/faceAgglomerate \
    applications/utilities/preProcessing/foamSetupCHT \
    applications/utilities/preProcessing/mapFields \
    applications/utilities/preProcessing/mapFieldsPar \
    applications/utilities/preProcessing/mdInitialise \
    applications/utilities/preProcessing/setAtmBoundaryLayer \
    applications/utilities/preProcessing/setFields \
    applications/utilities/preProcessing/setWaves \
    applications/utilities/preProcessing/snappyHexMeshConfig \
    applications/utilities/preProcessing/viewFactorsGen \
    applications/utilities/postProcessing/noise \
    applications/utilities/postProcessing/miscellaneous/engineCompRatio \
    applications/utilities/postProcessing/miscellaneous/pdfPlot \
    applications/utilities/postProcessing/miscellaneous/temporalInterpolate \
    applications/utilities/postProcessing/lagrangian/particleTracks \
    applications/utilities/postProcessing/lagrangian/steadyParticleTracks \
    applications/utilities/postProcessing/dataConversion/foamDataToFluent \
    applications/utilities/postProcessing/dataConversion/foamToEnsight \
    applications/utilities/postProcessing/dataConversion/foamToEnsightParts \
    applications/utilities/postProcessing/dataConversion/foamToGMV \
    applications/utilities/postProcessing/dataConversion/foamToTetDualMesh \
    applications/utilities/postProcessing/dataConversion/smapToFoam
do
    wmake -j "$JOBS" "$app"
done

#!/usr/bin/env bash
# Build the extra OpenFOAM utilities needed by attached CFD applications.
set -e
SOURCE=${OF14_SOURCE:-$(cd "$(dirname "$0")/../OpenFOAM-14" && pwd)}
cd "$SOURCE"
source etc/pre-bashrc-mingw_w64.sh
for app in applications/utilities/surface/surfaceFeatures applications/utilities/postProcessing/foamPostProcess; do
    wmake -j "${FOAM_BUILD_JOBS:-2}" "$app"
done
wmake -j "${FOAM_BUILD_JOBS:-2}" libso applications/utilities/postProcessing/dataConversion/foamToVTK/foamToVTK
wmake -j "${FOAM_BUILD_JOBS:-2}" applications/utilities/postProcessing/dataConversion/foamToVTK

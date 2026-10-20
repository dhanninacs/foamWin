#!/bin/bash
# Build OF14-win-setup.exe (NSIS) and OF14-win.zip from a completed build.
# Run from the repo root after a successful ./OpenFOAM-14/build-all.sh
set -e
cd "${0%/*}/.."

SRC=OpenFOAM-14
STAGE=$(mktemp -d)/OpenFOAM-14
mkdir -p "$STAGE"

cp -a "$SRC/etc"                 "$STAGE/"
cp -a "$SRC/COPYING"             "$STAGE/"
mkdir -p "$STAGE/platforms/linuxmingw-w64GccDPInt32Opt"
cp -a "$SRC/platforms/linuxmingw-w64GccDPInt32Opt/bin" \
      "$STAGE/platforms/linuxmingw-w64GccDPInt32Opt/"
cp -a "$SRC/platforms/linuxmingw-w64GccDPInt32Opt/lib" \
      "$STAGE/platforms/linuxmingw-w64GccDPInt32Opt/"

# MinGW runtime DLLs next to the exes (so the .exe set is self-contained)
for dll in libgcc_s_seh-1.dll libstdc++-6.dll libgnurx-0.dll zlib1.dll; do
    find /usr/x86_64-w64-mingw32 -name "$dll" -exec cp {} \
        "$STAGE/platforms/linuxmingw-w64GccDPInt32Opt/bin/" \; 2>/dev/null || true
done

# --- NSIS installer ---------------------------------------------------------
NSIS_STAGING=$(mktemp -d)
cp -a "$STAGE" "$NSIS_STAGING/OpenFOAM-14"
cp installer/LICENSE.txt "$NSIS_STAGING/"
cp installer/of14-shell.bat "$NSIS_STAGING/"
(cd installer && makensis -V2 OF14-installer.nsi)   # build into installer/
mv installer/OF14-win-setup.exe .

# --- portable zip ------------------------------------------------------------
zip -qr OF14-win.zip -j . <<ZIPEOF
$STAGE
ZIPEOF
echo "Done:"
ls -lh OF14-win-setup.exe OF14-win.zip 2>/dev/null

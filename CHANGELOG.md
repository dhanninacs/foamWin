# MPI update (unreleased)

- Added optional Microsoft MPI for local parallel meshing and solving.
- Added decomposePar, reconstructPar, and redistributePar.
- Added a missing-runtime prompt and serial fallback.
- Validated cavity solving and snappyHexMesh on two and four processes.

# FoamWin changelog

## v14.0.0-win.1 — 2026-10-20

**FoamWin 14 for Windows — Initial Release**

Native 64-bit Windows serial build of Foundation OpenFOAM 14 using MinGW-w64 and
the blueCFD-derived Windows compatibility layer.

### Included

- Guided installer and portable ZIP.
- Native PowerShell launcher and Desktop/Start Menu shortcuts.
- Required compiler/runtime and stack-trace DLLs with license notices.
- A cavity example and a smoke-test script.
- Fixes for Windows DLL filename collisions, constructor initialization order,
  installation paths with spaces, shell startup, and installer registration.

### Validation

All 85 executable startup checks passed. Mesh validation and legacy icoFoam and
modern foamRun cavity simulations completed on Windows. The installed package and
actual Desktop shortcut were tested. The updated installer also passed an approved
installation test, including shortcut working directory and uninstaller registration.

### Limitations

Serial only, double precision, 32-bit labels. ParaView is installed separately.
Runtime code compilation requires additional compiler setup. A full clean rebuild
and exhaustive validation of every physical model were not performed.

### Release assets

- `OF14-win-setup.exe`
- `OF14-win.zip`

# v14.0.0-win.4 — Runtime registration and clean rebuild

- Restore 91 source files that differ from another file only in case. A commit made from a Windows checkout had overwritten them with the other casing's content, which broke the library build. The tree now rebuilds cleanly from the repository.
- Build the stack-trace helper as a static library so a clean build no longer fails before `libOpenFOAM.dll` exists.
- Build the remaining libraries with upstream `src/Allwmake`, run twice so libraries that upstream orders before their dependencies still link on Windows. `build-all.sh` now fails if any library the packages need is missing.
- Add the cross-built zlib headers to the MinGW compile flags.
- Ship libraries the previous hand-written build list missed: forces, rigid-body and six-DoF motion, propeller disk, solid particles, specie transfer, and the solver and utility function objects.
- Skip the legacy `liblagrangianFunctionObjects` on Windows, where its name clashes with `libLagrangianFunctionObjects`.
- Correct Windows runtime registration for recovered solver modules, coupled temperature and film patches, and wall-function fields in mesh utilities.
- Correct the condenser tutorial's multiphase model library name.
- Normalize Windows executable paths and `mapFields` source paths, and encode reserved characters in function-object output directory names.
- Add build and validation helpers for recovered utilities and optional METIS and Scotch partitioners. Third-party dependencies and their redistribution terms require separate review.

# v14.0.0-win.3 — Native application engine support

- Added surfaceFeatures, foamPostProcess, foamToVTK and the VTK export library.
- Added an explicit JSON environment/tool handshake for native Windows hosts.
- Added a synthetic runtime workflow test and the modern cavity tutorial.
- Documented application attachment, MPI invocation and Windows host requirements.

# v14.0.0-win.2 — MPI update

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

# Unreleased

- Native runs are as fast as OpenFOAM 14 on WSL on the same machine: 3–4% faster on one core and 5–7% slower on 16 MPI ranks, against 43–67% and 21–51% slower before. Measured on an i9-13900 with the `pitzDailySteady` tutorial refined to 196k cells and a 343k-cell steady 3D lid-driven cavity, three interleaved runs each, with residuals identical to WSL's in every run. Four changes:
  - **Large heap blocks are reused.** The C runtime (`msvcrt`) hands every block above its heap threshold back to Windows, so each temporary field was faulted in and zeroed page by page again: 13× the page faults and 6× the kernel time of the Linux run. `libOpenFOAM` now replaces `operator new`/`delete` (`src/OSspecific/MSwindows/largeBlockCache.C`) and keeps freed blocks of 64 KiB and more, up to 1 GiB, for reuse. Every block is still a plain `malloc` block, so memory still passes safely between these operators and `libstdc++` or `free()`.
  - **Solver processes opt out of power throttling.** Windows 11 runs windowless processes, as every `mpiexec` rank is, at EcoQoS: lower clocks and the efficiency cores of a hybrid CPU. `processQoS.C` asks for full speed when `libOpenFOAM` loads; an 8-rank run got 25% faster.
  - **Medium MPI messages are split to fit MS-MPI's shared-memory slots.** MS-MPI copies a message larger than one 4 KiB slot with `ReadProcessMemory`, which costs 20–30 µs on some Windows installations whatever the size, against under 1 µs for a message that fits. `Pstream/mpi` now sends a message of 4080 bytes to 128 KiB as 4080-byte pieces ended by a shorter one, and waits for, tests and resets their requests with the message's own. Larger messages go whole, so gathers do not flood the receiver's queue. `FOAM_MPI_CHUNK_SIZE` (0 turns it off) and `FOAM_MPI_CHUNK_MAX` tune it; they must be the same on every rank, as they are when set before `mpiexec`.
  - The MinGW build uses `-O3`, as the Linux build does (1–2.5%).

- Ship coupledSimpleFoam's PETSc backend as `bin/msmpi/coupledSimpleFoam.exe`, used in place of the serial build when Microsoft MPI is installed, so coupled runs go parallel natively. The new `scripts/build-petsc.sh` cross-builds a static PETSc with hypre and a C BLAS/LAPACK against the Microsoft MPI SDK (unpacked with `msiextract`), and `scripts/build-coupled.sh` builds the PETSc variant when given `PETSC_DIR`. A 1M-cell laminar square duct on 6 ranks converged in 16 iterations and 77 s natively against 70 s on WSL, with the same friction factor.
- `decomposePar` and `reconstructPar` load the generic patch-field libraries themselves on Windows, where the PE linker drops an unreferenced import. A case with a patch type from a library they had not loaded (`nutkWallFunction` in the kEpsilon cavity, `alphatJayatillekeWallFunction`, `v2WallFunction`) stopped at "Unknown patchField type" unless `-libs` was given.
- `-libs` and `FOAM_LIBS` accept bare words, `'(lib1.dll lib2.dll)'` or a single `lib.dll`, as well as quoted names. PowerShell and MS-MPI's `mpiexec` strip the inner quotes, so every `-libs` given from either failed with "wrong token type - expected string".
- `stopAtWriteNowSignal` now stops the run on Windows. Its handler was `sigWriteNow`'s, so Ctrl+Break with the switch set to 21 did not write and stop: the run died without writing.
- The repository's 101 symlinks are regular copies of their targets. A Windows checkout made them empty files, and some are read at run time (`etc/caseDicts/postProcessing`, the dynamic-code thermo templates, test inputs).
- Add `scripts/test-windows-fixes.ps1`, which checks the three fixes above on an installed runtime.
- Ship `coupledSimpleFoam` (serial, Eigen backend), cross-built by the new `scripts/build-coupled.sh` from coupledSimpleFoam at `c2ca076`. Its `heatedDuct` tutorial matches the Linux build exactly, and Stokes' `coupled.simple` engine now runs natively on Windows. The PETSc backend for parallel runs is not built.
- The portable ZIP's `setup-openfoam14.ps1` now installs the `gmsh` folder and `of14-cfmesh-test.ps1`, as the GUI installer already did. Before, a ZIP install had no Gmsh: `of14-shell.ps1` found nothing to put on PATH, `of14-env.ps1` reported `gmsh` as absent, and Stokes' Gmsh mesher could not run.

# v14.0.0-win.5 — Graph partitioners and cfMesh

- Ship the Scotch and METIS partitioners for `decomposePar`, and PT-Scotch and Zoltan for parallel redistribution and load balancing under Microsoft MPI. Their license texts are packaged under `runtime-licenses`.
- `build-thirdparty-partitioners.sh` also cross-builds PT-Scotch and Zoltan against MS-MPI, and `build-partitioners.sh` builds their adapters into `lib/msmpi`.
- Load any optional partitioner library on demand on Windows, where an unreferenced DLL is never loaded. Previously only `metis` and `scotch` decomposers and the `scotch` distributor were found.
- Link the PT-Scotch and Zoltan adapters against their dependencies on Windows, without Linux's `-lrt`.
- The import check resolves DLLs in the launcher's `PATH` order for each MPI backend, so a real partitioner in `lib/msmpi` may shadow the stub in `lib/dummy`.
- Ship cfMesh (`cartesianMesh`, `tetMesh`, `pMesh`, `cartesian2DMesh`, `generateBoundaryLayers`, `improveMeshQuality` and its surface utilities), built from the cfMesh-OpenFOAM13 fork with `patches/cfmesh` for OpenFOAM 14 and MinGW, plus `libgomp-1.dll` for its OpenMP threads.
- Add `of14-cfmesh-test.ps1` and the `cfMeshBox` example, and extend `test-windows-partitioners.ps1` to PT-Scotch and Zoltan.

# v14.0.0-win.4 — Runtime registration and clean rebuild

- Restore 91 source files that differ from another file only in case. A commit made from a Windows checkout had overwritten them with the other casing's content, which broke the library build. The tree now rebuilds cleanly from the repository.
- Build the stack-trace helper as a static library so a clean build no longer fails before `libOpenFOAM.dll` exists.
- Build the remaining libraries with upstream `src/Allwmake`, run twice so libraries that upstream orders before their dependencies still link on Windows. `build-all.sh` now fails if any library the packages need is missing.
- Add the cross-built zlib headers to the MinGW compile flags.
- Ship libraries the previous hand-written build list missed: forces, rigid-body and six-DoF motion, propeller disk, solid particles, specie transfer, and the solver and utility function objects.
- Skip the legacy `liblagrangianFunctionObjects` on Windows, where its name clashes with `libLagrangianFunctionObjects`.
- Build the applications from `build-all.sh` with upstream `applications/Allwmake`. This adds the legacy solvers, including `icoFoam`, which the bundled smoke test runs but earlier packages did not contain.
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

# v14.0.0-win.8 (unreleased) — conjugate heat transfer on the CPU, GPU start-up

- The CPU coupled solver's `linearSolver BiCGSTAB` (Eigen) is about 10x faster on large cases: its preconditioner is kept between outer iterations (`pcReuseInterval`), it follows `adaptiveTolerance`, its matrix-vector products use all OpenMP threads, and the IncompleteLUT defaults are lighter (`fillFactor 5`, `dropTolerance 1e-4`). An 80k-cell conjugate case went from about 15 min to 82 s with the same answer.
- coupledSimpleFoam's convergence test no longer stalls on a velocity component that carries next to none of the flow (the cross-stream velocity of a periodic or symmetric case): its residual stayed O(1) on round-off, so `residualControl` never fired. `COUPLED/residualFloor` (default 1e-3) floors each component's normalisation; the solution itself is unchanged.
- Every executable is Terminal-Server aware (`IMAGE_DLLCHARACTERISTICS_TERMINAL_SERVER_AWARE`). Without the flag, Windows Server runs a program in a Remote Desktop session in a compatibility mode in which NVIDIA's driver faulted in `cuInit` for every MinGW-built program, so the GPU solver crashed at start-up on Windows Server over RDP (#1; found with the probes on the issue). The wmake rules link executables with `--tsaware`; `make-installer.sh` also marks every packaged executable (`scripts/set-tsaware.py`), and the import check refuses one without the flag.
- Cyclic patches inside a region are coupled in the conjugate temperature system, as in the p-U system; before, a periodic unit cell was adiabatic on its cyclic sides for T (coupledSimpleFoam #1). Other coupled patch types stop a conjugate run with an error.
- All three coupledSimpleFoam builds (`bin`, `bin/msmpi`, `bin/amgx`) are built from one commit, coupledSimpleFoam `feat/amgx-backend` at `a224afa`, so the CPU builds take `-region` and run conjugate cases with `conjugateSolver Eigen` without CUDA (#2). Conjugate cases run serially; the coupled p-U system can still use PETSc on one rank.
- Fix a crash in the first conjugate energy solve with `conjugateSolver Eigen`: the matrix given to Eigen's BiCGSTAB was a temporary that was freed before the solve (#2).
- The GPU build starts CUDA (through AmgX) first thing in `main`, before OpenFOAM's start-up, instead of at the first linear solve; `COUPLED_AMGX_LAZY=1` restores the old order. This alone did not fix the `cuInit` crash (#1); the Terminal-Server flag below did.
- `build-coupled.sh` replaces Visual Studio's read-only C++ runtime files in `bin/amgx` on a rebuild instead of failing.

# v14.0.0-win.7 — coupledSimpleFoam on an NVIDIA GPU

- Ship coupledSimpleFoam's GPU build as `bin/amgx/coupledSimpleFoam.exe`, from its `feat/amgx-backend` branch at `173f8bc`, beside NVIDIA AmgX 2.5.0 (`amgxsh.dll`, BSD-3-Clause) and MSVC's C++ runtime. It solves the coupled pressure-velocity system as one 4×4 block matrix with AmgX's aggregation AMG (`COUPLED { linearSolver AmgX; }`), any scalar equation with `solver AmgX;`, and, in its conjugate mode (`COUPLED { solidRegions (...); rhoCp ...; }`, run with `-region <fluid>`), the temperature of the fluid and every solid as one system. Natively on an RTX 4000 Ada against an i9-13900, public 2.1M-cell cases: an isothermal square duct in 45.8 s against 166.9 s for the coupled CPU solver on 10 MS-MPI ranks (3.6×) and 904.3 s for `foamRun incompressibleFluid` (19.7×); a heated duct in 73.3 s against 245.8 s (3.4×) and 1710.9 s for `foamRun fluid` (23.3×); a conjugate duct in 33.7 s against 474.8 s for `foamMultiRun` (14.1×), with the same answers.
- `of14-shell.ps1` adds the `coupledSimpleFoamAmgX` command, which runs the GPU build with the CUDA Toolkit's `bin` (found through `CUDA_PATH`) on its PATH. The GPU build stays off the shell's PATH, so `coupledSimpleFoam` is still the CPU build. cuBLAS, cuSPARSE and cuSOLVER come from the user's CUDA Toolkit 12 and are not shipped.
- AmgX is built for compute capabilities 7.5, 8.0, 8.6, 8.9 and 12.0 (Turing, Ampere, Ada, Blackwell workstation cards).
- Add `scripts/build-amgx.ps1`, which builds AmgX's `amgxsh.dll` natively with Visual Studio 2022 and the CUDA Toolkit, and an AmgX stage in `scripts/build-coupled.sh` (`AMGX_WINDOWS_BUILD`, `AMGX_INCLUDE`, `MSVC_RUNTIME_DIR`). `make-installer.sh` ships AmgX's license and NOTICES in `runtime-licenses/amgx` and refuses a GPU build without them. The import check resolves `bin/amgx` on its own and treats the CUDA libraries as the toolkit's.
- Add Agent Skills in `skills/` for running FoamWin from an AI coding agent: `foamwin-cpu-solvers` (shell, meshing, `foamRun`/`foamMultiRun`, Microsoft MPI), `foamwin-coupled-solver` (coupledSimpleFoam with Eigen or PETSc) and `foamwin-gpu-solver` (coupledSimpleFoamAmgX, including conjugate heat transfer). `docs/llms.txt` and the Windows README describe the coupled and GPU solvers.

# v14.0.0-win.6 — Parallel coupled solver and native speed

- Native runs are as fast as OpenFOAM 14 on WSL on the same machine: 3–4% faster on one core and 5–7% slower on 16 MPI ranks, against 43–67% and 21–51% slower before. Measured on an i9-13900 with the `pitzDailySteady` tutorial refined to 196k cells and a 343k-cell steady 3D lid-driven cavity, three interleaved runs each, with residuals identical to WSL's in every run. Four changes:
  - **Large heap blocks are reused.** The C runtime (`msvcrt`) hands every block above its heap threshold back to Windows, so each temporary field was faulted in and zeroed page by page again: 13× the page faults and 6× the kernel time of the Linux run. `libOpenFOAM` now replaces `operator new`/`delete` (`src/OSspecific/MSwindows/largeBlockCache.C`) and keeps freed blocks of 64 KiB and more, up to 1 GiB, for reuse. Every block is still a plain `malloc` block, so memory still passes safely between these operators and `libstdc++` or `free()`.
  - **Solver processes opt out of power throttling.** Windows 11 runs windowless processes, as every `mpiexec` rank is, at EcoQoS: lower clocks and the efficiency cores of a hybrid CPU. `processQoS.C` asks for full speed when `libOpenFOAM` loads; an 8-rank run got 25% faster.
  - **Medium MPI messages are split to fit MS-MPI's shared-memory slots.** MS-MPI copies a message larger than one 4 KiB slot with `ReadProcessMemory`, which costs 20–30 µs on some Windows installations whatever the size, against under 1 µs for a message that fits. `Pstream/mpi` now sends a message of 4080 bytes to 128 KiB as 4080-byte pieces ended by a shorter one, and waits for, tests and resets their requests with the message's own. Larger messages go whole, so gathers do not flood the receiver's queue. `FOAM_MPI_CHUNK_SIZE` (0 turns it off) and `FOAM_MPI_CHUNK_MAX` tune it; they must be the same on every rank, as they are when set before `mpiexec`.
  - The MinGW build uses `-O3`, as the Linux build does (1–2.5%).

- Ship coupledSimpleFoam's PETSc backend as `bin/msmpi/coupledSimpleFoam.exe`, used in place of the serial build when Microsoft MPI is installed, so coupled runs go parallel natively. The new `scripts/build-petsc.sh` cross-builds a static PETSc with hypre and a C BLAS/LAPACK against the Microsoft MPI SDK (unpacked with `msiextract`), and `scripts/build-coupled.sh` builds the PETSc variant when given `PETSC_DIR`. A 1M-cell laminar square duct on 6 ranks converged in 16 iterations and 77 s natively against 70 s on WSL, with the same friction factor.
- The packages carry the license texts of Eigen, PETSc, hypre and the reference BLAS/LAPACK in `runtime-licenses`, and `make-installer.sh` refuses to package a coupledSimpleFoam build without them. The import check follows `bin/msmpi` first for the Microsoft MPI backend, so it now checks the PETSc build too.
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

---
name: foamwin-cpu-solvers
description: Run OpenFOAM 14 natively on Windows with FoamWin on the CPU - load the shell, mesh (blockMesh, snappyHexMesh, cfMesh, gmshToFoam), run foamRun solver modules (incompressibleFluid, fluid, solid), foamMultiRun for conjugate heat transfer, legacy solvers like icoFoam, serial or in parallel with Microsoft MPI (decomposePar, Invoke-FoamWinParallel, reconstructPar), and post-process. Use whenever a task runs OpenFOAM on Windows without WSL, mentions FoamWin, of14-shell.ps1, OF14-win, foamRun on Windows, MS-MPI, mpiexec with OpenFOAM, or a FoamWin error such as "Cannot find patchField", "Unknown patchField type", "wrong token type" with -libs, or paths with spaces.
---

# OpenFOAM 14 on Windows with FoamWin: CPU solvers

FoamWin is Foundation OpenFOAM 14 compiled for native Windows (MinGW-w64). Executable names,
dictionaries and tutorials are the Linux ones; the differences are the launcher, parallel runs and
a few Windows rules below. For the coupled pressure-velocity solver see the `foamwin-coupled-solver`
skill; for NVIDIA GPUs see `foamwin-gpu-solver`.

## 1. Load the environment

Every command needs the FoamWin environment in the current PowerShell session:

```powershell
. "$env:LOCALAPPDATA\OpenFOAM-14-win\of14-shell.ps1" -Quiet            # serial
. "$env:LOCALAPPDATA\OpenFOAM-14-win\of14-shell.ps1" -Quiet -Parallel  # require MS-MPI
```

- The GUI installer's default is `C:\Program Files\OpenFOAM-14`; a ZIP install is wherever
  `setup-openfoam14.ps1 -InstallDir` put it (default `%LOCALAPPDATA%\OpenFOAM-14-win`). Find it with
  `Get-ChildItem -Recurse -Filter of14-shell.ps1` if unsure.
- **Dot-source it** (`. path`), or the variables vanish with the child scope.
- `-Quiet` skips the prompts and the `cd` to `%USERPROFILE%\OpenFOAM\run`; use it in scripts.
- `$env:FOAM_MPI` is `msmpi` when Microsoft MPI is installed, else `dummy` (serial only).
- `& "<install>\of14-env.ps1"` prints the environment and tool inventory as JSON (for programs
  that drive FoamWin).
- Smoke tests: `of14-smoke-test.ps1` (cavity, add `-Processes 4` for MPI), `of14-mesh-test.ps1`,
  `of14-cfmesh-test.ps1`.

## 2. Run a case

Run tools inside the case folder, exactly as on Linux:

```powershell
Set-Location D:\cases\pitzDaily
blockMesh
checkMesh
foamRun -solver incompressibleFluid      # steady/transient incompressible
foamRun -solver fluid                    # compressible / heat transfer
foamMultiRun                             # several regions (regionSolvers in controlDict)
foamPostProcess -func "patchAverage(name=outlet, p)" -latestTime
foamToVTK -latestTime
```

Rules that differ from Linux:

- **No Bash.** There are no `Allrun` scripts, `runApplication`, `foamDictionary -expand` pipelines or
  `sed`; write PowerShell, and redirect logs with `*> log.foamRun`.
- **Paths with spaces**: OpenFOAM rejects whitespace in `fileName`. Run from a case folder without
  spaces, or pass `-case (ConvertTo-OpenFOAMPath 'D:/my case')` (a junction alias).
- **`-libs`** accepts `'(libA.dll libB.dll)'`, a bare `libA.dll` or bare words; PowerShell strips
  inner quotes, which FoamWin tolerates.
- **Stopping a run cleanly**: `stopAtWriteNowSignal` must be `21` (SIGBREAK, sent by Ctrl+Break) and
  is read at startup from `configDict` (the installed `etc/configDict` or
  `%USERPROFILE%\.OpenFOAM\14\configDict`), not from the case. Alternatively edit the case's
  `system/controlDict` to `stopAt writeNow;` while `runTimeModifiable` is on.
- **No ParaView** is bundled: open `<case>.foam` (an empty file) in a separately installed ParaView,
  or use `foamToVTK`.
- No dynamic code compilation (`#codeStream`, `coded*` function objects) without extra compiler
  setup: prefer built-in function objects.

## 3. Parallel (Microsoft MPI)

Needs `msmpisetup.exe` (Microsoft MPI runtime) installed and the shell reopened.

```powershell
. "<install>\of14-shell.ps1" -Quiet -Parallel
# system/decomposeParDict: numberOfSubdomains N; method scotch;   (or metis, simple, hierarchical)
decomposePar -force
Invoke-FoamWinParallel -Processes 8 -Application foamRun -Arguments @('-solver','incompressibleFluid')
reconstructPar -latestTime
```

- `Invoke-FoamWinParallel` runs `mpiexec -n N <app> -parallel -case <case>`; `-Case` defaults to
  the current folder. Calling `& $env:FOAM_MPIEXEC -n 8 foamRun.exe -parallel ...` also works.
- `snappyHexMesh` runs in parallel the same way; `blockMesh` is serial.
- Partitioners: `scotch` and `metis` for `decomposePar`; `ptscotch` and `zoltan` for
  `redistributePar` and load balancing.
- Multi-region cases: `decomposePar -allRegions`, `reconstructPar -allRegions`.
- Native runs are about as fast as OpenFOAM on WSL (within a few percent, single and multi rank).
  Leave a couple of cores free for the desktop on a hybrid CPU.

## 4. Meshing tools

`blockMesh`, `snappyHexMesh` (+ `surfaceFeatures`), cfMesh (`cartesianMesh`, `tetMesh`, `pMesh`,
`cartesian2DMesh`, `generateBoundaryLayers`, `improveMeshQuality`), Gmsh (`gmsh.exe` in the
install's `gmsh` folder, on PATH) with `gmshToFoam`, `topoSet`, `splitMeshRegions -cellZones`,
`extrudeMesh`, `createPatch`, `checkMesh`.

- cfMesh: STL patches without a type become `empty`; set types with `renameBoundary` in `meshDict`.
- Multi-region (conjugate) meshes: cell zones, then `splitMeshRegions -cellZones -overwrite`;
  interfaces are `<a>_to_<b>` `mappedWall` patches.

## 5. Choosing a CPU solver

| Problem | Solver |
| --- | --- |
| Steady/transient incompressible flow, any turbulence | `foamRun -solver incompressibleFluid` |
| Heat transfer, buoyancy, compressible | `foamRun -solver fluid` |
| Fluid + solid conduction (CHT) | `foamMultiRun` with `regionSolvers { fluid fluid; solid solid; }` |
| Steady incompressible, faster convergence, passive temperature | `coupledSimpleFoam` (skill `foamwin-coupled-solver`) |
| Same, on an NVIDIA GPU, incl. CHT | `coupledSimpleFoamAmgX` (skill `foamwin-gpu-solver`) |

The segregated solvers typically need several hundred to a few thousand SIMPLE iterations on a
laminar duct; the coupled solver needs 10-30 outer iterations for the same answer.

## 6. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `Cannot find patchField entry for X` | A field lacks an entry for a patch the (region's) mesh has; add it (a split region gets patches from other bodies). |
| `Unknown patchField type` in decomposePar/reconstructPar | Fixed in win.6; on older installs pass `-libs '(libincompressibleMomentumTransportModels.dll)'`. |
| `wrong token type - expected string` with `-libs` | Old install; upgrade to win.6+ or use bare names. |
| A tool is "not recognized" | The shell is not loaded in this session, or the tool is a GPU build (`coupledSimpleFoamAmgX` is a shell function). |
| `0xC0000135` exit (DLL not found) | Started outside the FoamWin shell's PATH; dot-source `of14-shell.ps1` first. |
| `fileName ... contains whitespace` | Use a path without spaces or `ConvertTo-OpenFOAMPath`. |
| Parallel throws "Microsoft MPI is unavailable" | Install MS-MPI and reopen the shell. |

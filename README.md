# FoamWin

### OpenFOAM 14 for Windows.

**FoamWin** (`foamwin`) is a community Windows port of Foundation OpenFOAM 14,
using MinGW-w64 and the blueCFD-derived Windows OS layer. It includes a native
PowerShell launcher, a Windows installer, and validated cavity examples.

This is an independent community port, not an official OpenFOAM distribution.
The Windows binaries run without MSYS2 or WSL. Building from source requires Linux.

## Download and install

The latest release is **v14.0.0-win.3**, adding native application attachment support.
Microsoft MPI support was introduced in v14.0.0-win.2.
The original serial release remains available as v14.0.0-win.1.
Its distribution files retain the tested OpenFOAM package names:

| File | Purpose |
|---|---|
| `OF14-win-setup.exe` | Guided installer, Desktop/Start Menu shortcuts, and uninstaller |
| `OF14-win.zip` | Portable distribution with a PowerShell installation option |

Download these assets from [GitHub Releases](https://github.com/dhanninacs/foamWin/releases/latest).
The source archive alone does not contain the compiled Windows binaries.

For the installer, run `OF14-win-setup.exe` and approve the Windows administrator
prompt. For the portable package, extract the ZIP into a folder of your choice.
Open the **OpenFOAM 14** shortcut or double-click `of14-shell.bat`.

The shell configures the binaries and DLLs and opens your OpenFOAM run directory.
Installation paths containing spaces are supported through junction aliases.
MSYS2 is optional and is not required by the native launcher.

## Run the cavity example

In the OpenFOAM shell:

```powershell
blockMesh -help
```

Then run the complete smoke-test command printed by the launcher. It points to
`of14-smoke-test.ps1` in the installation directory. The script:

1. Copies the included legacy icoFoam cavity tutorial into a new run folder.
2. Runs `blockMesh`, `checkMesh`, and `icoFoam`.
3. Checks for `Mesh OK` and the final velocity field at time **0.5 s**.
4. Retains the logs and creates `cavity.foam` for post-processing.

If you are already in the extracted distribution directory, you can run it directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./of14-smoke-test.ps1
```

Install ParaView separately and open `cavity.foam` to inspect the result.
See [Windows usage](packaging/WINDOWS-README.md) for installation and path details.

## Validation

Native Windows testing covered:

- Startup checks for **all packaged executables**.
- The legacy cavity example: mesh generation, `Mesh OK`, and icoFoam through 0.5 s.
- Scotch and METIS decomposition, PT-Scotch and Zoltan parallel redistribution.
- cfMesh `cartesianMesh` with boundary layers, passing `checkMesh`.
- The modern incompressibleFluid cavity with `foamRun` through time 10.
- Actual installation, installed-package execution, and the Desktop shortcut.
- Installation/case paths with spaces, runtime DLL imports, and ZIP integrity.

These are execution and smoke tests, not exhaustive physical-model benchmarks.

## Limitations

- Optional Microsoft MPI enables local parallel solving and snappyHexMesh; serial fallback remains available.
- **64-bit Windows**, double precision, 32-bit labels.
- ParaView is not bundled.
- Runtime code compilation needs additional compiler configuration.
- The build needs its external zlib dependency, and the partitioners and cfMesh
  need their separately cloned sources (see below).

## Source and packaging

Use a **case-sensitive Linux filesystem** for the source checkout. OpenFOAM has
files and directories whose names differ only by capitalization; a normal Windows
checkout can merge or overwrite them.

Build tools include MinGW-w64 GCC, make, and flex. Packaging requires Python 3,
NSIS, and zip. With the cross-build prerequisites available:

```bash
bash OpenFOAM-14/build-all.sh
bash scripts/make-installer.sh
```

For a completed build outside this repository, set `OF14_SOURCE` to its OpenFOAM
directory. `OF14_OUTPUT` selects the output folder. `WIN_RUNTIME_DIR` and
`OF14_EXT_LIBBIN` select compiler runtimes and the stack-trace helper when needed.
Packaging validates imports and produces fresh EXE/ZIP distributions.

| Path | Contents |
|---|---|
| `OpenFOAM-14/` | Patched OpenFOAM sources and Windows build rules |
| `third-party/stack_trace/` | Windows stack-trace helper source |
| `installer/` | Native launcher, smoke test, and installer definitions |
| `scripts/` | Build/packaging helpers and validation checks |
| `patches/cfmesh/` | Patches applied to the cfMesh fork for OpenFOAM 14 and MinGW |
| `packaging/` | Windows usage, packaging, and repair documentation |

See [porting notes](PORTING-NOTES.md), [repair details](packaging/WINDOWS-REPAIR.md),
and [packaging instructions](packaging/README.md).

## Privacy and publishing

Before publishing source changes:

```bash
python3 scripts/check-private-data.py --history
```

This pattern-based check reports file paths and finding categories without printing
matched secrets. Credentials, compiled artifacts, and local validation output are
excluded by `.gitignore`. Keep private backups outside the repository. Attach the
EXE and ZIP to GitHub Releases rather than committing them to the source tree.
See [repository settings](REPOSITORY.md) and [release notes](CHANGELOG.md).

## License and credits

OpenFOAM and the derived Windows patches are distributed under **GPLv3**; see
[LICENSE](LICENSE) and [OpenFOAM COPYING](OpenFOAM-14/COPYING). Preserve the OpenFOAM
Foundation and blueCFD/blueCAPE upstream copyright and attribution. Third-party
runtime DLLs retain their own licenses and notices, included with the distributions.


## Parallel meshing and solving

Microsoft MPI is optional for serial work and required for parallel runs. Install
`msmpisetup.exe` from [Microsoft MPI](https://www.microsoft.com/en-us/download/details.aspx?id=105289),
then reopen FoamWin. If the runtime is missing, the interactive launcher prompts
to open that page and retains serial mode. The SDK is only needed when building.

From the extracted package directory, run these validated examples:

```powershell
. ./of14-shell.ps1 -Quiet -Parallel
./of14-smoke-test.ps1 -Processes 4
./of14-mesh-test.ps1 -Processes 4
```

For your own case, set `numberOfSubdomains` in `system/decomposeParDict` to match
`-Processes`, select a `method` (see below), then run `decomposePar`.
Use `Invoke-FoamWinParallel -Processes 4 -Application icoFoam -Case <case-folder>`
(or your solver). Run `reconstructPar -latestTime` afterwards.
`snappyHexMesh` supports the same helper; `blockMesh` remains serial.
The mesh example includes parallel refinement, mesh reconstruction, and quality checks.
Local runs on two and four processes have been validated; multi-host operation and
performance scaling have not been tested.

To build the MPI additions after a serial cross-build, run
`scripts/build-msmpi.sh <extracted-msmpi-sdk-directory>` on Linux.
The SDK must contain `mpi.h` and the x64 `msmpi64.lib`; SDK files are not committed.

## Partitioners

Besides the built-in `simple`, `hierarchical`, `manual` and `random` methods, the
packages include the graph partitioners:

| Method | Library | Use |
|---|---|---|
| `scotch`, `metis` | Scotch 7.0.12, METIS 5.2.1 with GKlib | `decomposePar`, serial or parallel |
| `ptscotch`, `zoltan` | PT-Scotch 7.0.12, Zoltan 3.90 | Parallel redistribution and load balancing (MS-MPI) |

`scripts/test-windows-partitioners.ps1 -RuntimeRoot <package> -OutputDirectory <new-folder> -Processes 4`
checks all four. To build them, cross-build the third-party sources with
`scripts/build-thirdparty-partitioners.sh` (Scotch and Zoltan from OpenFOAM's
ThirdParty-14 repository, METIS and GKlib from KarypisLab), then run
`scripts/build-partitioners.sh` with the paths it prints. Their license texts are
packaged under `runtime-licenses`.

## cfMesh

The packages include cfMesh (`cartesianMesh`, `tetMesh`, `pMesh`, `cartesian2DMesh`,
`generateBoundaryLayers`, `improveMeshQuality` and the surface utilities), built
from the [cfMesh-OpenFOAM13 fork](https://github.com/Ultravis66/cfMesh-OpenFOAM13)
at commit `2e36fe7` with `patches/cfmesh` applied for OpenFOAM 14 and MinGW.
Run `./of14-cfmesh-test.ps1` to mesh the included cube with boundary layers and
check it. To build it, run `scripts/build-cfmesh.sh` with `CFMESH_SOURCE` set to a
clone of the fork. STL patches without a type are read as `empty`; set their type
with a `renameBoundary` entry in `meshDict`, as the example does.

## Attaching a CFD application

The native engine includes surfaceFeatures, foamPostProcess and foamToVTK,
plus the existing meshing, solver and parallel tools. `of14-env.ps1` returns a
JSON environment and tool inventory for a Windows host adapter; no Bash is needed.
Run `./of14-runtime-test.ps1` to validate feature extraction, modern solving,
velocity post-processing and VTK export. See the source repository's
[attachment guide](https://github.com/dhanninacs/foamWin/blob/main/docs/NATIVE-ENGINE.md)
for the interface and Windows runner requirements. The GUI application and CAD/VTK
Python dependencies are separate from this engine.

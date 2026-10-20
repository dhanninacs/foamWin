# OpenFOAM 14 for native Windows

This repository ports Foundation OpenFOAM 14 to 64-bit Windows using MinGW-w64
and the blueCFD-derived Windows OS layer. Windows execution uses the native
PowerShell launcher; MSYS2 and WSL are not required at runtime.

## Run a Windows distribution

Extract OF14-win.zip or install OF14-win-setup.exe, then open of14-shell.bat or
the OpenFOAM 14 shortcut. The shell starts in the OpenFOAM run directory.
The launcher supports installation paths with spaces through junction aliases.

```powershell
blockMesh -help
& ./of14-smoke-test.ps1
```

The shell prints the full path to the smoke-test script. If your current folder
is the run directory, use that printed path. The test copies the included legacy
cavity case, runs blockMesh, checkMesh, and icoFoam, and verifies the final field
at time 0.5. See [Windows usage](packaging/WINDOWS-README.md).

## Build and package

Use a case-sensitive Linux filesystem for the source checkout. OpenFOAM has
source files and directories whose names differ only by capitalization.
Build tools: MinGW-w64 GCC, make, flex; packaging: Python 3, NSIS, zip.
The original full build driver still requires its external regex/zlib dependencies
and has not been validated by a complete rebuild during this runtime repair.

```bash
bash OpenFOAM-14/build-all.sh
bash scripts/make-installer.sh
```

For an existing completed build, set OF14_SOURCE to its OpenFOAM directory.
Packaging resolves matching compiler DLLs with CXX -print-file-name, bundles the
stack-trace helper, checks all package imports, and creates a fresh ZIP and EXE.
WIN_RUNTIME_DIR and OF14_EXT_LIBBIN override the runtime and helper locations.

```bash
python3 scripts/check-private-data.py --history
```

The privacy check reports filenames and categories, never matched credentials.
Local credentials and validation output are ignored. Git identities use a generic
contributor identity; upstream copyright and license attribution is preserved.

## Validation and limits

85 executable help checks, legacy cavity, modern foamRun incompressibleFluid
cavity, installed-package execution, and the actual desktop shortcut were tested
on Windows. Serial execution only; ParaView is installed separately. Runtime code
compilation needs additional compiler setup. This is smoke testing, not exhaustive
validation of all physical models.

See [repair details](packaging/WINDOWS-REPAIR.md), [porting notes](PORTING-NOTES.md),
and [packaging](packaging/README.md). OpenFOAM and its derived Windows patches are
GPLv3; retain upstream copyright and third-party runtime licenses.

# OpenFOAM 14 — native Windows package

64-bit Windows executables, double precision, 32-bit labels, serial execution.
The PowerShell launcher runs without MSYS2 or WSL. Building from source still
requires a Linux MinGW-w64 cross compiler.

## Run the portable package

Extract the ZIP, then double-click `of14-shell.bat`.
Installation directories with spaces work through a temporary junction alias.
The launcher leaves the installation in its original location. For your own case
folder with spaces, pass `-case (ConvertTo-OpenFOAMPath 'D:/my case')` after loading
the launcher. The smoke-test script handles this automatically.

Alternatively, from PowerShell:

```powershell
. ./of14-shell.ps1
blockMesh -help
& ./of14-smoke-test.ps1
```

If Windows blocks script execution, start with:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ./of14-smoke-test.ps1
```

The smoke test copies the included legacy icoFoam cavity tutorial into a new
folder under `%USERPROFILE%/OpenFOAM/run`, runs blockMesh, checkMesh and icoFoam,
and verifies the final velocity field at time 0.5. Logs stay in that case folder.
Open `cavity.foam` in a separately installed ParaView to view the result.

## Install

Use `OF14-win-setup.exe`, or:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ./setup-openfoam14.ps1
```

The script defaults to `%LOCALAPPDATA%/OpenFOAM-14-win`; `-InstallDir` changes it
and `-NoShortcut` disables the desktop shortcut. The GUI installer offers MSYS2
as an optional component; it is not needed by the native launcher.

## Validation on 20 October 2026

All 85 executables passed `-help` on Windows. The cavity case passed blockMesh,
checkMesh (Mesh OK), and icoFoam through time 0.5. This is a smoke test, not
validation of every solver or physical model.

The package includes the GCC 13 Win32 runtimes used for this validation and
libstack_trace.dll. The legacy particle library is named liblagrangOld.dll to
avoid Windows' case-insensitive collision with modern libLagrangian.dll.
OpenFOAM constructor initialization order is corrected for MinGW.

Serial only; no bundled ParaView. Runtime code compilation needs additional
compiler setup. See the source repository for GPLv3 source and porting notes.

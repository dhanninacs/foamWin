# FoamHarbor Windows packaging

Run `bash scripts/make-installer.sh` from a completed Linux cross-build. It creates
OF14-win-setup.exe and OF14-win.zip from the same staging tree. Set OF14_SOURCE
to package a completed build outside this repository, and OF14_OUTPUT for output.

Required runtimes and exported imports are checked before NSIS runs. Missing or
incompatible dependencies fail packaging. Archives contain only EXE/DLL runtime
files, environment configuration, native launchers, runtime license notices, and
a clean cavity fixture. A fresh ZIP prevents obsolete entries surviving a rebuild.

The EXE includes install/uninstall registration and optional shortcuts. MSYS2 is
optional; the PowerShell launcher requires neither MSYS2 nor WSL. See
[Windows usage](WINDOWS-README.md) and [repair details](WINDOWS-REPAIR.md).

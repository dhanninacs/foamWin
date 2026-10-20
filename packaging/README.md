# Packaging

Two end-user distributions can be produced from a completed build:

| File | Tool | Description |
|---|---|---|
| `OF14-win-setup.exe` | NSIS (`installer/OF14-installer.nsi`) | Guided GUI installer: license, component choice, folder picker, shortcuts, uninstaller, optional auto-MSYS2 download. |
| `OF14-win.zip` | `scripts/make-installer.sh` | Portable tree + `setup-openfoam14.ps1` silent installer. |

## Reproduce
```bash
./scripts/make-installer.sh
```

## Contents shipped
- `etc/` — OpenFOAM environment (bashrc, caseDicts, templates)
- `platforms/linuxmingw-w64GccDPInt32Opt/bin/*.exe` — 85 tools
- `platforms/linuxmingw-w64GccDPInt32Opt/lib/*.dll` — core libs (+ `lib/dummy`)
- MinGW runtime DLLs (`libgcc_s_seh-1`, `libstdc++-6`, `libgnurx-0`, `zlib1`)
- `of14-shell.bat` — location-independent launcher (`%~dp0`-based)

# OpenFOAM 14 for Windows — MinGW-w64 native port (blueCFD-style)

Native Windows build of **OpenFOAM 14** (OpenFOAM Foundation codebase), produced by
cross-compiling the patched sources in this repository with the **MinGW-w64 GCC**
toolchain on Linux. It follows the same technical approach popularized by the
blueCFD-Core project: a Win32 `OSspecific` layer, MinGW import-library linkage,
and a `.dll/.exe`-based platform target (`linuxmingw-w64GccDPInt32Opt`).

> **Status:** tested build of **85 executables + ~113 DLLs** — the full stack:
> meshing (blockMesh, snappyHexMesh, topoSet), solvers (modules + legacy),
> finite volume, thermophysical, Lagrangian, fvModels/fvConstraints,
> conversion, and all standard OpenFOAM utilities.

---

## Repository layout

| Path | Contents |
|---|---|
| [`OpenFOAM-14/`](OpenFOAM-14/) | **Full patched OpenFOAM 14 source.** Includes the MSwindows `OSspecific` layer, mingw-w64 `wmake` rules, and every source patch required to cross-compile for Windows. Builds on Linux; produces Windows binaries. |
| [`third-party/stack_trace/`](third-party/stack_trace/) | Small Windows stack-tracing helper library (dbghelp-based) required by `libOpenFOAM` during the link phase. |
| [`installer/`](installer/) | Two installers for end users: NSIS-driven GUI installer (`.nsi`) and a PowerShell script; plus the location-independent shell launcher `.bat`. |
| [`packaging/`](packaging/) | Packaging notes for producing `OF14-win-setup.exe` / `OF14-win.zip`. |
| [`scripts/make-installer.sh`](scripts/make-installer.sh) | Packages a completed build into `OF14-win-setup.exe` + `OF14-win.zip`. (The actual build driver is [`OpenFOAM-14/build-all.sh`](OpenFOAM-14/build-all.sh).) |

The **compile output** (`platforms/linuxmingw-w64GccDPInt32Opt/` with
`.exe`/`.dll`) is intentionally **not committed** (it's ~2 GB of binaries).
Build it from this repo, or grab a prebuilt package from
[Releases](https://github.com/YOUR-USER/of14-windows/releases).

---

## Building from source (on Linux)

Tested on Ubuntu 24.04/26.04; anything with:

```bash
sudo apt install mingw-w64 g++-mingw-w64-x86-64 flex make zip
```

### One-command build

```bash
cd OpenFOAM-14
./build-all.sh          # builds wmake host tools, stack_trace, all libs + solvers/utilities
```
Then (optionally) package installers:
```bash
../scripts/make-installer.sh
```

Behind the scenes it does:
1. Builds `wmake`'s **host** tools with native `gcc` (not mingw) — they run during the build.
2. Builds Windows `libstack_trace.dll` into `${FOAM_EXT_LIBBIN}`.
3. **Two-pass Pstream**: first as *static* `libPstream.a`, letting the first
   `libOpenFOAM.dll` link cleanly; then re-built as a real `libPstream.dll`,
   `libOpenFOAM.dll` deleted and re-linked against the shared Pstream.
   (This breaks the classic `OpenFOAM <-> Pstream` circularity on Windows.)
4. Builds all libraries in dependency order, then `applications/`.

Environment config (already configured for mingw cross-compile):

```bash
source OpenFOAM-14/etc/pre-bashrc-mingw_w64.sh
```

This sets `WM_ARCH=linuxmingw-w64`, `WM_CC=x86_64-w64-mingw32-gcc`,
`WM_CXX=x86_64-w64-mingw32-g++`, `WM_OSTYPE=MSwindows`, `WM_MPLIB=dummy`.

### Key technical notes (what makes the port work)

| Issue | Solution in this tree |
|---|---|
| `OSspecific` needs Win32 (no `fork`, POSIX-only `dlopen`) | `OpenFOAM-14/src/OSspecific/MSwindows/` (blueCFD-derived) using `LoadLibrary`, no inotify, Win32 file iter |
| `regex.h` absent in MinGW | link `libgnurx` from MSYS2 (`-lregex`); headers shipped in sysroot or via `installer/` |
| List-include cycles and `mode_t` mismatch | `hacks_on_mingw.h` + `Include order fixes in `fileMonitor.H``; `mode_t` handled in API callsites |
| `mode_t` streaming in `masterUncollatedFileOperation` | call-sites patched to `masterOp<unsigned int,...>` plus `static_cast<mode_t>` where returned |
| `off_t` is `long` (32-bit) under MinGW | streaming call-sites cast via `label`; `off_t` kept where only arithmetic |
| `Hash<void*>` — cast from pointer | hash via `intptr_t`, mask to 31 bits for deterministic hashing under `-Wall` |
| MinGW trans float math | `doubleFloat.H`: `j0f/j1f/ynf... -> _j0/_j1/_yn` shims under `__STRICT_ANSI__`. `longDoubleScalar.H`: fall back to `jn/yn` double variants under `WIN32/WIN64` |
| `MessageStream`/template instantiations compiled twice | Set `EXE_LIBS`/`LIB_LIBS` explicitly for Windows (mingw has no implicit linking from dependencies); some `.T.C` headers forces included via `#ifdef NoRepository` |
| `error::operator()` is non-const | Fixed v12-era const-callers that relied on older signatures |
| Circular OpenFOAM↔Pstream | Two-pass static-then-shared approach (see `build-all.sh`) |
| Executables link against `libOpenFOAM.dll` | `wmake` rules produce `.dll` (via `-shared -Wl,--out-implib`) and `.exe` (via `--enable-auto-import`) |
| `popen` / `backtrace` absent | `OSspecific/MSwindows` uses `CreateProcess`, and `third-party/stack_trace` (`dbghelp`) for stack traces |
| Very large TU (`.o` > 2 GB PE limit) for `multicomponentThermo` | trans. split into `...Thermos{CoeffGases,GasesLiquids,LiquidsTabulated}.C` in `Make/files` |

### Prebuilt runtime DLLs you need

`installer/` bundles the MinGW runtime DLLs (`libgcc_s_seh-1.dll`,
`libstdc++-6.dll`, `libgnurx-0.dll`, `zlib1.dll`) — they go next to the
`.exe`/`.dll` output (they are **shipped in the installer**; when building
yourself you may need-to-copy them from `/usr/x86_64-w64-mingw32/bin` to
`platforms/${WM_OPTIONS}/bin`).

---

## Installing (on Windows)

### Option A: guided installer (recommended)
Double-click **`OF14-win-setup.exe`** (built from `installer/OF14-installer.nsi`):

1. Welcome & GPLv3 license
2. Choose components (core required; Start-Menu/Desktop shortcuts; *Install
   MSYS2 automatically* to fetch `C:\msys64` if absent)
3. Choose install folder (default `C:\Program Files\OpenFOAM-14`)
4. Finish → *"Open an OpenFOAM 14 shell now"* button

Shortcuts launch `of14-shell.bat`, which sets `PATH` for DLL resolution,
finds MSYS2 (bundled copy, `C:\msys64`, or registry), and drops you into a
bash shell with OpenFOAM configured.

### Option B: PowerShell script
```
powershell -ExecutionPolicy Bypass -File installer/setup-openfoam14.ps1
```
Auto-installs MSYS2 if missing; flags `-Msys2Root`, `-InstallDir`, `-SkipMsys2`.

### First test (inside the shell)
```
mkdir -p $FOAM_RUN && cd $FOAM_RUN
cp -r $FOAM_TUTORIALS/incompressibleFluid/icoFoam/cavity .
cd cavity && blockMesh && checkMesh && icoFoam
```

---

## Limitations / known gaps

* **Serial only** (dummy MPI). Parallel (MPI) would need MS-MPI build of
  `src/Pstream/mpi` and `WM_MPLIB=MSMPI` — infrastructure exists, work not done.
* No ParaView: install standalone ParaView for post-processing.
* Dynamic code compilation (`codeStream`) requires a Windows compiler at
  runtime — not shipped.
* Some rarely-used utilities that need extra ThirdParty libs (e.g. scotch,
  CGAL) build only with dummy stubs.

---

## License

* **OpenFOAM** (under `OpenFOAM-14/`): **GPLv3**, © OpenFOAM Foundation —
  see [`OpenFOAM-14/COPYING`](OpenFOAM-14/COPYING).
* Windows-specific patches and the `MSwindows` OSspecific layer: GPL-derived;
  original code from [blueCFD-Core](https://github.com/blueCFD/Core) (GPLv3, ©
  blueCAPE / FS Dynamics), adapted for OpenFOAM 14 by this project.
* The `third-party/stack_trace` helper: original blueCFD-Core code (GPLv3).
* MinGW runtime DLLs in installers: their own free licenses (GPL with
  runtime-exception and BSD-family bits).

This repository is distributed under **GPLv3**. See [`LICENSE`](LICENSE.txt).

---

## Credits

* [OpenFOAM Foundation](https://openfoam.org) — OpenFOAM 14 source (GPLv3)
* [blueCFD-Core (blueCAPE / FS Dynamics)](https://github.com/blueCFD/Core) —
  the original `MSwindows` OSspecific layer and mingw-w64 wmake approach this
  port builds on (GPLv3)
* [MinGW-w64](https://mingw-w64.org) + MSYS2 — the toolchain
* NSIS — the GUI installer

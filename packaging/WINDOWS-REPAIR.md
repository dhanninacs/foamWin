# Windows repair, 20 October 2026

Confirmed on this machine using Windows executables launched by PowerShell.

## Causes and fixes

- Missing libgcc_s_seh-1.dll, libstdc++-6.dll, and libstack_trace.dll. Bundle the
  GCC 13 Win32 runtimes from the Ubuntu cross compiler and the stack-trace helper.
  GCC 14/16 runtimes tried during diagnosis lacked a symbol this build imports;
  choosing a newer runtime by filename alone did not work.
- liblagrangian.dll and libLagrangian.dll collide on normal Windows filesystems.
  Rebuilt src/lagrangian/basic as liblagrangOld.dll, updated its consumers' import
  names in the existing binaries, and changed Make definitions for future builds.
- MinGW invokes .ctors backwards, reversing dependencies established by Make/files.
  This crashed while dimensions initialized before dimensionTypeNames_. The current
  libOpenFOAM.dll has its constructor list reordered. Future Windows links reverse
  the object inputs in wmake/makefiles/general so constructor calls follow source
  order. A full rebuild of every library has not been performed in this repair.
- Added native PowerShell environment and smoke-test scripts, a clean cavity
  fixture, fail-fast import/export validation, and corrected ZIP/NSIS staging.
  MSYS2 is optional. The PowerShell installer now installs the same native launcher.

- OpenFOAM's fileName strips whitespace. The launcher and smoke test map installation
  and case directories with spaces through checked NTFS junctions in TEMP. The
  original files stay in place. This also supports the GUI installer's Program Files
  default. TEMP must have a whitespace-free path. Both package layouts pass the
  cavity test with spaces in the installation and case paths.

## Existing-build migration

scripts/repair-prebuilt.py applies the specific original binary migration with
SHA256 checks and refuses to alter an unfamiliar core library. It requires the
rebuilt liblagrangOld.dll, a compatible runtime directory, and libstack_trace.dll.
It is idempotent for the repaired core. New builds should use the source fixes.

The legacy library was rebuilt on the WSL Linux filesystem from `git archive HEAD`
so Windows source-name collisions did not affect compilation. Host wmake tools
were built using gcc; MinGW GCC 13 compiled the six legacy particle sources.
Existing import libraries were used for the other already-built OpenFOAM DLLs.
The repaired build directory is ~/of14-repair/OpenFOAM-14 in Ubuntu-24.04.

Runtime archive: Ubuntu gcc-mingw-w64-x86-64-win32-runtime
13.2.0-6ubuntu1+26.1 (amd64), SHA256
7ac09bc7f283f1148c8e1697373db069c1d4364a9f5fa58bb66c8a93760b8b65.
Runtime copyright notices accompany the package.

## Validation

- Import/export validation: 85 executables, 117 DLLs; no missing package imports.
- Every executable: -help returns 0 on Windows.
- Legacy cavity: blockMesh, checkMesh (Mesh OK), icoFoam return 0; time 0.5 fields.
- Modern cavity: blockMesh, checkMesh, foamRun return 0; incompressibleFluid module
  advances to time 10, including turbulence model iterations.
- Native PowerShell smoke test passes without MSYS2 or Git runtime directories.

No parallel MPI or exhaustive physical-model validation is claimed.

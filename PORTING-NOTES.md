# Porting notes: OpenFOAM 12 (blueCFD) → OpenFOAM 14 (MinGW-w64)

Detailed list of every code change needed to make Foundation OpenFOAM 14
cross-compile for Windows with MinGW-w64. See also git history inside
`OpenFOAM-14/` (each patch is observable as a diff against upstream).

## 1. OSspecific layer
- Replace `src/OSspecific/POSIX` with `src/OSspecific/MSwindows` (blueCFD).
- v12→v14 header renames inside it: `DynamicList.T.H`→`DynamicList.H`,
  `HashSet.T.H`→`HashSet.H`, `Pstream.T.H`→`Pstream.H`,
  `PackedList.T.H`→`PackedList.H`, `NamedEnum` overload updates, etc.
- v14 API deltas: `ping(const string&&)` (was `const word&`);
  `NamedEnum` brace-initialized (no `names[]` template specialization).
- `toUnixPath` declared in v14's `OSspecific.H`; implemented in MSwindows.C.

## 2. Include-order hacks (MinGW)
- `include/hacks_on_mingw.h` — tolerant `mode_t` import (mingw already
  defines it in `sys/types.h`).
- `fileMonitor.H` must include `hacks_on_mingw.h` BEFORE `<sys/types.h>`.
- `regex.h` (from libgnurx) also pulls `sys/types.h` — all sites tolerant
  now.

## 3. Streaming fixes for MinGW primitive types
- `mode_t` is `unsigned short` on mingw (vs `unsigned int` Linux) — has no
  Foam stream operators. Fix via patching call-sites of
  `masterOp<mode_t, ...>` in
  `masterUncollatedFileOperation.C` to `masterOp<unsigned int, ...>` with
  explicit casts.
- `off_t`/`time_t` streaming: cast to `label` in
  `masterUncollatedFileOperation.C`, `OFstreamCollator.C`, `dynamicCode.C`.
- `Pstream::scatter(off_t)` → scatter a `label` then cast back.

## 4. API / v14 upstream deltas
- `processorFvPatchScalarField.C` excluded from `finiteVolume/Make/files`
  (already header-included via `NoRepository`, avoids duplicate symbols).
- `ping()` signature const in newer `OSspecific.H`.
- `error::operator()` is non-const — fixed callers.
- `masterOp` templates instantiated for `unsigned int`.

## 5. wmake / build system
- `wmake/rules/linuxmingw-w64Gcc/` — mingw64 compile/link rules
  (produces `.dll` + `.exe`, `--enable-auto-import`, `-DWIN64
  -DLITTLE_ENDIAN`).
- Add rules `mplibDummy`, `rc` (resource compiler), and `mplibMSMPI`.
- `wmake/makefiles/general`: `libso` link statement now includes
  `$(PROJECT_LIBS)` (needed because MinGW has no implicit transitive
  linking; every DLL must explicitly link its dependencies).
- Env: `etc/pre-bashrc-mingw_w64.sh` sets
  `WM_ARCH=linuxmingw-w64`, `WM_OSTYPE=MSwindows`, `WM_MPLIB=dummy`,
  `WM_COMPILER_ARCH=x86_64-w64-mingw32`.
- Two-pass `Pstream`: static first, then shared; delete and relink
  `libOpenFOAM.dll` (see `build-all.sh`).

## 6. Library dependency fixes (Windows has no transitive link)
Because MinGW's `ld` needs explicit `-l` for each symbol provider, many
library `Make/options` needed extra libs (would link fine on Linux):
- `subsetMesh` → + `-lfiniteVolume -lmeshTools`
- `sampling` → + `-ltracking`
- `twoPhaseMixture` → + `-lphysicalProperties`
- `functionObjects/{field,forces,solvers}` → + `-ltracking
  -lthermophysicalTransportModel`
- MomentumTransportModels `phase{Incompressible,Compressible}` → +
  `-lmomentumTransportModels`
- `multicomponentThermo`, `solidThermo` → + `-lphysicalProperties`
- `saturationModels` → + `-lfiniteVolume`
- `radiationModels` → + `-lphysicalProperties`
- `reactionModels` → + `-lspecie -lfluidThermophysicalModels`
- `ThermophysicalTransportModels/{fluidThermo,fluidMulticomponentThermo,
  phaseFluidThermo,phaseFluidMulticomponentThermo}` → +
  `-lthermophysicalTransportModel -lfluidThermophysicalTransportModel`
- `renumberMethods` → + `-lmeshTools`
- `snappyHexMesh` → + `-ldecompositionMethods -ltracking`
- `distributed` (parallel) → built from src/parallel/distributed
- `mesh/snappyHexMesh` and `lagrangian/{parcel,DSMC,molecularDynamics,
  solidParticle}` → + `-ltracking`
- `genericFvFields` → needs `genericFields`, `genericFvPatches`
  (compile order!)
- `dummyThirdParty/{scotch,ptscotch,metis}` → + `-ldecompositionMethods`
- `fvConstraints`, `fvModels/general`, fvModel plugins → + various aligning
  models (physicalProperties, thermophysicalTransportModel,
  fluidThermoThermophysicalTransportModels, fvModels, finiteVolume)
- `tracking` accessible to everything particle-tracking related.

## 7. Very large translation units
`rhoFluidMulticomponentThermos.C` overflowed PE/COFF (">2GB sections").
Split into three files and updated `Make/files`:
- `...ThermosCoeffGases.C`
- `...ThermosGasesLiquids.C`
- `...ThermosLiquidsTabulated.C`

## 8. MinGW runtime specifics
- `doubleFloat.H`: `j0f/j1f/...` → `_j0/_j1/...` (only under strict ANSI),
  then restore.
- `longDoubleScalar.H`: skip `jnl/ynl` (no long-double Bessel on MinGW);
  fall back to double-precision `jn/yn`.
- `Hash<void*>`: hash `intptr_t` (pointer) instead of `long` (32-bit on
  Win64 — otherwise compiler error about narrowing).

## 9. Third-party
- `libgnurx` / `libregex` for POSIX `regex.h` functionality.
- `stack_trace` (blueCFD) wraps `dbghelp` for `error::printStack`.

## 10. Applications / link ordering
- All executables need explicit `EXE_LIBS`; nothing implicit.
- `foamRun` etc. are plain `.exe`s linking against their module `lib*solver.dll`.

## 11. Tests
Smoke: `blockMesh && checkMesh && icoFoam` on `icoFoam/cavity` tutorial
(passes). Full group passes as of this writing:
`solvevers / modules / legacy / utilities` → 0 link errors.

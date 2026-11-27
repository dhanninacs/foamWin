---
name: foamwin-gpu-solver
description: Run OpenFOAM cases on an NVIDIA GPU natively on Windows with FoamWin's coupledSimpleFoamAmgX (coupledSimpleFoam with NVIDIA AmgX) - steady incompressible flow, passive heat transfer, and conjugate heat transfer (fluid + solids in one temperature system) - including the CUDA requirements, the COUPLED dictionary for AmgX, the multi-region layout for CHT, expected speed-ups and troubleshooting. Use whenever a task mentions GPU CFD on Windows, AmgX, CUDA with OpenFOAM, coupledSimpleFoamAmgX, bin/amgx, solidRegions, a GPU conjugate heat transfer run, or wants a faster steady solve on a workstation with an NVIDIA card.
---

# GPU solving with FoamWin (coupledSimpleFoamAmgX)

FoamWin (v14.0.0-win.7+) ships `bin/amgx/coupledSimpleFoam.exe`: coupledSimpleFoam whose linear
algebra runs on one NVIDIA GPU through AmgX. It is the `foamwin-coupled-solver` skill's solver
with `linearSolver AmgX`, so case setup is the same; this skill covers what differs.

| What | Setting | On the GPU |
| --- | --- | --- |
| Coupled p-U system | `COUPLED { linearSolver AmgX; }` | one 4x4 block matrix, BiCGStab + aggregation block AMG |
| Any scalar equation (T, k, omega) | `solvers { T { solver AmgX; ... } }` | AmgX AMG |
| Conjugate heat transfer | `COUPLED { solidRegions (...); rhoCp ...; }`, run with `-region <fluid>` | fluid and all solid temperatures as one system |

Measured on an RTX 4000 Ada vs an i9-13900 (public 2.1M-cell ducts): 3.4-3.7x the coupled CPU
solver on 10 MPI ranks, 20-25x `foamRun`, 14-15x `foamMultiRun` for CHT, with the same answers.

## Requirements (check first)

- NVIDIA GPU, compute capability 7.5, 8.x, 8.9 or 12.0 (Turing, Ampere, Ada, Blackwell
  workstation). `nvidia-smi` must work.
- **CUDA Toolkit 12** installed (cuBLAS, cuSPARSE, cuSOLVER are loaded from it, not shipped);
  `CUDA_PATH` set by its installer. Check in the shell: `Get-FoamWinCudaBin` returns its `bin`.
- One process, one GPU: no `-parallel`. The mesh must fit in GPU memory (2.1M cells used < 8 GB).
- Steady, incompressible, temperature passive (no buoyancy), as for the CPU coupled solver.

## Run

```powershell
. "<install>\of14-shell.ps1" -Quiet
Set-Location D:\cases\duct
coupledSimpleFoamAmgX *> log.gpu                    # single region
coupledSimpleFoamAmgX -region fluid *> log.gpu      # conjugate case
```

`coupledSimpleFoamAmgX` is a shell function: it runs `bin/amgx/coupledSimpleFoam.exe` with
`bin/amgx` and the CUDA `bin` on PATH. Plain `coupledSimpleFoam` stays the CPU build. A program
driving FoamWin directly must do the same (put both folders on the child's PATH).

## Single-region settings

```c++
solvers
{
    T { solver AmgX; tolerance 1e-10; relTol 0.01; }   // when solveEnergy is on
}
COUPLED
{
    nOuterIterations  100;
    linearSolver      AmgX;
    amgxReuse         resetup;   // default; "none" does NOT converge
    amgxPrecision     double;    // "mixed" = single-precision AMG, faster on consumer cards
    pseudoTransient   yes;   pseudoCo 50;
    adaptiveTolerance yes;   relTolMax 1e-2; relTolMin 1e-8;
    pcReuseInterval   8;         // rebuild the AMG hierarchy every 8 outer iterations
    maxLinearIter     500;
    solveEnergy       yes;   Pr 0.7;                    // optional
    timing            yes;   // per-section wall times
    residualControl { U 1e-4; p 1e-4; T 1e-4; }
}
```

The rest of the case is the coupled solver's: kinematic `p`, `viscosityModel constant; nu ...;`,
`simulationType laminar;` (or kEpsilon / kOmegaSST), steady schemes.

## Conjugate heat transfer (fluid + solids)

The case is the multi-region layout `splitMeshRegions` writes:

1. Mesh with cell zones (e.g. `fluid`, `solid`), then
   `splitMeshRegions -cellZones '(fluid solid)' -overwrite -noFields`. Interfaces must be conformal
   (`fluid_to_solid` / `solid_to_fluid`).
2. `0/fluid/{U,p,T}`, `constant/fluid/{physicalProperties,momentumTransport}`,
   `system/fluid/{fvSchemes,fvSolution}` — a coupledSimpleFoam case for the fluid region.
   Interface patch: `U` noSlip, `p` zeroGradient, `T` **fixedValue** (the solve overwrites it).
3. Each solid: `0/<solid>/T` (interface `fixedValue`, outer faces `zeroGradient` or `fixedValue`),
   `constant/<solid>/physicalProperties` with `mixture { transport { kappa 200; } }`,
   `system/<solid>/fvSchemes` with a `laplacianSchemes` entry.
4. In `system/fluid/fvSolution`:

```c++
COUPLED
{
    linearSolver       AmgX;
    solveEnergy        yes;
    Pr                 0.7;
    solidRegions       (solid);   // every solid region
    rhoCp              4.17e6;    // fluid rho*cp, J/m^3/K (scales the fluid equation to W/K)
    conjugateSolver    AmgX;      // or Eigen (CPU)
    conjugateTolerance 1e-9;
    conjugateMaxIter   2000;
}
```

5. One case-level `system/controlDict` (endTime = outer iterations, deltaT 1); run
   `coupledSimpleFoamAmgX -region fluid`. Function objects take `region=fluid`.

The log prints `Conjugate region solid: N cells, kappa = ...`, `Conjugate interface fluid <-> solid:
N matched faces` and an energy check each iteration. Limits: one fluid region; solid-solid contacts,
radiation, volumetric sources and temperature-dependent properties are not supported (use
`foamMultiRun` for those). A solid's outer faces can carry `fixedValue` temperatures.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `The GPU solver needs the NVIDIA CUDA Toolkit 12` | Install CUDA 12, reopen the shell; check `CUDA_PATH`. |
| Exit `0xC0000135` | Started without the CUDA `bin` / `bin\amgx` on PATH: use `coupledSimpleFoamAmgX`. |
| Segfault in `nvcuda64.dll` / `nvdxgdmal64.dll` under `cuInit` at start-up, on Windows Server over Remote Desktop | The executable lacks the Terminal-Server-aware PE flag (win.7). Fixed in win.8: every FoamWin executable carries it. For an older build, `python scripts/set-tsaware.py <folder>` marks a copy (FoamWin #1). |
| `AMGX ERROR` about the device / no kernel image | GPU architecture not in 7.5/8.x/8.9/12.0, or driver too old. |
| Out of memory | Mesh too big for the card; use the CPU PETSc build in parallel. |
| Krylov stalls then floating-point exception | `amgxReuse none` set: use `resetup`. |
| Interface faces not matched (CHT) | Non-conformal interface; remesh with the zones in one mesh before splitting. |
| Slower than expected | Part of each iteration (operator and matrix assembly, the conjugate energy system) runs on the CPU; set `timing yes` to see where the time goes. `amgxPrecision mixed` helps on cards with slow FP64. |

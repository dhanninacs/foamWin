---
name: foamwin-coupled-solver
description: Run coupledSimpleFoam, the fully coupled steady incompressible pressure-velocity solver, on Windows with FoamWin - serially (Eigen) or in parallel with PETSc over Microsoft MPI. Covers converting a foamRun incompressibleFluid case (physicalProperties, momentumTransport, COUPLED dictionary), choosing linearSolver (SparseLU, BiCGSTAB, PETSc), the parallel outer-loop settings, heat transfer as a passive scalar (solveEnergy, Pr, T), reading its log and fixing stalls. Use whenever a task mentions coupledSimpleFoam, a coupled or block-coupled solver, COUPLED dictionary, faster steady convergence than SIMPLE, PETSc on Windows, or bin/msmpi.
---

# coupledSimpleFoam on FoamWin (CPU)

`coupledSimpleFoam` solves momentum and continuity as **one** linear system (4 unknowns per cell,
`[u v w p]`), so a steady laminar case converges in 10-30 outer iterations instead of hundreds of
SIMPLE iterations, with no pressure/velocity relaxation factors. It is steady and incompressible;
turbulence (laminar, kEpsilon, kOmegaSST tested) is solved segregated and lagged; temperature is an
optional passive scalar. Source and full manual: https://github.com/dhanninacs/coupledSimpleFoam
(`doc/USAGE.md`). For an NVIDIA GPU see the `foamwin-gpu-solver` skill.

## Builds in FoamWin

| File | Backend | When the shell uses it |
| --- | --- | --- |
| `bin/coupledSimpleFoam.exe` | Eigen (`SparseLU`, `BiCGSTAB`), serial | no Microsoft MPI |
| `bin/msmpi/coupledSimpleFoam.exe` | PETSc + hypre, serial or MPI | Microsoft MPI installed (shadows the serial one) |
| `bin/amgx/coupledSimpleFoam.exe` | AmgX on the GPU | only through `coupledSimpleFoamAmgX` |

Check which one runs: `(Get-Command coupledSimpleFoam).Source`.

## Convert a case

A case that runs with `foamRun -solver incompressibleFluid` needs four things; one folder can drive
both solvers (the extra entries are ignored by the other):

1. `constant/physicalProperties`: `viscosityModel constant; nu 1e-05;` (kinematic).
2. `constant/momentumTransport`: `simulationType laminar;` — **mandatory even for laminar**.
3. `system/fvSchemes`: `ddtSchemes { default steadyState; }` and a `div(phi,U)` scheme
   (`bounded Gauss linearUpwind grad(U)` is a good default).
4. `system/fvSolution`: a `COUPLED` dictionary (every key has a default).

`p` is **kinematic** (p/rho), `0/p` and `0/U` are required; turbulence fields as for the model.
Give at least one outlet a `fixedValue` pressure (otherwise `pRefCell`/`pRefValue` pin the level).

```c++
COUPLED
{
    nOuterIterations 100;          // laminar 12-30; RANS ~1000
    linearSolver     SparseLU;     // serial default; PETSc in parallel
    residualControl { U 1e-5; p 1e-4; }
}
```

Run in the case folder: `coupledSimpleFoam *> log.coupled`. There is no `-solver` argument.

## Linear solver choice

| `linearSolver` | Use for |
| --- | --- |
| `SparseLU` (Eigen, direct) | 2D, or 3D up to ~80k cells; robust, no tuning |
| `BiCGSTAB` (Eigen + ILUT) | mid-size serial |
| `PETSc` | 3D beyond that, and every parallel run (field-split Schur + hypre BoomerAMG by default) |

For large 3D cases in parallel the measured fast settings are:

```c++
COUPLED
{
    linearSolver      PETSc;
    pseudoTransient   yes;   pseudoCo 50;              // damping for the first iterations
    adaptiveTolerance yes;   relTolMax 1e-2; relTolMin 1e-8;
    pcReuseInterval   8;                                // rebuild the AMG every 8 iterations
    maxLinearIter     500;
}
```

## Parallel (PETSc over MS-MPI)

```powershell
. "<install>\of14-shell.ps1" -Quiet -Parallel           # uses bin/msmpi/coupledSimpleFoam.exe
decomposePar -force
Invoke-FoamWinParallel -Processes 10 -Application coupledSimpleFoam
reconstructPar -latestTime
```

Outer-iteration counts are identical for any rank count; answers agree with serial to ~1e-10. A
1M-cell 3D laminar duct ran in 77 s on 6 ranks; a 2.1M-cell duct in 167 s on 10 ranks.

## Heat transfer (passive scalar)

```c++
COUPLED { solveEnergy yes; Pr 0.7; Prt 0.85; residualControl { U 1e-5; p 1e-4; T 1e-6; } }
solvers { T { solver PBiCGStab; preconditioner DILU; tolerance 1e-12; relTol 0; } }
```

plus `0/T` (fixedValue / zeroGradient / fixedGradient walls, `inletOutlet` outlet) and schemes
`div(phi,T)` and `laplacian(alphaEff,T)`. T is solved after each coupled solve and never feeds back
(no buoyancy, constant properties). The log prints an energy balance
(`coupled energy check: wall heat flux = ...`) — the imbalance should be ~1e-6 %.

## Reading the log and fixing stalls

- Each outer iteration prints the coupled residuals for Ux, Uy, Uz, p and the linear iterations;
  the end prints `COUPLED solution converged in N iterations` or `did NOT converge`.
- Stalls at a plateau: tighten the inner tolerance (`relTolMin 1e-10`) or turn on
  `pseudoTransient` with a lower `pseudoCo` (20-50).
- PETSc diverges on a poor mesh: lower `pseudoCo`, check `checkMesh` non-orthogonality.
- `linearSolver SparseLU` in a parallel run is a fatal error; use `PETSc`.
- Not supported: transient runs, buoyancy, non-conformal coupled patches; `cyclic`/`wedge` untested.

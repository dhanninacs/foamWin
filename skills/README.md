# FoamWin skills for AI coding agents

Three [Agent Skills](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview)
that teach an agent (Claude Code and others that read `SKILL.md`) to run OpenFOAM 14 natively on
Windows with FoamWin:

| Skill | Covers |
| --- | --- |
| [`foamwin-cpu-solvers`](foamwin-cpu-solvers/SKILL.md) | The shell, meshing, `foamRun` / `foamMultiRun` and legacy solvers, serial and Microsoft MPI runs, Windows-specific rules |
| [`foamwin-coupled-solver`](foamwin-coupled-solver/SKILL.md) | `coupledSimpleFoam` on the CPU: converting a case, `COUPLED` settings, Eigen and PETSc, parallel runs, passive heat transfer |
| [`foamwin-gpu-solver`](foamwin-gpu-solver/SKILL.md) | `coupledSimpleFoamAmgX` on an NVIDIA GPU: requirements, AmgX settings, conjugate heat transfer |

Install them for Claude Code by copying the folders into your skills directory:

```powershell
Copy-Item -Recurse skills\foamwin-* "$env:USERPROFILE\.claude\skills\"
```

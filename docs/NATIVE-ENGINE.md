# Attaching a CFD application to FoamWin

FoamWin supplies a native Windows x64 OpenFOAM Foundation 14 engine. It does
not require Bash, MSYS2, WSL or a Linux OpenFOAM install at runtime. Applications
must use a Windows host adapter rather than a Linux-only runner.

## Environment handshake

Run the trusted package helper as an argument list and parse its UTF-8 JSON:

```python
import json
import subprocess
from pathlib import Path

package = Path(r"C:\CFD\FoamWin")
case = Path(r"C:\CFD\Cases\My Case")  # Must already exist.
reply = subprocess.run(
    ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
     "-File", str(package / "of14-env.ps1"), "-CaseDirectory", str(case)],
    check=True, capture_output=True, encoding="utf-8",
)
engine = json.loads(reply.stdout)
subprocess.run(
    [engine["tools"]["checkMesh"], "-case", engine["caseDirectory"]],
    env=engine["environment"], cwd=engine["workingDirectory"], check=True,
)
```

The helper returns `schemaVersion`, OpenFOAM flavour/version, an explicit
runtime environment, absolute tool paths, library names, missing required
tools, MPI availability and a normalized case path. It exits with status 2 if
required tools are missing. Add `-Parallel` to require Microsoft MPI and fail
with an installation diagnostic when unavailable. Quiet capture never prompts.
Only explicit runtime variables are exported; application/provider API keys
are not included. Returned paths describe the local installation: keep this
JSON in memory and do not commit it or include it in shared reports.

Use `caseDirectory` for native OpenFOAM arguments: it may be a junction alias
because this port's OpenFOAM file names cannot contain whitespace. Use the
original directory for the application's own file access. Set an explicit
working directory without spaces for subprocesses. Never build a shell command
from case names, parameters or executable paths.

## Runtime coverage

| Need | Provided tools/libraries |
|---|---|
| Mesh creation and features | blockMesh, snappyHexMesh, surfaceFeatures, checkMesh |
| Mesh selection and conversion | topoSet, gmshToFoam, fluentMeshToFoam, ideasUnvToFoam |
| Solver execution | foamRun, foamMultiRun, incompressibleFluid solver library and other packaged modules |
| Results and function objects | foamPostProcess, sampling and field-function libraries, foamToVTK |
| Local parallel execution | Microsoft MPI backend, decomposePar, reconstructPar, redistributePar |

The legacy `surfaceFeatureExtract` shell wrapper is not supplied; invoke
`surfaceFeatures` with a Foundation 14 `surfaceFeaturesDict`. Gmsh mesh import
is available; the Gmsh mesher itself is separate. cfMesh, custom coupled solvers,
ParaView, Python/VTK and CAD kernels are separate optional dependencies, not
requirements for the current Foundation incompressible workflow. A catalogue
entry for a future backend is not evidence that the backend is supported.

## Parallel jobs and cancellation

Match `numberOfSubdomains` to the process count. Run decomposition first, then
launch `[parallel.executable, "-n", count, tool, "-parallel", "-case", case]`
with the returned environment. Reconstruct results afterwards. `blockMesh`
is serial. When a tutorial contains turbulence fields, decomposition may need
`-libs '("libincompressibleMomentumTransportModels.dll")'` so its wall-function
types are registered, even if the selected run is laminar. Microsoft MPI uses `mpiexec.exe`, not Linux `mpirun` flags such as
`--oversubscribe`.

A native host adapter must implement Windows process-tree lifetime management
(e.g. Windows Job Objects), timeout and cancellation, including all MPI ranks.
POSIX `killpg`/signals are not portable. Preserve the application's authentication,
argument validation and job-directory checks. A running CLI workflow does not
establish that a separate application's host adapter has been integrated.

## Validation

Run `./of14-runtime-test.ps1` from the extracted package. It creates a clean
synthetic case and checks blockMesh, checkMesh, surface feature output,
`foamRun -solver incompressibleFluid`, `mag(U)` function-object output and VTK
export. The cavity runs to 0.05 s. The unit-cube surface fixture contains no
private CAD data. The existing `of14-smoke-test.ps1 -Processes 4` and
`of14-mesh-test.ps1 -Processes 4` validate parallel solving and meshing.

To rebuild the additional utilities after the normal cross-build, run
`scripts/build-runtime-support.sh` on Linux.

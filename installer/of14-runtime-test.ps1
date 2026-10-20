param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/of14-shell.ps1" -Quiet
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $env:FOAM_RUN ('runtime-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')) }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) { throw "Output directory exists: $OutputDirectory" }
New-Item -ItemType Directory -Path (Split-Path -Parent $OutputDirectory) -Force | Out-Null
Copy-Item "$env:WM_PROJECT_DIR/tutorials/incompressibleFluid/cavity" $OutputDirectory -Recurse
Copy-Item "$env:WM_PROJECT_DIR/examples/runtimeSupport/*" $OutputDirectory -Recurse -Force
$control = Get-Content "$OutputDirectory/system/controlDict" -Raw
$control = $control -replace 'endTime\s+[^;]+;', 'endTime 0.05;' -replace 'writeInterval\s+[^;]+;', 'writeInterval 10;'
$control | Set-Content "$OutputDirectory/system/controlDict" -Encoding ASCII
# A laminar fixture exercises the engine used by applications without turbulence prerequisites.
'FoamFile { format ascii; class dictionary; object momentumTransport; } simulationType laminar;' | Set-Content "$OutputDirectory/constant/momentumTransport" -Encoding ASCII
$nativeCase = ConvertTo-OpenFOAMPath $OutputDirectory
function Run-Tool([string]$Name, [string[]]$ToolArguments = @()) {
    & "$env:FOAM_APPBIN/$Name.exe" -case $nativeCase @ToolArguments *> "$OutputDirectory/log.$Name"
    if ($LASTEXITCODE -ne 0) { throw "$Name failed; see log.$Name" }
    Write-Host "$Name passed"
}
Push-Location $nativeCase
try {
    Run-Tool blockMesh
    Run-Tool checkMesh
    Run-Tool surfaceFeatures
    if (-not (Get-ChildItem "$OutputDirectory/constant/triSurface" -Filter '*.eMesh')) { throw 'Surface feature output missing' }
    Run-Tool foamRun @('-solver','incompressibleFluid')
    if (-not (Test-Path "$OutputDirectory/0.05/U")) { throw 'Solver output missing' }
    Run-Tool foamPostProcess @('-latestTime','-func','mag(U)')
    if (-not (Test-Path "$OutputDirectory/0.05/mag(U)")) { throw 'Post-processing output missing' }
    Run-Tool foamToVTK @('-latestTime','-ascii')
    if (-not (Get-ChildItem "$OutputDirectory/VTK" -Recurse -Filter '*.vtk')) { throw 'VTK output missing' }
    Write-Host "Native application runtime workflow passed: $OutputDirectory"
} finally { Pop-Location }

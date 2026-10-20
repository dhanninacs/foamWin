param([string]$OutputDirectory, [ValidateRange(1,256)][int]$Processes = 1)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/of14-shell.ps1" -Quiet -Parallel:($Processes -gt 1)
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $env:FOAM_RUN ('cavity-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path $OutputDirectory) { throw "Test output directory already exists: $OutputDirectory" }
New-Item -ItemType Directory -Path (Split-Path -Parent $OutputDirectory) -Force | Out-Null
$fixture = "$env:FOAM_TUTORIALS/legacy/incompressible/icoFoam/cavity/cavity"
Copy-Item -LiteralPath $fixture -Destination $OutputDirectory -Recurse
$nativeCase = ConvertTo-OpenFOAMPath $OutputDirectory
function Run-CaseTool([string]$Tool, [string[]]$ToolArguments = @()) {
    & "$env:FOAM_APPBIN/$Tool.exe" -case $nativeCase @ToolArguments *> "$OutputDirectory/log.$Tool"
    if ($LASTEXITCODE -ne 0) { throw "$Tool failed ($LASTEXITCODE). See $OutputDirectory/log.$Tool" }
    Write-Host "$Tool passed"
}
Push-Location $nativeCase
try {
    Run-CaseTool blockMesh
    Run-CaseTool checkMesh
    if ($Processes -gt 1) {
        @"
FoamFile { format ascii; class dictionary; object decomposeParDict; }
numberOfSubdomains $Processes;
method simple;
simple { n ($Processes 1 1); delta 0.001; }
"@ | Set-Content "$OutputDirectory/system/decomposeParDict" -Encoding ASCII
        Run-CaseTool decomposePar
        Invoke-FoamWinParallel -Processes $Processes -Application icoFoam -Case $OutputDirectory *> "$OutputDirectory/log.icoFoam"
        Write-Host "icoFoam passed on $Processes MPI processes"
        Run-CaseTool reconstructPar @('-latestTime')
    } else { Run-CaseTool icoFoam }
    if (-not (Select-String -LiteralPath "$OutputDirectory/log.checkMesh" -SimpleMatch 'Mesh OK.')) {
        throw 'checkMesh did not report Mesh OK.'
    }
    if (-not (Test-Path "$OutputDirectory/0.5/U")) { throw 'Solver did not produce the final velocity field.' }
    New-Item -ItemType File -Path "$OutputDirectory/cavity.foam" | Out-Null
    Write-Host "Cavity simulation completed: $OutputDirectory"
} finally { Pop-Location }

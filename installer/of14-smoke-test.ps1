param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/of14-shell.ps1" -Quiet
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $env:FOAM_RUN ('cavity-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
}
if (Test-Path $OutputDirectory) { throw "Test output directory already exists: $OutputDirectory" }
New-Item -ItemType Directory -Path (Split-Path -Parent $OutputDirectory) -Force | Out-Null
$fixture = "$env:FOAM_TUTORIALS/legacy/incompressible/icoFoam/cavity/cavity"
Copy-Item -LiteralPath $fixture -Destination $OutputDirectory -Recurse
$nativeCase = ConvertTo-OpenFOAMPath $OutputDirectory
foreach ($tool in @('blockMesh', 'checkMesh', 'icoFoam')) {
    $log = Join-Path $OutputDirectory "log.$tool"
    & "$env:FOAM_APPBIN/$tool.exe" -case $nativeCase *> $log
    if ($LASTEXITCODE -ne 0) { throw "$tool failed ($LASTEXITCODE). See $log" }
    Write-Host "$tool passed"
}
if (-not (Select-String -LiteralPath "$OutputDirectory/log.checkMesh" -SimpleMatch 'Mesh OK.')) {
    throw 'checkMesh did not report Mesh OK.'
}
if (-not (Test-Path "$OutputDirectory/0.5/U")) { throw 'Solver did not produce the final velocity field.' }
New-Item -ItemType File -Path "$OutputDirectory/cavity.foam" | Out-Null
Write-Host "Cavity simulation completed: $OutputDirectory"

param([string]$OutputDirectory, [ValidateRange(2,64)][int]$Processes = 2)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/of14-shell.ps1" -Quiet -Parallel
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $env:FOAM_RUN ('parallel-mesh-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')) }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path $OutputDirectory) { throw "Test output directory already exists: $OutputDirectory" }
New-Item -ItemType Directory -Path (Split-Path -Parent $OutputDirectory) -Force | Out-Null
Copy-Item "$env:WM_PROJECT_DIR/examples/parallelMesh" $OutputDirectory -Recurse
$nativeCase = ConvertTo-OpenFOAMPath $OutputDirectory
@"
FoamFile { format ascii; class dictionary; object decomposeParDict; }
numberOfSubdomains $Processes;
method simple;
simple { n ($Processes 1 1); delta 0.001; }
"@ | Set-Content "$OutputDirectory/system/decomposeParDict" -Encoding ASCII
Push-Location $nativeCase
try {
    & "$env:FOAM_APPBIN/blockMesh.exe" -case $nativeCase *> "$OutputDirectory/log.blockMesh"
    if ($LASTEXITCODE -ne 0) { throw 'blockMesh failed' }
    & "$env:FOAM_APPBIN/decomposePar.exe" -case $nativeCase -noFields *> "$OutputDirectory/log.decomposePar"
    if ($LASTEXITCODE -ne 0) { throw 'decomposePar failed' }
    Invoke-FoamWinParallel -Processes $Processes -Application snappyHexMesh -Case $OutputDirectory -Arguments @('-overwrite') *> "$OutputDirectory/log.snappyHexMesh"
    Invoke-FoamWinParallel -Processes $Processes -Application checkMesh -Case $OutputDirectory *> "$OutputDirectory/log.checkMesh-parallel"
    & "$env:FOAM_APPBIN/reconstructPar.exe" -case $nativeCase -constant -noFields *> "$OutputDirectory/log.reconstructPar"
    if ($LASTEXITCODE -ne 0) { throw 'Mesh reconstruction failed' }
    & "$env:FOAM_APPBIN/checkMesh.exe" -case $nativeCase *> "$OutputDirectory/log.checkMesh"
    if ($LASTEXITCODE -ne 0 -or -not (Select-String -LiteralPath "$OutputDirectory/log.checkMesh" -SimpleMatch 'Mesh OK.')) { throw 'Reconstructed mesh check failed' }
    Write-Host "Parallel snappyHexMesh and reconstructed mesh passed on $Processes processes: $OutputDirectory"
} finally { Pop-Location }

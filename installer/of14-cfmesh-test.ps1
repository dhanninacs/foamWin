param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/of14-shell.ps1" -Quiet
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $env:FOAM_RUN ('cfmesh-box-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')) }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path $OutputDirectory) { throw "Test output directory already exists: $OutputDirectory" }
New-Item -ItemType Directory -Path (Split-Path -Parent $OutputDirectory) -Force | Out-Null
Copy-Item "$env:WM_PROJECT_DIR/examples/cfMeshBox" $OutputDirectory -Recurse
$nativeCase = ConvertTo-OpenFOAMPath $OutputDirectory
Push-Location $nativeCase
try {
    & "$env:FOAM_APPBIN/cartesianMesh.exe" -case $nativeCase *> "$OutputDirectory/log.cartesianMesh"
    if ($LASTEXITCODE -ne 0) { throw "cartesianMesh failed. See $OutputDirectory/log.cartesianMesh" }
    & "$env:FOAM_APPBIN/checkMesh.exe" -case $nativeCase *> "$OutputDirectory/log.checkMesh"
    if ($LASTEXITCODE -ne 0 -or -not (Select-String -LiteralPath "$OutputDirectory/log.checkMesh" -SimpleMatch 'Mesh OK.')) { throw 'cfMesh mesh check failed' }
    Write-Host "cfMesh cartesianMesh with boundary layers passed: $OutputDirectory"
} finally { Pop-Location }

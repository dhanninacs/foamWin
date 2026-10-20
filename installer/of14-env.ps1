param([string]$CaseDirectory, [switch]$Parallel)
# JSON handshake for applications. Only explicit runtime variables are returned.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
. "$PSScriptRoot/of14-shell.ps1" -Quiet -Parallel:$Parallel
$keys = @('PATH','SystemRoot','WINDIR','COMSPEC','PATHEXT','TEMP','TMP',
    'USERPROFILE','APPDATA','LOCALAPPDATA','WM_PROJECT','WM_PROJECT_VERSION',
    'WM_PROJECT_DIR','WM_OPTIONS','WM_MPLIB','FOAM_ETC','FOAM_APPBIN','FOAM_LIBBIN',
    'FOAM_TUTORIALS','FOAM_RUN','FOAM_MPI','FOAM_MPIEXEC','MPI_BUFFER_SIZE')
$environment = [ordered]@{}
foreach ($key in $keys) {
    $value = [Environment]::GetEnvironmentVariable($key)
    if ($null -ne $value) { $environment[$key] = $value }
}
$required = @('blockMesh','checkMesh','snappyHexMesh','surfaceFeatures','foamRun',
    'foamMultiRun','foamPostProcess','foamToVTK','decomposePar','reconstructPar','topoSet')
$tools = [ordered]@{}
$missing = @()
foreach ($name in $required) {
    $path = Join-Path $env:FOAM_APPBIN "$name.exe"
    if (Test-Path -LiteralPath $path -PathType Leaf) { $tools[$name] = $path }
    else { $tools[$name] = $null; $missing += $name }
}
$modules = @(Get-ChildItem -LiteralPath $env:FOAM_LIBBIN -Filter '*.dll' | ForEach-Object { $_.BaseName -replace '^lib','' })
$casePath = $null
if ($CaseDirectory) { $casePath = ConvertTo-OpenFOAMPath $CaseDirectory }
[ordered]@{
    schemaVersion = 1
    distribution = 'FoamWin'
    openfoam = @{ flavour = 'org'; version = '14'; platform = 'windows-x64' }
    environment = $environment
    tools = $tools
    missingRequiredTools = @($missing)
    libraries = @($modules | Sort-Object)
    parallel = @{ available = ($env:FOAM_MPI -eq 'msmpi'); backend = $env:FOAM_MPI; executable = $env:FOAM_MPIEXEC; countFlag = '-n' }
    caseDirectory = $casePath
    workingDirectory = $env:WM_PROJECT_DIR
} | ConvertTo-Json -Depth 6
if ($missing.Count) { exit 2 }

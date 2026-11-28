param([string]$CaseDirectory, [switch]$Parallel, [switch]$Gpu)
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
# Optional tools are reported without making an older core install invalid.
foreach ($name in @('gmsh','gmshToFoam','polyDualMesh')) {
    $command = Get-Command "$name.exe" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $tools[$name] = if ($command) { $command.Source } else { $null }
}
# The NVIDIA GPU parts. With -Gpu, PATH carries bin/amgx and the CUDA folders even when the shell did not
# add them (no libamgxSolvers.dll), so a host program can run the GPU build like the CPU tools.
$gpuBin = Join-Path $env:FOAM_APPBIN 'amgx'
$gpuExe = Join-Path $gpuBin 'coupledSimpleFoam.exe'
$gpuLib = Join-Path $gpuBin 'libamgxSolvers.dll'
$cudaBin = Get-FoamWinCudaBin
$gpuInfo = [ordered]@{
    available = [bool]((Test-Path -LiteralPath $gpuExe -PathType Leaf) -and $cudaBin)
    executable = $(if (Test-Path -LiteralPath $gpuExe -PathType Leaf) { $gpuExe } else { $null })
    library = $(if (Test-Path -LiteralPath $gpuLib -PathType Leaf) { $gpuLib } else { $null })
    cudaBin = @($(if ($cudaBin) { $cudaBin -split ';' } else { @() }))
}
if ($Gpu -and $gpuInfo.available -and ($env:PATH -notlike "*$($gpuBin.Replace('\','/'))*") -and ($env:PATH -notlike "*$gpuBin*")) {
    $env:PATH = "$env:PATH;$gpuBin;$cudaBin"
    $environment['PATH'] = $env:PATH
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
    gpu = $gpuInfo
    parallel = @{ available = ($env:FOAM_MPI -eq 'msmpi'); backend = $env:FOAM_MPI; executable = $env:FOAM_MPIEXEC; countFlag = '-n' }
    caseDirectory = $casePath
    workingDirectory = $env:WM_PROJECT_DIR
} | ConvertTo-Json -Depth 6
if ($missing.Count) { exit 2 }

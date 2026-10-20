param([switch]$Quiet, [switch]$Parallel)
$ErrorActionPreference = 'Stop'
$foamRoot = $PSScriptRoot
if (Test-Path (Join-Path $foamRoot 'OpenFOAM-14/etc/configDict')) {
    $foamRoot = Join-Path $foamRoot 'OpenFOAM-14'
}
if (-not (Test-Path (Join-Path $foamRoot 'etc/configDict'))) {
    throw "OpenFOAM etc/configDict was not found beside this launcher."
}
# OpenFOAM fileName rejects whitespace. Keep files in place and pass a junction
# with a whitespace-free spelling to native programs.
function global:ConvertTo-OpenFOAMPath([string]$Path) {
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if ($resolved -notmatch '\s') { return $resolved.Replace('\', '/') }
    $aliasBase = Join-Path $env:TEMP 'OpenFOAM-native-paths'
    if ($aliasBase -match '\s') {
        throw 'OpenFOAM needs a TEMP directory without spaces to create path aliases.'
    }
    New-Item -ItemType Directory -Path $aliasBase -Force | Out-Null
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($resolved.ToLowerInvariant()))).Replace('-', '') }
    finally { $sha.Dispose() }
    $alias = Join-Path $aliasBase $hash.Substring(0, 24)
    if (-not (Test-Path -LiteralPath $alias)) {
        New-Item -ItemType Junction -Path $alias -Target $resolved | Out-Null
    }
    $item = Get-Item -LiteralPath $alias
    if ($item.LinkType -ne 'Junction' -or [IO.Path]::GetFullPath([string]$item.Target).TrimEnd('\') -ine $resolved.TrimEnd('\')) {
        throw "Unexpected path alias target: $alias"
    }
    return $alias.Replace('\', '/')
}
$foamRoot = ConvertTo-OpenFOAMPath $foamRoot
# Normalize environment paths for the native Windows file layer.
$foamRoot = $foamRoot.Replace('\', '/')
$platform = "$foamRoot/platforms/linuxmingw-w64GccDPInt32Opt"
$env:WM_PROJECT = 'OpenFOAM'
$env:WM_PROJECT_VERSION = '14'
$env:WM_PROJECT_DIR = $foamRoot
$env:WM_OPTIONS = 'linuxmingw-w64GccDPInt32Opt'
$env:FOAM_ETC = "$foamRoot/etc"
$env:FOAM_APPBIN = "$platform/bin"
$env:FOAM_LIBBIN = "$platform/lib"
$env:FOAM_TUTORIALS = "$foamRoot/tutorials"
$env:FOAM_RUN = (Join-Path $env:USERPROFILE 'OpenFOAM/run').Replace('\', '/')
$mpiBufferSize = 0L
if (-not [long]::TryParse($env:MPI_BUFFER_SIZE, [ref]$mpiBufferSize) -or $mpiBufferSize -lt 20000000) {
    $env:MPI_BUFFER_SIZE = '20000000'
}
function global:Get-FoamWinMpiRuntime {
    foreach ($candidate in @($env:MSMPI_BIN, "$env:ProgramFiles/Microsoft MPI/Bin")) {
        if ($candidate -and (Test-Path -LiteralPath (Join-Path $candidate 'mpiexec.exe'))) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}
$mpiRuntime = Get-FoamWinMpiRuntime
$mpiBackend = Test-Path -LiteralPath "$platform/lib/msmpi/libPstream.dll"
if ($mpiBackend -and -not $mpiRuntime -and -not $Quiet) {
    Write-Host 'Microsoft MPI is required for multi-core meshing and solving.'
    $choice = Read-Host 'Open the Microsoft MPI installation instructions now? [y/N]'
    if ($choice -match '^(y|yes)$') {
        Start-Process 'https://www.microsoft.com/en-us/download/details.aspx?id=105289'
    }
    Write-Host 'Install msmpisetup.exe and reopen FoamWin to enable parallel mode. Serial mode remains available.'
}
if ($Parallel -and (-not $mpiRuntime -or -not $mpiBackend)) {
    throw 'Parallel mode requires the MPI-enabled FoamWin build and Microsoft MPI. Install msmpisetup.exe from the Microsoft download page, then reopen the shell.'
}
if ($mpiRuntime -and $mpiBackend) {
    $env:FOAM_MPI = 'msmpi'
    $env:WM_MPLIB = 'MSMPI'
    $env:FOAM_MPIEXEC = Join-Path $mpiRuntime 'mpiexec.exe'
    $env:PATH = "$platform/bin;$platform/lib;$platform/lib/msmpi;$platform/lib/dummy;$mpiRuntime;$env:PATH"
} else {
    $env:FOAM_MPI = 'dummy'
    $env:WM_MPLIB = 'dummy'
    $env:FOAM_MPIEXEC = ''
    $env:PATH = "$platform/bin;$platform/lib;$platform/lib/dummy;$env:PATH"
}
function global:Invoke-FoamWinParallel {
    param(
        [Parameter(Mandatory=$true)][ValidateRange(2,256)][int]$Processes,
        [Parameter(Mandatory=$true)][string]$Application,
        [string]$Case = (Get-Location).Path,
        [string[]]$Arguments = @()
    )
    if ($env:FOAM_MPI -ne 'msmpi' -or -not $env:FOAM_MPIEXEC) {
        throw 'Microsoft MPI is unavailable. Install it and reopen the FoamWin shell.'
    }
    $exe = Join-Path $env:FOAM_APPBIN (($Application -replace '\.exe$','') + '.exe')
    if (-not (Test-Path -LiteralPath $exe)) { throw "Application not found: $Application" }
    $nativeCase = ConvertTo-OpenFOAMPath $Case
    & $env:FOAM_MPIEXEC -n $Processes $exe -parallel -case $nativeCase @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Application failed with MPI exit code $LASTEXITCODE" }
}
if (-not $Quiet) {
    New-Item -ItemType Directory -Path $env:FOAM_RUN -Force | Out-Null
    Set-Location (ConvertTo-OpenFOAMPath $env:FOAM_RUN)
    Write-Host 'OpenFOAM 14 native Windows environment loaded.'
    Write-Host 'Try: blockMesh -help'
    Write-Host "Parallel backend: $env:FOAM_MPI"
    if ($env:FOAM_MPI -eq 'msmpi') { Write-Host 'Example: Invoke-FoamWinParallel -Processes 4 -Application icoFoam -Case <case-folder>' }
    Write-Host "Run the cavity test: & '$PSScriptRoot/of14-smoke-test.ps1'"
}

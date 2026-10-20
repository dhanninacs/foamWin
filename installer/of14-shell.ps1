param([switch]$Quiet)
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
function ConvertTo-OpenFOAMPath([string]$Path) {
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
$env:PATH = "$platform/bin;$platform/lib;$platform/lib/dummy;$env:PATH"
if (-not $Quiet) {
    New-Item -ItemType Directory -Path $env:FOAM_RUN -Force | Out-Null
    Set-Location (ConvertTo-OpenFOAMPath $env:FOAM_RUN)
    Write-Host 'OpenFOAM 14 native Windows environment loaded.'
    Write-Host 'Try: blockMesh -help'
    Write-Host "Run the cavity test: & '$PSScriptRoot/of14-smoke-test.ps1'"
}

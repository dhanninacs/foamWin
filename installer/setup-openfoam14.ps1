# Install the native Windows package. MSYS2 is optional and is not required.
param(
    [string]$InstallDir = "$env:LOCALAPPDATA/OpenFOAM-14-win",
    [switch]$NoShortcut,
    [string]$Msys2Root,
    [switch]$SkipMsys2
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path "$PSScriptRoot/OpenFOAM-14/etc/configDict")) {
    throw 'Run this script from the extracted Windows distribution.'
}
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
& robocopy "$PSScriptRoot/OpenFOAM-14" "$InstallDir/OpenFOAM-14" /E /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed: $LASTEXITCODE" }
foreach ($name in @('of14-shell.bat','of14-shell.ps1','of14-smoke-test.ps1','of14-mesh-test.ps1','README.md')) {
    Copy-Item "$PSScriptRoot/$name" $InstallDir -Force
}
if (Test-Path "$PSScriptRoot/runtime-licenses") {
    Copy-Item "$PSScriptRoot/runtime-licenses" $InstallDir -Recurse -Force
}
if (-not $NoShortcut) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path $desktop 'OpenFOAM 14.lnk'))
    $shortcut.TargetPath = Join-Path $InstallDir 'of14-shell.bat'
    $shortcut.WorkingDirectory = $InstallDir
    $shortcut.Save()
}
Write-Host "Installed in $InstallDir. Open of14-shell.bat to begin."
exit 0

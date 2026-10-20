# =============================================================================
# OpenFOAM 14 for Windows - installer (blueCFD-style MinGW-w64 build)
# Installs everything needed: MSYS2 (auto-downloaded if missing) + OpenFOAM.
# Run in PowerShell:
#   powershell -ExecutionPolicy Bypass -File setup-openfoam14.ps1
# Optional params:
#   -Msys2Root  C:\msys64           (where MSYS2 lives / will be installed)
#   -InstallDir C:\OpenFOAM-14-win  (where OpenFOAM will be copied)
#   -SkipMsys2  switch              (use if MSYS2 is already set up)
# =============================================================================
param(
    [string]$Msys2Root = "C:\msys64",
    [string]$InstallDir = "C:\OpenFOAM-14-win",
    [switch]$SkipMsys2
)
$ErrorActionPreference = "Stop"

# --- 1. Ensure MSYS2 is present (auto-download + silent install if missing) --
if (-not $SkipMsys2 -and -not (Test-Path "$Msys2Root\usr\bin\bash.exe")) {
    Write-Host "==> MSYS2 not found at $Msys2Root. Installing it for you..."

    $dlDir = Join-Path $env:TEMP "of14-msys2-setup"
    New-Item -ItemType Directory -Force -Path $dlDir | Out-Null

    # Resolve latest installer: try the official 'latest' link, fall back to
    # a pinned release known to work.
    $installer = Join-Path $dlDir "msys2-x86_64-latest.exe"
    $urls = @(
        "https://github.com/msys2/msys2-installer/releases/download/nightly-x86_64/msys2-base-x86_64-20250113.sfx.exe",
        "https://repo.msys2.org/distrib/msys2-x86_64-latest.sfx.exe",
        "https://github.com/msys2/msys2-installer/releases/latest/download/msys2-base-x86_64-latest.sfx.exe"
    )
    $downloaded = $false
    foreach ($u in $urls) {
        try {
            Write-Host "    downloading $u ..."
            Invoke-WebRequest -Uri $u -OutFile $installer -UseBasicParsing -TimeoutSec 300
            if ((Get-Item $installer).Length -gt 10MB) { $downloaded = $true; break }
        } catch { Write-Host "    failed: $($_.Exception.Message)" }
    }
    if (-not $downloaded) {
        throw "Could not download MSYS2. Please install it manually from https://www.msys2.org into $Msys2Root, then re-run with -SkipMsys2."
    }

    # The .sfx.exe is a self-extracting archive: extract to the drive root so
    # it lands in <drive>:\msys64, then finalize first-run initialization.
    Write-Host "    extracting (~1-2 min) ..."
    $drive = Split-Path -Qualifier $Msys2Root        # e.g. "C:"
    Push-Location $drive
    & $installer 2>&1 | Out-Null                     # extracts .\msys64
    Pop-Location
    if (-not (Test-Path "$Msys2Root\usr\bin\bash.exe")) {
        throw "MSYS2 extraction did not produce $Msys2Root. Install manually from https://www.msys2.org and re-run with -SkipMsys2."
    }

    # First-run initialization (keys, pacman db). Ignore transient errors.
    Write-Host "    initializing MSYS2 (first run) ..."
    & "$Msys2Root\usr\bin\bash.exe" -lc 'true' 2>&1 | Out-Null
    & "$Msys2Root\usr\bin\pacman.exe" -Sy --noconfirm 2>&1 | Out-Null
} elseif (-not (Test-Path "$Msys2Root\usr\bin\bash.exe") -and $SkipMsys2) {
    throw "MSYS2 not found at $Msys2Root and -SkipMsys2 was given."
} else {
    Write-Host "==> Using existing MSYS2 at $Msys2Root"
}

# --- 2. Refresh pacman DB (non-fatal if offline; binaries are prebuilt) ------
Write-Host "==> Refreshing MSYS2 package database..."
& "$Msys2Root\usr\bin\pacman.exe" -Sy --noconfirm 2>&1 | Out-Null

# --- 3. Copy the OpenFOAM build ------------------------------------------------
Write-Host "==> Copying OpenFOAM-14 to $InstallDir ..."
if (Test-Path "$InstallDir\OpenFOAM-14") {
    Write-Host "    (existing install found; updating)"
}
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
robocopy "$PSScriptRoot\OpenFOAM-14" "$InstallDir\OpenFOAM-14" /E /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with code $LASTEXITCODE" }

# --- 4. Create desktop launcher (adds our DLL dirs to PATH) ------------------
# Convert Windows paths to MSYS2-style POSIX paths for the bash command line.
$ofWin = Join-Path $InstallDir "OpenFOAM-14"
$ofPosix = "/" + ($ofWin -replace '^([A-Za-z]):', { $args[0].Groups[1].Value.ToLower() }) -replace '\\', '/'
$msysPosix = "/" + ($Msys2Root -replace '^([A-Za-z]):', { $args[0].Groups[1].Value.ToLower() }) -replace '\\', '/'
$pOpt = "$ofPosix/platforms/linuxmingw-w64GccDPInt32Opt"

$bat = @"
@echo off
title OpenFOAM 14 (MinGW-w64 native)
set OF=$ofWin
set MSYS=$Msys2Root
set PATH=%OF%\platforms\linuxmingw-w64GccDPInt32Opt\bin;%OF%\platforms\linuxmingw-w64GccDPInt32Opt\lib;%OF%\platforms\linuxmingw-w64GccDPInt32Opt\lib\dummy;%PATH%
%MSYS%\usr\bin\env.exe MSYSTEM=MINGW64 %MSYS%\usr\bin\bash.exe --login -i -c ^
  'export PATH="$pOpt/bin:$pOpt/lib:$pOpt/lib/dummy:`$PATH" && source $ofPosix/etc/bashrc && echo "OpenFOAM-14 environment loaded. Try: blockMesh -help" && exec bash'
"@
Set-Content -Path "$env:USERPROFILE\Desktop\OpenFOAM14.bat" -Value $bat -Encoding ASCII

Write-Host ""
Write-Host "Done. Double-click the desktop shortcut 'OpenFOAM14.bat' to start."
Write-Host "Quick test inside that shell:"
Write-Host "    mkdir -p `$FOAM_RUN && cd `$FOAM_RUN"
Write-Host "    cp -r `$FOAM_TUTORIALS/incompressibleFluid/icoFoam/cavity . && cd cavity"
Write-Host "    blockMesh && checkMesh && icoFoam"

# Build NVIDIA AmgX's shared library (amgxsh.dll and its import library amgxsh.lib) natively on
# Windows, for coupledSimpleFoam's GPU build (scripts/build-coupled.sh, AMGX_WINDOWS_BUILD).
#
# AmgX is CUDA C++ and builds only with MSVC, so this runs on Windows, not in the MinGW
# cross-build; coupledSimpleFoam calls it through its C API only, which MinGW code can link.
#
#   scripts\build-amgx.ps1 -Source <AmgX 2.5.0 source> -Build <new folder> [-Cuda <toolkit>]
#                          [-Architectures "75-real;80-real;86-real;89-real;120-real"]
#
# Needs: Visual Studio 2022 Build Tools (C++), CMake 3.24 or later, the CUDA Toolkit 12.x.
# The source is AmgX v2.5.0 (BSD-3-Clause), https://github.com/NVIDIA/AMGX/releases/tag/v2.5.0,
# unpacked; this script does not download anything. No MPI (amgxsh is the single-GPU library).
# The default architectures are Turing (7.5), Ampere (8.0, 8.6), Ada (8.9) and Blackwell
# workstation cards (12.0); an 8.0 binary also runs on 8.7. Each architecture adds about 65 MB.
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Build,
    [string]$Cuda = $env:CUDA_PATH,
    [string]$Architectures = '75-real;80-real;86-real;89-real;120-real',
    [int]$Jobs = [Environment]::ProcessorCount
)
$ErrorActionPreference = 'Stop'
$Source = (Resolve-Path -LiteralPath $Source).Path
$version = (Get-Content -LiteralPath (Join-Path $Source 'ReleaseVersion.txt') -TotalCount 1).Trim()
if ($version -ne '2.5.0') { throw "Expected the AmgX 2.5.0 source, found version '$version' in $Source" }
if (-not $Cuda) { throw 'Set -Cuda or CUDA_PATH to the CUDA Toolkit folder' }
# Some installations point CUDA_PATH at the toolkit's bin folder.
if ((Split-Path -Leaf $Cuda) -ieq 'bin') { $Cuda = Split-Path -Parent $Cuda }
if (-not (Test-Path -LiteralPath (Join-Path $Cuda 'bin\nvcc.exe'))) { throw "nvcc.exe not found under $Cuda\bin" }
if (Test-Path -LiteralPath $Build) { throw "Build folder already exists: $Build" }
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) { throw 'cmake is not on PATH' }
New-Item -ItemType Directory -Path $Build | Out-Null
$Build = (Resolve-Path -LiteralPath $Build).Path
# cmake writes progress to stderr; run it through cmd so PowerShell does not treat that as an error.
$configure = "cmake -S `"$Source`" -B `"$Build`" -G `"Visual Studio 17 2022`" -A x64 -T `"cuda=$Cuda`" " +
    "-DCMAKE_CUDA_ARCHITECTURES=`"$Architectures`" -DCMAKE_NO_MPI=True"
cmd /c "$configure > `"$Build\cmake.log`" 2>&1"
if ($LASTEXITCODE -ne 0) { Get-Content "$Build\cmake.log" -Tail 40; throw 'AmgX configure failed' }
cmd /c "cmake --build `"$Build`" --config Release --target amgxsh --parallel $Jobs > `"$Build\build.log`" 2>&1"
if ($LASTEXITCODE -ne 0) { Get-Content "$Build\build.log" -Tail 40; throw 'AmgX build failed' }
foreach ($name in 'amgxsh.dll', 'amgxsh.lib') {
    if (-not (Test-Path -LiteralPath "$Build\Release\$name")) { throw "Missing $Build\Release\$name" }
}
# AmgX's own license (BSD-3-Clause) and NOTICES (the CUSP library, Apache-2.0); make-installer.sh
# ships both with the GPU build.
Copy-Item -LiteralPath (Join-Path $Source 'LICENSES\BSD-3-Clause.txt'), (Join-Path $Source 'NOTICES') -Destination "$Build\Release"
Write-Host "Built $Build\Release\amgxsh.dll for CUDA architectures $Architectures"
Write-Host "Set AMGX_WINDOWS_BUILD to $Build\Release for scripts/build-coupled.sh"

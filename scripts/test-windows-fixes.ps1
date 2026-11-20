param(
    [Parameter(Mandatory = $true)][string]$RuntimeRoot,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)
# Checks the Windows fixes in decomposePar, reconstructPar, argList and sigStopAtWriteNow on
# copies of the kEpsilon cavity tutorial. Prints one PASS or FAIL line per check and exits 1 if
# any check fails. The Ctrl+Break check needs Python 3 on PATH and is skipped without it.

$ErrorActionPreference = 'Stop'
$runtime = (Resolve-Path -LiteralPath $RuntimeRoot).Path
if (Test-Path -LiteralPath $OutputDirectory) {
    throw "Output directory already exists: $OutputDirectory"
}
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$output = (Resolve-Path -LiteralPath $OutputDirectory).Path
. (Join-Path $runtime 'of14-shell.ps1') -Quiet -Parallel
$fixture = Join-Path $runtime 'OpenFOAM-14/tutorials/incompressibleFluid/cavity'
if (-not (Test-Path -LiteralPath $fixture -PathType Container)) {
    throw "Cavity fixture is missing: $fixture"
}
$ErrorActionPreference = 'Continue'
$failed = 0

function New-Case([string]$Name) {
    $case = Join-Path $output $Name
    Copy-Item -Recurse -LiteralPath $fixture $case
    Push-Location $case
    blockMesh *> log.blockMesh
    @('FoamFile { format ascii; class dictionary; object decomposeParDict; }',
      'numberOfSubdomains 2;', 'method simple;', 'simpleCoeffs { n (2 1 1); }') |
        Set-Content 'system/decomposeParDict' -Encoding ascii
}

function Write-Check([string]$What, [bool]$Ok, [string]$Log) {
    $detail = ''
    if (-not $Ok -and $Log -and (Test-Path $Log)) {
        $detail = (Select-String -Path $Log -Pattern 'FOAM FATAL|Unknown|wrong token|Unexpected' |
            Select-Object -First 2 | ForEach-Object { $_.Line.Trim() }) -join ' | '
    }
    if (-not $Ok) { $script:failed++ }
    '{0,-4} {1} {2}' -f ($(if ($Ok) { 'PASS' } else { 'FAIL' })), $What, $detail
}

# decomposePar and reconstructPar read nutkWallFunction without -libs: both load the generic
# patch fields themselves on Windows.
New-Case 'genericPatchFields'
decomposePar -force *> log.decomposePar
Write-Check 'decomposePar without -libs (nutkWallFunction)' ($LASTEXITCODE -eq 0 -and (Test-Path 'processor1/0/nut')) 'log.decomposePar'
reconstructPar -withZero *> log.reconstructPar
Write-Check 'reconstructPar without -libs' ($LASTEXITCODE -eq 0) 'log.reconstructPar'
Pop-Location

# -libs and FOAM_LIBS accept bare words: PowerShell and mpiexec strip the inner quotes.
New-Case 'libsWords'
$checks = @(
    @{ What = "-libs '(`"lib.dll`")'"; Libs = '("libgenericFvFields.dll")' },
    @{ What = "-libs '(lib1.dll lib2.dll)'"; Libs = '(libgenericFvFields.dll libfieldFunctionObjects.dll)' },
    @{ What = "-libs 'lib.dll'"; Libs = 'libgenericFvFields.dll' }
)
$n = 0
foreach ($check in $checks) {
    $n++
    foamDictionary -libs $check.Libs system/controlDict -entry endTime *> "log.libs$n"
    Write-Check $check.What ($LASTEXITCODE -eq 0) "log.libs$n"
}
$env:FOAM_LIBS = '(libgenericFvFields.dll)'
foamDictionary system/controlDict -entry endTime *> log.foamLibs
$code = $LASTEXITCODE
Remove-Item Env:FOAM_LIBS
Write-Check 'FOAM_LIBS=(lib.dll)' ($code -eq 0) 'log.foamLibs'
if ($env:FOAM_MPIEXEC) {
    & $env:FOAM_MPIEXEC -n 2 (Get-Command foamDictionary.exe).Source -libs '(libgenericFvFields.dll)' system/controlDict -entry endTime *> log.mpiexec
    Write-Check "mpiexec -n 2 ... -libs '(lib.dll)'" ($LASTEXITCODE -eq 0) 'log.mpiexec'
}
Pop-Location

# stopAtWriteNowSignal: Ctrl+Break (SIGBREAK, 21) writes the current time and ends the run with
# exit 0. The switch is read from configDict at startup, not from the case, so this check puts it
# in a user configDict under a HOME of its own.
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    'SKIP Ctrl+Break with stopAtWriteNowSignal 21 (no python on PATH)'
} else {
    $userHome = Join-Path $output 'home'
    New-Item -ItemType Directory -Path (Join-Path $userHome '.OpenFOAM/14') | Out-Null
    @('FoamFile { format ascii; class dictionary; object configDict; }',
      'OptimisationSwitches { stopAtWriteNowSignal 21; }') |
        Set-Content (Join-Path $userHome '.OpenFOAM/14/configDict') -Encoding ascii
    New-Case 'stopAtWriteNow'
    (Get-Content system/controlDict) -replace '^endTime .*', 'endTime         1000;' `
        -replace '^writeInterval.*', 'writeInterval   100000;' | Set-Content system/controlDict -Encoding ascii
    $savedHome = $env:HOME
    $env:HOME = $userHome
    & $python.Source -I (Join-Path $PSScriptRoot 'send-ctrl-break.py') (Get-Command foamRun.exe).Source log.foamRun 4 -solver incompressibleFluid
    $code = $LASTEXITCODE
    if ($null -eq $savedHome) { Remove-Item Env:HOME } else { $env:HOME = $savedHome }
    $written = @(Get-ChildItem -Directory | Where-Object { $_.Name -match '^[0-9.eE+-]+$' -and $_.Name -ne '0' })
    $stopped = Select-String -Path log.foamRun -Pattern 'setting up write and stop' -Quiet
    Write-Check "Ctrl+Break with stopAtWriteNowSignal 21 (exit $code, wrote $($written.Name -join ','))" ($code -eq 0 -and $stopped -and $written.Count -ge 1) 'log.foamRun'
    Pop-Location
}

if ($failed -gt 0) { "$failed check(s) failed"; exit 1 }
'All checks passed'

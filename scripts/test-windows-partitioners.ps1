param(
    [Parameter(Mandatory = $true)][string]$RuntimeRoot,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [ValidateRange(2, 32)][int]$Processes = 2
)

$ErrorActionPreference = 'Stop'
$runtime = (Resolve-Path -LiteralPath $RuntimeRoot).Path
if (Test-Path -LiteralPath $OutputDirectory) {
    throw "Output directory already exists: $OutputDirectory"
}
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$output = (Resolve-Path -LiteralPath $OutputDirectory).Path
. (Join-Path $runtime 'of14-shell.ps1') -Quiet
$fixture = Join-Path $runtime 'OpenFOAM-14/tutorials/legacy/incompressible/icoFoam/cavity/cavity'
if (-not (Test-Path -LiteralPath $fixture -PathType Container)) {
    throw "Cavity fixture is missing: $fixture"
}

foreach ($method in @('metis', 'scotch')) {
    $case = Join-Path $output $method
    Copy-Item -LiteralPath $fixture -Destination $case -Recurse
    @"
FoamFile
{
    format ascii;
    class dictionary;
    object decomposeParDict;
}
numberOfSubdomains $Processes;
method $method;
"@ | Set-Content -LiteralPath (Join-Path $case 'system/decomposeParDict') -Encoding ASCII
    $foamCase = ConvertTo-OpenFOAMPath $case
    & blockMesh -case $foamCase *> (Join-Path $case 'log.blockMesh')
    if ($LASTEXITCODE -ne 0) { throw "blockMesh failed for $method" }
    & decomposePar -case $foamCase *> (Join-Path $case 'log.decomposePar')
    if ($LASTEXITCODE -ne 0) { throw "decomposePar failed for $method" }
    if (-not (Select-String -LiteralPath (Join-Path $case 'log.decomposePar') -SimpleMatch "Selecting decomposer $method")) {
        throw "The $method decomposer was not selected"
    }
    for ($i = 0; $i -lt $Processes; $i++) {
        if (-not (Test-Path -LiteralPath (Join-Path $case "processor$i/constant/polyMesh/cellProcAddressing"))) {
            throw "$method did not write processor$i addressing"
        }
    }
    Write-Host "${method}: $Processes partitions passed"
}

# PT-Scotch and Zoltan need MS-MPI: redistribute a simple decomposition with each
$platform = Join-Path $runtime 'OpenFOAM-14/platforms/linuxmingw-w64GccDPInt32Opt'
if (-not (Test-Path -LiteralPath (Join-Path $platform 'lib/msmpi/libptscotchDecomp.dll'))) {
    Write-Host 'Skipping ptscotch and zoltan: this runtime has no MS-MPI partitioners'
    Write-Host "Partitioner logs: $output"
    return
}
. (Join-Path $runtime 'of14-shell.ps1') -Quiet -Parallel
foreach ($method in @('ptscotch', 'zoltan')) {
    $case = Join-Path $output $method
    Copy-Item -LiteralPath $fixture -Destination $case -Recurse
    # Redistribution moves the mesh only, and needs an internal patch to
    # receive faces that become exposed between processors.
    Remove-Item -LiteralPath (Join-Path $case '0') -Recurse
    $blockMeshDict = Join-Path $case 'system/blockMeshDict'
    (Get-Content -Raw -LiteralPath $blockMeshDict).Replace(
        "boundary`n(",
        "boundary`n(`n    internal`n    {`n        type internal;`n        faces ();`n    }"
    ) | Set-Content -LiteralPath $blockMeshDict -Encoding ASCII
    $foamCase = ConvertTo-OpenFOAMPath $case
    & blockMesh -case $foamCase *> (Join-Path $case 'log.blockMesh')
    if ($LASTEXITCODE -ne 0) { throw "blockMesh failed for $method" }
    foreach ($step in @('simple', $method)) {
        @"
FoamFile
{
    format ascii;
    class dictionary;
    object decomposeParDict;
}
numberOfSubdomains $Processes;
method $step;
simpleCoeffs { n ($Processes 1 1); }
"@ | Set-Content -LiteralPath (Join-Path $case 'system/decomposeParDict') -Encoding ASCII
        if ($step -eq 'simple') {
            & decomposePar -case $foamCase *> (Join-Path $case 'log.decomposePar')
            if ($LASTEXITCODE -ne 0) { throw "decomposePar failed for $method" }
        }
    }
    $log = Join-Path $case 'log.redistributePar'
    $redistribute = Join-Path $env:FOAM_APPBIN 'redistributePar.exe'
    & cmd /c "`"$env:FOAM_MPIEXEC`" -n $Processes `"$redistribute`" -parallel -case $foamCase > `"$log`" 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "redistributePar failed for $method. See $log" }
    if (-not (Select-String -LiteralPath $log -SimpleMatch "Selecting distributor $method")) {
        throw "The $method distributor was not selected"
    }
    Write-Host "${method}: redistributed on $Processes MPI processes"
}
Write-Host "Partitioner logs: $output"

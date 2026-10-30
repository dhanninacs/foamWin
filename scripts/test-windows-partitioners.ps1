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
Write-Host "Partitioner logs: $output"

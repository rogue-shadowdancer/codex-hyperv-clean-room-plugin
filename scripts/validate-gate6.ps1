[CmdletBinding()]
param(
    [switch]$SkipInheritedBaseline,
    [string]$PythonExecutable,
    [string]$DependencyPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimePath = Join-Path $repoRoot '.artifacts\test-python\runtime.json'
$prepareHint = '.\scripts\prepare-test-python.ps1'

if (-not $SkipInheritedBaseline) {
    $null = & (Join-Path $PSScriptRoot 'validate-gate2.ps1') -SkipRealHostSmoke
}

$runtime = if ([string]::IsNullOrWhiteSpace($PythonExecutable) -and
    [string]::IsNullOrWhiteSpace($DependencyPath)) {
    if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
        throw "Prepared test Python is unavailable. Run $prepareHint, then rerun validate-gate6.ps1."
    }
    try {
        Get-Content -LiteralPath $runtimePath -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Prepared test Python metadata is unreadable. Run $prepareHint to repair it."
    }
}
elseif (-not [string]::IsNullOrWhiteSpace($PythonExecutable) -and
    -not [string]::IsNullOrWhiteSpace($DependencyPath)) {
    [pscustomobject]@{
        pythonExecutable = [IO.Path]::GetFullPath($PythonExecutable)
        dependencyPath = [IO.Path]::GetFullPath($DependencyPath)
    }
}
else {
    throw 'PythonExecutable and DependencyPath must be supplied together.'
}

$pythonExecutable = [string]$runtime.pythonExecutable
$dependencyPath = [string]$runtime.dependencyPath
if ([string]::IsNullOrWhiteSpace($pythonExecutable) -or
    -not (Test-Path -LiteralPath $pythonExecutable -PathType Leaf) -or
    [string]::IsNullOrWhiteSpace($dependencyPath) -or
    -not (Test-Path -LiteralPath $dependencyPath -PathType Container)) {
    throw "Prepared test Python is stale or incomplete. Run $prepareHint, then rerun validate-gate6.ps1."
}

$oldPythonPath = $env:PYTHONPATH
$oldNoUserSite = $env:PYTHONNOUSERSITE
try {
    $env:PYTHONPATH = $dependencyPath
    $env:PYTHONNOUSERSITE = '1'
    $contractOutput = & $pythonExecutable -S `
        (Join-Path $repoRoot 'tests\gate6_contract_tests.py')
    if ($LASTEXITCODE -ne 0 -or @($contractOutput).Count -ne 1) {
        throw 'Gate 6 schema-v2 contract validation failed.'
    }
    try {
        $contractResult = [string]$contractOutput | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw 'Gate 6 contract validation returned invalid metadata.'
    }
    if (-not [bool]$contractResult.ok -or
        [string]$contractResult.targetPluginVersion -cne '0.3.0' -or
        [string]$contractResult.currentRuntimeVersion -cne '0.4.1' -or
        [int]$contractResult.v1ToolsPreserved -ne 16 -or
        [int]$contractResult.v2ToolsDeclared -ne 20 -or
        [int]$contractResult.v1SchemasPreserved -ne 5 -or
        [int]$contractResult.v2Schemas -ne 7 -or
        [int]$contractResult.validFixtures -ne 8 -or
        [int]$contractResult.schemaInvalidFixtures -ne 5 -or
        [int]$contractResult.semanticInvalidFixtures -ne 3 -or
        [int]$contractResult.migrationFixtures -ne 2 -or
        [int]$contractResult.dynamicCompatibilityChecks -ne 19 -or
        [int]$contractResult.p3_1ValidFixtures -ne 7 -or
        [int]$contractResult.p3_1SchemaInvalidFixtures -ne 5 -or
        [int]$contractResult.p3_1NegativeCases -ne 41 -or
        -not [bool]$contractResult.p3_1Closable -or
        [int]$contractResult.realHyperVMutations -ne 0 -or
        [int]$contractResult.realGuestOperations -ne 0) {
        throw 'Gate 6 contract validation did not preserve its frozen counts or safety boundary.'
    }
}
finally {
    $env:PYTHONPATH = $oldPythonPath
    $env:PYTHONNOUSERSITE = $oldNoUserSite
}

$previousErrorAction = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $diffCheck = & git -C $repoRoot diff --check 2>&1
    $diffExitCode = $LASTEXITCODE
    $cachedDiffCheck = & git -C $repoRoot diff --cached --check 2>&1
    $cachedDiffExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorAction
}
if ($diffExitCode -ne 0) {
    throw "git diff --check failed:`n$($diffCheck -join "`n")"
}
if ($cachedDiffExitCode -ne 0) {
    throw "git diff --cached --check failed:`n$($cachedDiffCheck -join "`n")"
}

[ordered]@{
    ok = $true
    gate = 6
    targetPluginVersion = [string]$contractResult.targetPluginVersion
    currentRuntimeVersion = [string]$contractResult.currentRuntimeVersion
    v1ToolsPreserved = [int]$contractResult.v1ToolsPreserved
    targetTools = [int]$contractResult.v2ToolsDeclared
    v1SchemasPreserved = [int]$contractResult.v1SchemasPreserved
    v2Schemas = [int]$contractResult.v2Schemas
    fixtures = [int]$contractResult.validFixtures +
        [int]$contractResult.schemaInvalidFixtures +
        [int]$contractResult.semanticInvalidFixtures
    migrationFixtures = [int]$contractResult.migrationFixtures
    dynamicContractChecks = [int]$contractResult.dynamicCompatibilityChecks
    p3_1ValidFixtures = [int]$contractResult.p3_1ValidFixtures
    p3_1SchemaInvalidFixtures = [int]$contractResult.p3_1SchemaInvalidFixtures
    p3_1NegativeCases = [int]$contractResult.p3_1NegativeCases
    p3_1Closable = [bool]$contractResult.p3_1Closable
    inheritedBaseline = if ($SkipInheritedBaseline) { 'externallyRequired' } else { 'passed' }
    realHostOperations = 0
    realHyperVMutations = 0
    realGuestOperations = 0
    portableDeployments = 0
    webDriverLaunches = 0
} | ConvertTo-Json -Compress

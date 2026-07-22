[CmdletBinding()]
param([switch]$SkipInheritedBaseline)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtime = Get-Content -LiteralPath (Join-Path $repoRoot '.artifacts\test-python\runtime.json') -Raw -Encoding UTF8 |
    ConvertFrom-Json -ErrorAction Stop

if (-not $SkipInheritedBaseline) {
    $null = & (Join-Path $PSScriptRoot 'validate-gate2.ps1') -SkipRealHostSmoke
}
$null = & (Join-Path $PSScriptRoot 'validate-gate6.ps1') -SkipInheritedBaseline

$runtimeOutput = @(& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
    -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $repoRoot 'tests\gate7-runtime.tests.ps1'))
if ($LASTEXITCODE -ne 0 -or $runtimeOutput.Count -ne 1) {
    throw 'Gate 7 mock runtime validation failed.'
}
$runtimeResult = [string]$runtimeOutput | ConvertFrom-Json -ErrorAction Stop

$oldPythonPath = $env:PYTHONPATH
$oldNoUserSite = $env:PYTHONNOUSERSITE
try {
    $env:PYTHONPATH = [string]$runtime.dependencyPath
    $env:PYTHONNOUSERSITE = '1'
    $implementationOutput = @(& ([string]$runtime.pythonExecutable) -S `
        (Join-Path $repoRoot 'tests\gate7_implementation_tests.py'))
    if ($LASTEXITCODE -ne 0 -or $implementationOutput.Count -ne 1) {
        throw 'Gate 7 production integration/static validation failed.'
    }
    $implementationResult = [string]$implementationOutput | ConvertFrom-Json -ErrorAction Stop
}
finally {
    $env:PYTHONPATH = $oldPythonPath
    $env:PYTHONNOUSERSITE = $oldNoUserSite
}

$previousErrorAction = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $diffCheck = @(& git -C $repoRoot diff --check 2>&1)
    $diffExitCode = $LASTEXITCODE
}
finally { $ErrorActionPreference = $previousErrorAction }
if ($diffExitCode -ne 0) { throw "git diff --check failed: $($diffCheck -join ' ')" }

if (-not [bool]$runtimeResult.ok -or [int]$runtimeResult.tools -ne 20 -or
    -not [bool]$implementationResult.ok -or [int]$implementationResult.v2SchemasInstalled -ne 7 -or
    [int]$runtimeResult.realHyperVMutations -ne 0 -or
    [int]$implementationResult.realGuestOperations -ne 0) {
    throw 'Gate 7 validation did not preserve its frozen counts or zero-real-operation boundary.'
}

[ordered]@{
    ok = $true
    gate = 7
    pluginVersion = [string]$implementationResult.pluginVersion
    tools = [int]$runtimeResult.tools
    v1ToolsPreserved = [int]$runtimeResult.v1ToolsPreserved
    v1SchemasPreserved = [int]$implementationResult.v1SchemasPreserved
    v2SchemasInstalled = [int]$implementationResult.v2SchemasInstalled
    runtimeAssertions = [int]$runtimeResult.assertions
    generatedEvidenceValidated = [int]$implementationResult.generatedEvidenceValidated
    inheritedBaseline = if ($SkipInheritedBaseline) { 'externallyRequired' } else { 'passed' }
    realHostOperations = 0
    realHyperVMutations = 0
    realGuestOperations = 0
    portableDeployments = 0
    webDriverLaunches = 0
    uiOperations = 0
} | ConvertTo-Json -Compress

[CmdletBinding()]
param(
    [switch]$SkipInheritedBaseline,
    [string]$PythonExecutable,
    [string]$DependencyPath,
    [string]$TestRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtime = if ([string]::IsNullOrWhiteSpace($PythonExecutable) -and
    [string]::IsNullOrWhiteSpace($DependencyPath)) {
    Get-Content -LiteralPath (Join-Path $repoRoot '.artifacts\test-python\runtime.json') -Raw -Encoding UTF8 |
        ConvertFrom-Json -ErrorAction Stop
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

if (-not $SkipInheritedBaseline) {
    $null = & (Join-Path $PSScriptRoot 'validate-gate2.ps1') `
        -SkipRealHostSmoke `
        -PythonCommand ([string]$runtime.pythonExecutable) `
        -PythonDependencyPath ([string]$runtime.dependencyPath)
}
$null = & (Join-Path $PSScriptRoot 'validate-gate6.ps1') `
    -SkipInheritedBaseline `
    -PythonExecutable ([string]$runtime.pythonExecutable) `
    -DependencyPath ([string]$runtime.dependencyPath)

$oldGate7TestRoot = $env:HCR_GATE7_TEST_ROOT
try {
    if (-not [string]::IsNullOrWhiteSpace($TestRoot)) {
        $env:HCR_GATE7_TEST_ROOT = [IO.Path]::GetFullPath($TestRoot)
    }
    $runtimeOutput = @(& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
        -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass `
        -File (Join-Path $repoRoot 'tests\gate7-runtime.tests.ps1'))
}
finally {
    $env:HCR_GATE7_TEST_ROOT = $oldGate7TestRoot
}
if ($LASTEXITCODE -ne 0 -or $runtimeOutput.Count -ne 1) {
    throw 'Gate 7 mock runtime validation failed.'
}
$runtimeResult = [string]$runtimeOutput | ConvertFrom-Json -ErrorAction Stop

$oldPythonPath = $env:PYTHONPATH
$oldNoUserSite = $env:PYTHONNOUSERSITE
try {
    $env:PYTHONPATH = [string]$runtime.dependencyPath
    $env:PYTHONNOUSERSITE = '1'
    $env:HCR_GATE7_ARTIFACT_ROOT = [string]$runtimeResult.testRoot
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
    Remove-Item Env:HCR_GATE7_ARTIFACT_ROOT -ErrorAction SilentlyContinue
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

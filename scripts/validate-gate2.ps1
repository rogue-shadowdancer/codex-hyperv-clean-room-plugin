[CmdletBinding()]
param(
    [string]$MarketplacePath,
    [string]$PythonCommand,
    [string[]]$PythonArguments = @(),
    [string]$PythonDependencyPath,
    [switch]$SkipRealHostSmoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$requirementsPath = Join-Path $repoRoot 'requirements-dev.txt'
$preparedRuntimePath = Join-Path $repoRoot '.artifacts\test-python\runtime.json'
$expectedPackages = [ordered]@{
    attrs = '26.1.0'
    jsonschema = '4.26.0'
    'jsonschema-specifications' = '2025.9.1'
    pyyaml = '6.0.3'
    referencing = '0.37.0'
    'rpds-py' = '0.30.0'
    'typing-extensions' = '4.16.0'
}
$expectedJson = $expectedPackages | ConvertTo-Json -Compress
$expectedBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($expectedJson))
if ([string]::IsNullOrWhiteSpace($MarketplacePath)) {
    $MarketplacePath = Join-Path $repoRoot 'tests\fixtures\marketplace.json'
}

$usingPreparedRuntime = [string]::IsNullOrWhiteSpace($PythonCommand)
if ($usingPreparedRuntime) {
    $prepareHint = '.\scripts\prepare-test-python.ps1'
    if (-not (Test-Path -LiteralPath $preparedRuntimePath -PathType Leaf)) {
        throw "Prepared test Python is unavailable. Run $prepareHint, then rerun validate-gate2.ps1."
    }
    try {
        $preparedRuntime = Get-Content -LiteralPath $preparedRuntimePath -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Prepared test Python metadata is unreadable. Run $prepareHint to repair it."
    }
    $requirementsHash = if (Test-Path -LiteralPath $requirementsPath -PathType Leaf) {
        (Get-FileHash -LiteralPath $requirementsPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    else { '' }
    $PythonCommand = [string]$preparedRuntime.pythonCommand
    $PythonArguments = @($preparedRuntime.pythonArguments | ForEach-Object { [string]$_ })
    $PythonDependencyPath = [string]$preparedRuntime.dependencyPath
    if ([int]$preparedRuntime.schemaVersion -ne 1 -or
        [string]::IsNullOrWhiteSpace($PythonCommand) -or
        [string]::IsNullOrWhiteSpace($PythonDependencyPath) -or
        -not (Test-Path -LiteralPath $PythonDependencyPath -PathType Container) -or
        [string]$preparedRuntime.requirementsSha256 -ne $requirementsHash) {
        throw "Prepared test Python is stale or incomplete. Run $prepareHint, then rerun validate-gate2.ps1."
    }
}

$python = Get-Command $PythonCommand -ErrorAction SilentlyContinue
if ($null -eq $python) {
    if ($usingPreparedRuntime) {
        throw 'The prepared Python interpreter is no longer available. Rerun .\scripts\prepare-test-python.ps1.'
    }
    throw 'The requested Python interpreter is unavailable.'
}
$pythonExecutable = if (-not [string]::IsNullOrWhiteSpace([string]$python.Source)) {
    [string]$python.Source
}
else { [string]$python.Path }
if ([string]::IsNullOrWhiteSpace($pythonExecutable)) {
    throw 'The requested Python interpreter could not be resolved to an executable.'
}

function Invoke-Gate2Python {
    param([Parameter(Mandatory = $true)][string]$ScriptPath)

    & $pythonExecutable @PythonArguments -S $ScriptPath
    if ($LASTEXITCODE -ne 0) {
        throw "Python validation failed: $([IO.Path]::GetFileName($ScriptPath))."
    }
}

$oldPythonPath = $env:PYTHONPATH
$oldNoUserSite = $env:PYTHONNOUSERSITE
try {
    if (-not [string]::IsNullOrWhiteSpace($PythonDependencyPath)) {
        $dependencyItem = Get-Item -LiteralPath $PythonDependencyPath -ErrorAction SilentlyContinue
        if ($null -eq $dependencyItem -or -not $dependencyItem.PSIsContainer) {
            throw 'The requested Python dependency directory is unavailable.'
        }
        $env:PYTHONPATH = $dependencyItem.FullName
    }
    $env:PYTHONNOUSERSITE = '1'
    $probeCode = @'
import base64
import importlib.metadata as metadata
import json
import platform
import re
import sys
import sysconfig
expected = json.loads(base64.b64decode(sys.argv[1]).decode('utf-8'))
dependency_path = sys.argv[2]
exact_inventory = sys.argv[3] == '1'
if exact_inventory:
    items = []
    for distribution in metadata.distributions(path=[dependency_path]):
        name = distribution.metadata.get('Name')
        if name:
            items.append((re.sub(r'[-_.]+', '-', name).lower(), distribution.version))
    if len(items) != len(set(name for name, _ in items)):
        raise SystemExit('duplicate prepared distributions')
    actual = dict(items)
else:
    actual = {name: metadata.version(name) for name in expected}
if actual != expected:
    raise SystemExit('development dependency inventory mismatch')
import jsonschema
import yaml
print(json.dumps({
    'packages': actual,
    'pythonVersion': platform.python_version(),
    'implementation': platform.python_implementation(),
    'cacheTag': sys.implementation.cache_tag,
    'platformTag': sysconfig.get_platform(),
    'machine': platform.machine(),
    'pythonExecutable': sys.executable,
}, sort_keys=True))
'@
    $exactInventory = if ([string]::IsNullOrWhiteSpace($PythonDependencyPath)) { '0' } else { '1' }
    $probe = & $pythonExecutable @PythonArguments -S -c `
        $probeCode $expectedBase64 ([string]$PythonDependencyPath) $exactInventory 2>$null
    if ($LASTEXITCODE -ne 0 -or @($probe).Count -ne 1) {
        if ($usingPreparedRuntime) {
            throw 'Prepared test Python failed dependency readback. Rerun .\scripts\prepare-test-python.ps1.'
        }
        throw 'Python development dependencies are unavailable; run prepare-test-python.ps1 or pass an isolated dependency path.'
    }
    try { $probeResult = [string]$probe | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'Python development dependency readback returned invalid metadata.' }
    if ($usingPreparedRuntime) {
        $expectedAbiLabel = (([string]$probeResult.cacheTag + '-' + [string]$probeResult.platformTag) `
            -replace '[^a-zA-Z0-9._-]', '-').ToLowerInvariant()
        if ([string]$probeResult.pythonVersion -cne [string]$preparedRuntime.pythonVersion -or
            [string]$probeResult.implementation -cne [string]$preparedRuntime.implementation -or
            [string]$probeResult.cacheTag -cne [string]$preparedRuntime.cacheTag -or
            [string]$probeResult.platformTag -cne [string]$preparedRuntime.platformTag -or
            [string]$probeResult.machine -cne [string]$preparedRuntime.machine -or
            [string]$probeResult.pythonExecutable -ine [string]$preparedRuntime.pythonExecutable -or
            $expectedAbiLabel -cne [string]$preparedRuntime.abiLabel -or
            [IO.Path]::GetFullPath([string]$preparedRuntime.requirementsPath) -ine `
                [IO.Path]::GetFullPath($requirementsPath)) {
            throw 'Prepared test Python ABI metadata drifted. Rerun .\scripts\prepare-test-python.ps1.'
        }
    }

    $null = & (Join-Path $PSScriptRoot 'validate-gate1.ps1') `
        -MarketplacePath $MarketplacePath
    $null = & (Join-Path $repoRoot 'tests\gate1-contract.tests.ps1')
    $null = & (Join-Path $repoRoot 'tests\gate2-runtime.tests.ps1')
    if (-not $SkipRealHostSmoke) {
        $null = & (Join-Path $repoRoot 'tests\gate2-real-readonly.tests.ps1')
    }
    $null = & (Join-Path $PSScriptRoot 'validate-docs.ps1')
    Invoke-Gate2Python (Join-Path $repoRoot 'tests\schema_contract_tests.py')
    Invoke-Gate2Python (Join-Path $repoRoot 'tests\runtime_artifact_schema_tests.py')
    Invoke-Gate2Python (Join-Path $repoRoot 'tests\static_quality_tests.py')
}
finally {
    $env:PYTHONPATH = $oldPythonPath
    $env:PYTHONNOUSERSITE = $oldNoUserSite
}

$realHostOperations = @()
if (-not $SkipRealHostSmoke) {
    $realHostOperations = @(
        'inspect_host',
        'plan_vm_create missing-ISO rejection'
    )
}

[ordered]@{
    ok = $true
    gate = 2
    marketplacePath = [IO.Path]::GetFullPath($MarketplacePath)
    python = $pythonExecutable
    isolatedDependencies = -not [string]::IsNullOrWhiteSpace($PythonDependencyPath)
    realHostOperations = $realHostOperations
    realHyperVMutations = 0
} | ConvertTo-Json -Compress

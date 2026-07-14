[CmdletBinding()]
param(
    [string]$MarketplacePath = (
        Join-Path (Split-Path -Parent $PSScriptRoot) 'tests\fixtures\marketplace.json'
    ),
    [string]$PythonCommand = 'python',
    [string[]]$PythonArguments = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$null = & (Join-Path $PSScriptRoot 'validate-gate1.ps1') `
    -MarketplacePath $MarketplacePath
$null = & (Join-Path $repoRoot 'tests\gate1-contract.tests.ps1')
$null = & (Join-Path $repoRoot 'tests\gate2-runtime.tests.ps1')

$python = Get-Command $PythonCommand -ErrorAction SilentlyContinue
if ($null -eq $python) {
    throw 'Python is required only for the development schema and static-quality checks.'
}
& $python.Source @PythonArguments (Join-Path $repoRoot 'tests\schema_contract_tests.py')
if ($LASTEXITCODE -ne 0) { throw 'Draft 2020-12 schema tests failed.' }
& $python.Source @PythonArguments (Join-Path $repoRoot 'tests\runtime_artifact_schema_tests.py')
if ($LASTEXITCODE -ne 0) { throw 'Runtime artifact schema tests failed.' }
& $python.Source @PythonArguments (Join-Path $repoRoot 'tests\static_quality_tests.py')
if ($LASTEXITCODE -ne 0) { throw 'Static-quality tests failed.' }

[ordered]@{
    ok = $true
    gate = 2
    marketplacePath = [IO.Path]::GetFullPath($MarketplacePath)
    realHyperVMutations = 0
} | ConvertTo-Json -Compress

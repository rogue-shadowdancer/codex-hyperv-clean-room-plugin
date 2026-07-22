[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Assert-Gate4Ci {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) { throw $Message }
}

$gate2Output = @(& (Join-Path $PSScriptRoot 'validate-gate2.ps1') `
        -SkipRealHostSmoke)
Assert-Gate4Ci ($gate2Output.Count -gt 0) `
    'CI-safe Gate 2 validation returned no result.'
$gate2Result = [string]$gate2Output[-1] | ConvertFrom-Json -ErrorAction Stop

$sourceResult = & (Join-Path $PSScriptRoot 'validate-install-source.ps1') |
    ConvertFrom-Json -ErrorAction Stop
$installationOutput = @(& (Join-Path $repoRoot 'tests\gate4-installation.tests.ps1'))
Assert-Gate4Ci ($installationOutput.Count -gt 0) `
    'Gate 4 installer-security tests returned no result.'
$installationResult = [string]$installationOutput[-1] |
    ConvertFrom-Json -ErrorAction Stop

Assert-Gate4Ci ([bool]$gate2Result.ok -and [int]$gate2Result.gate -eq 2) `
    'The inherited Gate 2 baseline did not pass.'
Assert-Gate4Ci (@($gate2Result.realHostOperations).Count -eq 0) `
    'CI-safe Gate 4 validation must not execute a real-host smoke.'
Assert-Gate4Ci ([int]$gate2Result.realHyperVMutations -eq 0) `
    'CI-safe Gate 4 validation reported a Hyper-V mutation.'
Assert-Gate4Ci ([int]$sourceResult.fileCount -eq 31 -and
    [int]$sourceResult.schemaCount -eq 5 -and
    [int]$sourceResult.schemaV2Count -eq 7) `
    'Integrated source inventory no longer has 31 files, five v1 schemas, and seven v2 schemas.'
Assert-Gate4Ci ([int]$installationResult.assertions -ge 33 -and
    [int]$installationResult.realHyperVMutations -eq 0) `
    'Gate 4 installer-security coverage did not pass its frozen boundary.'

[ordered]@{
    ok = $true
    gate = 4
    mode = 'ci-safe'
    sourceFiles = [int]$sourceResult.fileCount
    publicSchemas = [int]$sourceResult.schemaCount
    schemaV2Files = [int]$sourceResult.schemaV2Count
    installerAssertions = [int]$installationResult.assertions
    personalInstallOperations = 0
    marketplaceMutations = 0
    installedCopyOperations = 0
    realHostOperations = 0
    realGuestOperations = 0
    realHyperVMutations = 0
} | ConvertTo-Json -Compress

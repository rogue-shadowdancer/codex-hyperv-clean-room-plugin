[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$output = @(& (Join-Path $repoRoot 'scripts\validate-github-actions-history.ps1') `
        -PolicySelfTest)
if ($output.Count -eq 0) { throw 'Actions log hygiene policy returned no result.' }
$result = [string]$output[-1] | ConvertFrom-Json -ErrorAction Stop
if (-not [bool]$result.ok -or [int]$result.allowedFixtures -lt 8 -or
    [int]$result.rejectedFixtures -lt 11 -or
    -not [bool]$result.exactRunnerSegments -or
    -not [bool]$result.secretLiteralPolicy -or
    -not [bool]$result.machineStatePolicy) {
    throw 'Actions log hygiene policy regressions did not pass.'
}
$result | ConvertTo-Json -Compress

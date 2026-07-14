[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $repoRoot 'hyperv-clean-room'
$targetRoot = Join-Path $HOME 'plugins\hyperv-clean-room'
$marketplacePath = Join-Path $HOME '.agents\plugins\marketplace.json'
. (Join-Path $PSScriptRoot 'install-common.ps1')

$inventory = Get-HcrSourceInventory -SourceRoot $sourceRoot
$result = Get-HcrInstallCheck `
    -SourceInventory $inventory `
    -TargetRoot $targetRoot `
    -MarketplacePath $marketplacePath
$result | ConvertTo-Json -Depth 10 -Compress

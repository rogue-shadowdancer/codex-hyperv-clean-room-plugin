[CmdletBinding()]
param([switch]$RequireCachebuster)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $repoRoot 'hyperv-clean-room'
. (Join-Path $PSScriptRoot 'install-common.ps1')

$inventory = Get-HcrSourceInventory `
    -SourceRoot $sourceRoot `
    -RequireCachebuster:$RequireCachebuster
[ordered]@{
    ok = $true
    pluginName = $inventory.pluginName
    sourceRoot = $inventory.sourceRoot
    sourceVersion = $inventory.sourceVersion
    baseVersion = $inventory.baseVersion
    sourceCommit = $inventory.sourceCommit
    cachebuster = $inventory.cachebuster
    fileCount = $inventory.fileCount
    schemaCount = @(Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'schemas') `
        -File -Filter '*.json').Count
    schemaV2Count = @(Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'schemas\v2') `
        -File -Filter '*.json').Count
    totalBytes = $inventory.totalBytes
    reparsePoints = 0
    untrackedPayloadFiles = 0
} | ConvertTo-Json -Compress

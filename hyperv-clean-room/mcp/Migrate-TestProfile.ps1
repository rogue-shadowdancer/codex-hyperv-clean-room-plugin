[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceProfilePath,
    [Parameter(Mandatory = $true)][string]$DestinationProfilePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$libRoot = Join-Path $PSScriptRoot 'lib'
foreach ($file in @('Common.ps1', 'State.ps1', 'ToolSchemas.ps1', 'Validation.ps1', 'Validation.V2.ps1')) {
    . (Join-Path $libRoot $file)
}

$source = Read-HcrJsonDocument $SourceProfilePath 'MIGRATION_SOURCE_INVALID' 4MB
if ((Get-HcrExactSchemaVersion $source.document 'Profile') -ne 1) {
    Throw-HcrError 'MIGRATION_SOURCE_INVALID' 'Only a schema-v1 source profile can be migrated.'
}
$destination = Get-HcrNormalizedPath $DestinationProfilePath
if (Test-Path -LiteralPath $destination) {
    Throw-HcrError 'MIGRATION_DESTINATION_EXISTS' 'Migration never overwrites an existing destination.'
}
$parent = Split-Path -Parent $destination
if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    Throw-HcrError 'MIGRATION_DESTINATION_INVALID' 'The destination parent directory does not exist.'
}
$migrated = Convert-HcrProfileV1ToV2 $source.document
$validation = Test-HcrProfileDocumentV2 $migrated
if (-not $validation.valid) {
    Throw-HcrError 'MIGRATION_RESULT_INVALID' 'The deterministic migration result failed schema-v2 validation.' ([ordered]@{
        errors = @($validation.errors)
    })
}
Write-HcrJsonFile $destination $migrated
[pscustomobject][ordered]@{
    sourcePath = $source.path
    destinationPath = $destination
    sourceSchemaVersion = 1
    destinationSchemaVersion = 2
    sourcePreserved = $true
    destinationSha256 = Get-HcrSha256File $destination
} | ConvertTo-Json -Depth 10

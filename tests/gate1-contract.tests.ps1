[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$specificationPath = Join-Path $repoRoot 'docs\specification.md'
$profileSchemaPath = Join-Path `
    $repoRoot `
    'hyperv-clean-room\schemas\test-profile.schema.json'
$evidenceSchemaPath = Join-Path `
    $repoRoot `
    'hyperv-clean-room\schemas\evidence.schema.json'

$specification = Get-Content -LiteralPath $specificationPath -Raw -Encoding UTF8
$profileSchema = Get-Content -LiteralPath $profileSchemaPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$evidenceSchema = Get-Content -LiteralPath $evidenceSchemaPath -Raw -Encoding UTF8 |
    ConvertFrom-Json

$requiredTools = @(
    'inspect_host',
    'list_vms',
    'inspect_vm',
    'validate_test_profile',
    'validate_evidence',
    'plan_vm_create',
    'apply_vm_create',
    'create_checkpoint',
    'plan_checkpoint_restore',
    'apply_checkpoint_restore',
    'inspect_guest',
    'stage_artifact',
    'run_test_profile',
    'collect_evidence'
)
foreach ($tool in $requiredTools) {
    $toolToken = '`{0}`' -f $tool
    if ($specification -notmatch [regex]::Escape($toolToken)) {
        throw "Frozen specification is missing tool: $tool"
    }
}

$forbiddenTools = @('delete_vm', 'delete_vhdx', 'remove_checkpoint')
$specificationLines = @($specification -split "`r?`n")
foreach ($tool in $forbiddenTools) {
    $toolToken = '`{0}`' -f $tool
    if ($specificationLines -contains $toolToken) {
        throw "Frozen specification exposes forbidden tool: $tool"
    }
}

$stepProperties = @($profileSchema.'$defs'.step.properties.PSObject.Properties.Name)
foreach ($forbiddenField in @('command', 'script', 'shell', 'url', 'executable')) {
    if ($stepProperties -contains $forbiddenField) {
        throw "Profile step schema exposes forbidden field: $forbiddenField"
    }
}

$guestRequired = @($evidenceSchema.properties.guest.required)
foreach ($field in @('isAdministrator', 'isElevated', 'tokenIntegrity')) {
    if ($guestRequired -notcontains $field) {
        throw "Evidence does not require ordinary-user token field: $field"
    }
}
$artifactRequired = @($evidenceSchema.properties.artifact.required)
foreach ($field in @('sourceSha256', 'guestSha256')) {
    if ($artifactRequired -notcontains $field) {
        throw "Evidence does not require staged artifact hash: $field"
    }
}

[ordered]@{
    ok = $true
    requiredTools = $requiredTools.Count
    forbiddenTools = $forbiddenTools.Count
    profileStepFields = $stepProperties.Count
    guestIdentityFields = $guestRequired.Count
    artifactIdentityFields = $artifactRequired.Count
} | ConvertTo-Json -Depth 3

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
$vmPlanSchemaPath = Join-Path `
    $repoRoot `
    'hyperv-clean-room\schemas\vm-plan.schema.json'
$checkpointPlanSchemaPath = Join-Path `
    $repoRoot `
    'hyperv-clean-room\schemas\checkpoint-plan.schema.json'

$specification = Get-Content -LiteralPath $specificationPath -Raw -Encoding UTF8
$profileSchema = Get-Content -LiteralPath $profileSchemaPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$evidenceSchema = Get-Content -LiteralPath $evidenceSchemaPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$vmPlanSchema = Get-Content -LiteralPath $vmPlanSchemaPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$checkpointPlanSchema = Get-Content `
    -LiteralPath $checkpointPlanSchemaPath `
    -Raw `
    -Encoding UTF8 |
    ConvertFrom-Json

$requiredTools = @(
    'inspect_host',
    'list_vms',
    'inspect_vm',
    'validate_test_profile',
    'validate_evidence',
    'plan_vm_create',
    'apply_vm_create',
    'plan_checkpoint_create',
    'apply_checkpoint_create',
    'plan_checkpoint_restore',
    'apply_checkpoint_restore',
    'inspect_guest',
    'stage_artifact',
    'run_test_profile',
    'collect_evidence',
    'record_manual_attestation'
)
foreach ($tool in $requiredTools) {
    $toolToken = '`{0}`' -f $tool
    if ($specification -notmatch [regex]::Escape($toolToken)) {
        throw "Frozen specification is missing tool: $tool"
    }
}

$forbiddenTools = @(
    'create_checkpoint',
    'delete_vm',
    'delete_vhdx',
    'remove_checkpoint'
)
$specificationLines = @($specification -split "`r?`n")
foreach ($tool in $forbiddenTools) {
    $toolToken = '`{0}`' -f $tool
    if ($specificationLines -contains $toolToken) {
        throw "Frozen specification exposes forbidden tool: $tool"
    }
}

foreach ($pattern in @(
        'Recompute\s+the\s+overall\s+status',
        'matching\s+source\s+and\s+guest\s+artifact\s+SHA-256\s+values',
        'never\s+let\s+`run_test_profile`\s+produce\s+a\s+passed\s+manual\s+assertion'
    )) {
    if ($specification -notmatch $pattern) {
        throw "Frozen specification is missing semantic evidence rule: $pattern"
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

$vmPlanRequired = @($vmPlanSchema.required)
foreach ($field in @(
        'isoPath',
        'vmPath',
        'vhdxPath',
        'targetVolume',
        'preconditions',
        'switchName',
        'switchId'
    )) {
    if ($vmPlanRequired -notcontains $field) {
        throw "VM plan does not require auditable precondition field: $field"
    }
}
$preconditions = $vmPlanSchema.properties.preconditions
foreach ($field in @(
        'isoRegularFile',
        'switchPresent',
        'vmNameAbsent',
        'vmPathAbsent',
        'vhdxPathAbsent'
    )) {
    if (@($preconditions.required) -notcontains $field) {
        throw "VM plan does not require precondition: $field"
    }
    if ($preconditions.properties.$field.const -ne $true) {
        throw "VM plan precondition is not const true: $field"
    }
}

if (@($checkpointPlanSchema.oneOf).Count -ne 2) {
    throw 'Checkpoint plan must contain create and restore variants.'
}
$checkpointCommon = @($checkpointPlanSchema.required)
foreach ($field in @(
        'planKind',
        'vmId',
        'ownershipId',
        'vmFingerprint',
        'checkpointName',
        'checkpointInventoryFingerprint'
    )) {
    if ($checkpointCommon -notcontains $field) {
        throw "Checkpoint plan does not require common field: $field"
    }
}

$manualAssertion = $evidenceSchema.'$defs'.manualAssertion
$attestation = $evidenceSchema.'$defs'.attestation
if (@($manualAssertion.required) -notcontains 'attestation') {
    throw 'Manual assertions do not require an attestation field.'
}
foreach ($field in @(
        'operationId',
        'profileId',
        'assertionId',
        'observer',
        'observedAt',
        'method',
        'summary',
        'evidenceReferences'
    )) {
    if (@($attestation.required) -notcontains $field) {
        throw "Manual attestation does not require provenance field: $field"
    }
}

[ordered]@{
    ok = $true
    requiredTools = $requiredTools.Count
    forbiddenTools = $forbiddenTools.Count
    profileStepFields = $stepProperties.Count
    guestIdentityFields = $guestRequired.Count
    artifactIdentityFields = $artifactRequired.Count
    vmPlanFields = $vmPlanRequired.Count
    checkpointPlanVariants = @($checkpointPlanSchema.oneOf).Count
    manualAttestationFields = @($attestation.required).Count
} | ConvertTo-Json -Depth 3

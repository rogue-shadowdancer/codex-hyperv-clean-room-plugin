[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-SetEqual {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Actual,
        [Parameter(Mandatory = $true)]
        [object[]]$Expected,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $actualValues = @($Actual | ForEach-Object { "$_" } | Sort-Object -Unique)
    $expectedValues = @($Expected | ForEach-Object { "$_" } | Sort-Object -Unique)
    $difference = @(Compare-Object $expectedValues $actualValues)
    if ($difference.Count -ne 0) {
        throw "$Message Difference: $($difference | Out-String)"
    }
}

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
$manifestPath = Join-Path `
    $repoRoot `
    'hyperv-clean-room\.codex-plugin\plugin.json'
$serverPath = Join-Path $repoRoot 'hyperv-clean-room\mcp\server.ps1'
$documentationPaths = @(
    (Join-Path $repoRoot 'README.md'),
    (Join-Path $repoRoot 'docs\README.md'),
    (Join-Path $repoRoot 'docs\profile-authoring.md'),
    (Join-Path $repoRoot 'examples\minimal-test-profile.json')
)

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
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$serverScript = Get-Content -LiteralPath $serverPath -Raw -Encoding UTF8

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
if ($requiredTools.Count -ne 16) {
    throw "Expected exactly 16 frozen MCP tools, found $($requiredTools.Count)."
}
foreach ($tool in $requiredTools) {
    $toolToken = '`{0}`' -f $tool
    if ($specification -notmatch [regex]::Escape($toolToken)) {
        throw "Frozen specification is missing tool: $tool"
    }
}
$declaredToolHeadings = @(
    [regex]::Matches($specification, '(?m)^####\s+`([a-z][a-z0-9_]*)`$') |
        ForEach-Object { $_.Groups[1].Value }
)
Assert-SetEqual $declaredToolHeadings $requiredTools `
    'Specification tool headings do not match the exact 16-tool surface.'

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
        'never\s+let\s+`run_test_profile`\s+produce\s+a\s+passed\s+manual\s+assertion',
        'atomically\s+consumes?\s+the\s+plan\s+before\s+checking',
        'current\s+`availableBytes`\s+must\s+be\s+at\s+least\s+the\s+recorded\s+`requiredBytes`',
        'Plaintext\s+may\s+appear\s+exactly\s+once',
        '`artifactPath`\s+is\s+a\s+host-local\s+ordinary\s+file',
        'low-level\s+preflight,\s+troubleshooting,\s+or\s+explicitly\s+manual',
        'never\s+implicitly\s+reused\s+by\s+a\s+later\s+`run_test_profile`',
        'server-controlled\s+evidence\s+staging\s+root',
        'cleanup\s+results\s+are\s+excluded\s+from\s+this\s+derivation',
        '`Initialize-GuestCredential\.ps1`\s+accepts\s+exactly\s+`-ProfileName`\s+and\s+`-VmName`',
        'must\s+not\s+depend\s+on\s+Python',
        'Cleanup\s+is\s+armed\s+only\s+after\s+`run_test_profile`',
        'failed\s+required\s+assertion,\s+failed\s+action\s+or\s+mutation,\s+step\s+timeout,\s+or\s+guest-adapter',
        'does\s+not\s+trigger\s+for\s+pre-execution\s+validation\s+failures',
        'does\s+not\s+prevent\s+later\s+declared\s+cleanup\s+steps',
        'target\s+only\s+a\s+PID\s+recorded\s+as\s+launched\s+by\s+the\s+current',
        'Cleanup\s+never\s+uninstalls\s+a\s+package',
        '`cleanupTriggered`\s+is\s+copied\s+from\s+immutable\s+operation\s+trigger\s+state',
        'When\s+`cleanupTriggered`\s+is\s+false,\s+every\s+declared\s+entry\s+is\s+`notPerformed`'
    )) {
    if ($specification -notmatch $pattern) {
        throw "Frozen specification is missing semantic evidence rule: $pattern"
    }
}

$protocolVersions = @(
    [regex]::Matches($specification, '\b20\d{2}-\d{2}-\d{2}\b') |
        ForEach-Object { $_.Value }
)
Assert-SetEqual $protocolVersions @(
    '2024-11-05',
    '2025-03-26',
    '2025-06-18',
    '2025-11-25'
) 'Frozen MCP protocol versions changed.'

if ($manifest.version -ne '0.1.0') {
    throw "Gate 1.1 plugin version must remain exactly 0.1.0: $($manifest.version)"
}
if ($serverScript -match 'not implemented yet' -or $serverScript -match 'exit\s+78\s*$') {
    throw 'MCP entry point still contains the obsolete Gate 1.1 fail-closed stub.'
}
if ($serverScript -notmatch 'Initialize-HcrRuntime' -or
    $serverScript -notmatch "'tools/list'" -or
    $serverScript -notmatch "'tools/call'") {
    throw 'MCP entry point does not load and expose the Gate 2 runtime.'
}
foreach ($path in $documentationPaths) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required Gate 1.1 documentation artifact is missing: $path"
    }
}

$stepProperties = @($profileSchema.'$defs'.step.properties.PSObject.Properties.Name)
foreach ($forbiddenField in @('command', 'script', 'shell', 'url', 'executable')) {
    if ($stepProperties -contains $forbiddenField) {
        throw "Profile step schema exposes forbidden field: $forbiddenField"
    }
}

if (@($profileSchema.required) -notcontains 'cleanupSteps') {
    throw 'Profile schema does not require explicit cleanupSteps.'
}
$cleanupArray = $profileSchema.properties.cleanupSteps
$cleanupStep = $profileSchema.'$defs'.cleanupStep
if ($cleanupArray.maxItems -ne 16) {
    throw 'cleanupSteps maxItems must be 16.'
}
if ($cleanupStep.additionalProperties -ne $false) {
    throw 'cleanupStep must be independently closed.'
}
if ($cleanupStep.properties.timeoutSeconds.minimum -ne 1 -or
    $cleanupStep.properties.timeoutSeconds.maximum -ne 120) {
    throw 'cleanupStep timeout must be from 1 through 120 seconds.'
}
$requiredCleanupTypes = @(
    'stopApplication',
    'wait',
    'assertFile',
    'assertRegistry',
    'assertProcess',
    'assertModule',
    'assertShortcut',
    'assertPort',
    'assertSentinel'
)
Assert-SetEqual @($cleanupStep.properties.type.enum) $requiredCleanupTypes `
    'cleanupStep type allowlist changed.'
$cleanupProperties = @($cleanupStep.properties.PSObject.Properties.Name)
foreach ($forbiddenField in @(
        'command',
        'script',
        'shell',
        'url',
        'executable'
    )) {
    if ($cleanupProperties -contains $forbiddenField) {
        throw "cleanupStep exposes forbidden field: $forbiddenField"
    }
}
$safeRelativePattern = $profileSchema.'$defs'.safeRelativePath.pattern
if ('%USERPROFILE%\escape.exe' -match $safeRelativePattern) {
    throw 'safeRelativePath accepts an environment-expanding path.'
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
foreach ($field in @('cleanupTriggered', 'cleanupResults')) {
    if (@($evidenceSchema.required) -notcontains $field) {
        throw "Evidence schema does not require $field."
    }
}
$cleanupResult = $evidenceSchema.'$defs'.cleanupResult
if ($cleanupResult.additionalProperties -ne $false) {
    throw 'cleanupResult must be closed.'
}
foreach ($field in @(
        'operationId',
        'profileId',
        'cleanupStepId',
        'cleanupStepType',
        'status',
        'summary',
        'evidence'
    )) {
    if (@($cleanupResult.required) -notcontains $field) {
        throw "cleanupResult does not require identity/result field: $field"
    }
}
Assert-SetEqual @($cleanupResult.properties.status.enum) @(
    'passed',
    'failed',
    'notPerformed',
    'unsupported'
) 'cleanupResult status allowlist changed.'
Assert-SetEqual @($cleanupResult.properties.cleanupStepType.enum) `
    $requiredCleanupTypes `
    'cleanupResult type allowlist changed.'

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
    declaredTools = $declaredToolHeadings.Count
    protocolVersions = $protocolVersions.Count
    forbiddenTools = $forbiddenTools.Count
    profileStepFields = $stepProperties.Count
    cleanupTypes = $requiredCleanupTypes.Count
    cleanupTriggerRequired = @($evidenceSchema.required) -contains 'cleanupTriggered'
    cleanupResultFields = @($cleanupResult.required).Count
    guestIdentityFields = $guestRequired.Count
    artifactIdentityFields = $artifactRequired.Count
    vmPlanFields = $vmPlanRequired.Count
    checkpointPlanVariants = @($checkpointPlanSchema.oneOf).Count
    manualAttestationFields = @($attestation.required).Count
} | ConvertTo-Json -Depth 3

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:AssertionCount = 0

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $script:AssertionCount++
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param(
        [AllowNull()][object]$Actual,
        [AllowNull()][object]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $script:AssertionCount++
    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected', received '$Actual'."
    }
}

function Assert-ErrorCode {
    param(
        [Parameter(Mandatory = $true)][object]$Envelope,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )
    Assert-True (-not [bool]$Envelope.ok) "$Message The operation unexpectedly succeeded."
    Assert-Equal ([string]$Envelope.error.code) $Code $Message
}

function Assert-OperationEnvelope {
    param([Parameter(Mandatory = $true)][object]$Envelope)

    Assert-Equal ([int]$Envelope.schemaVersion) 1 'Envelope schemaVersion changed.'
    Assert-True ($Envelope.ok -is [bool]) 'Envelope ok must be boolean.'
    Assert-True (Test-HcrUuid $Envelope.operationId) 'Envelope operationId must be a UUID.'
    Assert-True ($Envelope.changed -is [bool]) 'Envelope changed must be boolean.'
    Assert-True (Test-HcrObjectLike $Envelope.data) 'Envelope data must be an object.'
    Assert-True ($Envelope.warnings -is [System.Collections.IEnumerable]) 'Envelope warnings must be an array.'
    if ($Envelope.ok) {
        Assert-True (-not (Test-HcrProperty $Envelope 'error')) 'Successful envelope contains an error.'
    }
    else {
        Assert-True (Test-HcrProperty $Envelope 'error') 'Failed envelope lacks an error.'
        Assert-True ([string]$Envelope.error.code -match '^[A-Z][A-Z0-9_]*$') 'Error code format changed.'
    }
}

function Write-TestJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    [IO.File]::WriteAllText(
        $Path,
        (($Value | ConvertTo-Json -Depth 100 -Compress) + "`n"),
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Invoke-TestTool {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][object]$Arguments = $null
    )
    if ($null -eq $Arguments) { $Arguments = [pscustomobject]@{} }
    $result = Invoke-HcrToolCall $Name $Arguments
    Assert-OperationEnvelope $result
    return $result
}

function Start-TestProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $FilePath
    $info.Arguments = $Arguments
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    [void]$process.Start()
    return $process
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$pluginRoot = Join-Path $repoRoot 'hyperv-clean-room'
$testRoot = Join-Path $repoRoot (
    '.artifacts\gate2-tests-' + [Guid]::NewGuid().ToString('N')
)
$vmRoot = Join-Path $testRoot 'vm-root'
$stateRoot = Join-Path $testRoot 'state'
$credentialRoot = Join-Path $testRoot 'credentials'
$mockPath = Join-Path $testRoot 'mock-adapter.json'
$isoPath = Join-Path $testRoot 'source.iso'
$exportRoot = Join-Path $testRoot 'exports'
$schemaSampleRoot = Join-Path $testRoot 'runtime-schema-samples'
foreach ($directory in @($vmRoot, $exportRoot, $schemaSampleRoot)) {
    [void](New-Item -ItemType Directory -Path $directory -Force)
}
[IO.File]::WriteAllBytes($isoPath, [byte[]](1..128))

$volumeRoot = [IO.Path]::GetPathRoot($testRoot)
$mockState = [ordered]@{
    schemaVersion = 1
    host = [ordered]@{
        computerName = 'MOCK-HOST'
        windowsEdition = 'Windows 11 Pro'
        windowsBuild = '26100'
        architecture = 'AMD64'
        hyperVCommandsAvailable = $true
        hypervisorPresent = $true
        elevated = $true
        processorCount = 8
        memoryBytes = 17179869184
        switches = @([ordered]@{
            id = 'switch-1'
            name = 'Default Switch'
            type = 'Internal'
        })
        targetVolumes = @([ordered]@{
            uniqueId = 'mock-volume'
            root = $volumeRoot
            fileSystem = 'NTFS'
            availableBytes = 1099511627776
        })
    }
    vms = @()
    credentialProfiles = @([ordered]@{
        name = 'test-profile'
        vmName = 'cleanroom-test'
    })
    guest = [ordered]@{
        windowsBuild = '26100'
        architecture = 'x64'
        userName = 'TEST\standard'
        isAdministrator = $false
        isElevated = $false
        tokenIntegrity = 'medium'
        profilePathContainsNonAscii = $false
    }
    stepResults = [ordered]@{}
    cleanupResults = [ordered]@{}
}
Write-TestJson $mockPath $mockState

$env:HCR_TEST_MODE = '1'
$env:HCR_ADAPTER_MODE = 'mock'
$env:HCR_MOCK_ADAPTER_PATH = $mockPath
$env:HCR_STATE_ROOT = $stateRoot
$env:HCR_CREDENTIAL_ROOT = $credentialRoot
$script:HcrInitialized = $false
foreach ($runtimeFile in @(
        'Common.ps1',
        'State.ps1',
        'ToolSchemas.ps1',
        'Validation.ps1',
        'Adapters.ps1',
        'Tools.Host.ps1',
        'Tools.Guest.ps1',
        'Runtime.ps1'
    )) {
    . (Join-Path (Join-Path (Join-Path $pluginRoot 'mcp') 'lib') $runtimeFile)
}
Initialize-HcrRuntime $pluginRoot

$expectedTools = @(
    'inspect_host', 'list_vms', 'inspect_vm', 'validate_test_profile',
    'validate_evidence', 'plan_vm_create', 'apply_vm_create',
    'plan_checkpoint_create', 'apply_checkpoint_create',
    'plan_checkpoint_restore', 'apply_checkpoint_restore', 'inspect_guest',
    'stage_artifact', 'run_test_profile', 'collect_evidence',
    'record_manual_attestation'
)
$definitions = @(Get-HcrToolDefinitions)
Assert-Equal $definitions.Count 16 'Runtime tool count changed.'
Assert-Equal (@(Compare-Object $expectedTools @($definitions.name)).Count) 0 `
    'Runtime tool names changed.'
Assert-Equal (@($definitions | Where-Object { $_.name -match 'delete|remove|shell|command' }).Count) 0 `
    'A forbidden public tool appeared.'
foreach ($definition in $definitions) {
    Assert-True ($definition.inputSchema.additionalProperties -eq $false) `
        "Tool input schema is not closed: $($definition.name)"
}
$savedTestMode = $env:HCR_TEST_MODE
Remove-Item Env:HCR_TEST_MODE
try {
    [void](Get-HcrAdapterMode)
    throw 'Mock adapter unexpectedly initialized outside test mode.'
}
catch {
    $failure = Get-HcrExceptionData $_.Exception
    Assert-Equal $failure.code 'MOCK_ADAPTER_FORBIDDEN' 'Mock adapter test-mode guard failed.'
}
$env:HCR_TEST_MODE = $savedTestMode

$profilePath = Join-Path $repoRoot 'examples\minimal-test-profile.json'
$validProfile = Invoke-TestTool 'validate_test_profile' ([pscustomobject]@{
    profilePath = $profilePath
})
Assert-True $validProfile.ok 'Canonical profile failed runtime validation.'
$invalidProfile = Invoke-TestTool 'validate_test_profile' ([pscustomobject]@{
    profilePath = Join-Path $PSScriptRoot 'fixtures\schemas\test-profile.traversal-path.invalid.json'
})
Assert-ErrorCode $invalidProfile 'PROFILE_INVALID' 'Unsafe profile was accepted.'
$commandProfilePath = Join-Path $testRoot 'command-profile.json'
$commandProfile = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$commandProfile.steps[1] | Add-Member `
    -NotePropertyName command `
    -NotePropertyValue 'whoami' `
    -Force
Write-TestJson $commandProfilePath $commandProfile
$commandProfileResult = Invoke-TestTool 'validate_test_profile' ([pscustomobject]@{
    profilePath = $commandProfilePath
})
Assert-ErrorCode $commandProfileResult 'PROFILE_INVALID' `
    'A caller-supplied command field was accepted.'

$vmPlan = Invoke-TestTool 'plan_vm_create' ([pscustomobject]@{
    name = 'cleanroom-test'
    isoPath = $isoPath
    vmRoot = $vmRoot
    switchName = 'Default Switch'
    diskSizeGb = 40
})
Assert-True $vmPlan.ok 'VM creation plan failed.'
Assert-True (@($vmPlan.warnings) -contains $script:HcrMockWarning) `
    'Mock VM plan lacks its mandatory test-only warning.'
Write-TestJson (Join-Path $schemaSampleRoot 'operation-envelope.json') $vmPlan
Write-TestJson (Join-Path $schemaSampleRoot 'vm-plan.json') $vmPlan.data.plan
$vmPlanId = [string]$vmPlan.data.plan.planId
$malformedApply = Invoke-TestTool 'apply_vm_create' ([pscustomobject]@{
    planId = $vmPlanId
    unexpected = $true
})
Assert-ErrorCode $malformedApply 'INVALID_ARGUMENT' 'Malformed apply did not fail input validation.'
$unconsumed = Get-HcrPlanRecord $vmPlanId
Assert-True (-not [bool]$unconsumed.consumed) 'Malformed input consumed a plan.'
$vmApply = Invoke-TestTool 'apply_vm_create' ([pscustomobject]@{ planId = $vmPlanId })
Assert-True $vmApply.ok 'VM creation apply failed against the mock adapter.'
Assert-True $vmApply.changed 'Successful VM creation did not report changed=true.'
$vmReplay = Invoke-TestTool 'apply_vm_create' ([pscustomobject]@{ planId = $vmPlanId })
Assert-ErrorCode $vmReplay 'PLAN_ALREADY_CONSUMED' 'VM plan replay was accepted.'

$mock = Read-HcrMockAdapterState
$ownershipId = [string]$vmApply.data.ownershipId
$mock.vms[0].notes = 'tampered-marker'
Write-HcrMockAdapterState $mock
$tamperedOwnership = Invoke-TestTool 'plan_checkpoint_create' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    checkpointName = 'blocked'
})
Assert-ErrorCode $tamperedOwnership 'OWNERSHIP_UNVERIFIED' 'Ownership tampering did not stop mutation.'
$mock = Read-HcrMockAdapterState
$mock.vms[0].notes = "hyperv-clean-room/v1:$ownershipId"
Write-HcrMockAdapterState $mock

$checkpointPlan = Invoke-TestTool 'plan_checkpoint_create' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    checkpointName = 'baseline'
})
Assert-True $checkpointPlan.ok 'Checkpoint plan failed.'
Write-TestJson `
    (Join-Path $schemaSampleRoot 'checkpoint-create-plan.json') `
    $checkpointPlan.data.plan
$checkpointApply = Invoke-TestTool 'apply_checkpoint_create' ([pscustomobject]@{
    planId = [string]$checkpointPlan.data.plan.planId
})
Assert-True $checkpointApply.ok 'Checkpoint apply failed.'

$restorePlan = Invoke-TestTool 'plan_checkpoint_restore' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    checkpointName = 'baseline'
})
Assert-True $restorePlan.ok 'Restore plan failed.'
Write-TestJson `
    (Join-Path $schemaSampleRoot 'checkpoint-restore-plan.json') `
    $restorePlan.data.plan
$restorePlanId = [string]$restorePlan.data.plan.planId
$restoreToken = [string]$restorePlan.data.plan.confirmationToken
Assert-True ($restoreToken.Length -ge 32) 'Restore token is too short.'
$persistedRestoreText = Get-Content `
    -LiteralPath (Get-HcrStateSubpath 'plans' "$restorePlanId.json") `
    -Raw `
    -Encoding UTF8
Assert-True ($persistedRestoreText -notmatch '"confirmationToken"\s*:') `
    'Restore-token plaintext field was persisted.'
Assert-True (-not $persistedRestoreText.Contains($restoreToken)) `
    'Restore-token plaintext bytes were persisted.'
Assert-True ($persistedRestoreText -match '"confirmationTokenHash"\s*:') `
    'Restore-token hash was not persisted.'
$wrongRestore = Invoke-TestTool 'apply_checkpoint_restore' ([pscustomobject]@{
    planId = $restorePlanId
    checkpointName = 'baseline'
    confirmationToken = ('x' * 32)
})
Assert-ErrorCode $wrongRestore 'CONFIRMATION_MISMATCH' 'Wrong restore token was accepted.'
$restoreReplay = Invoke-TestTool 'apply_checkpoint_restore' ([pscustomobject]@{
    planId = $restorePlanId
    checkpointName = 'baseline'
    confirmationToken = $restoreToken
})
Assert-ErrorCode $restoreReplay 'PLAN_ALREADY_CONSUMED' 'Wrong token did not consume the plan.'
$restorePlan2 = Invoke-TestTool 'plan_checkpoint_restore' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    checkpointName = 'baseline'
})
$restoreApply = Invoke-TestTool 'apply_checkpoint_restore' ([pscustomobject]@{
    planId = [string]$restorePlan2.data.plan.planId
    checkpointName = 'baseline'
    confirmationToken = [string]$restorePlan2.data.plan.confirmationToken
})
Assert-True $restoreApply.ok 'Correct restore plan failed.'

$capacityPlan = Invoke-TestTool 'plan_vm_create' ([pscustomobject]@{
    name = 'capacity-drift-vm'
    isoPath = $isoPath
    vmRoot = $vmRoot
    switchName = 'Default Switch'
    diskSizeGb = 40
})
$mock = Read-HcrMockAdapterState
$originalCapacity = [int64]$mock.host.targetVolumes[0].availableBytes
$mock.host.targetVolumes[0].availableBytes = 1
Write-HcrMockAdapterState $mock
$capacityApply = Invoke-TestTool 'apply_vm_create' ([pscustomobject]@{
    planId = [string]$capacityPlan.data.plan.planId
})
Assert-ErrorCode $capacityApply 'PLAN_DRIFT' 'Capacity drift was not rejected.'
$capacityReplay = Invoke-TestTool 'apply_vm_create' ([pscustomobject]@{
    planId = [string]$capacityPlan.data.plan.planId
})
Assert-ErrorCode $capacityReplay 'PLAN_ALREADY_CONSUMED' 'Drift did not consume the VM plan.'
$mock = Read-HcrMockAdapterState
$mock.host.targetVolumes[0].availableBytes = $originalCapacity
Write-HcrMockAdapterState $mock

$expiredPlan = Invoke-TestTool 'plan_vm_create' ([pscustomobject]@{
    name = 'expired-vm'
    isoPath = $isoPath
    vmRoot = $vmRoot
    switchName = 'Default Switch'
    diskSizeGb = 40
})
$expiredId = [string]$expiredPlan.data.plan.planId
$expiredRecord = Get-HcrPlanRecord $expiredId
$expiredRecord.plan.expiresAt = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
Save-HcrPlanRecord $expiredRecord
$expiredApply = Invoke-TestTool 'apply_vm_create' ([pscustomobject]@{ planId = $expiredId })
Assert-ErrorCode $expiredApply 'PLAN_EXPIRED' 'Expired plan was accepted.'
$expiredReplay = Invoke-TestTool 'apply_vm_create' ([pscustomobject]@{ planId = $expiredId })
Assert-ErrorCode $expiredReplay 'PLAN_ALREADY_CONSUMED' 'Expired plan was not consumed.'

$racePlan = Invoke-TestTool 'plan_vm_create' ([pscustomobject]@{
    name = 'race-vm'
    isoPath = $isoPath
    vmRoot = $vmRoot
    switchName = 'Default Switch'
    diskSizeGb = 40
})
$raceArgumentsPath = Join-Path $testRoot 'race-arguments.json'
Write-TestJson $raceArgumentsPath ([ordered]@{ planId = [string]$racePlan.data.plan.planId })
$helperPath = Join-Path $PSScriptRoot 'helpers\invoke-runtime-tool.ps1'
$helperArguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass ' +
    '-File "{0}" -PluginRoot "{1}" -ToolName apply_vm_create -ArgumentsPath "{2}"' -f
    $helperPath, $pluginRoot, $raceArgumentsPath
$raceA = Start-TestProcess 'powershell.exe' $helperArguments $repoRoot
$raceB = Start-TestProcess 'powershell.exe' $helperArguments $repoRoot
$raceA.StandardInput.Close()
$raceB.StandardInput.Close()
Assert-True ($raceA.WaitForExit(20000)) 'First concurrent apply did not exit.'
Assert-True ($raceB.WaitForExit(20000)) 'Second concurrent apply did not exit.'
$raceOutputA = $raceA.StandardOutput.ReadToEnd()
$raceOutputB = $raceB.StandardOutput.ReadToEnd()
$raceErrorA = $raceA.StandardError.ReadToEnd()
$raceErrorB = $raceB.StandardError.ReadToEnd()
Assert-Equal $raceA.ExitCode 0 'First concurrent apply process failed.'
Assert-Equal $raceB.ExitCode 0 'Second concurrent apply process failed.'
Assert-True ([string]::IsNullOrWhiteSpace($raceErrorA)) 'First concurrent apply wrote stderr.'
Assert-True ([string]::IsNullOrWhiteSpace($raceErrorB)) 'Second concurrent apply wrote stderr.'
$raceResults = @($raceOutputA, $raceOutputB | ForEach-Object {
    $_.Trim() | ConvertFrom-Json -ErrorAction Stop
})
Assert-Equal (@($raceResults | Where-Object { $_.ok }).Count) 1 `
    'Atomic apply allowed other than exactly one winner.'
Assert-Equal (@($raceResults | Where-Object {
    -not $_.ok -and $_.error.code -eq 'PLAN_ALREADY_CONSUMED'
}).Count) 1 'Atomic apply did not produce one consumed-plan loser.'

$managedList = Invoke-TestTool 'list_vms' ([pscustomobject]@{})
Assert-True $managedList.ok 'Managed VM listing failed.'
Assert-True (@($managedList.data.vms).Count -ge 2) 'Managed VM listing omitted created VMs.'
$inspectVm = Invoke-TestTool 'inspect_vm' ([pscustomobject]@{ vmName = 'cleanroom-test' })
Assert-True $inspectVm.data.ownership.verified 'Managed VM inspection lost ownership verification.'
$inspectGuest = Invoke-TestTool 'inspect_guest' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    credentialProfile = 'test-profile'
})
Assert-True $inspectGuest.ok 'Guest inspection failed against mock adapter.'
Assert-True (-not $inspectGuest.data.guest.isAdministrator) 'Mock guest is not a standard user.'
$plaintextCredentialInput = Invoke-TestTool 'inspect_guest' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    credentialProfile = 'test-profile'
    password = 'must-not-be-accepted'
})
Assert-ErrorCode $plaintextCredentialInput 'INVALID_ARGUMENT' `
    'A plaintext credential field entered the MCP surface.'

$standaloneArtifact = Join-Path $testRoot 'standalone.bin'
[IO.File]::WriteAllBytes($standaloneArtifact, [byte[]](2..65))
$stageOk = Invoke-TestTool 'stage_artifact' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    credentialProfile = 'test-profile'
    sourcePath = $standaloneArtifact
    guestDestination = 'manual\standalone.bin'
})
Assert-True $stageOk.ok 'Standalone artifact staging failed.'
$mock = Read-HcrMockAdapterState
$mock | Add-Member -NotePropertyName stageHashMismatch -NotePropertyValue $true -Force
Write-HcrMockAdapterState $mock
$stageMismatch = Invoke-TestTool 'stage_artifact' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    credentialProfile = 'test-profile'
    sourcePath = $standaloneArtifact
    guestDestination = 'manual\mismatch.bin'
})
Assert-ErrorCode $stageMismatch 'ARTIFACT_HASH_MISMATCH' 'Staging hash mismatch was accepted.'
$mock = Read-HcrMockAdapterState
$mock.stageHashMismatch = $false
Write-HcrMockAdapterState $mock

$happyArtifact = Join-Path $testRoot 'SampleApp-1.0-x64.exe'
[IO.File]::WriteAllBytes($happyArtifact, [byte[]](3..66))
$happyRun = Invoke-TestTool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    credentialProfile = 'test-profile'
    profilePath = $profilePath
    artifactPath = $happyArtifact
})
Assert-True $happyRun.ok 'Happy-path profile execution failed.'
Assert-Equal $happyRun.data.overallStatus 'passed' 'Happy-path overall status is wrong.'
Assert-True (-not $happyRun.data.cleanupTriggered) 'Happy path triggered cleanup.'
Assert-Equal (@($happyRun.data.cleanupResults | Where-Object {
    $_.status -eq 'notPerformed'
}).Count) 2 'Untriggered cleanup results were not all notPerformed.'
$happyOperation = Get-HcrOperationRecord $happyRun.data.testOperationId
$happyEvidence = Read-HcrJsonFile $happyOperation.evidenceFile 'EVIDENCE_NOT_READY'
Assert-True (@($happyEvidence.warnings) -contains $script:HcrMockWarning) `
    'Mock evidence lacks its mandatory test-only warning.'
$happyValidation = Invoke-TestTool 'validate_evidence' ([pscustomobject]@{
    evidencePath = [string]$happyOperation.evidenceFile
})
Assert-True $happyValidation.ok 'Generated happy-path evidence failed validation.'
$manualAttestation = Invoke-TestTool 'record_manual_attestation' ([pscustomobject]@{
    operationId = [string]$happyRun.data.testOperationId
    assertionId = 'first-launch-visible'
    status = 'unsupported'
    method = 'declaredUnsupported'
    summary = 'Interactive validation is unavailable in the mock test harness.'
})
Assert-True $manualAttestation.ok 'Manual unsupported attestation failed.'
$duplicateAttestation = Invoke-TestTool 'record_manual_attestation' ([pscustomobject]@{
    operationId = [string]$happyRun.data.testOperationId
    assertionId = 'first-launch-visible'
    status = 'unsupported'
    method = 'declaredUnsupported'
    summary = 'Duplicate observation.'
})
Assert-ErrorCode $duplicateAttestation 'MANUAL_ASSERTION_ALREADY_RECORDED' `
    'Manual assertion was recorded twice.'
$postManualEvidence = Read-HcrJsonFile $happyOperation.evidenceFile 'EVIDENCE_NOT_READY'
Assert-Equal $postManualEvidence.overallStatus 'passed' `
    'Optional unsupported manual assertion changed overallStatus.'
Write-TestJson (Join-Path $schemaSampleRoot 'evidence.json') $postManualEvidence
$collected = Invoke-TestTool 'collect_evidence' ([pscustomobject]@{
    operationId = [string]$happyRun.data.testOperationId
    outputDirectory = $exportRoot
})
Assert-True $collected.ok 'Evidence export failed.'
Assert-True (Test-Path -LiteralPath $collected.evidencePath -PathType Leaf) `
    'Exported evidence file is missing.'
Assert-True (Test-Path -LiteralPath $collected.data.inventoryPath -PathType Leaf) `
    'Evidence inventory is missing.'
$forbiddenExport = Invoke-TestTool 'collect_evidence' ([pscustomobject]@{
    operationId = [string]$happyRun.data.testOperationId
    outputDirectory = $pluginRoot
})
Assert-ErrorCode $forbiddenExport 'EVIDENCE_OUTPUT_FORBIDDEN' `
    'Plugin-root evidence export was accepted.'

$tamperedEvidencePath = Join-Path $testRoot 'tampered-evidence.json'
$tamperedEvidence = Copy-HcrObject $postManualEvidence
$tamperedEvidence.cleanupResults[0].status = 'passed'
$tamperedEvidence.cleanupResults[0].summary = 'forged performed cleanup'
$tamperedEvidence.cleanupResults[0].evidence = [pscustomobject]@{ forged = $true }
Write-TestJson $tamperedEvidencePath $tamperedEvidence
$tamperedEvidenceResult = Invoke-TestTool 'validate_evidence' ([pscustomobject]@{
    evidencePath = $tamperedEvidencePath
})
Assert-ErrorCode $tamperedEvidenceResult 'EVIDENCE_INVALID' `
    'Performed-while-untriggered cleanup evidence was accepted.'
$forgedAutomaticPath = Join-Path $testRoot 'forged-automatic-evidence.json'
$forgedAutomatic = Copy-HcrObject $postManualEvidence
$forgedAutomatic.automaticAssertions[0].id = 'forged-stage-result'
Write-TestJson $forgedAutomaticPath $forgedAutomatic
$forgedAutomaticResult = Invoke-TestTool 'validate_evidence' ([pscustomobject]@{
    evidencePath = $forgedAutomaticPath
})
Assert-ErrorCode $forgedAutomaticResult 'EVIDENCE_INVALID' `
    'Automatic assertion identity forgery was accepted.'
$missingMockWarningPath = Join-Path $testRoot 'missing-mock-warning-evidence.json'
$missingMockWarning = Copy-HcrObject $postManualEvidence
$missingMockWarning.warnings = @()
Write-TestJson $missingMockWarningPath $missingMockWarning
$missingMockWarningResult = Invoke-TestTool 'validate_evidence' ([pscustomobject]@{
    evidencePath = $missingMockWarningPath
})
Assert-ErrorCode $missingMockWarningResult 'EVIDENCE_INVALID' `
    'Mock evidence without its test-only warning was accepted.'

$mock = Read-HcrMockAdapterState
$mock.stepResults | Add-Member `
    -NotePropertyName 'assert-running-process' `
    -NotePropertyValue ([pscustomobject][ordered]@{
        status = 'failed'
        summary = 'Configured required assertion failure.'
        evidence = [pscustomobject]@{ configured = $true }
    }) `
    -Force
$mock.cleanupResults | Add-Member `
    -NotePropertyName 'cleanup-stop-application' `
    -NotePropertyValue ([pscustomobject][ordered]@{
        status = 'passed'
        summary = 'Configured identity drift.'
        evidence = [pscustomobject]@{}
        processIdentityMatches = $false
    }) `
    -Force
Write-HcrMockAdapterState $mock
$failureArtifact = Join-Path $testRoot 'SampleApp-2.0-x64.exe'
[IO.File]::WriteAllBytes($failureArtifact, [byte[]](4..67))
$failureRun = Invoke-TestTool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    credentialProfile = 'test-profile'
    profilePath = $profilePath
    artifactPath = $failureArtifact
})
Assert-True $failureRun.ok 'Failure-path profile did not return auditable evidence.'
Assert-Equal $failureRun.data.overallStatus 'failed' 'Required failure did not fail overallStatus.'
Assert-True $failureRun.data.cleanupTriggered 'Required execution failure did not trigger cleanup.'
Assert-Equal (@($failureRun.data.cleanupResults).Count) 2 'Cleanup result count changed.'
Assert-Equal $failureRun.data.cleanupResults[0].status 'failed' `
    'Changed process identity was not rejected by cleanup.'
Assert-True (-not $failureRun.data.cleanupResults[0].evidence.processIdentityRevalidated) `
    'Failed cleanup falsely reported process identity validation.'
Assert-Equal $failureRun.data.cleanupResults[1].status 'passed' `
    'A cleanup failure prevented the next cleanup step.'
$failureOperation = Get-HcrOperationRecord $failureRun.data.testOperationId
$failureEvidenceValidation = Invoke-TestTool 'validate_evidence' ([pscustomobject]@{
    evidencePath = [string]$failureOperation.evidenceFile
})
Assert-True $failureEvidenceValidation.ok 'Failure-path evidence failed validation.'
$absoluteReferenceAttestation = Invoke-TestTool 'record_manual_attestation' ([pscustomobject]@{
    operationId = [string]$failureRun.data.testOperationId
    assertionId = 'first-launch-visible'
    status = 'failed'
    method = 'visualInspection'
    summary = 'Invalid absolute reference probe.'
    evidenceReferences = @([pscustomobject]@{
        path = [string]$failureOperation.evidenceFile
        sha256 = Get-HcrSha256File ([string]$failureOperation.evidenceFile)
    })
})
Assert-ErrorCode $absoluteReferenceAttestation 'EVIDENCE_REFERENCE_INVALID' `
    'Absolute manual evidence reference was accepted.'

$initializerPath = Join-Path $pluginRoot 'mcp\Initialize-GuestCredential.ps1'
$tokens = $null
$parseErrors = $null
$initializerAst = [Management.Automation.Language.Parser]::ParseFile(
    $initializerPath,
    [ref]$tokens,
    [ref]$parseErrors
)
Assert-Equal (@($parseErrors).Count) 0 'Credential initializer has parse errors.'
$parameterNames = @($initializerAst.ParamBlock.Parameters | ForEach-Object {
    $_.Name.VariablePath.UserPath
})
Assert-Equal (@(Compare-Object @('ProfileName', 'VmName') $parameterNames).Count) 0 `
    'Credential initializer accepts parameters outside ProfileName and VmName.'
$commands = @($initializerAst.FindAll({
    param($node)
    $node -is [Management.Automation.Language.CommandAst]
}, $true) | ForEach-Object { $_.GetCommandName() })
Assert-Equal (@($commands | Where-Object { $_ -eq 'Get-Credential' }).Count) 2 `
    'Credential initializer must prompt separately for both roles.'
Assert-Equal (@($commands | Where-Object { $_ -eq 'Export-Clixml' }).Count) 2 `
    'Credential initializer must persist two DPAPI credential objects.'
$productionPython = @(Get-ChildItem -LiteralPath $pluginRoot -Recurse -Filter '*.py' -File)
Assert-Equal $productionPython.Count 0 'Production plugin gained a Python dependency.'
$adapterSource = Get-Content `
    -LiteralPath (Join-Path $pluginRoot 'mcp\lib\Adapters.ps1') `
    -Raw `
    -Encoding UTF8
Assert-True ($adapterSource -match 'MOCK_ADAPTER_FORBIDDEN') `
    'Mock adapter no longer has a production guard.'
Assert-True ($adapterSource -match 'GUEST_ADAPTER_UNVALIDATED') `
    'Unvalidated real guest execution no longer fails closed.'

$protocolRoot = Join-Path $testRoot 'protocol'
[void](New-Item -ItemType Directory -Path $protocolRoot -Force)
$serverPath = Join-Path $pluginRoot 'mcp\server.ps1'
$serverInfo = New-Object Diagnostics.ProcessStartInfo
$serverInfo.FileName = 'powershell.exe'
$serverInfo.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass ' +
    '-File "{0}"' -f $serverPath
$serverInfo.WorkingDirectory = $pluginRoot
$serverInfo.UseShellExecute = $false
$serverInfo.RedirectStandardInput = $true
$serverInfo.RedirectStandardOutput = $true
$serverInfo.RedirectStandardError = $true
$serverInfo.CreateNoWindow = $true
$serverInfo.EnvironmentVariables['HCR_TEST_MODE'] = '1'
$serverInfo.EnvironmentVariables['HCR_ADAPTER_MODE'] = 'mock'
$serverInfo.EnvironmentVariables['HCR_MOCK_ADAPTER_PATH'] = $mockPath
$serverInfo.EnvironmentVariables['HCR_STATE_ROOT'] = Join-Path $protocolRoot 'state'
$serverInfo.EnvironmentVariables['HCR_CREDENTIAL_ROOT'] = Join-Path $protocolRoot 'credentials'
$server = New-Object Diagnostics.Process
$server.StartInfo = $serverInfo
[void]$server.Start()
$server.StandardInput.WriteLine('{not-json')
$parseResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-Equal $parseResponse.error.code -32700 'Malformed JSON did not return parse error.'
$server.StandardInput.WriteLine('[{"jsonrpc":"2.0","id":99,"method":"ping"}]')
$batchResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-Equal $batchResponse.error.code -32600 'A single-entry JSON-RPC batch was accepted.'
$server.StandardInput.WriteLine('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-01-01","capabilities":{},"clientInfo":{"name":"gate2","version":"1"}}}')
$oldProtocol = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-Equal $oldProtocol.error.code -32602 'Too-old MCP version was accepted.'
$server.StandardInput.WriteLine('{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"2026-01-01","capabilities":{},"clientInfo":{"name":"gate2","version":"1"}}}')
$initializeResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-Equal $initializeResponse.result.protocolVersion '2025-11-25' `
    'Protocol negotiation announced an unsupported or newer version.'
$server.StandardInput.WriteLine('{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{}}')
$prematureList = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-Equal $prematureList.error.code -32002 'tools/list ran before initialized notification.'
$server.StandardInput.WriteLine('{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}')
$server.StandardInput.WriteLine('{"jsonrpc":"2.0","id":4,"method":"tools/list","params":{}}')
$toolListResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-Equal (@($toolListResponse.result.tools).Count) 16 'MCP tools/list count changed.'
$server.StandardInput.WriteLine('{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"inspect_host","arguments":{}}}')
$inspectResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-True (-not $inspectResponse.result.isError) 'MCP inspect_host returned isError.'
$inspectEnvelope = $inspectResponse.result.content[0].text | ConvertFrom-Json
Assert-True $inspectEnvelope.ok 'MCP inspect_host envelope failed.'
Assert-Equal $inspectEnvelope.data.host.computerName 'MOCK-HOST' 'MCP returned wrong mock host.'
$server.StandardInput.WriteLine('{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"delete_vm","arguments":{}}}')
$unknownToolResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-True $unknownToolResponse.result.isError 'Unknown tool did not set MCP isError.'
$unknownToolEnvelope = $unknownToolResponse.result.content[0].text | ConvertFrom-Json
Assert-Equal $unknownToolEnvelope.error.code 'METHOD_NOT_FOUND' 'Unknown tool error code changed.'
$server.StandardInput.WriteLine('{"jsonrpc":"2.0","id":7,"method":"unknown/method","params":{}}')
$unknownMethodResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-Equal $unknownMethodResponse.error.code -32601 'Unknown JSON-RPC method was accepted.'
$server.StandardInput.Close()
Assert-True ($server.WaitForExit(15000)) 'MCP server did not exit after stdin closed.'
$serverStderr = $server.StandardError.ReadToEnd()
Assert-Equal $server.ExitCode 0 'MCP server exited unsuccessfully.'
Assert-True ([string]::IsNullOrWhiteSpace($serverStderr)) `
    'Successful MCP session wrote diagnostics to stderr.'

[ordered]@{
    ok = $true
    gate = 2
    assertions = $script:AssertionCount
    tools = $definitions.Count
    protocolVersions = $script:HcrSupportedProtocolVersions.Count
    mockVmMutations = @((Read-HcrMockAdapterState).vms).Count
    realHyperVMutations = 0
    happyOverallStatus = $happyRun.data.overallStatus
    failureOverallStatus = $failureRun.data.overallStatus
    cleanupResults = @($failureRun.data.cleanupResults).Count
    concurrentApplyWinners = @($raceResults | Where-Object { $_.ok }).Count
} | ConvertTo-Json -Depth 5 -Compress

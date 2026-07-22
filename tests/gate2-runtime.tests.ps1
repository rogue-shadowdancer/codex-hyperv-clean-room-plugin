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

function Assert-ThrowsHcrCode {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:AssertionCount++
    try {
        & $Action
    }
    catch {
        $actual = if ($_.Exception.Data.Contains('HcrCode')) {
            [string]$_.Exception.Data['HcrCode']
        }
        else { 'NONE' }
        if ($actual -ne $Code) {
            throw "$Message Expected '$Code', received '$actual'."
        }
        return
    }
    throw "$Message The action unexpectedly succeeded."
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

function Assert-PartialMutationFailure {
    param(
        [Parameter(Mandatory = $true)][object]$Envelope,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)]
        [ValidateSet('confirmed', 'indeterminate')]
        [string]$EffectState,
        [Parameter(Mandatory = $true)][string]$ResourceType
    )

    Assert-ErrorCode $Envelope $Code 'A partial mutation returned the wrong error.'
    Assert-True ([bool]$Envelope.changed) 'A partial or indeterminate mutation did not report changed=true.'
    Assert-True ([bool]$Envelope.error.details.mutationEntered) `
        'A partial mutation did not report mutationEntered=true.'
    Assert-Equal ([string]$Envelope.error.details.effectState) $EffectState `
        'A partial mutation returned the wrong effect state.'
    Assert-True (Test-HcrObjectLike $Envelope.error.details.partialIdentity) `
        'A partial mutation omitted its bounded identity.'
    Assert-Equal ([string]$Envelope.error.details.partialIdentity.resourceType) $ResourceType `
        'A partial mutation returned the wrong resource identity type.'
    $recoveryWarning = [string]$Envelope.error.details.recoveryWarning
    Assert-True (-not [string]::IsNullOrWhiteSpace($recoveryWarning)) `
        'A partial mutation omitted its recovery warning.'
    Assert-True (@($Envelope.warnings) -contains $recoveryWarning) `
        'The partial-mutation recovery warning was not projected to the envelope.'
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

function Set-TestMutationFault {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)]
        [ValidateSet('before', 'entered', 'after')]
        [string]$Phase
    )

    $state = Read-HcrMockAdapterState
    $state | Add-Member -NotePropertyName mutationFault -NotePropertyValue ([pscustomobject][ordered]@{
        operation = $Operation
        phase = $Phase
    }) -Force
    Write-HcrMockAdapterState $state
}

function Clear-TestMutationFault {
    $state = Read-HcrMockAdapterState
    if (Test-HcrProperty $state 'mutationFault') {
        $state.PSObject.Properties.Remove('mutationFault')
        Write-HcrMockAdapterState $state
    }
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
        'Validation.V2.ps1',
        'Adapters.ps1',
        'Tools.Host.ps1',
        'Tools.Host.V2.ps1',
        'Tools.Guest.ps1',
        'Tools.Guest.V2.ps1',
        'Runtime.ps1'
    )) {
    . (Join-Path (Join-Path (Join-Path $pluginRoot 'mcp') 'lib') $runtimeFile)
}
Initialize-HcrRuntime $pluginRoot

$junctionTarget = Join-Path $testRoot 'junction-target'
$junctionPath = Join-Path $testRoot 'junction-link'
[void](New-Item -ItemType Directory -Path $junctionTarget -Force)
$junctionPayload = Join-Path $junctionTarget 'payload.json'
[IO.File]::WriteAllText(
    $junctionPayload,
    '{}',
    (New-Object System.Text.UTF8Encoding($false))
)
$junction = New-Item `
    -ItemType Junction `
    -Path $junctionPath `
    -Target $junctionTarget `
    -ErrorAction Stop
Assert-True (($junction.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) `
    'The NTFS junction fixture was not created as a reparse point.'
Assert-ThrowsHcrCode {
    [void](Assert-HcrRegularLocalFile `
        (Join-Path $junctionPath 'payload.json') `
        'REPARSE_PATH_REJECTED')
} 'REPARSE_PATH_REJECTED' `
    'A regular file reached through an NTFS junction was accepted.'

$aclCommonRoot = Join-Path $testRoot 'acl-common-root'
[void](New-Item -ItemType Directory -Path $aclCommonRoot -Force)
$aclParent = Get-Acl -LiteralPath $aclCommonRoot
$usersSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545')
$inheritedWrite = New-Object Security.AccessControl.FileSystemAccessRule(
    $usersSid,
    [Security.AccessControl.FileSystemRights]::Write,
    [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
    [Security.AccessControl.PropagationFlags]::None,
    [Security.AccessControl.AccessControlType]::Allow
)
[void]$aclParent.AddAccessRule($inheritedWrite)
Set-Acl -LiteralPath $aclCommonRoot -AclObject $aclParent
$aclProbe = Join-Path $aclCommonRoot 'inherited-probe'
[void](New-Item -ItemType Directory -Path $aclProbe)
$probeRules = @(Get-Acl -LiteralPath $aclProbe).GetAccessRules(
    $true,
    $true,
    [Security.Principal.SecurityIdentifier]
)
Assert-True (@($probeRules | Where-Object {
    $_.IdentityReference.Value -eq $usersSid.Value -and $_.IsInherited
}).Count -gt 0) 'The inherited BUILTIN\Users Write ACL regression fixture is ineffective.'
$workspaceTestSid = 'S-1-5-21-111111111-222222222-333333333-1001'
$aclWorkspace = & $script:HcrInitializeGuestWorkspaceScript `
    ([Guid]::NewGuid().ToString()) `
    $workspaceTestSid `
    $aclCommonRoot
$workspaceAdministratorSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$privilegedWorkspaceSids = @(
    $workspaceAdministratorSid,
    'S-1-5-18',
    'S-1-5-32-544'
)
$writeCapableMask = [Security.AccessControl.FileSystemRights]::WriteData -bor
    [Security.AccessControl.FileSystemRights]::AppendData -bor
    [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
    [Security.AccessControl.FileSystemRights]::WriteAttributes -bor
    [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
    [Security.AccessControl.FileSystemRights]::Delete -bor
    [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
    [Security.AccessControl.FileSystemRights]::TakeOwnership
$expectedWorkspaceInheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
    [Security.AccessControl.InheritanceFlags]::ObjectInherit
$expectedTestWorkspaceRights = [Security.AccessControl.FileSystemRights]::ReadAndExecute -bor
    [Security.AccessControl.FileSystemRights]::Synchronize
foreach ($workspacePath in @(
    $aclWorkspace.operationRoot,
    $aclWorkspace.controlRoot,
    $aclWorkspace.outputRoot,
    $aclWorkspace.stagingRoot
)) {
    $workspaceAcl = Get-Acl -LiteralPath $workspacePath
    Assert-True $workspaceAcl.AreAccessRulesProtected `
        'A supervised guest workspace path still inherits its parent ACL.'
    Assert-Equal `
        ([string]$workspaceAcl.GetOwner([Security.Principal.SecurityIdentifier]).Value) `
        $workspaceAdministratorSid `
        'A supervised guest workspace path did not transfer ownership to the live administrator.'
    $workspaceRules = @($workspaceAcl.GetAccessRules(
        $true,
        $true,
        [Security.Principal.SecurityIdentifier]
    ))
    Assert-Equal $workspaceRules.Count 4 `
        'An operation workspace ACL does not contain exactly four explicit grants.'
    Assert-Equal (@($workspaceRules | Where-Object {
        $_.IdentityReference.Value -eq $usersSid.Value
    }).Count) 0 'Inherited BUILTIN\Users access survived protected workspace ACL installation.'
    $testRules = @($workspaceRules | Where-Object {
        $_.IdentityReference.Value -eq $workspaceTestSid
    })
    Assert-Equal $testRules.Count 1 'The explicit standard-user read/execute ACL is missing or duplicated.'
    Assert-Equal ([int]$testRules[0].FileSystemRights) ([int]$expectedTestWorkspaceRights) `
        'The explicit standard-user workspace ACL is not the exact read/execute grant.'
    Assert-Equal ([int]$testRules[0].InheritanceFlags) ([int]$expectedWorkspaceInheritance) `
        'The explicit standard-user workspace ACL has non-canonical inheritance flags.'
    Assert-Equal ([int]$testRules[0].PropagationFlags) 0 `
        'The explicit standard-user workspace ACL has non-canonical propagation flags.'
    Assert-Equal ([int]($testRules[0].FileSystemRights -band $writeCapableMask)) 0 `
        'The explicit standard-user workspace ACL retains a write-capable right.'
    Assert-Equal `
        ([int]($testRules[0].FileSystemRights -band
            [Security.AccessControl.FileSystemRights]::ReadAndExecute)) `
        ([int][Security.AccessControl.FileSystemRights]::ReadAndExecute) `
        'The explicit standard-user workspace ACL lacks read/execute.'
    foreach ($privilegedSid in $privilegedWorkspaceSids) {
        $privilegedRules = @($workspaceRules | Where-Object {
            $_.IdentityReference.Value -eq $privilegedSid
        })
        Assert-Equal $privilegedRules.Count 1 `
            'A privileged workspace full-control ACL is missing or duplicated.'
        Assert-Equal ([int]$privilegedRules[0].FileSystemRights) `
            ([int][Security.AccessControl.FileSystemRights]::FullControl) `
            'A privileged workspace principal lacks full control.'
        Assert-Equal ([int]$privilegedRules[0].InheritanceFlags) `
            ([int]$expectedWorkspaceInheritance) `
            'A privileged workspace ACL has non-canonical inheritance flags.'
        Assert-Equal ([int]$privilegedRules[0].PropagationFlags) 0 `
            'A privileged workspace ACL has non-canonical propagation flags.'
    }
}
foreach ($workspaceAncestor in @(
    (Join-Path $aclCommonRoot 'Codex'),
    (Join-Path $aclCommonRoot 'Codex\hyperv-clean-room'),
    (Join-Path $aclCommonRoot 'Codex\hyperv-clean-room\v1'),
    (Join-Path $aclCommonRoot 'Codex\hyperv-clean-room\v1\operations')
)) {
    $ancestorAcl = Get-Acl -LiteralPath $workspaceAncestor
    Assert-True $ancestorAcl.AreAccessRulesProtected `
        'A plugin-owned workspace ancestor still inherits a writable parent ACL.'
    Assert-Equal `
        ([string]$ancestorAcl.GetOwner([Security.Principal.SecurityIdentifier]).Value) `
        $workspaceAdministratorSid `
        'A plugin-owned workspace ancestor did not transfer ownership to the live administrator.'
    $ancestorRules = @($ancestorAcl.GetAccessRules(
        $true,
        $true,
        [Security.Principal.SecurityIdentifier]
    ))
    Assert-Equal $ancestorRules.Count 3 `
        'A plugin-owned workspace ancestor does not contain exactly three explicit grants.'
    Assert-Equal (@($ancestorRules | Where-Object {
        $_.IdentityReference.Value -eq $usersSid.Value -or
        $_.IdentityReference.Value -eq $workspaceTestSid
    }).Count) 0 'A plugin-owned workspace ancestor retained standard-user authority.'
}

$expectedTools = @(
    'inspect_host', 'list_vms', 'inspect_vm', 'validate_test_profile',
    'validate_evidence', 'plan_vm_create', 'apply_vm_create',
    'plan_checkpoint_create', 'apply_checkpoint_create',
    'plan_checkpoint_restore', 'apply_checkpoint_restore', 'inspect_guest',
    'stage_artifact', 'run_test_profile', 'collect_evidence',
    'record_manual_attestation', 'plan_vm_power', 'apply_vm_power',
    'plan_vm_network', 'apply_vm_network'
)
$definitions = @(Get-HcrToolDefinitions)
Assert-Equal $definitions.Count 20 'Runtime tool count changed.'
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

$mock = Read-HcrMockAdapterState
$stableVolumeId = [string]$mock.host.targetVolumes[0].uniqueId
$mock.host.targetVolumes[0].uniqueId = ''
Write-HcrMockAdapterState $mock
$missingVolumeIdentity = Invoke-TestTool 'plan_vm_create' ([pscustomobject]@{
    name = 'missing-volume-identity-vm'
    isoPath = $isoPath
    vmRoot = $vmRoot
    switchName = 'Default Switch'
    diskSizeGb = 40
})
Assert-ErrorCode $missingVolumeIdentity 'TARGET_VOLUME_IDENTITY_UNAVAILABLE' `
    'VM planning accepted a target volume without a stable UniqueId.'
$mock = Read-HcrMockAdapterState
$mock.host.targetVolumes[0].uniqueId = $stableVolumeId
Write-HcrMockAdapterState $mock

$junctionSwapRoot = Join-Path $testRoot 'vm-root-swap'
$junctionSwapOriginal = Join-Path $testRoot 'vm-root-swap-original'
$junctionSwapTarget = Join-Path $testRoot 'vm-root-swap-target'
[void](New-Item -ItemType Directory -Path $junctionSwapRoot -Force)
[void](New-Item -ItemType Directory -Path $junctionSwapTarget -Force)
$junctionSwapPlan = Invoke-TestTool 'plan_vm_create' ([pscustomobject]@{
    name = 'junction-swap-vm'
    isoPath = $isoPath
    vmRoot = $junctionSwapRoot
    switchName = 'Default Switch'
    diskSizeGb = 40
})
Assert-True $junctionSwapPlan.ok 'The junction-swap VM plan could not be prepared.'
Rename-Item `
    -LiteralPath $junctionSwapRoot `
    -NewName ([IO.Path]::GetFileName($junctionSwapOriginal)) `
    -ErrorAction Stop
$swappedRoot = New-Item `
    -ItemType Junction `
    -Path $junctionSwapRoot `
    -Target $junctionSwapTarget `
    -ErrorAction Stop
Assert-True (($swappedRoot.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) `
    'The apply-time VM-root swap did not create a junction.'
$junctionSwapApply = Invoke-TestTool 'apply_vm_create' ([pscustomobject]@{
    planId = [string]$junctionSwapPlan.data.plan.planId
})
Assert-ErrorCode $junctionSwapApply 'PLAN_DRIFT' `
    'A planned normal VM root replaced by a junction reached mutation.'
Assert-True (-not [bool]$junctionSwapApply.changed) `
    'A pre-mutation VM-root reparse swap reported changed=true.'

$volumeReplacementPlan = Invoke-TestTool 'plan_vm_create' ([pscustomobject]@{
    name = 'volume-replacement-vm'
    isoPath = $isoPath
    vmRoot = $vmRoot
    switchName = 'Default Switch'
    diskSizeGb = 40
})
$mock = Read-HcrMockAdapterState
$plannedVolumeRoot = [string]$mock.host.targetVolumes[0].root
$mock.host.targetVolumes[0].uniqueId = 'mock-volume-replaced-at-same-root'
Write-HcrMockAdapterState $mock
$volumeReplacementApply = Invoke-TestTool 'apply_vm_create' ([pscustomobject]@{
    planId = [string]$volumeReplacementPlan.data.plan.planId
})
Assert-ErrorCode $volumeReplacementApply 'PLAN_DRIFT' `
    'A same-root target-volume replacement was accepted.'
Assert-True (-not [bool]$volumeReplacementApply.changed) `
    'Pre-mutation target-volume identity drift reported changed=true.'
$mock = Read-HcrMockAdapterState
Assert-Equal ([string]$mock.host.targetVolumes[0].root) $plannedVolumeRoot `
    'The same-root volume replacement fixture changed the drive root.'
$mock.host.targetVolumes[0].uniqueId = $stableVolumeId
Write-HcrMockAdapterState $mock

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

foreach ($faultPhase in @('before', 'entered', 'after')) {
    $faultVmName = "fault-vm-$faultPhase"
    $faultVmPlan = Invoke-TestTool 'plan_vm_create' ([pscustomobject]@{
        name = $faultVmName
        isoPath = $isoPath
        vmRoot = $vmRoot
        switchName = 'Default Switch'
        diskSizeGb = 40
    })
    Set-TestMutationFault 'CreateVm' $faultPhase
    $faultVmApply = Invoke-TestTool 'apply_vm_create' ([pscustomobject]@{
        planId = [string]$faultVmPlan.data.plan.planId
    })
    if ($faultPhase -eq 'before') {
        Assert-ErrorCode $faultVmApply 'VM_CREATE_FAILED' `
            'The pre-entry VM-create fault returned the wrong error.'
        Assert-True (-not [bool]$faultVmApply.changed) `
            'A pre-entry VM-create fault reported changed=true.'
    }
    else {
        $expectedEffectState = if ($faultPhase -eq 'entered') { 'indeterminate' } else { 'confirmed' }
        Assert-PartialMutationFailure `
            $faultVmApply `
            'VM_CREATE_FAILED' `
            $expectedEffectState `
            'vm'
        Assert-Equal ([string]$faultVmApply.error.details.partialIdentity.vmName) $faultVmName `
            'VM partial identity was not bound to the requested name.'
        Assert-Equal `
            ([string]$faultVmApply.error.details.partialIdentity.vmPath) `
            ([string]$faultVmPlan.data.plan.vmPath) `
            'VM partial identity was not bound to the recomputed VM path.'
        Assert-Equal `
            ([string]$faultVmApply.error.details.partialIdentity.vhdxPath) `
            ([string]$faultVmPlan.data.plan.vhdxPath) `
            'VM partial identity was not bound to the recomputed VHDX path.'
    }
    $faultState = Read-HcrMockAdapterState
    $faultVmMatches = @($faultState.vms | Where-Object { $_.name -eq $faultVmName })
    Assert-Equal $faultVmMatches.Count $(if ($faultPhase -eq 'after') { 1 } else { 0 }) `
        'The VM-create fault fixture produced the wrong mock side effect.'
    Clear-TestMutationFault
}

$faultVmState = Read-HcrMockAdapterState
$faultOwnedVm = @($faultVmState.vms | Where-Object { $_.name -eq 'cleanroom-test' })[0]
foreach ($faultPhase in @('before', 'entered', 'after')) {
    $faultCheckpointName = "fault-checkpoint-$faultPhase"
    $faultCheckpointPlan = Invoke-TestTool 'plan_checkpoint_create' ([pscustomobject]@{
        vmName = 'cleanroom-test'
        checkpointName = $faultCheckpointName
    })
    Set-TestMutationFault 'CreateCheckpoint' $faultPhase
    $faultCheckpointApply = Invoke-TestTool 'apply_checkpoint_create' ([pscustomobject]@{
        planId = [string]$faultCheckpointPlan.data.plan.planId
    })
    if ($faultPhase -eq 'before') {
        Assert-ErrorCode $faultCheckpointApply 'CHECKPOINT_CREATE_FAILED' `
            'The pre-entry checkpoint-create fault returned the wrong error.'
        Assert-True (-not [bool]$faultCheckpointApply.changed) `
            'A pre-entry checkpoint-create fault reported changed=true.'
    }
    else {
        $expectedEffectState = if ($faultPhase -eq 'entered') { 'indeterminate' } else { 'confirmed' }
        Assert-PartialMutationFailure `
            $faultCheckpointApply `
            'CHECKPOINT_CREATE_FAILED' `
            $expectedEffectState `
            'checkpoint'
        Assert-Equal ([string]$faultCheckpointApply.error.details.partialIdentity.vmId) `
            ([string]$faultOwnedVm.id) `
            'Checkpoint partial identity was not bound to the managed VM ID.'
        Assert-Equal ([string]$faultCheckpointApply.error.details.partialIdentity.checkpointName) `
            $faultCheckpointName `
            'Checkpoint partial identity was not bound to the requested name.'
    }
    $faultState = Read-HcrMockAdapterState
    $faultVm = @($faultState.vms | Where-Object { $_.name -eq 'cleanroom-test' })[0]
    $faultCheckpointMatches = @($faultVm.checkpoints | Where-Object {
        $_.name -eq $faultCheckpointName
    })
    Assert-Equal $faultCheckpointMatches.Count $(if ($faultPhase -eq 'after') { 1 } else { 0 }) `
        'The checkpoint-create fault fixture produced the wrong mock side effect.'
    Clear-TestMutationFault
}

foreach ($faultPhase in @('before', 'entered', 'after')) {
    $faultRestorePlan = Invoke-TestTool 'plan_checkpoint_restore' ([pscustomobject]@{
        vmName = 'cleanroom-test'
        checkpointName = 'baseline'
    })
    Set-TestMutationFault 'RestoreCheckpoint' $faultPhase
    $faultRestoreApply = Invoke-TestTool 'apply_checkpoint_restore' ([pscustomobject]@{
        planId = [string]$faultRestorePlan.data.plan.planId
        checkpointName = 'baseline'
        confirmationToken = [string]$faultRestorePlan.data.plan.confirmationToken
    })
    if ($faultPhase -eq 'before') {
        Assert-ErrorCode $faultRestoreApply 'CHECKPOINT_RESTORE_FAILED' `
            'The pre-entry checkpoint-restore fault returned the wrong error.'
        Assert-True (-not [bool]$faultRestoreApply.changed) `
            'A pre-entry checkpoint-restore fault reported changed=true.'
    }
    else {
        $expectedEffectState = if ($faultPhase -eq 'entered') { 'indeterminate' } else { 'confirmed' }
        Assert-PartialMutationFailure `
            $faultRestoreApply `
            'CHECKPOINT_RESTORE_FAILED' `
            $expectedEffectState `
            'checkpointRestore'
        Assert-Equal ([string]$faultRestoreApply.error.details.partialIdentity.vmId) `
            ([string]$faultRestorePlan.data.plan.vmId) `
            'Restore partial identity was not bound to the managed VM ID.'
        Assert-Equal ([string]$faultRestoreApply.error.details.partialIdentity.checkpointId) `
            ([string]$faultRestorePlan.data.plan.checkpointId) `
            'Restore partial identity was not bound to the exact checkpoint ID.'
    }
    Clear-TestMutationFault
}

foreach ($restoreDispatchDrift in @('state', 'currentState', 'checkpointReplacement', 'inventory')) {
    $adapterBoundaryPlan = Invoke-TestTool 'plan_checkpoint_restore' ([pscustomobject]@{
        vmName = 'cleanroom-test'
        checkpointName = 'baseline'
    })
    Assert-True $adapterBoundaryPlan.ok `
        "Restore planning failed before the $restoreDispatchDrift adapter-boundary drift probe."
    $mock = Read-HcrMockAdapterState
    $mock | Add-Member -NotePropertyName restoreDispatchDrift -NotePropertyValue $restoreDispatchDrift -Force
    Write-HcrMockAdapterState $mock
    $adapterBoundaryApply = Invoke-TestTool 'apply_checkpoint_restore' ([pscustomobject]@{
        planId = [string]$adapterBoundaryPlan.data.plan.planId
        checkpointName = 'baseline'
        confirmationToken = [string]$adapterBoundaryPlan.data.plan.confirmationToken
    })
    Assert-ErrorCode $adapterBoundaryApply 'PLAN_DRIFT' `
        "Restore accepted $restoreDispatchDrift drift introduced at adapter dispatch."
    if ($restoreDispatchDrift -eq 'state') {
        $mock = Read-HcrMockAdapterState
        @($mock.vms | Where-Object { $_.name -eq 'cleanroom-test' })[0].state = 'Off'
        Write-HcrMockAdapterState $mock
    }
}
$mock = Read-HcrMockAdapterState
$restoreVm = @($mock.vms | Where-Object { $_.name -eq 'cleanroom-test' })[0]
$restoreVm.state = 'Running'
Write-HcrMockAdapterState $mock
$runningRestorePlan = Invoke-TestTool 'plan_checkpoint_restore' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    checkpointName = 'baseline'
})
Assert-ErrorCode $runningRestorePlan 'VM_STATE_UNSUPPORTED' `
    'Checkpoint restore planning accepted a running VM with advancing uptime.'
$mock = Read-HcrMockAdapterState
@($mock.vms | Where-Object { $_.name -eq 'cleanroom-test' })[0].state = 'Off'
Write-HcrMockAdapterState $mock

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
$mock = Read-HcrMockAdapterState
$replacementVm = @($mock.vms | Where-Object { $_.name -ne 'cleanroom-test' } | Select-Object -First 1)
Assert-Equal $replacementVm.Count 1 'VM dispatch-race fixture has no replacement VM.'
$mock | Add-Member -NotePropertyName dispatchVmIdOverride -NotePropertyValue ([string]$replacementVm[0].id) -Force
Write-HcrMockAdapterState $mock
$dispatchRaceGuest = Invoke-TestTool 'inspect_guest' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    credentialProfile = 'test-profile'
})
Assert-ErrorCode $dispatchRaceGuest 'VM_IDENTITY_DRIFT' `
    'A name-to-ID replacement between ownership guard and adapter dispatch was accepted.'
$mock = Read-HcrMockAdapterState
$mock.PSObject.Properties.Remove('dispatchVmIdOverride')
Write-HcrMockAdapterState $mock
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
$stageFailureArtifact = Join-Path $testRoot 'SampleApp-stage-mismatch-x64.exe'
[IO.File]::WriteAllBytes($stageFailureArtifact, [byte[]](8..71))
$stageMismatchRun = Invoke-TestTool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    credentialProfile = 'test-profile'
    profilePath = $profilePath
    artifactPath = $stageFailureArtifact
})
Assert-True $stageMismatchRun.ok 'Profile staging mismatch did not return auditable evidence.'
Assert-Equal $stageMismatchRun.data.overallStatus 'failed' `
    'A profile staging mismatch did not fail overallStatus.'
Assert-True $stageMismatchRun.data.cleanupTriggered 'A profile staging mismatch did not trigger cleanup.'
Assert-Equal (@($stageMismatchRun.data.automaticAssertions).Count) `
    (@((Get-Content $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json).steps).Count + 1) `
    'A staging mismatch omitted an immutable automatic assertion identity.'
$stageMismatchOperation = Get-HcrOperationRecord $stageMismatchRun.data.testOperationId
$stageMismatchValidation = Invoke-TestTool 'validate_evidence' ([pscustomobject]@{
    evidencePath = [string]$stageMismatchOperation.evidenceFile
})
Assert-True $stageMismatchValidation.ok 'Staging-mismatch evidence was not schema-v1 collectable.'
$stageMismatchCollection = Invoke-TestTool 'collect_evidence' ([pscustomobject]@{
    operationId = [string]$stageMismatchRun.data.testOperationId
    outputDirectory = $exportRoot
})
Assert-True $stageMismatchCollection.ok 'Staging-mismatch evidence could not be collected.'
$mock = Read-HcrMockAdapterState
$mock.stageHashMismatch = $false
$mock | Add-Member -NotePropertyName stageAdapterFailure -NotePropertyValue $true -Force
Write-HcrMockAdapterState $mock
$stageAdapterFailureRun = Invoke-TestTool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    credentialProfile = 'test-profile'
    profilePath = $profilePath
    artifactPath = $stageFailureArtifact
})
Assert-True $stageAdapterFailureRun.ok 'Profile stage-adapter failure did not return evidence.'
$stageAdapterFailureOperation = Get-HcrOperationRecord $stageAdapterFailureRun.data.testOperationId
$stageAdapterFailureEvidence = Read-HcrJsonFile `
    $stageAdapterFailureOperation.evidenceFile `
    'EVIDENCE_NOT_READY'
Assert-True ($null -eq $stageAdapterFailureEvidence.artifact.guestSha256) `
    'An unavailable staged guest hash was not represented as null.'
$stageAdapterFailureValidation = Invoke-TestTool 'validate_evidence' ([pscustomobject]@{
    evidencePath = [string]$stageAdapterFailureOperation.evidenceFile
})
Assert-True $stageAdapterFailureValidation.ok 'Stage-adapter failure evidence was invalid.'
$failedStageIndex = 0
for ($index = 0; $index -lt @($stageAdapterFailureOperation.automaticAssertions).Count; $index++) {
    if ([string]$stageAdapterFailureOperation.automaticAssertions[$index].type -eq 'stageArtifact') {
        $failedStageIndex = $index
        break
    }
}
foreach ($guestHashVariant in @($null, ('b' * 64))) {
    foreach ($invalidStageStatus in @('passed', 'notPerformed', 'unsupported')) {
        $forgedStageEvidence = Copy-HcrObject $stageAdapterFailureEvidence
        $forgedStageOperation = Copy-HcrObject $stageAdapterFailureOperation
        $forgedStageEvidence.artifact.guestSha256 = $guestHashVariant
        $forgedStageOperation.artifact.guestSha256 = $guestHashVariant
        $forgedStageEvidence.automaticAssertions[$failedStageIndex].status = $invalidStageStatus
        $forgedStageEvidence.overallStatus = Get-HcrDerivedOverallStatus `
            @($forgedStageEvidence.automaticAssertions) `
            @($forgedStageEvidence.manualAssertions)
        $forgedStageOperation.evidenceSha256 = Get-HcrEvidenceDocumentDigest $forgedStageEvidence
        $forgedStageValidation = Test-HcrEvidenceDocument `
            $forgedStageEvidence `
            $forgedStageOperation
        Assert-True (-not $forgedStageValidation.valid) `
            "Native evidence validation accepted $invalidStageStatus stage status with an unverified guest hash."
    }
}
foreach ($invalidMatchingStageStatus in @('failed', 'notPerformed', 'unsupported')) {
    $forgedMatchingEvidence = Copy-HcrObject $stageAdapterFailureEvidence
    $forgedMatchingOperation = Copy-HcrObject $stageAdapterFailureOperation
    $matchingHash = [string]$forgedMatchingEvidence.artifact.sourceSha256
    $forgedMatchingEvidence.artifact.guestSha256 = $matchingHash
    $forgedMatchingOperation.artifact.guestSha256 = $matchingHash
    $forgedMatchingEvidence.automaticAssertions[$failedStageIndex].status = `
        $invalidMatchingStageStatus
    $forgedMatchingEvidence.overallStatus = Get-HcrDerivedOverallStatus `
        @($forgedMatchingEvidence.automaticAssertions) `
        @($forgedMatchingEvidence.manualAssertions)
    $forgedMatchingOperation.evidenceSha256 = Get-HcrEvidenceDocumentDigest `
        $forgedMatchingEvidence
    $forgedMatchingValidation = Test-HcrEvidenceDocument `
        $forgedMatchingEvidence `
        $forgedMatchingOperation
    Assert-True (-not $forgedMatchingValidation.valid) `
        "Native evidence validation accepted $invalidMatchingStageStatus stage status with matching hashes."
}
$reservedInventoryPath = Join-Path `
    ([string]$stageAdapterFailureOperation.evidenceRoot) `
    'inventory.json'
[IO.File]::WriteAllText(
    $reservedInventoryPath,
    '{}',
    (New-Object System.Text.UTF8Encoding($false))
)
$reservedInventoryExport = Invoke-TestTool 'collect_evidence' ([pscustomobject]@{
    operationId = [string]$stageAdapterFailureRun.data.testOperationId
    outputDirectory = $exportRoot
})
Assert-ErrorCode $reservedInventoryExport 'EVIDENCE_STAGING_INVALID' `
    'A staged inventory.json was copied and then overwritten by generated inventory.'
$mock = Read-HcrMockAdapterState
$mock.stageAdapterFailure = $false
$mock.guest | Add-Member -NotePropertyName hasAdministratorsSid -NotePropertyValue $true -Force
Write-HcrMockAdapterState $mock
$filteredAdministratorRun = Invoke-TestTool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    credentialProfile = 'test-profile'
    profilePath = $profilePath
    artifactPath = $stageFailureArtifact
})
Assert-True $filteredAdministratorRun.ok 'Filtered-administrator token did not return auditable evidence.'
$tokenInvariant = @($filteredAdministratorRun.data.automaticAssertions | Where-Object {
    $_.id -eq 'runtime-ordinary-user-token'
})
Assert-Equal $tokenInvariant.Count 1 'Runtime token invariant result is missing.'
Assert-Equal $tokenInvariant[0].status 'failed' `
    'A token containing the Administrators SID passed as an ordinary user.'
Assert-True $filteredAdministratorRun.data.cleanupTriggered `
    'Filtered-administrator token failure did not trigger cleanup.'
$mock = Read-HcrMockAdapterState
$mock.guest.hasAdministratorsSid = $false
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
$architectureInput = Copy-HcrObject (Get-HcrPropertyValue (Read-HcrMockAdapterState) 'guest')
$architectureInput.architecture = 'AMD64'
$architectureProjection = Get-HcrGuestEvidenceProjection $architectureInput
Assert-Equal $architectureProjection.architecture 'x64' `
    'Production AMD64 architecture was not normalized to schema-v1 x64.'
$architectureEvidence = Copy-HcrObject $postManualEvidence
$architectureEvidence.guest = $architectureProjection
$architectureOperation = Copy-HcrObject (Get-HcrOperationRecord $happyRun.data.testOperationId)
$architectureOperation.guest = $architectureProjection
$architectureOperation.evidenceSha256 = Get-HcrEvidenceDocumentDigest $architectureEvidence
$architectureValidation = Test-HcrEvidenceDocument $architectureEvidence $architectureOperation
Assert-True $architectureValidation.valid `
    'Normalized production guest projection failed native public-evidence validation.'
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

$optionalFailureProfilePath = Join-Path $testRoot 'optional-adapter-failure-profile.json'
$optionalFailureProfile = Get-Content $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
@($optionalFailureProfile.steps | Where-Object { $_.id -eq 'assert-installed-file' })[0].required = $false
Write-TestJson $optionalFailureProfilePath $optionalFailureProfile
$mock = Read-HcrMockAdapterState
$mock | Add-Member -NotePropertyName stepAdapterFailureId -NotePropertyValue 'assert-installed-file' -Force
Write-HcrMockAdapterState $mock
$optionalAdapterFailureRun = Invoke-TestTool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    credentialProfile = 'test-profile'
    profilePath = $optionalFailureProfilePath
    artifactPath = $happyArtifact
})
Assert-True $optionalAdapterFailureRun.ok 'Optional assertion adapter failure returned no evidence.'
Assert-True $optionalAdapterFailureRun.data.cleanupTriggered `
    'An optional assertion infrastructure failure did not trigger cleanup.'
Assert-Equal (@($optionalAdapterFailureRun.data.automaticAssertions | Where-Object {
    $_.id -eq 'launch-application'
})[0].status) 'notPerformed' `
    'Execution continued after an optional assertion infrastructure failure.'
$mock = Read-HcrMockAdapterState
$mock.PSObject.Properties.Remove('stepAdapterFailureId')
Write-HcrMockAdapterState $mock

$global:HcrEvidenceExportAfterValidationTestHook = {
    param([string]$SourceRoot, [string]$EvidencePath)

    $changed = Get-Content -LiteralPath $EvidencePath -Raw -Encoding UTF8 |
        ConvertFrom-Json -ErrorAction Stop
    $changed.warnings = @($changed.warnings) + 'mutated after locked validation'
    Write-TestJson $EvidencePath $changed
}
try {
    $postValidationMutationExport = Invoke-TestTool 'collect_evidence' ([pscustomobject]@{
        operationId = [string]$optionalAdapterFailureRun.data.testOperationId
        outputDirectory = $exportRoot
    })
}
finally {
    Remove-Variable `
        -Name HcrEvidenceExportAfterValidationTestHook `
        -Scope Global `
        -ErrorAction SilentlyContinue
}
Assert-ErrorCode $postValidationMutationExport 'EVIDENCE_INVALID' `
    'Evidence changed after locked validation was exported as immutable operation evidence.'

$inventoryCorruptionRun = Invoke-TestTool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    credentialProfile = 'test-profile'
    profilePath = $profilePath
    artifactPath = $happyArtifact
})
Assert-True $inventoryCorruptionRun.ok `
    'The final-inventory corruption regression could not create valid operation evidence.'
$global:HcrEvidenceExportAfterInventoryWriteTestHook = {
    param([string]$InventoryPath, [string]$TargetRoot)

    $changedInventory = Get-Content -LiteralPath $InventoryPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -ErrorAction Stop
    $changedInventory.files[0].sha256 = 'f' * 64
    Write-TestJson $InventoryPath $changedInventory
}
try {
    $postInventoryCorruptionExport = Invoke-TestTool 'collect_evidence' ([pscustomobject]@{
        operationId = [string]$inventoryCorruptionRun.data.testOperationId
        outputDirectory = $exportRoot
    })
}
finally {
    Remove-Variable `
        -Name HcrEvidenceExportAfterInventoryWriteTestHook `
        -Scope Global `
        -ErrorAction SilentlyContinue
}
Assert-ErrorCode $postInventoryCorruptionExport 'EVIDENCE_INVENTORY_INVALID' `
    'A corrupted final serialized inventory was reported as a successful evidence export.'

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
$failureEvidence = Read-HcrJsonFile $failureOperation.evidenceFile 'EVIDENCE_NOT_READY'
$upgradedFailure = Copy-HcrObject $failureEvidence
$failedRequired = @($upgradedFailure.automaticAssertions | Where-Object {
    $_.required -and $_.status -eq 'failed'
} | Select-Object -First 1)
Assert-Equal $failedRequired.Count 1 'Failure-evidence forgery fixture has no required failure.'
$failedRequired[0].status = 'passed'
$failedRequired[0].summary = 'forged upgrade from failure to pass'
$upgradedFailure.overallStatus = Get-HcrDerivedOverallStatus `
    @($upgradedFailure.automaticAssertions) `
    @($upgradedFailure.manualAssertions)
$upgradedFailurePath = Join-Path $testRoot 'upgraded-failure-evidence.json'
Write-TestJson $upgradedFailurePath $upgradedFailure
$upgradedFailureResult = Invoke-TestTool 'validate_evidence' ([pscustomobject]@{
    evidencePath = $upgradedFailurePath
})
Assert-ErrorCode $upgradedFailureResult 'EVIDENCE_INVALID' `
    'A canonical required failure was rewritten while preserving evidence validity.'
$forgedManual = Copy-HcrObject $postManualEvidence
$forgedManual.manualAssertions[0].attestation.observer = 'forged-observer'
$forgedManualPath = Join-Path $testRoot 'forged-manual-attestation.json'
Write-TestJson $forgedManualPath $forgedManual
$forgedManualResult = Invoke-TestTool 'validate_evidence' ([pscustomobject]@{
    evidencePath = $forgedManualPath
})
Assert-ErrorCode $forgedManualResult 'EVIDENCE_INVALID' `
    'A recorded manual observer was changed while preserving evidence validity.'
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
$selfReferenceAttestation = Invoke-TestTool 'record_manual_attestation' ([pscustomobject]@{
    operationId = [string]$failureRun.data.testOperationId
    assertionId = 'first-launch-visible'
    status = 'failed'
    method = 'visualInspection'
    summary = 'Mutable control-document self-reference probe.'
    evidenceReferences = @([pscustomobject]@{
        path = 'evidence.json'
        sha256 = Get-HcrSha256File ([string]$failureOperation.evidenceFile)
    })
})
Assert-ErrorCode $selfReferenceAttestation 'EVIDENCE_REFERENCE_INVALID' `
    'The mutable evidence.json control document was accepted as an attestation reference.'
$mutableReferencePath = Join-Path ([string]$failureOperation.evidenceRoot) 'manual-observation.txt'
[IO.File]::WriteAllText(
    $mutableReferencePath,
    'original observation',
    (New-Object System.Text.UTF8Encoding($false))
)
$mutableReferenceAttestation = Invoke-TestTool 'record_manual_attestation' ([pscustomobject]@{
    operationId = [string]$failureRun.data.testOperationId
    assertionId = 'first-launch-visible'
    status = 'failed'
    method = 'visualInspection'
    summary = 'Hash-bound observation that will be mutated before export.'
    evidenceReferences = @([pscustomobject]@{
        path = 'manual-observation.txt'
        sha256 = Get-HcrSha256File $mutableReferencePath
    })
})
Assert-True $mutableReferenceAttestation.ok 'A valid hash-bound manual evidence reference was rejected.'
[IO.File]::WriteAllText(
    $mutableReferencePath,
    'mutated after attestation',
    (New-Object System.Text.UTF8Encoding($false))
)
$mutableReferenceExport = Invoke-TestTool 'collect_evidence' ([pscustomobject]@{
    operationId = [string]$failureRun.data.testOperationId
    outputDirectory = $exportRoot
})
Assert-ErrorCode $mutableReferenceExport 'EVIDENCE_REFERENCE_HASH_MISMATCH' `
    'Evidence export accepted a file changed after manual attestation.'

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
$initializerSource = Get-Content -LiteralPath $initializerPath -Raw -Encoding UTF8
Assert-True ($initializerSource -match 'Publish-HcrCredentialDirectory') `
    'Credential initialization does not use the exact-destination publication helper.'
Assert-True ($initializerSource -notmatch '(?m)^\s*Move-Item\b') `
    'Credential initialization still uses container-merging Move-Item publication.'
$initializerFunctions = @($initializerAst.FindAll({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        @('Assert-HcrPrivateCredentialAcl', 'Set-HcrPrivateCredentialAcl') -contains $node.Name
}, $true))
Assert-Equal $initializerFunctions.Count 2 `
    'Credential ACL installation/readback functions are missing.'
foreach ($functionAst in $initializerFunctions) {
    Invoke-Expression $functionAst.Extent.Text
}
$setCredentialAclFunction = @($initializerFunctions | Where-Object {
    $_.Name -eq 'Set-HcrPrivateCredentialAcl'
})
Assert-Equal $setCredentialAclFunction.Count 1 `
    'Credential ACL installation function is missing or duplicated.'
Assert-True ($setCredentialAclFunction[0].Extent.Text -match
    '\$acl\.SetOwner\(\$currentSid\)') `
    'Credential ACL installation does not explicitly assign current-user ownership.'
$credentialAclProbe = Join-Path $testRoot 'credential-acl-probe'
[void](New-Item -ItemType Directory -Path $credentialAclProbe)
Set-HcrPrivateCredentialAcl $credentialAclProbe
Assert-HcrPrivateCredentialAcl $credentialAclProbe
$credentialProbeAcl = Get-Acl -LiteralPath $credentialAclProbe
Assert-True $credentialProbeAcl.AreAccessRulesProtected `
    'Credential ACL readback accepted inherited permissions.'
Assert-Equal `
    ([string]$credentialProbeAcl.GetOwner([Security.Principal.SecurityIdentifier]).Value) `
    ([string][Security.Principal.WindowsIdentity]::GetCurrent().User.Value) `
    'Credential ACL readback accepted an unexpected owner.'
$credentialProbeRules = @($credentialProbeAcl.GetAccessRules(
    $true,
    $true,
    [Security.Principal.SecurityIdentifier]
))
Assert-Equal $credentialProbeRules.Count 3 `
    'Credential ACL installation did not produce exactly three explicit grants.'
foreach ($credentialProbeRule in $credentialProbeRules) {
    Assert-Equal ([int]$credentialProbeRule.FileSystemRights) `
        ([int][Security.AccessControl.FileSystemRights]::FullControl) `
        'Credential ACL installation produced a non-exact full-control grant.'
    Assert-Equal ([int]$credentialProbeRule.InheritanceFlags) `
        ([int]$expectedWorkspaceInheritance) `
        'Credential ACL installation produced non-canonical inheritance flags.'
    Assert-Equal ([int]$credentialProbeRule.PropagationFlags) 0 `
        'Credential ACL installation produced non-canonical propagation flags.'
}
$publicationRoot = Join-Path $testRoot 'credential-publication-race'
[void](New-Item -ItemType Directory -Path $publicationRoot)
$publicationDestination = Join-Path $publicationRoot 'shared-profile'
$pendingDirectories = @(
    (Join-Path $publicationRoot ('.pending-' + [Guid]::NewGuid().ToString('N')))
    (Join-Path $publicationRoot ('.pending-' + [Guid]::NewGuid().ToString('N')))
)
foreach ($pendingDirectory in $pendingDirectories) {
    [void](New-Item -ItemType Directory -Path $pendingDirectory)
    foreach ($component in @('orchestration-admin.clixml', 'standard-test-user.clixml', 'profile.json')) {
        [IO.File]::WriteAllText(
            (Join-Path $pendingDirectory $component),
            ((Split-Path -Leaf $pendingDirectory) + ':' + $component),
            (New-Object System.Text.UTF8Encoding($false))
        )
    }
}
$releaseName = 'Local\hcr-publish-release-' + [Guid]::NewGuid().ToString('N')
$readyNames = @(
    ('Local\hcr-publish-ready-' + [Guid]::NewGuid().ToString('N'))
    ('Local\hcr-publish-ready-' + [Guid]::NewGuid().ToString('N'))
)
$releaseEvent = New-Object Threading.EventWaitHandle(
    $false,
    [Threading.EventResetMode]::ManualReset,
    $releaseName
)
$readyEvents = @($readyNames | ForEach-Object {
    New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, $_)
})
$publicationScript = {
    param($CommonPath, $Pending, $Destination, $Root, $ReadyName, $ReleaseName)
    . $CommonPath
    $ready = [Threading.EventWaitHandle]::OpenExisting($ReadyName)
    $release = [Threading.EventWaitHandle]::OpenExisting($ReleaseName)
    try {
        [void]$ready.Set()
        [void]$release.WaitOne()
        try {
            [void](Publish-HcrCredentialDirectory $Pending $Destination $Root)
            [pscustomobject]@{ ok = $true; code = $null }
        }
        catch {
            $code = if ($_.Exception.Data.Contains('HcrCode')) {
                [string]$_.Exception.Data['HcrCode']
            }
            else { 'UNEXPECTED' }
            [pscustomobject]@{ ok = $false; code = $code }
        }
    }
    finally {
        $ready.Dispose()
        $release.Dispose()
    }
}
$commonPath = Join-Path $pluginRoot 'mcp\lib\Common.ps1'
$publicationJobs = @(
    (Start-Job -ScriptBlock $publicationScript -ArgumentList $commonPath, $pendingDirectories[0], $publicationDestination, $publicationRoot, $readyNames[0], $releaseName)
    (Start-Job -ScriptBlock $publicationScript -ArgumentList $commonPath, $pendingDirectories[1], $publicationDestination, $publicationRoot, $readyNames[1], $releaseName)
)
try {
    Assert-True ($readyEvents[0].WaitOne(15000)) 'First credential publication racer did not reach the barrier.'
    Assert-True ($readyEvents[1].WaitOne(15000)) 'Second credential publication racer did not reach the barrier.'
    [void]$releaseEvent.Set()
    $completedPublicationJobs = @(Wait-Job -Job $publicationJobs -Timeout 20)
    Assert-Equal $completedPublicationJobs.Count 2 'Concurrent credential publication did not finish.'
    $publicationResults = @($publicationJobs | Receive-Job)
    Assert-Equal (@($publicationResults | Where-Object { $_.ok }).Count) 1 `
        'Exact-destination credential publication did not produce one winner.'
    Assert-Equal (@($publicationResults | Where-Object {
        -not $_.ok -and $_.code -eq 'CREDENTIAL_PROFILE_EXISTS'
    }).Count) 1 'Credential publication race did not produce one collision loser.'
    $publishedComponents = @(Get-ChildItem -LiteralPath $publicationDestination -Force)
    Assert-Equal $publishedComponents.Count 3 `
        'The concurrent publication destination is not one exact three-file bundle.'
}
finally {
    $publicationJobs | Remove-Job -Force -ErrorAction SilentlyContinue
    $readyEvents | ForEach-Object { $_.Dispose() }
    $releaseEvent.Dispose()
}
$productionPython = @(Get-ChildItem -LiteralPath $pluginRoot -Recurse -Filter '*.py' -File)
Assert-Equal $productionPython.Count 0 'Production plugin gained a Python dependency.'
$adapterSource = Get-Content `
    -LiteralPath (Join-Path $pluginRoot 'mcp\lib\Adapters.ps1') `
    -Raw `
    -Encoding UTF8
$supervisorSourceMatch = [regex]::Match(
    $adapterSource,
    "(?s)Add-Type -TypeDefinition @'\r?\n(?<source>.*?)\r?\n'@ -ErrorAction Stop"
)
Assert-True $supervisorSourceMatch.Success `
    'The embedded suspended-worker supervisor source could not be located.'
Add-Type `
    -TypeDefinition $supervisorSourceMatch.Groups['source'].Value `
    -ErrorAction Stop
Assert-True ($null -ne ('Hcr.SupervisedProcess' -as [type])) `
    'The embedded suspended-worker supervisor did not compile.'
Assert-True ($adapterSource -match 'MOCK_ADAPTER_FORBIDDEN') `
    'Mock adapter no longer has a production guard.'
Assert-True ($adapterSource -notmatch 'GUEST_ADAPTER_UNVALIDATED') `
    'The production guest adapter still contains the former fail-closed stub.'
Assert-True ($adapterSource -notmatch 'Uptime\.Ticks') `
    'A naturally advancing VM uptime still invalidates checkpoint restore plans.'
Assert-True ($adapterSource -match 'TARGET_VOLUME_IDENTITY_UNAVAILABLE') `
    'The production adapter does not fail closed when target-volume UniqueId is unavailable.'
Assert-True ($adapterSource -notmatch 'DriveInfo remains an adequate stable fallback') `
    'The production adapter still treats a drive letter as stable volume identity.'
Assert-True ($adapterSource -match
    '(?s)Get-HcrRevalidatedVmCreatePaths \$plan.*?\$mutationEntered = \$true.*?\$createdVm = New-VM') `
    'The production VM adapter does not revalidate the VM-root binding immediately before mutation.'
foreach ($partialMutationCode in @(
    'VM_CREATE_FAILED',
    'CHECKPOINT_CREATE_FAILED',
    'CHECKPOINT_RESTORE_FAILED'
)) {
    Assert-True ($adapterSource -match
        "(?s)$partialMutationCode.*?Throw-HcrPartialMutationError") `
        "The production adapter does not report bounded partial state for $partialMutationCode."
}
foreach ($functionName in @(
    'Invoke-HcrRealInspectGuest',
    'Invoke-HcrRealStageArtifact',
    'Invoke-HcrRealGuestStep',
    'Invoke-HcrFixedGuestWorker'
)) {
    Assert-True ($adapterSource -match [regex]::Escape($functionName)) `
        "The production guest adapter is missing $functionName."
}
$contractOperationId = [Guid]::NewGuid().ToString()
$validRealStep = [pscustomobject][ordered]@{
    operationId = $contractOperationId
    step = [pscustomobject][ordered]@{
        id = 'assert-file'
        type = 'assertFile'
        path = 'AppData\Local\Sample\sample.exe'
        timeoutSeconds = 30
        required = $true
    }
    applications = @([pscustomobject][ordered]@{
        id = 'sample-app'
        installerType = 'nsis'
        installMode = 'currentUser'
        executableRelativePath = 'AppData\Local\Sample\sample.exe'
        uninstallerDiscovery = 'hkcuUninstall'
    })
}
Assert-HcrRealGuestStepContract $validRealStep $false
Assert-True $true 'The closed production guest step contract rejected a valid assertion.'
$commandStep = Copy-HcrObject $validRealStep
$commandStep.step | Add-Member -NotePropertyName command -NotePropertyValue 'whoami' -Force
Assert-ThrowsHcrCode { Assert-HcrRealGuestStepContract $commandStep $false } `
    'GUEST_STEP_FIELD_FORBIDDEN' `
    'The production adapter accepted a caller-supplied command field.'
$cleanupInstall = Copy-HcrObject $validRealStep
$cleanupInstall.step.type = 'installPackage'
$cleanupInstall.step | Add-Member -NotePropertyName application -NotePropertyValue 'sample-app' -Force
Assert-ThrowsHcrCode { Assert-HcrRealGuestStepContract $cleanupInstall $true } `
    'GUEST_STEP_TYPE_FORBIDDEN' `
    'Cleanup accepted an install mutation.'
$administratorInstall = Copy-HcrObject $validRealStep
$administratorInstall.applications[0].installMode = 'administrator'
Assert-ThrowsHcrCode { Assert-HcrRealGuestStepContract $administratorInstall $false } `
    'GUEST_INSTALL_MODE_FORBIDDEN' `
    'The production adapter accepted an administrator install mode.'
Assert-Equal (Get-HcrBoundedCleanupTimeout -DeclaredSeconds 120 -RemainingSeconds 17) 17 `
    'Cleanup timeout was not capped to the remaining total budget.'
Assert-Equal (Get-HcrBoundedCleanupTimeout -DeclaredSeconds 30 -RemainingSeconds 0) 0 `
    'Cleanup attempted to start after the total budget was exhausted.'
$workerPath = Join-Path $pluginRoot 'mcp\lib\GuestWorker.ps1'
$workerTokens = $null
$workerParseErrors = $null
$workerAst = [Management.Automation.Language.Parser]::ParseFile(
    $workerPath,
    [ref]$workerTokens,
    [ref]$workerParseErrors
)
Assert-Equal (@($workerParseErrors).Count) 0 'The fixed guest worker has parse errors.'
$workerSource = Get-Content -LiteralPath $workerPath -Raw -Encoding UTF8
foreach ($forbiddenSource in @(
    'Invoke-Expression',
    'ScriptBlock]::Create',
    'Invoke-WebRequest',
    'DownloadString',
    'cmd.exe',
    'ssh.exe',
    'Enter-PSSession'
)) {
    Assert-True ($workerSource -notmatch [regex]::Escape($forbiddenSource)) `
        "The fixed guest worker contains forbidden execution surface: $forbiddenSource."
}
Assert-True ($workerSource -match "ValidateSet\('InspectGuest', 'RunTestStep', 'RunCleanupStep'\)") `
    'The fixed guest worker mode dispatcher is not closed.'
Assert-True ($workerSource -match 'Test-WorkerProcessIdentity') `
    'The fixed guest worker does not revalidate operation-scoped process identity.'
Assert-True ($workerSource -match "S-1-16-8448'[\s\S]{0,80}'mediumPlus'") `
    'Medium-plus integrity would be mislabeled as the required exact medium integrity.'
Assert-True ($workerSource -match 'Initialize-WorkerDirectoryTree') `
    'The standard-user sentinel path is not created with segment-by-segment reparse checks.'
Assert-True ($workerSource -match '\[Console\]::OpenStandardOutput') `
    'The worker does not return its result over the process-bound stdout channel.'
Assert-True ($workerSource -notmatch '\[string\]\$OutputPath') `
    'The worker still accepts a same-user-writable result-file path.'
Assert-True ($adapterSource -match '\[IO\.FileMode\]::CreateNew') `
    'The administrator supervisor does not create fixed-worker input files atomically.'
foreach ($containmentSeam in @(
    'CreateProcessWithLogonW',
    'CreateSuspended',
    'AssignProcessToJobObject',
    'ResumeThread',
    'TerminateAndVerify',
    'ActiveProcessCount',
    'ReleaseVerifiedSingleProcess',
    'NtSuspendProcess',
    'Synchronize',
    'WaitFailed',
    'GetProcessCreationTicks',
    'GetProcessImagePath'
)) {
    Assert-True ($adapterSource -match [regex]::Escape($containmentSeam)) `
        "The suspended worker containment seam is missing: $containmentSeam."
}
Assert-True ($adapterSource -match 'AssignProcessToJobObject') `
    'The administrator supervisor does not bind the worker process tree to a job.'
$deadlineGuardIndex = $adapterSource.IndexOf(
    'if ([DateTimeOffset]::UtcNow -ge $deadline)'
)
$suspendedCreateIndex = $adapterSource.IndexOf(
    '$supervised = [Hcr.SupervisedProcess]::CreateSuspendedInJob('
)
Assert-True ($deadlineGuardIndex -ge 0 -and
    $suspendedCreateIndex -gt $deadlineGuardIndex) `
    'An already-expired worker deadline can reach suspended process creation.'
foreach ($restoreIdentitySeam in @(
    'RequireOfflineDiskIdentity',
    'RESTORE_DISK_IDENTITY_UNAVAILABLE',
    'RESTORE_CHECKPOINT_INVENTORY_UNAVAILABLE',
    'Get-VMHardDiskDrive -VM $Vm -ErrorAction Stop',
    'Get-VHD -Path $path -ErrorAction Stop',
    '-CheckpointInventory $boundaryCheckpoints',
    '$snapshots = @($boundaryCheckpoints | Where-Object'
)) {
    Assert-True ($adapterSource -match [regex]::Escape($restoreIdentitySeam)) `
        "Restore-specific offline disk identity seam is missing: $restoreIdentitySeam."
}
Assert-True ($adapterSource -match
    'ProcessQueryLimitedInformation \| ProcessSuspendResume \| Synchronize') `
    'Sole-child release does not request SYNCHRONIZE for its retained process handle.'
Assert-True ($adapterSource -match 'candidateWait == WaitFailed') `
    'Sole-child release does not fail closed on WAIT_FAILED.'
Assert-True ($adapterSource -notmatch
    'if \(suspended\) \{ NtResumeProcess\(candidate\); \}') `
    'A rejected launch candidate is resumed before whole-job termination.'
Assert-True ($adapterSource -match
    '(?s)Assert-HcrRestoreAdapterBindings \$liveSnapshot \$Arguments.*?\$snapshots = @\(\$boundaryCheckpoints \| Where-Object.*?Restore-VMSnapshot -VMSnapshot \$snapshots\[0\]') `
    'Restore does not pass the exact checkpoint object from the validated boundary inventory.'
Assert-True ($adapterSource -match
    'New-ProtectedWorkspaceAcl \$TestSid \$AllowTestRead \$true') `
    'Existing workspace ACL repair does not explicitly rebind administrator ownership.'
foreach ($restoreBoundaryIdentityField in @(
    'expectedVmId',
    'expectedVmName',
    'expectedOwnershipId',
    'expectedVmPath',
    'expectedVhdxPath'
)) {
    $restoreBoundaryPattern = 'Assert-HcrRestoreAdapterBindings[\s\S]+' +
        'Get-HcrPropertyValue \$Arguments ''' +
        [regex]::Escape($restoreBoundaryIdentityField) + ''''
    Assert-True ($adapterSource -match $restoreBoundaryPattern) `
        "Restore mutation-boundary identity does not rebind $restoreBoundaryIdentityField."
}
foreach ($bindingField in @('operationId', 'invocationId', 'mode', 'inputSha256')) {
    Assert-True ($adapterSource -match "Get-HcrPropertyValue \`$document '$bindingField'") `
        "The worker result is not bound to $bindingField."
}
Assert-True ($adapterSource -notmatch 'outputRoot; rights = \[Security\.AccessControl\.FileSystemRights\]::Modify') `
    'The standard user can still modify the whole administrator-controlled output directory.'
Assert-True ($adapterSource -match 'SetAccessRuleProtection\(\$true, \$false\)') `
    'Guest workspace ACLs are not protected from inherited parent grants.'
Assert-True ($workerSource -match 'WorkerProcessHandle\]::TerminateAndWait') `
    'stopApplication does not terminate and wait on the retained validated process handle.'
Assert-True ($workerSource -notmatch 'Stop-Process\s+-Id') `
    'stopApplication still performs a second PID-only process lookup.'

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
$mock = Read-HcrMockAdapterState
$mock | Add-Member -NotePropertyName emitNonProtocolStreams -NotePropertyValue $true -Force
Write-HcrMockAdapterState $mock
$server = New-Object Diagnostics.Process
$server.StartInfo = $serverInfo
[void]$server.Start()
$server.StandardInput.WriteLine('{not-json')
$parseResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-Equal $parseResponse.error.code -32700 'Malformed JSON did not return parse error.'
$server.StandardInput.WriteLine('[{"jsonrpc":"2.0","id":99,"method":"ping"}]')
$batchResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-Equal $batchResponse.error.code -32600 'A single-entry JSON-RPC batch was accepted.'
$server.StandardInput.WriteLine('42')
$scalarResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-Equal $scalarResponse.error.code -32600 'A JSON scalar was treated as a notification.'
Assert-True ($null -eq $scalarResponse.id) 'A scalar Invalid Request did not use id null.'
$server.StandardInput.WriteLine('{"jsonrpc":"2.0"}')
$malformedNotificationResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-Equal $malformedNotificationResponse.error.code -32600 `
    'A malformed id-less object was silently treated as a notification.'
Assert-True ($null -eq $malformedNotificationResponse.id) `
    'An id-less Invalid Request did not use id null.'
$server.StandardInput.WriteLine('{"jsonrpc":"2.0","id":{},"method":"ping"}')
$invalidIdResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-Equal $invalidIdResponse.error.code -32600 'An object JSON-RPC id was accepted.'
Assert-True ($null -eq $invalidIdResponse.id) 'An invalid JSON-RPC id was echoed.'

foreach ($invalidPingMessage in @(
    '{"jsonrpc":"2.0","id":10,"method":"ping","params":"scalar"}',
    '{"jsonrpc":"2.0","id":11,"method":"ping","params":null}',
    '{"jsonrpc":"2.0","id":12,"method":"ping","params":[]}',
    '{"jsonrpc":"2.0","id":13,"method":"ping","params":{"unexpected":true}}'
)) {
    $server.StandardInput.WriteLine($invalidPingMessage)
    $invalidPingResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
    Assert-Equal $invalidPingResponse.error.code -32602 `
        'Ping accepted scalar, null, array, or unknown parameters.'
}
$server.StandardInput.WriteLine('{"jsonrpc":"2.0","id":14,"method":"ping"}')
$omittedPingResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-True (Test-HcrObjectLike $omittedPingResponse.result) `
    'Ping rejected omitted parameters.'
$server.StandardInput.WriteLine('{"jsonrpc":"2.0","id":15,"method":"ping","params":{}}')
$emptyPingResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-True (Test-HcrObjectLike $emptyPingResponse.result) `
    'Ping rejected an empty parameter object.'

foreach ($invalidInitializeMessage in @(
    '{"jsonrpc":"2.0","id":20,"method":"initialize","params":{"protocolVersion":"2025-11-25","clientInfo":{"name":"gate2","version":"1"}}}',
    '{"jsonrpc":"2.0","id":21,"method":"initialize","params":{"protocolVersion":20251125,"capabilities":{},"clientInfo":{"name":"gate2","version":"1"}}}',
    '{"jsonrpc":"2.0","id":22,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":[],"clientInfo":{"name":"gate2","version":"1"}}}',
    '{"jsonrpc":"2.0","id":23,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":"gate2"}}',
    '{"jsonrpc":"2.0","id":24,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":1,"version":"1"}}}',
    '{"jsonrpc":"2.0","id":25,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"gate2","version":"1"},"unexpected":true}}'
)) {
    $server.StandardInput.WriteLine($invalidInitializeMessage)
    $invalidInitializeResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
    Assert-Equal $invalidInitializeResponse.error.code -32602 `
        'Initialize accepted a missing, mistyped, or unknown parameter.'
}
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

$invalidInitializedNotifications = @(
    '{"jsonrpc":"2.0","method":"notifications/initialized","params":"scalar"}',
    '{"jsonrpc":"2.0","method":"notifications/initialized","params":null}',
    '{"jsonrpc":"2.0","method":"notifications/initialized","params":[]}',
    '{"jsonrpc":"2.0","method":"notifications/initialized","params":{"unexpected":true}}'
)
$notificationProbeId = 30
foreach ($invalidInitializedNotification in $invalidInitializedNotifications) {
    $server.StandardInput.WriteLine($invalidInitializedNotification)
    $server.StandardInput.WriteLine(
        '{"jsonrpc":"2.0","id":' + $notificationProbeId + ',"method":"tools/list","params":{}}'
    )
    $invalidNotificationProbe = $server.StandardOutput.ReadLine() | ConvertFrom-Json
    Assert-Equal $invalidNotificationProbe.error.code -32002 `
        'Invalid initialized-notification parameters advanced protocol state.'
    $notificationProbeId++
}
$server.StandardInput.WriteLine('{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}')

foreach ($invalidListMessage in @(
    '{"jsonrpc":"2.0","id":34,"method":"tools/list","params":"scalar"}',
    '{"jsonrpc":"2.0","id":35,"method":"tools/list","params":{"unexpected":true}}',
    '{"jsonrpc":"2.0","id":36,"method":"tools/list","params":null}'
)) {
    $server.StandardInput.WriteLine($invalidListMessage)
    $invalidListResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
    Assert-Equal $invalidListResponse.error.code -32602 `
        'tools/list accepted scalar, null, or unknown parameters.'
}
$server.StandardInput.WriteLine('{"jsonrpc":"2.0","id":4,"method":"tools/list","params":{}}')
$toolListResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-Equal (@($toolListResponse.result.tools).Count) 20 'MCP tools/list count changed.'
$server.StandardInput.WriteLine('{"jsonrpc":"2.0","id":37,"method":"tools/list"}')
$omittedListResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-Equal (@($omittedListResponse.result.tools).Count) 20 `
    'tools/list rejected omitted parameters.'

foreach ($invalidToolCallMessage in @(
    '{"jsonrpc":"2.0","id":38,"method":"tools/call","params":"scalar"}',
    '{"jsonrpc":"2.0","id":39,"method":"tools/call","params":{"name":"inspect_host","arguments":{},"unexpected":true}}',
    '{"jsonrpc":"2.0","id":40,"method":"tools/call","params":{"name":"inspect_host","arguments":"scalar"}}'
)) {
    $server.StandardInput.WriteLine($invalidToolCallMessage)
    $invalidToolCallResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
    Assert-Equal $invalidToolCallResponse.error.code -32602 `
        'tools/call accepted scalar, unknown, or unstructured parameters.'
}
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

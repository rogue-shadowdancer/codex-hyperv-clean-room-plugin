function Get-HcrAdapterMode {
    $mode = if ([string]::IsNullOrWhiteSpace($env:HCR_ADAPTER_MODE)) {
        'hyperv'
    }
    else {
        $env:HCR_ADAPTER_MODE.ToLowerInvariant()
    }
    if ($mode -eq 'mock') {
        if ($env:HCR_TEST_MODE -ne '1') {
            Throw-HcrError 'MOCK_ADAPTER_FORBIDDEN' 'The mock adapter is available only in explicit test mode.'
        }
        if ([string]::IsNullOrWhiteSpace($env:HCR_MOCK_ADAPTER_PATH) -or
            -not (Test-HcrLocalAbsolutePath $env:HCR_MOCK_ADAPTER_PATH)) {
            Throw-HcrError 'MOCK_ADAPTER_INVALID' 'A local absolute mock-adapter state path is required.'
        }
        return 'mock'
    }
    if ($mode -ne 'hyperv') {
        Throw-HcrError 'ADAPTER_INVALID' 'The adapter mode is not supported.'
    }
    return 'hyperv'
}

function Read-HcrMockAdapterState {
    $path = Get-HcrNormalizedPath $env:HCR_MOCK_ADAPTER_PATH
    $state = Read-HcrJsonFile $path 'MOCK_ADAPTER_INVALID'
    if ((Get-HcrPropertyValue $state 'schemaVersion') -ne 1 -or
        -not (Test-HcrProperty $state 'host') -or
        -not (Test-HcrProperty $state 'vms')) {
        Throw-HcrError 'MOCK_ADAPTER_INVALID' 'The mock-adapter state has an invalid shape.'
    }
    return $state
}

function Write-HcrMockAdapterState {
    param([Parameter(Mandatory = $true)][object]$State)
    Write-HcrJsonFile (Get-HcrNormalizedPath $env:HCR_MOCK_ADAPTER_PATH) $State
}

function Get-HcrMockVm {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][string]$VmName
    )

    $matches = @(@((Get-HcrPropertyValue $State 'vms' @())) |
        Where-Object { [string](Get-HcrPropertyValue $_ 'name') -eq $VmName } |
        Select-Object -First 1)
    if ($matches.Count -eq 0) { return $null }
    return $matches[0]
}

function Assert-HcrMockDispatchVm {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][object]$Arguments
    )

    $expectedId = [string](Get-HcrPropertyValue $Arguments 'expectedVmId')
    $dispatchId = [string](Get-HcrPropertyValue $State 'dispatchVmIdOverride' $expectedId)
    $matches = @(@((Get-HcrPropertyValue $State 'vms' @())) | Where-Object {
        [string](Get-HcrPropertyValue $_ 'id') -eq $dispatchId
    } | Select-Object -First 1)
    if ($matches.Count -ne 1) {
        Throw-HcrError 'VM_IDENTITY_DRIFT' 'The adapter could not resolve the previously verified VM identity.'
    }
    $vm = $matches[0]
    $marker = 'hyperv-clean-room/v1:' + [string](Get-HcrPropertyValue $Arguments 'expectedOwnershipId')
    if ([string](Get-HcrPropertyValue $vm 'id') -ne $expectedId -or
        [string](Get-HcrPropertyValue $vm 'name') -ne [string](Get-HcrPropertyValue $Arguments 'expectedVmName') -or
        [string](Get-HcrPropertyValue $vm 'notes') -ne $marker -or
        (Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $vm 'vmPath'))) -ne
            (Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $Arguments 'expectedVmPath'))) -or
        (Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $vm 'vhdxPath'))) -ne
            (Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $Arguments 'expectedVhdxPath')))) {
        Throw-HcrError 'VM_IDENTITY_DRIFT' 'The adapter VM identity no longer matches the ownership guard.'
    }
    return $vm
}

function Get-HcrMockConfiguredResult {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][string]$CollectionName,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$DefaultSummary
    )

    $collection = Get-HcrPropertyValue $State $CollectionName
    if ($null -ne $collection -and (Test-HcrProperty $collection $Id)) {
        return Copy-HcrObject (Get-HcrPropertyValue $collection $Id)
    }
    return [pscustomobject][ordered]@{
        status = 'passed'
        summary = $DefaultSummary
        evidence = [pscustomobject]@{ adapter = 'mock' }
    }
}

function Get-HcrMockMutationFaultPhase {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    $fault = Get-HcrPropertyValue $State 'mutationFault'
    if ($null -eq $fault) { return $null }
    if (-not (Test-HcrObjectLike $fault) -or
        [string](Get-HcrPropertyValue $fault 'operation') -ne $Operation) {
        return $null
    }
    $phase = [string](Get-HcrPropertyValue $fault 'phase')
    if (@('before', 'entered', 'after') -notcontains $phase) {
        Throw-HcrError 'MOCK_ADAPTER_INVALID' 'The configured mutation fault phase is invalid.'
    }
    return $phase
}

function Invoke-HcrMockAdapter {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [AllowNull()][object]$Arguments
    )

    $state = Read-HcrMockAdapterState
    if ($Operation -eq 'GetHostSnapshot' -and
        [bool](Get-HcrPropertyValue $state 'emitNonProtocolStreams' $false)) {
        Write-Warning 'mock warning stream probe' -WarningAction Continue
        Write-Information 'mock information stream probe' -InformationAction Continue
        Write-Verbose 'mock verbose stream probe' -Verbose
        $savedDebugPreference = $DebugPreference
        try {
            # The -Debug common parameter switches Windows PowerShell 5.1 to
            # Inquire and fails under -NonInteractive before redirection can be
            # tested. Continue emits stream 5 without introducing a prompt.
            $DebugPreference = 'Continue'
            Write-Debug 'mock debug stream probe'
        }
        finally { $DebugPreference = $savedDebugPreference }
        Write-Progress -Activity 'mock progress stream probe' -Status 'bounded'
        Write-Host 'mock host stream probe'
    }
    switch ($Operation) {
        'GetHostSnapshot' {
            return Copy-HcrObject (Get-HcrPropertyValue $state 'host')
        }
        'GetTargetVolume' {
            $path = Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $Arguments 'path'))
            $matches = @(@((Get-HcrPropertyValue (Get-HcrPropertyValue $state 'host') 'targetVolumes' @())) |
                Where-Object {
                    $root = [string](Get-HcrPropertyValue $_ 'root')
                    $path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)
                } |
                Sort-Object { ([string](Get-HcrPropertyValue $_ 'root')).Length } -Descending)
            if ($matches.Count -eq 0) {
                Throw-HcrError 'TARGET_VOLUME_NOT_FOUND' 'No mock target volume matches the path.'
            }
            return Copy-HcrObject $matches[0]
        }
        'GetSwitch' {
            $name = [string](Get-HcrPropertyValue $Arguments 'name')
            $switch = @(@((Get-HcrPropertyValue (Get-HcrPropertyValue $state 'host') 'switches' @())) |
                Where-Object { [string](Get-HcrPropertyValue $_ 'name') -eq $name } |
                Select-Object -First 1)
            if ($switch.Count -eq 0) { return $null }
            return Copy-HcrObject $switch[0]
        }
        'ListVms' {
            return @(@((Get-HcrPropertyValue $state 'vms' @())) | ForEach-Object { Copy-HcrObject $_ })
        }
        'GetVm' {
            $vm = Get-HcrMockVm $state ([string](Get-HcrPropertyValue $Arguments 'name'))
            if ($null -eq $vm) { return $null }
            return Copy-HcrObject $vm
        }
        'CreateVm' {
            $plan = Get-HcrPropertyValue $Arguments 'plan'
            $name = [string](Get-HcrPropertyValue $plan 'name')
            if ($null -ne (Get-HcrMockVm $state $name)) {
                Throw-HcrError 'VM_ALREADY_EXISTS' 'The VM already exists in the mock adapter.'
            }
            $ownershipId = [string](Get-HcrPropertyValue $Arguments 'ownershipId')
            $faultPhase = Get-HcrMockMutationFaultPhase $state 'CreateVm'
            $partialIdentity = [pscustomobject][ordered]@{
                resourceType = 'vm'
                vmId = $null
                vmName = $name
                ownershipId = $ownershipId
                vmPath = [string](Get-HcrPropertyValue $plan 'vmPath')
                vhdxPath = [string](Get-HcrPropertyValue $plan 'vhdxPath')
            }
            if ($faultPhase -eq 'before') {
                Throw-HcrError 'VM_CREATE_FAILED' 'The configured VM-create fault occurred before mutation entry.'
            }
            if ($faultPhase -eq 'entered') {
                Throw-HcrPartialMutationError `
                    'VM_CREATE_FAILED' `
                    'The configured VM-create fault occurred after mutation entry.' `
                    'indeterminate' `
                    $partialIdentity `
                    'A VM or VHDX may have been created. Inspect only the exact partial identity in error.details; automatic cleanup was not attempted.'
            }
            $vmId = [Guid]::NewGuid().ToString()
            $mockSwitch = Invoke-HcrMockAdapter 'GetSwitch' ([pscustomobject]@{
                name = [string](Get-HcrPropertyValue $plan 'switchName')
            })
            if ($null -eq $mockSwitch) {
                Throw-HcrError 'VM_CREATE_FAILED' 'The planned mock switch disappeared before VM creation.'
            }
            $vm = [pscustomobject][ordered]@{
                id = $vmId
                name = $name
                state = 'Off'
                generation = 2
                notes = "hyperv-clean-room/v1:$ownershipId"
                vmPath = [string](Get-HcrPropertyValue $plan 'vmPath')
                vhdxPath = [string](Get-HcrPropertyValue $plan 'vhdxPath')
                processorCount = [int](Get-HcrPropertyValue $plan 'processorCount')
                startupMemoryGb = [int](Get-HcrPropertyValue $plan 'startupMemoryGb')
                maximumMemoryGb = [int](Get-HcrPropertyValue $plan 'maximumMemoryGb')
                diskSizeGb = [int](Get-HcrPropertyValue $plan 'diskSizeGb')
                switchName = [string](Get-HcrPropertyValue $plan 'switchName')
                switchId = [string](Get-HcrPropertyValue $plan 'switchId')
                networkAdapters = @([pscustomobject][ordered]@{
                    id = [Guid]::NewGuid().ToString()
                    name = 'Network Adapter'
                    macAddress = '00155D010203'
                    switchId = [string](Get-HcrPropertyValue $mockSwitch 'id')
                    switchName = [string](Get-HcrPropertyValue $mockSwitch 'name')
                    switchType = [string](Get-HcrPropertyValue $mockSwitch 'type')
                })
                secureBoot = $true
                vtpm = $true
                checkpoints = @()
                currentStateNonce = [Guid]::NewGuid().ToString()
            }
            $state.vms = @(@((Get-HcrPropertyValue $state 'vms' @())) + $vm)
            Write-HcrMockAdapterState $state
            if ($faultPhase -eq 'after') {
                $partialIdentity.vmId = $vmId
                Throw-HcrPartialMutationError `
                    'VM_CREATE_FAILED' `
                    'The configured VM-create fault occurred after a VM effect was confirmed.' `
                    'confirmed' `
                    $partialIdentity `
                    'A VM or VHDX may have been created. Inspect only the exact partial identity in error.details; automatic cleanup was not attempted.'
            }
            return Copy-HcrObject $vm
        }
        'SetVmPower' {
            $vm = Assert-HcrMockDispatchVm $state $Arguments
            if ((Get-HcrVmFingerprint $vm) -ne
                    [string](Get-HcrPropertyValue $Arguments 'expectedVmFingerprint') -or
                [string](Get-HcrPropertyValue $vm 'state') -ne
                    [string](Get-HcrPropertyValue $Arguments 'expectedState')) {
                Throw-HcrError 'PLAN_DRIFT' 'The mock VM changed at the power mutation boundary.'
            }
            $faultPhase = Get-HcrMockMutationFaultPhase $state 'SetVmPower'
            $identity = [pscustomobject][ordered]@{
                resourceType = 'vmPower'
                vmId = [string](Get-HcrPropertyValue $vm 'id')
                vmName = [string](Get-HcrPropertyValue $vm 'name')
                action = [string](Get-HcrPropertyValue $Arguments 'action')
            }
            if ($faultPhase -eq 'before') {
                Throw-HcrError 'POWER_TRANSITION_FAILED' 'The configured power fault occurred before mutation entry.'
            }
            if ($faultPhase -eq 'entered') {
                Throw-HcrPartialMutationError `
                    'POWER_TRANSITION_FAILED' `
                    'The configured power fault occurred after mutation entry.' `
                    'indeterminate' `
                    $identity `
                    'The planned power transition may have taken effect. Inspect the exact managed VM before creating a new plan.'
            }
            $previous = [string](Get-HcrPropertyValue $vm 'state')
            $vm.state = [string](Get-HcrPropertyValue $Arguments 'targetState')
            $vm.currentStateNonce = [Guid]::NewGuid().ToString()
            Write-HcrMockAdapterState $state
            if ($faultPhase -eq 'after') {
                Throw-HcrPartialMutationError `
                    'POWER_TRANSITION_FAILED' `
                    'The configured power fault occurred after the target state was confirmed.' `
                    'confirmed' `
                    $identity `
                    'The planned power transition took effect. Inspect the exact managed VM before creating a new plan.'
            }
            return [pscustomobject][ordered]@{
                previousState = $previous
                currentState = [string](Get-HcrPropertyValue $vm 'state')
                effectState = 'confirmed'
            }
        }
        'SetVmNetwork' {
            $vm = Assert-HcrMockDispatchVm $state $Arguments
            if ((Get-HcrVmNetworkInvariantFingerprint $vm) -ne
                    [string](Get-HcrPropertyValue $Arguments 'expectedVmFingerprint')) {
                Throw-HcrError 'PLAN_DRIFT' 'The mock VM changed at the network mutation boundary.'
            }
            $primary = Get-HcrVerifiedPrimaryAdapter $vm
            $expectedAttachment = Get-HcrPropertyValue $Arguments 'expectedAttachment'
            if ([string]$primary.id -ne
                    [string](Get-HcrPropertyValue $Arguments 'expectedAdapterId') -or
                [string]$primary.fingerprint -ne
                    [string](Get-HcrPropertyValue $Arguments 'expectedAdapterFingerprint') -or
                -not (Test-HcrBoundObjectEqual $primary.attachment $expectedAttachment)) {
                Throw-HcrError 'PLAN_DRIFT' 'The mock primary adapter changed at the mutation boundary.'
            }
            $faultPhase = Get-HcrMockMutationFaultPhase $state 'SetVmNetwork'
            $recoveryPlanId = [string](Get-HcrPropertyValue $Arguments 'recoveryPlanId')
            $identity = [pscustomobject][ordered]@{
                resourceType = 'vmNetwork'
                vmId = [string](Get-HcrPropertyValue $vm 'id')
                vmName = [string](Get-HcrPropertyValue $vm 'name')
                adapterId = [string]$primary.id
                target = [string](Get-HcrPropertyValue $Arguments 'target')
            }
            $details = if ([string]::IsNullOrWhiteSpace($recoveryPlanId)) {
                $null
            }
            else { [pscustomobject][ordered]@{ recoveryPlanId = $recoveryPlanId } }
            if ($faultPhase -eq 'before') {
                Throw-HcrError 'NETWORK_TRANSITION_FAILED' 'The configured network fault occurred before mutation entry.'
            }
            if ($faultPhase -eq 'entered') {
                Throw-HcrPartialMutationError `
                    $(if ($null -eq $details) { 'NETWORK_TRANSITION_FAILED' } else { 'NETWORK_RECOVERY_REQUIRED' }) `
                    'The configured network fault occurred after mutation entry.' `
                    'indeterminate' `
                    $identity `
                    'The planned adapter transition may have taken effect. Use only the pre-created recovery plan when recovery is required.' `
                    $details
            }
            $previous = Copy-HcrObject $primary.attachment
            $targetAttachment = Get-HcrPropertyValue $Arguments 'targetAttachment'
            if ([string](Get-HcrPropertyValue $targetAttachment 'mode') -eq 'disconnected') {
                $primary.raw.switchId = $null
                $primary.raw.switchName = $null
                $primary.raw.switchType = $null
                $vm.switchId = $null
                $vm.switchName = $null
            }
            else {
                $primary.raw.switchId = [string](Get-HcrPropertyValue $targetAttachment 'switchId')
                $primary.raw.switchName = [string](Get-HcrPropertyValue $targetAttachment 'switchName')
                $primary.raw.switchType = [string](Get-HcrPropertyValue $targetAttachment 'switchType')
                $vm.switchId = [string](Get-HcrPropertyValue $targetAttachment 'switchId')
                $vm.switchName = [string](Get-HcrPropertyValue $targetAttachment 'switchName')
            }
            Write-HcrMockAdapterState $state
            if ($faultPhase -eq 'after') {
                Throw-HcrPartialMutationError `
                    $(if ($null -eq $details) { 'NETWORK_TRANSITION_FAILED' } else { 'NETWORK_RECOVERY_REQUIRED' }) `
                    'The configured network fault occurred after the target attachment was confirmed.' `
                    'confirmed' `
                    $identity `
                    'The planned adapter transition took effect. Use only the pre-created recovery plan when recovery is required.' `
                    $details
            }
            return [pscustomobject][ordered]@{
                previousAttachment = $previous
                currentAttachment = Copy-HcrObject $targetAttachment
                effectState = 'confirmed'
            }
        }
        'CreateCheckpoint' {
            $vmName = [string](Get-HcrPropertyValue $Arguments 'vmName')
            $checkpointName = [string](Get-HcrPropertyValue $Arguments 'checkpointName')
            $vm = Assert-HcrMockDispatchVm $state $Arguments
            if (@(@((Get-HcrPropertyValue $vm 'checkpoints' @())) |
                Where-Object { (Get-HcrPropertyValue $_ 'name') -eq $checkpointName }).Count -gt 0) {
                Throw-HcrError 'CHECKPOINT_ALREADY_EXISTS' 'The checkpoint already exists.'
            }
            $faultPhase = Get-HcrMockMutationFaultPhase $state 'CreateCheckpoint'
            $partialIdentity = [pscustomobject][ordered]@{
                resourceType = 'checkpoint'
                vmId = [string](Get-HcrPropertyValue $vm 'id')
                vmName = $vmName
                checkpointId = $null
                checkpointName = $checkpointName
            }
            if ($faultPhase -eq 'before') {
                Throw-HcrError 'CHECKPOINT_CREATE_FAILED' 'The configured checkpoint-create fault occurred before mutation entry.'
            }
            if ($faultPhase -eq 'entered') {
                Throw-HcrPartialMutationError `
                    'CHECKPOINT_CREATE_FAILED' `
                    'The configured checkpoint-create fault occurred after mutation entry.' `
                    'indeterminate' `
                    $partialIdentity `
                    'The exact checkpoint may have been created. Inspect the bound VM and checkpoint identity; automatic cleanup was not attempted.'
            }
            $checkpoint = [pscustomobject][ordered]@{
                id = [Guid]::NewGuid().ToString()
                name = $checkpointName
                parentId = $null
                configurationFingerprint = Get-HcrSha256Text (ConvertTo-HcrJson $vm 50)
                createdAt = Get-HcrUtcTimestamp
            }
            $vm.checkpoints = @(@((Get-HcrPropertyValue $vm 'checkpoints' @())) + $checkpoint)
            Write-HcrMockAdapterState $state
            if ($faultPhase -eq 'after') {
                $partialIdentity.checkpointId = [string]$checkpoint.id
                Throw-HcrPartialMutationError `
                    'CHECKPOINT_CREATE_FAILED' `
                    'The configured checkpoint-create fault occurred after a checkpoint effect was confirmed.' `
                    'confirmed' `
                    $partialIdentity `
                    'The exact checkpoint may have been created. Inspect the bound VM and checkpoint identity; automatic cleanup was not attempted.'
            }
            return Copy-HcrObject $checkpoint
        }
        'RestoreCheckpoint' {
            $checkpointName = [string](Get-HcrPropertyValue $Arguments 'checkpointName')
            $vm = Assert-HcrMockDispatchVm $state $Arguments
            $dispatchDrift = [string](Get-HcrPropertyValue $state 'restoreDispatchDrift')
            if (-not [string]::IsNullOrWhiteSpace($dispatchDrift)) {
                switch ($dispatchDrift) {
                    'state' { $vm.state = 'Running' }
                    'currentState' { $vm.currentStateNonce = [Guid]::NewGuid().ToString() }
                    'checkpointReplacement' {
                        $replacement = @(@($vm.checkpoints) | Where-Object {
                            [string](Get-HcrPropertyValue $_ 'name') -eq $checkpointName
                        } | Select-Object -First 1)
                        if ($replacement.Count -eq 1) {
                            $replacement[0].id = [Guid]::NewGuid().ToString()
                            $replacement[0].configurationFingerprint = Get-HcrSha256Text ([Guid]::NewGuid().ToString())
                        }
                    }
                    'inventory' {
                        $vm.checkpoints = @(@($vm.checkpoints) + [pscustomobject][ordered]@{
                            id = [Guid]::NewGuid().ToString()
                            name = 'adapter-boundary-drift'
                            parentId = $null
                            configurationFingerprint = Get-HcrSha256Text ([Guid]::NewGuid().ToString())
                            createdAt = Get-HcrUtcTimestamp
                        })
                    }
                }
                $state.PSObject.Properties.Remove('restoreDispatchDrift')
                Write-HcrMockAdapterState $state
            }
            $checkpoint = Assert-HcrRestoreAdapterBindings $vm $Arguments
            $faultPhase = Get-HcrMockMutationFaultPhase $state 'RestoreCheckpoint'
            $partialIdentity = [pscustomobject][ordered]@{
                resourceType = 'checkpointRestore'
                vmId = [string](Get-HcrPropertyValue $vm 'id')
                vmName = [string](Get-HcrPropertyValue $vm 'name')
                checkpointId = [string](Get-HcrPropertyValue $checkpoint 'id')
                checkpointName = [string](Get-HcrPropertyValue $checkpoint 'name')
            }
            if ($faultPhase -eq 'before') {
                Throw-HcrError 'CHECKPOINT_RESTORE_FAILED' 'The configured checkpoint-restore fault occurred before mutation entry.'
            }
            if ($faultPhase -eq 'entered') {
                Throw-HcrPartialMutationError `
                    'CHECKPOINT_RESTORE_FAILED' `
                    'The configured checkpoint-restore fault occurred after mutation entry.' `
                    'indeterminate' `
                    $partialIdentity `
                    'The exact checkpoint restore may have taken effect. Inspect the bound VM and checkpoint identity before further mutation; no automatic recovery was attempted.'
            }
            $vm.currentStateNonce = "restored:$((Get-HcrPropertyValue $checkpoint 'id'))"
            Write-HcrMockAdapterState $state
            if ($faultPhase -eq 'after') {
                Throw-HcrPartialMutationError `
                    'CHECKPOINT_RESTORE_FAILED' `
                    'The configured checkpoint-restore fault occurred after the restore effect was confirmed.' `
                    'confirmed' `
                    $partialIdentity `
                    'The exact checkpoint restore may have taken effect. Inspect the bound VM and checkpoint identity before further mutation; no automatic recovery was attempted.'
            }
            return [pscustomobject][ordered]@{
                checkpointId = [string](Get-HcrPropertyValue $checkpoint 'id')
                restoredAt = Get-HcrUtcTimestamp
            }
        }
        'ResolveCredentialProfile' {
            $name = [string](Get-HcrPropertyValue $Arguments 'profileName')
            $vmName = [string](Get-HcrPropertyValue $Arguments 'vmName')
            $profiles = @((Get-HcrPropertyValue $state 'credentialProfiles' @()))
            $profile = @($profiles | Where-Object {
                [string](Get-HcrPropertyValue $_ 'name') -eq $name -and
                [string](Get-HcrPropertyValue $_ 'vmName') -eq $vmName
            } | Select-Object -First 1)
            if ($profile.Count -eq 0) {
                Throw-HcrError 'CREDENTIAL_PROFILE_NOT_FOUND' 'The named credential profile is unavailable for this VM.'
            }
            return Copy-HcrObject $profile[0]
        }
        'InspectGuest' {
            [void](Assert-HcrMockDispatchVm $state $Arguments)
            return Copy-HcrObject (Get-HcrPropertyValue $state 'guest')
        }
        'StageArtifact' {
            [void](Assert-HcrMockDispatchVm $state $Arguments)
            if ([bool](Get-HcrPropertyValue $state 'stageAdapterFailure' $false)) {
                Throw-HcrError 'MOCK_STAGE_FAILURE' 'The configured mock stage adapter failed.'
            }
            $sourceHash = [string](Get-HcrPropertyValue $Arguments 'sourceSha256')
            $guestHash = if ([bool](Get-HcrPropertyValue $state 'stageHashMismatch' $false)) {
                ('0' * 64)
            }
            else { $sourceHash }
            $operationId = [string](Get-HcrPropertyValue $Arguments 'operationId')
            $requestedDestination = [string](Get-HcrPropertyValue $Arguments 'guestDestination')
            return [pscustomobject][ordered]@{
                guestDestination = "operations\$operationId\$requestedDestination"
                guestSha256 = $guestHash
                bytesCopied = [int64](Get-HcrPropertyValue $Arguments 'size')
            }
        }
        'RunTestStep' {
            [void](Assert-HcrMockDispatchVm $state $Arguments)
            $step = Get-HcrPropertyValue $Arguments 'step'
            $id = [string](Get-HcrPropertyValue $step 'id')
            if ([string](Get-HcrPropertyValue $state 'stepAdapterFailureId') -eq $id) {
                Throw-HcrError 'MOCK_STEP_ADAPTER_FAILURE' 'The configured mock guest step adapter failed.'
            }
            $result = Get-HcrMockConfiguredResult $state 'stepResults' $id "Mock step '$id' passed."
            if ((Get-HcrPropertyValue $step 'type') -eq 'launchApplication' -and
                -not (Test-HcrProperty $result 'process')) {
                $result | Add-Member -NotePropertyName process -NotePropertyValue ([pscustomobject][ordered]@{
                    operationId = [string](Get-HcrPropertyValue $Arguments 'operationId')
                    pid = 4000 + [Math]::Abs($id.GetHashCode() % 1000)
                    identity = "mock-process-$id"
                    startedAt = Get-HcrUtcTimestamp
                    executablePath = "C:\Mock\$id.exe"
                    application = [string](Get-HcrPropertyValue $step 'application')
                })
            }
            if ((Get-HcrPropertyValue $step 'type') -eq 'deployPortable') {
                $result | Add-Member -NotePropertyName evidence -NotePropertyValue ([pscustomobject][ordered]@{
                    deploymentId = [Guid]::NewGuid().ToString()
                    deploymentFingerprint = Get-HcrSha256Text "$([string](Get-HcrPropertyValue $Arguments 'operationId'))|mock-portable-deployment"
                    dataPreserved = $true
                    previousDataInventorySha256 = Get-HcrSha256Text 'mock-portable-data-inventory'
                    deployedDataInventorySha256 = Get-HcrSha256Text 'mock-portable-data-inventory'
                    portableManifestSha256 = [string](Get-HcrPropertyValue (Get-HcrPropertyValue $Arguments 'portableArtifact') 'portableManifestSha256')
                    fixedWebView2Version = [string](Get-HcrPropertyValue (Get-HcrPropertyValue $Arguments 'webDriver') 'browserVersion')
                }) -Force
            }
            if ((Get-HcrPropertyValue $step 'type') -eq 'acquireWebDriver') {
                $driver = Get-HcrPropertyValue $Arguments 'webDriver'
                $result | Add-Member -NotePropertyName evidence -NotePropertyValue ([pscustomobject][ordered]@{
                    driverVersion = [string](Get-HcrPropertyValue $driver 'driverVersion')
                    loopbackOnly = $true
                    archiveSha256 = [string](Get-HcrPropertyValue (Get-HcrPropertyValue $driver 'acquisition') 'archiveSha256')
                    executableSha256 = [string](Get-HcrPropertyValue (Get-HcrPropertyValue $driver 'executable') 'sha256')
                }) -Force
            }
            if ((Get-HcrPropertyValue $step 'type') -eq 'startUiSession') {
                $result | Add-Member -NotePropertyName evidence -NotePropertyValue ([pscustomobject][ordered]@{
                    sessionOwned = $true
                    loopbackOnly = $true
                }) -Force
            }
            return $result
        }
        'RunCleanupStep' {
            [void](Assert-HcrMockDispatchVm $state $Arguments)
            $step = Get-HcrPropertyValue $Arguments 'step'
            $id = [string](Get-HcrPropertyValue $step 'id')
            $result = Get-HcrMockConfiguredResult $state 'cleanupResults' $id "Mock cleanup step '$id' passed."
            if ((Get-HcrPropertyValue $step 'type') -eq 'stopApplication') {
                $launchedProcess = Get-HcrPropertyValue $Arguments 'launchedProcess'
                if ($null -eq $launchedProcess) {
                    return [pscustomobject][ordered]@{
                        status = 'failed'
                        summary = 'No current-operation process identity was supplied.'
                        evidence = [pscustomobject]@{ processIdentityRevalidated = $false }
                    }
                }
                $identityMatches = [bool](Get-HcrPropertyValue $result 'processIdentityMatches' $true)
                if (-not $identityMatches) {
                    return [pscustomobject][ordered]@{
                        status = 'failed'
                        summary = 'The launched process identity changed before cleanup.'
                        evidence = [pscustomobject]@{
                            processIdentityRevalidated = $false
                            pid = Get-HcrPropertyValue $launchedProcess 'pid'
                        }
                    }
                }
                $result | Add-Member -NotePropertyName evidence -NotePropertyValue ([pscustomobject]@{
                    processIdentityRevalidated = $true
                    pid = Get-HcrPropertyValue $launchedProcess 'pid'
                    identity = Get-HcrPropertyValue $launchedProcess 'identity'
                }) -Force
            }
            return $result
        }
        default {
            Throw-HcrError 'ADAPTER_OPERATION_UNSUPPORTED' 'The mock adapter operation is unsupported.'
        }
    }
}

function Test-HcrCurrentProcessElevated {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Assert-HcrRealDispatchVm {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
        Throw-HcrError 'HYPERV_UNAVAILABLE' 'The Hyper-V PowerShell module is unavailable.'
    }
    $expectedId = [string](Get-HcrPropertyValue $Arguments 'expectedVmId')
    $parsedId = [Guid]::Empty
    if (-not [Guid]::TryParse($expectedId, [ref]$parsedId)) {
        Throw-HcrError 'VM_IDENTITY_DRIFT' 'The adapter received no valid verified VM identity.'
    }
    $matches = @(Get-VM -Id $parsedId -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($matches.Count -ne 1) {
        Throw-HcrError 'VM_IDENTITY_DRIFT' 'The previously verified VM identity is no longer available.'
    }
    $snapshot = ConvertTo-HcrRealVmSnapshot $matches[0]
    $expectedMarker = 'hyperv-clean-room/v1:' + [string](Get-HcrPropertyValue $Arguments 'expectedOwnershipId')
    if ([string](Get-HcrPropertyValue $snapshot 'id') -ne $expectedId -or
        [string](Get-HcrPropertyValue $snapshot 'name') -ne [string](Get-HcrPropertyValue $Arguments 'expectedVmName') -or
        [string](Get-HcrPropertyValue $snapshot 'notes') -ne $expectedMarker -or
        (Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $snapshot 'vmPath'))) -ne
            (Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $Arguments 'expectedVmPath'))) -or
        (Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $snapshot 'vhdxPath'))) -ne
            (Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $Arguments 'expectedVhdxPath')))) {
        Throw-HcrError 'VM_IDENTITY_DRIFT' 'The adapter VM no longer matches the verified ownership identity.'
    }
    return $matches[0]
}

function Assert-HcrRestoreAdapterBindings {
    param(
        [Parameter(Mandatory = $true)][object]$VmSnapshot,
        [Parameter(Mandatory = $true)][object]$Arguments
    )

    $expectedMarker = 'hyperv-clean-room/v1:' +
        [string](Get-HcrPropertyValue $Arguments 'expectedOwnershipId')
    if ([string](Get-HcrPropertyValue $VmSnapshot 'id') -ne
            [string](Get-HcrPropertyValue $Arguments 'expectedVmId') -or
        [string](Get-HcrPropertyValue $VmSnapshot 'name') -ne
            [string](Get-HcrPropertyValue $Arguments 'expectedVmName') -or
        [string](Get-HcrPropertyValue $VmSnapshot 'notes') -ne $expectedMarker -or
        (Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $VmSnapshot 'vmPath'))) -ne
            (Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $Arguments 'expectedVmPath'))) -or
        (Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $VmSnapshot 'vhdxPath'))) -ne
            (Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $Arguments 'expectedVhdxPath'))) -or
        [string](Get-HcrPropertyValue $Arguments 'expectedVmState') -ne 'Off' -or
        [string](Get-HcrPropertyValue $VmSnapshot 'state') -ne 'Off' -or
        (Get-HcrCurrentStateFingerprint $VmSnapshot) -ne
            [string](Get-HcrPropertyValue $Arguments 'expectedCurrentStateFingerprint') -or
        (Get-HcrCheckpointInventoryFingerprint $VmSnapshot) -ne
            [string](Get-HcrPropertyValue $Arguments 'expectedCheckpointInventoryFingerprint')) {
        Throw-HcrError 'PLAN_DRIFT' 'The restore preconditions changed at the adapter mutation boundary.'
    }
    $expectedId = [string](Get-HcrPropertyValue $Arguments 'expectedCheckpointId')
    $expectedName = [string](Get-HcrPropertyValue $Arguments 'checkpointName')
    $matches = @(@((Get-HcrPropertyValue $VmSnapshot 'checkpoints' @())) | Where-Object {
        [string](Get-HcrPropertyValue $_ 'id') -eq $expectedId -and
        [string](Get-HcrPropertyValue $_ 'name') -eq $expectedName
    })
    if ($matches.Count -ne 1 -or
        (Get-HcrCheckpointFingerprint $matches[0]) -ne
            [string](Get-HcrPropertyValue $Arguments 'expectedCheckpointFingerprint')) {
        Throw-HcrError 'PLAN_DRIFT' 'The exact restore checkpoint changed at the adapter mutation boundary.'
    }
    return $matches[0]
}

function Get-HcrRealGuestRemainingSeconds {
    param([Parameter(Mandatory = $true)][object]$Context)

    $remaining = ([DateTimeOffset](Get-HcrPropertyValue $Context 'deadlineUtc') -
        [DateTimeOffset]::UtcNow).TotalSeconds
    if ($remaining -lt 1) {
        Throw-HcrError 'GUEST_OPERATION_TIMEOUT' 'The supervised guest operation exhausted its end-to-end deadline.'
    }
    return [int][Math]::Floor($remaining)
}

function Get-HcrRealTargetVolume {
    param([Parameter(Mandatory = $true)][string]$Path)

    $root = [IO.Path]::GetPathRoot((Get-HcrNormalizedPath $Path))
    if ([string]::IsNullOrWhiteSpace($root)) {
        Throw-HcrError 'TARGET_VOLUME_NOT_FOUND' 'The target volume cannot be resolved.'
    }
    $driveInfo = New-Object IO.DriveInfo($root)
    if (-not $driveInfo.IsReady) {
        Throw-HcrError 'TARGET_VOLUME_NOT_READY' 'The target volume is not ready.'
    }
    $fileSystem = $driveInfo.DriveFormat
    if (-not (Get-Command Get-Volume -ErrorAction SilentlyContinue)) {
        Throw-HcrError 'TARGET_VOLUME_IDENTITY_UNAVAILABLE' 'Get-Volume is unavailable, so no stable target-volume UniqueId can be obtained.'
    }
    try {
        $volumes = @(Get-Volume -DriveLetter $root.Substring(0, 1) -ErrorAction Stop)
    }
    catch {
        Throw-HcrError 'TARGET_VOLUME_IDENTITY_UNAVAILABLE' 'The target-volume UniqueId could not be queried.'
    }
    if ($volumes.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$volumes[0].UniqueId)) {
        Throw-HcrError 'TARGET_VOLUME_IDENTITY_UNAVAILABLE' 'The target volume has no unambiguous stable UniqueId.'
    }
    $uniqueId = [string]$volumes[0].UniqueId
    if (-not [string]::IsNullOrWhiteSpace([string]$volumes[0].FileSystem)) {
        $fileSystem = [string]$volumes[0].FileSystem
    }
    return [pscustomobject][ordered]@{
        uniqueId = $uniqueId
        root = $root
        fileSystem = $fileSystem
        availableBytes = [int64]$driveInfo.AvailableFreeSpace
    }
}

function ConvertTo-HcrRealVmSnapshot {
    param(
        [Parameter(Mandatory = $true)][object]$Vm,
        [switch]$RequireOfflineDiskIdentity,
        [AllowNull()][object[]]$CheckpointInventory
    )

    try { $hardDrives = @(Get-VMHardDiskDrive -VM $Vm -ErrorAction Stop) }
    catch {
        if ($RequireOfflineDiskIdentity) {
            Throw-HcrError 'RESTORE_DISK_IDENTITY_UNAVAILABLE' 'The attached disk inventory is unavailable for checkpoint restore.'
        }
        $hardDrives = @()
    }
    if ($RequireOfflineDiskIdentity -and
        ([string]$Vm.State -ne 'Off' -or $hardDrives.Count -lt 1)) {
        Throw-HcrError 'RESTORE_DISK_IDENTITY_UNAVAILABLE' 'Checkpoint restore requires an Off VM with a readable attached disk inventory.'
    }
    $hardDrive = @($hardDrives | Select-Object -First 1)
    $currentStateDisks = @($hardDrives | ForEach-Object {
        $drive = $_
        $path = [string]$drive.Path
        $fileLength = $null
        $lastWriteUtc = $null
        try {
            if ([string]::IsNullOrWhiteSpace($path)) {
                throw 'The attached disk path is empty.'
            }
            $file = Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if ($file.PSIsContainer -or
                ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'The attached disk is not an ordinary file.'
            }
            $fileLength = [int64]$file.Length
            $lastWriteUtc = $file.LastWriteTimeUtc.ToString('o')
        }
        catch {
            if ($RequireOfflineDiskIdentity) {
                Throw-HcrError 'RESTORE_DISK_IDENTITY_UNAVAILABLE' 'An attached VHDX file identity is unavailable for checkpoint restore.'
            }
        }
        $vhd = $null
        try { $vhd = Get-VHD -Path $path -ErrorAction Stop }
        catch {
            if ($RequireOfflineDiskIdentity) {
                Throw-HcrError 'RESTORE_DISK_IDENTITY_UNAVAILABLE' 'Hyper-V VHD identity is unavailable for checkpoint restore.'
            }
            $vhd = $null
        }
        if ($RequireOfflineDiskIdentity -and (
            $null -eq $vhd -or
            [string]::IsNullOrWhiteSpace([string](Get-HcrPropertyValue $vhd 'DiskIdentifier')) -or
            $null -eq (Get-HcrPropertyValue $vhd 'Size') -or
            $null -eq (Get-HcrPropertyValue $vhd 'FileSize')
        )) {
            Throw-HcrError 'RESTORE_DISK_IDENTITY_UNAVAILABLE' 'The attached VHDX identity is incomplete for checkpoint restore.'
        }
        [ordered]@{
            controllerType = [string]$drive.ControllerType
            controllerNumber = [int]$drive.ControllerNumber
            controllerLocation = [int]$drive.ControllerLocation
            path = $path
            fileLength = $fileLength
            lastWriteUtc = $lastWriteUtc
            diskIdentifier = if ($null -eq $vhd) { $null } else { [string](Get-HcrPropertyValue $vhd 'DiskIdentifier') }
            virtualSize = if ($null -eq $vhd) { $null } else { Get-HcrPropertyValue $vhd 'Size' }
            physicalFileSize = if ($null -eq $vhd) { $null } else { Get-HcrPropertyValue $vhd 'FileSize' }
            parentPath = if ($null -eq $vhd) { $null } else { [string](Get-HcrPropertyValue $vhd 'ParentPath') }
        }
    } | Sort-Object controllerType, controllerNumber, controllerLocation, path)
    $network = @(Get-VMNetworkAdapter -VM $Vm -ErrorAction SilentlyContinue)
    $networkAdapters = @($network | ForEach-Object {
        $adapter = $_
        $switchId = [string](Get-HcrPropertyValue $adapter 'SwitchId')
        $switchName = [string](Get-HcrPropertyValue $adapter 'SwitchName')
        $switchType = $null
        if (-not [string]::IsNullOrWhiteSpace($switchId)) {
            try {
                $switchObject = @(Get-VMSwitch -Id ([Guid]$switchId) -ErrorAction Stop |
                    Select-Object -First 1)
                if ($switchObject.Count -eq 1) {
                    $switchName = [string]$switchObject[0].Name
                    $switchType = [string]$switchObject[0].SwitchType
                }
            }
            catch { $switchType = $null }
        }
        [pscustomobject][ordered]@{
            id = [string](Get-HcrPropertyValue $adapter 'Id')
            name = [string](Get-HcrPropertyValue $adapter 'Name')
            macAddress = ([string](Get-HcrPropertyValue $adapter 'MacAddress')).Replace('-', '').ToUpperInvariant()
            switchId = if ([string]::IsNullOrWhiteSpace($switchId)) { $null } else { $switchId }
            switchName = if ([string]::IsNullOrWhiteSpace($switchName)) { $null } else { $switchName }
            switchType = $switchType
        }
    })
    if ($PSBoundParameters.ContainsKey('CheckpointInventory')) {
        $checkpointObjects = @($CheckpointInventory)
    }
    else {
        try { $checkpointObjects = @(Get-VMSnapshot -VM $Vm -ErrorAction Stop) }
        catch {
            if ($RequireOfflineDiskIdentity) {
                Throw-HcrError 'RESTORE_CHECKPOINT_INVENTORY_UNAVAILABLE' 'The checkpoint inventory is unavailable for checkpoint restore.'
            }
            $checkpointObjects = @()
        }
    }
    $checkpoints = @($checkpointObjects | ForEach-Object {
        [pscustomobject][ordered]@{
            id = [string]$_.Id
            name = [string]$_.Name
            parentId = if ($null -eq $_.ParentSnapshotId) { $null } else { [string]$_.ParentSnapshotId }
            configurationFingerprint = Get-HcrSha256Text "$($_.Id)|$($_.CreationTime.ToUniversalTime().ToString('o'))"
            createdAt = $_.CreationTime.ToUniversalTime().ToString('o')
        }
    })
    $firmware = $null
    try { $firmware = Get-VMFirmware -VM $Vm -ErrorAction Stop } catch { $firmware = $null }
    $security = $null
    try { $security = Get-VMSecurity -VM $Vm -ErrorAction Stop } catch { $security = $null }
    return [pscustomobject][ordered]@{
        id = [string]$Vm.Id
        name = [string]$Vm.Name
        state = [string]$Vm.State
        generation = [int]$Vm.Generation
        notes = [string]$Vm.Notes
        vmPath = [string]$Vm.Path
        vhdxPath = if ($hardDrive.Count -eq 0) { $null } else { [string]$hardDrive[0].Path }
        processorCount = [int]$Vm.ProcessorCount
        startupMemoryGb = [int][Math]::Round([double]$Vm.MemoryStartup / 1GB)
        maximumMemoryGb = [int][Math]::Round([double]$Vm.MemoryMaximum / 1GB)
        diskSizeGb = $null
        switchName = if ($network.Count -eq 0) { $null } else { [string]$network[0].SwitchName }
        switchId = if ($network.Count -eq 0) { $null } else { [string]$network[0].SwitchId }
        networkAdapters = $networkAdapters
        secureBoot = if ($null -eq $firmware) { $false } else { [string]$firmware.SecureBoot -eq 'On' }
        vtpm = if ($null -eq $security) { $false } else { [bool]$security.TpmEnabled }
        checkpoints = $checkpoints
        currentStateNonce = Get-HcrSha256Text (ConvertTo-HcrJson ([ordered]@{
            vmId = [string]$Vm.Id
            state = [string]$Vm.State
            status = [string]$Vm.Status
            disks = $currentStateDisks
        }) 30)
    }
}

function Get-HcrRealHostSnapshot {
    $computerSystem = $null
    $operatingSystem = $null
    try { $computerSystem = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop } catch { $computerSystem = $null }
    try { $operatingSystem = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch { $operatingSystem = $null }
    $hypervAvailable = $null -ne (Get-Command Get-VM -ErrorAction SilentlyContinue)
    $switches = @()
    if ($hypervAvailable) {
        try {
            $switches = @(Get-VMSwitch -ErrorAction Stop | ForEach-Object {
                [pscustomobject][ordered]@{
                    id = [string]$_.Id
                    name = [string]$_.Name
                    type = [string]$_.SwitchType
                }
            })
        }
        catch { $switches = @() }
    }
    return [pscustomobject][ordered]@{
        computerName = [Environment]::MachineName
        windowsEdition = if ($null -eq $operatingSystem) { [Environment]::OSVersion.VersionString } else { [string]$operatingSystem.Caption }
        windowsBuild = if ($null -eq $operatingSystem) { [Environment]::OSVersion.Version.Build.ToString() } else { [string]$operatingSystem.BuildNumber }
        architecture = [string]$env:PROCESSOR_ARCHITECTURE
        hyperVCommandsAvailable = $hypervAvailable
        hypervisorPresent = if ($null -eq $computerSystem) { $false } else { [bool]$computerSystem.HypervisorPresent }
        elevated = Test-HcrCurrentProcessElevated
        processorCount = [Environment]::ProcessorCount
        memoryBytes = if ($null -eq $computerSystem) { 0 } else { [int64]$computerSystem.TotalPhysicalMemory }
        switches = $switches
    }
}

function Get-HcrCredentialBundle {
    param(
        [Parameter(Mandatory = $true)][string]$ProfileName,
        [Parameter(Mandatory = $true)][string]$VmName
    )

    if ($ProfileName -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}$') {
        Throw-HcrError 'CREDENTIAL_PROFILE_INVALID' 'The credential profile name is invalid.'
    }
    $root = Get-HcrCredentialRoot
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        Throw-HcrError 'CREDENTIAL_PROFILE_NOT_FOUND' 'The credential root does not exist.'
    }
    [void](Assert-HcrLocalDirectory $root 'CREDENTIAL_PROFILE_INVALID')
    $directory = Get-HcrNormalizedPath (Join-Path $root $ProfileName)
    if (-not (Test-HcrPathWithin $directory $root) -or
        -not (Test-Path -LiteralPath $directory -PathType Container)) {
        Throw-HcrError 'CREDENTIAL_PROFILE_NOT_FOUND' 'The named credential profile does not exist.'
    }
    [void](Assert-HcrLocalDirectory $directory 'CREDENTIAL_PROFILE_INVALID')
    $metadataPath = Join-Path $directory 'profile.json'
    $adminPath = Join-Path $directory 'orchestration-admin.clixml'
    $userPath = Join-Path $directory 'standard-test-user.clixml'
    $metadata = Read-HcrJsonFile $metadataPath 'CREDENTIAL_PROFILE_INVALID'
    if ((Get-HcrPropertyValue $metadata 'vmName') -ne $VmName) {
        Throw-HcrError 'CREDENTIAL_PROFILE_VM_MISMATCH' 'The credential profile is bound to another VM.'
    }
    foreach ($path in @($adminPath, $userPath)) {
        $item = Assert-HcrRegularLocalFile $path 'CREDENTIAL_PROFILE_INVALID'
        if ($item.Length -lt 1 -or $item.Length -gt 1MB) {
            Throw-HcrError 'CREDENTIAL_PROFILE_INVALID' 'A credential bundle component is outside its size bound.'
        }
    }
    try {
        $administrator = Import-Clixml -LiteralPath $adminPath -ErrorAction Stop
        $testUser = Import-Clixml -LiteralPath $userPath -ErrorAction Stop
    }
    catch {
        Throw-HcrError 'CREDENTIAL_PROFILE_UNREADABLE' 'The DPAPI credential bundle cannot be opened by this user on this machine.'
    }
    if ($administrator -isnot [pscredential] -or $testUser -isnot [pscredential]) {
        Throw-HcrError 'CREDENTIAL_PROFILE_INVALID' 'The credential bundle has an invalid type.'
    }
    return [pscustomobject][ordered]@{
        metadata = $metadata
        administrator = $administrator
        testUser = $testUser
    }
}

function Assert-HcrGuestOperationId {
    param([Parameter(Mandatory = $true)][string]$OperationId)

    $parsed = [Guid]::Empty
    if (-not [Guid]::TryParse($OperationId, [ref]$parsed) -or
        $parsed.ToString() -ne $OperationId.ToLowerInvariant()) {
        Throw-HcrError 'GUEST_OPERATION_INVALID' 'A canonical operation ID is required for guest work.'
    }
}

function Assert-HcrRealGuestStepContract {
    param(
        [Parameter(Mandatory = $true)][object]$Arguments,
        [bool]$Cleanup
    )

    $operationId = [string](Get-HcrPropertyValue $Arguments 'operationId')
    Assert-HcrGuestOperationId $operationId
    $step = Get-HcrPropertyValue $Arguments 'step'
    if ($null -eq $step) {
        Throw-HcrError 'GUEST_STEP_INVALID' 'A declarative guest step is required.'
    }
    $schemaVersion = [int](Get-HcrPropertyValue $Arguments 'schemaVersion' 1)
    if (@(1, 2) -notcontains $schemaVersion) {
        Throw-HcrError 'GUEST_STEP_VERSION_UNSUPPORTED' 'The production guest adapter rejected the step schema version.'
    }
    $type = [string](Get-HcrPropertyValue $step 'type')
    $allowedTypes = if ($schemaVersion -eq 2) {
        if ($Cleanup) { $script:HcrV2CleanupStepTypes } else {
            @($script:HcrV2ActionStepTypes + $script:HcrV2AssertionStepTypes) |
                Where-Object { $_ -ne 'stageArtifact' }
        }
    }
    elseif ($Cleanup) { $script:HcrCleanupStepTypes } else {
        @($script:HcrActionStepTypes + $script:HcrAssertionStepTypes) |
            Where-Object { $_ -ne 'stageArtifact' }
    }
    if ($allowedTypes -notcontains $type) {
        Throw-HcrError 'GUEST_STEP_TYPE_FORBIDDEN' 'The production guest adapter rejected the step type.'
    }
    $allowedStepProperties = @(
        'id', 'type', 'application', 'timeoutSeconds', 'path', 'registryPath',
        'registryName', 'expected', 'processName', 'moduleRelativePath', 'port',
        'sentinelId', 'required', 'testId', 'text', 'key', 'value',
        'fixtureId', 'state', 'evidenceName'
    )
    foreach ($property in @($step.PSObject.Properties)) {
        if ($allowedStepProperties -notcontains $property.Name) {
            Throw-HcrError 'GUEST_STEP_FIELD_FORBIDDEN' 'The production guest adapter rejected an unknown step field.'
        }
    }
    foreach ($application in @((Get-HcrPropertyValue $Arguments 'applications' @()))) {
        foreach ($property in @($application.PSObject.Properties)) {
            $allowedApplicationProperties = if ($schemaVersion -eq 2) {
                @('id', 'packageKind', 'installMode', 'executableRelativePath',
                    'uninstallerDiscovery', 'dataDirectoryRelativePath', 'processName')
            }
            else {
                @('id', 'installerType', 'installMode', 'executableRelativePath',
                    'uninstallerDiscovery', 'processName')
            }
            if ($allowedApplicationProperties -notcontains $property.Name) {
                Throw-HcrError 'GUEST_APPLICATION_FIELD_FORBIDDEN' 'The production guest adapter rejected an unknown application field.'
            }
        }
        if ($schemaVersion -eq 1 -and (Get-HcrPropertyValue $application 'installMode') -ne 'currentUser') {
            Throw-HcrError 'GUEST_INSTALL_MODE_FORBIDDEN' 'Only the fixed current-user install mode is supported.'
        }
        if ($schemaVersion -eq 2 -and
            @('nsis', 'msi', 'portableZip') -notcontains (Get-HcrPropertyValue $application 'packageKind')) {
            Throw-HcrError 'GUEST_PACKAGE_KIND_FORBIDDEN' 'The schema-v2 package kind is unsupported.'
        }
    }
}

function New-HcrRealGuestContext {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $vmName = [string](Get-HcrPropertyValue $Arguments 'vmName')
    $profileName = [string](Get-HcrPropertyValue $Arguments 'profileName')
    $operationId = [string](Get-HcrPropertyValue $Arguments 'operationId')
    Assert-HcrGuestOperationId $operationId
    $verifiedVm = Assert-HcrRealDispatchVm $Arguments
    $bundle = Get-HcrCredentialBundle $profileName $vmName
    $metadata = $bundle.metadata
    $administratorSid = [string](Get-HcrPropertyValue $metadata 'administratorSid')
    $testUserSid = [string](Get-HcrPropertyValue $metadata 'testUserSid')
    if ((Get-HcrPropertyValue $metadata 'schemaVersion') -ne 1 -or
        (Get-HcrPropertyValue $metadata 'profileName') -ne $profileName -or
        (Get-HcrPropertyValue $metadata 'vmName') -ne $vmName -or
        $administratorSid -notmatch '^S-1-[0-9-]{3,}$' -or
        $testUserSid -notmatch '^S-1-[0-9-]{3,}$' -or
        $administratorSid -eq $testUserSid) {
        Throw-HcrError 'CREDENTIAL_PROFILE_INVALID' 'The credential profile role metadata is invalid.'
    }
    $timeoutSeconds = [int](Get-HcrPropertyValue $Arguments 'timeoutSeconds' 60)
    if ($timeoutSeconds -lt 1 -or $timeoutSeconds -gt 900) {
        Throw-HcrError 'GUEST_OPERATION_TIMEOUT_INVALID' 'The supervised guest timeout is outside the fixed bounds.'
    }
    $deadlineUtc = [DateTimeOffset]::UtcNow.AddSeconds($timeoutSeconds)
    $declaredDeadline = [string](Get-HcrPropertyValue $Arguments 'deadlineUtc')
    if (-not [string]::IsNullOrWhiteSpace($declaredDeadline)) {
        $parsedDeadline = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse(
            $declaredDeadline,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$parsedDeadline
        )) {
            Throw-HcrError 'GUEST_OPERATION_TIMEOUT_INVALID' 'The supervised guest deadline is invalid.'
        }
        if ($parsedDeadline -lt $deadlineUtc) { $deadlineUtc = $parsedDeadline }
    }
    $session = $null
    $previousOption = Get-Variable -Name PSSessionOption -Scope Local -ErrorAction SilentlyContinue
    try {
        $scriptOption = New-PSSessionOption `
            -OpenTimeout ([Math]::Max(1000, $timeoutSeconds * 1000)) `
            -OperationTimeout ([Math]::Max(1000, $timeoutSeconds * 1000)) `
            -CancelTimeout 5000
        Set-Variable -Name PSSessionOption -Scope Local -Value $scriptOption
        $session = New-PSSession `
            -VMId ([Guid]([string](Get-HcrPropertyValue $verifiedVm 'Id'))) `
            -Credential $bundle.administrator `
            -ErrorAction Stop
    }
    catch {
        Throw-HcrError 'POWERSHELL_DIRECT_UNAVAILABLE' 'The orchestration administrator could not open the supervised PowerShell Direct session.'
    }
    finally {
        if ($null -eq $previousOption) {
            Remove-Variable -Name PSSessionOption -Scope Local -ErrorAction SilentlyContinue
        }
        else {
            Set-Variable -Name PSSessionOption -Scope Local -Value $previousOption.Value
        }
    }
    try {
        $administratorProbe = Invoke-Command -Session $session -ScriptBlock {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object Security.Principal.WindowsPrincipal($identity)
            $groups = @($identity.Groups | ForEach-Object { [string]$_.Value })
            $integrity = if ($groups -contains 'S-1-16-16384') { 'system' }
                elseif ($groups -contains 'S-1-16-12288') { 'high' }
                elseif ($groups -contains 'S-1-16-8448') { 'mediumPlus' }
                elseif ($groups -contains 'S-1-16-8192') { 'medium' }
                elseif ($groups -contains 'S-1-16-4096') { 'low' }
                else { 'unknown' }
            return [pscustomobject]@{
                sid = [string]$identity.User.Value
                hasAdministratorsSid = $groups -contains 'S-1-5-32-544'
                isAdministrator = $principal.IsInRole(
                    [Security.Principal.WindowsBuiltInRole]::Administrator
                )
                tokenIntegrity = $integrity
            }
        } -ErrorAction Stop
        if ([string](Get-HcrPropertyValue $administratorProbe 'sid') -ne $administratorSid -or
            -not [bool](Get-HcrPropertyValue $administratorProbe 'hasAdministratorsSid' $false) -or
            -not [bool](Get-HcrPropertyValue $administratorProbe 'isAdministrator' $false) -or
            @('high', 'system') -notcontains [string](Get-HcrPropertyValue $administratorProbe 'tokenIntegrity')) {
            Throw-HcrError 'GUEST_ADMINISTRATOR_IDENTITY_DRIFT' 'The PowerShell Direct supervisor no longer matches the enrolled administrator role.'
        }
    }
    catch {
        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
        if ($_.Exception.Data.Contains('HcrCode')) { throw }
        Throw-HcrError 'GUEST_ADMINISTRATOR_IDENTITY_DRIFT' 'The PowerShell Direct administrator identity could not be revalidated.'
    }
    if (([DateTimeOffset]::UtcNow -ge $deadlineUtc)) {
        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
        Throw-HcrError 'GUEST_OPERATION_TIMEOUT' 'Guest session setup exhausted the end-to-end deadline.'
    }
    return [pscustomobject][ordered]@{
        operationId = $operationId
        vmName = $vmName
        profileName = $profileName
        metadata = $metadata
        administrator = $bundle.administrator
        testUser = $bundle.testUser
        session = $session
        workspace = $null
        deadlineUtc = $deadlineUtc
        verifiedVmId = [string](Get-HcrPropertyValue $verifiedVm 'Id')
    }
}

function Close-HcrRealGuestContext {
    param([AllowNull()][object]$Context)

    if ($null -ne $Context -and $null -ne (Get-HcrPropertyValue $Context 'session')) {
        Remove-PSSession -Session $Context.session -ErrorAction SilentlyContinue
    }
}

$script:HcrInitializeGuestWorkspaceScript = {
    param(
        [string]$OperationId,
        [string]$TestUserSid,
        [AllowNull()][string]$CommonRootOverride
    )

    function New-ProtectedWorkspaceAcl {
        param(
            [Parameter(Mandatory = $true)][Security.Principal.SecurityIdentifier]$TestSid,
            [Parameter(Mandatory = $true)][bool]$AllowTestRead,
            [bool]$IncludeOwner = $false
        )

        $administratorSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $systemSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
        $administratorsSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
        $fullControlSids = @($administratorSid, $systemSid, $administratorsSid)
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)
        if ($IncludeOwner) { $acl.SetOwner($administratorSid) }
        foreach ($sid in $fullControlSids) {
            $rule = New-Object Security.AccessControl.FileSystemAccessRule(
                $sid,
                [Security.AccessControl.FileSystemRights]::FullControl,
                [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
                [Security.AccessControl.PropagationFlags]::None,
                [Security.AccessControl.AccessControlType]::Allow
            )
            [void]$acl.AddAccessRule($rule)
        }
        if ($AllowTestRead) {
            $testRule = New-Object Security.AccessControl.FileSystemAccessRule(
                $TestSid,
                [Security.AccessControl.FileSystemRights]::ReadAndExecute,
                [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
                [Security.AccessControl.PropagationFlags]::None,
                [Security.AccessControl.AccessControlType]::Allow
            )
            [void]$acl.AddAccessRule($testRule)
        }
        return $acl
    }

    function Assert-ProtectedWorkspaceAcl {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][Security.Principal.SecurityIdentifier]$TestSid,
            [Parameter(Mandatory = $true)][bool]$AllowTestRead
        )

        $administratorSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $systemSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
        $administratorsSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
        $fullControlSids = @($administratorSid, $systemSid, $administratorsSid)
        $readback = Get-Acl -LiteralPath $Path -ErrorAction Stop
        if (-not $readback.AreAccessRulesProtected) {
            throw 'A supervised workspace ACL still inherits parent permissions.'
        }
        $ownerSid = $readback.GetOwner(
            [Security.Principal.SecurityIdentifier]
        )
        if ([string]$ownerSid.Value -ne [string]$administratorSid.Value) {
            throw 'A supervised workspace owner is not the live administrator.'
        }
        $allowedSids = @($fullControlSids | ForEach-Object { $_.Value })
        if ($AllowTestRead) { $allowedSids += $TestSid.Value }
        $testRuleCount = 0
        $fullControlFound = @{}
        foreach ($sid in $fullControlSids) { $fullControlFound[$sid.Value] = 0 }
        $expectedInheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
            [Security.AccessControl.InheritanceFlags]::ObjectInherit
        $expectedPropagation = [Security.AccessControl.PropagationFlags]::None
        $expectedTestRights = [Security.AccessControl.FileSystemRights]::ReadAndExecute -bor
            [Security.AccessControl.FileSystemRights]::Synchronize
        $writeCapableMask = [Security.AccessControl.FileSystemRights]::WriteData -bor
            [Security.AccessControl.FileSystemRights]::AppendData -bor
            [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
            [Security.AccessControl.FileSystemRights]::WriteAttributes -bor
            [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
            [Security.AccessControl.FileSystemRights]::Delete -bor
            [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
            [Security.AccessControl.FileSystemRights]::TakeOwnership
        $rules = @($readback.GetAccessRules(
            $true,
            $true,
            [Security.Principal.SecurityIdentifier]
        ))
        foreach ($rule in $rules) {
            $ruleSid = [string]$rule.IdentityReference.Value
            if ($rule.IsInherited -or
                $rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or
                $allowedSids -notcontains $ruleSid) {
                throw 'A supervised workspace ACL contains an unexpected access rule.'
            }
            if ($rule.InheritanceFlags -ne $expectedInheritance -or
                $rule.PropagationFlags -ne $expectedPropagation) {
                throw 'A supervised workspace ACL contains a non-canonical access rule.'
            }
            if ($ruleSid -eq $TestSid.Value) {
                $testRuleCount++
                if ($rule.FileSystemRights -ne $expectedTestRights -or
                    ($rule.FileSystemRights -band $writeCapableMask) -ne 0) {
                    throw 'The standard test-user workspace permission is not the exact read/execute grant.'
                }
            }
            else {
                $fullControlFound[$ruleSid] = [int]$fullControlFound[$ruleSid] + 1
                if ($rule.FileSystemRights -ne
                    [Security.AccessControl.FileSystemRights]::FullControl) {
                    throw 'A privileged workspace principal lacks full control.'
                }
            }
        }
        $expectedTestRuleCount = if ($AllowTestRead) { 1 } else { 0 }
        if ($testRuleCount -ne $expectedTestRuleCount) {
            throw 'The standard test-user workspace ACL did not match the explicit policy.'
        }
        foreach ($sid in $fullControlSids) {
            if ([int]$fullControlFound[$sid.Value] -ne 1) {
                throw 'A privileged workspace ACL is missing or duplicated.'
            }
        }
    }

    function Set-ProtectedWorkspaceAcl {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][Security.Principal.SecurityIdentifier]$TestSid,
            [Parameter(Mandatory = $true)][bool]$AllowTestRead
        )

        try {
            Assert-ProtectedWorkspaceAcl $Path $TestSid $AllowTestRead
            return
        }
        catch {
            # Existing or concurrently pre-created paths must be replaced with
            # the exact policy. Newly created paths normally pass above and do
            # not require a second security-descriptor write.
        }
        # Rebind both ownership and the DACL for a pre-existing or raced-in
        # directory. Readback below proves that the live administrator became
        # owner; merely rejecting the old owner is not sufficient.
        $acl = New-ProtectedWorkspaceAcl $TestSid $AllowTestRead $true
        Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
        Assert-ProtectedWorkspaceAcl $Path $TestSid $AllowTestRead
    }

    $commonRoot = if ([string]::IsNullOrWhiteSpace($CommonRootOverride)) {
        [Environment]::GetFolderPath('CommonApplicationData')
    }
    else { [IO.Path]::GetFullPath($CommonRootOverride) }
    $commonItem = Get-Item -LiteralPath $commonRoot -Force -ErrorAction Stop
    if (-not $commonItem.PSIsContainer -or
        ($commonItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'The common application-data root is not an ordinary directory.'
    }
    $testSid = New-Object Security.Principal.SecurityIdentifier($TestUserSid)
    $current = $commonRoot
    foreach ($segment in @('Codex', 'hyperv-clean-room', 'v1', 'operations')) {
        $current = Join-Path $current $segment
        if (-not (Test-Path -LiteralPath $current)) {
            try {
                # Directory.CreateDirectory applies the protected descriptor as
                # part of creation; a writable parent never exposes a newly
                # created plugin ancestor with inherited test-user authority.
                [void][IO.Directory]::CreateDirectory(
                    $current,
                    (New-ProtectedWorkspaceAcl $testSid $false $true)
                )
            }
            catch {
                if (-not (Test-Path -LiteralPath $current -PathType Container)) { throw }
            }
        }
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (-not $item.PSIsContainer -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'A supervised guest workspace ancestor is not an ordinary directory.'
        }
        Set-ProtectedWorkspaceAcl $current $testSid $false
    }
    $base = $current
    $operationRoot = Join-Path $base $OperationId
    $controlRoot = Join-Path $operationRoot 'control'
    $outputRoot = Join-Path $operationRoot 'output'
    $stagingRoot = Join-Path $operationRoot 'staging'
    foreach ($path in @($operationRoot, $controlRoot, $outputRoot, $stagingRoot)) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            try {
                [void][IO.Directory]::CreateDirectory(
                    $path,
                    (New-ProtectedWorkspaceAcl $testSid $true $true)
                )
            }
            catch {
                if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw }
            }
        }
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if (-not $item.PSIsContainer -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'A supervised guest workspace path is not an ordinary directory.'
        }
        Set-ProtectedWorkspaceAcl $path $testSid $true
    }
    return [pscustomobject][ordered]@{
        operationRoot = $operationRoot
        controlRoot = $controlRoot
        outputRoot = $outputRoot
        stagingRoot = $stagingRoot
    }
}

function Initialize-HcrRealGuestWorkspace {
    param([Parameter(Mandatory = $true)][object]$Context)

    if ($null -ne (Get-HcrPropertyValue $Context 'workspace')) {
        return $Context.workspace
    }
    [void](Get-HcrRealGuestRemainingSeconds $Context)
    try {
        $workspace = Invoke-Command `
            -Session $Context.session `
            -ArgumentList $Context.operationId, ([string](Get-HcrPropertyValue $Context.metadata 'testUserSid')), $null `
            -ScriptBlock $script:HcrInitializeGuestWorkspaceScript `
            -ErrorAction Stop
    }
    catch {
        Throw-HcrError 'GUEST_WORKSPACE_FAILED' 'The administrator could not create the fixed operation-scoped guest workspace.'
    }
    [void](Get-HcrRealGuestRemainingSeconds $Context)
    $Context.workspace = $workspace
    return $workspace
}

function Install-HcrFixedGuestWorker {
    param([Parameter(Mandatory = $true)][object]$Context)

    [void](Get-HcrRealGuestRemainingSeconds $Context)
    $workspace = Initialize-HcrRealGuestWorkspace $Context
    $source = Assert-HcrRegularLocalFile `
        (Join-Path (Join-Path (Join-Path $script:HcrPluginRoot 'mcp') 'lib') 'GuestWorker.ps1') `
        'GUEST_WORKER_INVALID'
    $sourceHash = Get-HcrSha256File $source.FullName
    $guestPath = Join-Path ([string](Get-HcrPropertyValue $workspace 'controlRoot')) 'GuestWorker.ps1'
    try {
        $existingHash = Invoke-Command -Session $Context.session -ArgumentList $guestPath -ScriptBlock {
            param([string]$Path)
            if (-not (Test-Path -LiteralPath $Path)) { return $null }
            $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
            if ($item.PSIsContainer -or
                ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'The existing fixed-worker destination is not an ordinary file.'
            }
            return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        } -ErrorAction Stop
        if ($null -ne $existingHash -and $existingHash -ne $sourceHash) {
            throw 'The existing fixed-worker destination has an unexpected hash.'
        }
        if ($null -eq $existingHash) {
            Copy-Item `
                -LiteralPath $source.FullName `
                -Destination $guestPath `
                -ToSession $Context.session `
                -ErrorAction Stop
        }
        $guestHash = Invoke-Command -Session $Context.session -ArgumentList $guestPath -ScriptBlock {
            param([string]$Path)
            $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'The copied worker is a reparse point.'
            }
            return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        } -ErrorAction Stop
    }
    catch {
        Throw-HcrError 'GUEST_WORKER_TRANSFER_FAILED' 'The fixed plugin-owned guest worker could not be staged.'
    }
    if ($guestHash -ne $sourceHash) {
        Throw-HcrError 'GUEST_WORKER_HASH_MISMATCH' 'The fixed guest worker hash changed during transfer.'
    }
    [void](Get-HcrRealGuestRemainingSeconds $Context)
    return $guestPath
}

function Invoke-HcrFixedGuestWorker {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)]
        [ValidateSet('InspectGuest', 'RunTestStep', 'RunCleanupStep')]
        [string]$Mode,
        [Parameter(Mandatory = $true)][object]$Input,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    [void](Get-HcrRealGuestRemainingSeconds $Context)
    $workspace = Initialize-HcrRealGuestWorkspace $Context
    $workerPath = Install-HcrFixedGuestWorker $Context
    $invocationId = [Guid]::NewGuid().ToString('N')
    $inputPath = Join-Path ([string](Get-HcrPropertyValue $workspace 'controlRoot')) "input-$invocationId.json"
    $boundInput = Copy-HcrObject $Input
    $boundInput | Add-Member -NotePropertyName invocationId -NotePropertyValue $invocationId -Force
    $boundInput | Add-Member -NotePropertyName mode -NotePropertyValue $Mode -Force
    $inputJson = ConvertTo-HcrJson $boundInput 50
    $expectedWorkerSchemaVersion = [int](Get-HcrPropertyValue $boundInput 'schemaVersion' 0)
    if (@(1, 2) -notcontains $expectedWorkerSchemaVersion) {
        Throw-HcrError 'GUEST_WORKER_INPUT_INVALID' 'The fixed-worker schema version is unsupported.'
    }
    if ([Text.Encoding]::UTF8.GetByteCount($inputJson) -gt 1048576) {
        Throw-HcrError 'GUEST_WORKER_INPUT_TOO_LARGE' 'The bounded fixed-worker input exceeds one MiB.'
    }
    $inputHash = Get-HcrSha256Text ($inputJson + "`n")
    try {
        [void](Invoke-Command -Session $Context.session -ArgumentList $inputPath, $inputJson -ScriptBlock {
            param([string]$Path, [string]$Json)
            $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($Json + "`n")
            $stream = [IO.File]::Open(
                $Path,
                [IO.FileMode]::CreateNew,
                [IO.FileAccess]::Write,
                [IO.FileShare]::None
            )
            try { $stream.Write($bytes, 0, $bytes.Length) }
            finally { $stream.Dispose() }
        } -ErrorAction Stop)
        # Workspace setup and transfer consume the operation deadline. Recompute
        # the launch budget at the last possible boundary before process creation.
        $launchTimeoutSeconds = [Math]::Min(
            $TimeoutSeconds,
            (Get-HcrRealGuestRemainingSeconds $Context)
        )
        $absoluteDeadline = ([DateTimeOffset](Get-HcrPropertyValue $Context 'deadlineUtc')).ToString('o')
        $supervision = Invoke-Command `
            -Session $Context.session `
            -ArgumentList $Context.testUser, $workerPath, $Mode, $inputPath, $Context.operationId, $invocationId, $inputHash, $launchTimeoutSeconds, $absoluteDeadline, $expectedWorkerSchemaVersion `
            -ScriptBlock {
                param(
                    [pscredential]$StandardUser,
                    [string]$WorkerPath,
                    [string]$WorkerMode,
                    [string]$InputPath,
                    [string]$OperationId,
                    [string]$InvocationId,
                    [string]$InputSha256,
                    [int]$TimeoutSeconds,
                    [string]$AbsoluteDeadline,
                    [int]$ExpectedWorkerSchemaVersion
                )
                if (-not ('Hcr.SupervisedProcess' -as [type])) {
                    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security;
using System.Text;
using Microsoft.Win32.SafeHandles;
namespace Hcr {
    public sealed class SupervisedProcess : IDisposable {
        [StructLayout(LayoutKind.Sequential)]
        private struct SecurityAttributes {
            public int Length;
            public IntPtr SecurityDescriptor;
            [MarshalAs(UnmanagedType.Bool)] public bool InheritHandle;
        }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct StartupInfo {
            public int Cb;
            public string Reserved;
            public string Desktop;
            public string Title;
            public int X;
            public int Y;
            public int XSize;
            public int YSize;
            public int XCountChars;
            public int YCountChars;
            public int FillAttribute;
            public int Flags;
            public short ShowWindow;
            public short Reserved2;
            public IntPtr Reserved2Pointer;
            public IntPtr StandardInput;
            public IntPtr StandardOutput;
            public IntPtr StandardError;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct ProcessInformation {
            public IntPtr Process;
            public IntPtr Thread;
            public int ProcessId;
            public int ThreadId;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct BasicAccounting {
            public long TotalUserTime;
            public long TotalKernelTime;
            public long ThisPeriodTotalUserTime;
            public long ThisPeriodTotalKernelTime;
            public uint TotalPageFaultCount;
            public uint TotalProcesses;
            public uint ActiveProcesses;
            public uint TotalTerminatedProcesses;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct FileTime {
            public uint Low;
            public uint High;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct BasicLimitInformation {
            public long PerProcessUserTimeLimit;
            public long PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass;
            public uint SchedulingClass;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct IoCounters {
            public ulong ReadOperationCount;
            public ulong WriteOperationCount;
            public ulong OtherOperationCount;
            public ulong ReadTransferCount;
            public ulong WriteTransferCount;
            public ulong OtherTransferCount;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct ExtendedLimitInformation {
            public BasicLimitInformation BasicLimitInformation;
            public IoCounters IoInfo;
            public UIntPtr ProcessMemoryLimit;
            public UIntPtr JobMemoryLimit;
            public UIntPtr PeakProcessMemoryUsed;
            public UIntPtr PeakJobMemoryUsed;
        }
        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreateProcessWithLogonW(
            string userName, string domain,
            [MarshalAs(UnmanagedType.LPWStr)] SecureString password,
            uint logonFlags, string applicationName, StringBuilder commandLine,
            uint creationFlags, IntPtr environment, string currentDirectory,
            ref StartupInfo startupInfo, out ProcessInformation processInformation);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreatePipe(
            out IntPtr readPipe, out IntPtr writePipe,
            ref SecurityAttributes attributes, int size);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetHandleInformation(IntPtr handle, uint mask, uint flags);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateJobObject(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool TerminateJobObject(IntPtr job, uint exitCode);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool QueryInformationJobObject(
            IntPtr job, int infoClass, out BasicAccounting info, int length, IntPtr returnedLength);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetInformationJobObject(
            IntPtr job, int infoClass, ref ExtendedLimitInformation info, int length);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint ResumeThread(IntPtr thread);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetExitCodeProcess(IntPtr process, out uint exitCode);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool TerminateProcess(IntPtr process, uint exitCode);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(uint access, bool inheritHandle, int processId);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsProcessInJob(IntPtr process, IntPtr job, out bool result);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetProcessTimes(
            IntPtr process, out FileTime creation, out FileTime exit,
            out FileTime kernel, out FileTime user);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool QueryFullProcessImageName(
            IntPtr process, int flags, StringBuilder path, ref int size);
        [DllImport("ntdll.dll")]
        private static extern int NtSuspendProcess(IntPtr process);
        [DllImport("ntdll.dll")]
        private static extern int NtResumeProcess(IntPtr process);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);

        private const uint LogonWithProfile = 0x00000001;
        private const uint CreateSuspended = 0x00000004;
        private const uint CreateNoWindow = 0x08000000;
        private const uint HandleFlagInherit = 0x00000001;
        private const uint JobObjectLimitKillOnClose = 0x00002000;
        private const uint ProcessQueryLimitedInformation = 0x00001000;
        private const uint ProcessSuspendResume = 0x00000800;
        private const uint Synchronize = 0x00100000;
        private const uint WaitObject0 = 0x00000000;
        private const uint WaitTimeout = 0x00000102;
        private const uint WaitFailed = 0xFFFFFFFF;
        private const uint StillActive = 259;
        private const int StartfUseStdHandles = 0x00000100;

        private IntPtr processHandle;
        private IntPtr threadHandle;
        private IntPtr jobHandle;
        private bool acceptedProcessReleased;
        public StreamReader StandardOutput { get; private set; }
        public StreamReader StandardError { get; private set; }

        private SupervisedProcess(
            IntPtr process, IntPtr thread, IntPtr job,
            IntPtr stdoutRead, IntPtr stderrRead) {
            processHandle = process;
            threadHandle = thread;
            jobHandle = job;
            StandardOutput = new StreamReader(
                new FileStream(new SafeFileHandle(stdoutRead, true), FileAccess.Read, 4096, false),
                new UTF8Encoding(false, true));
            StandardError = new StreamReader(
                new FileStream(new SafeFileHandle(stderrRead, true), FileAccess.Read, 4096, false),
                new UTF8Encoding(false, true));
        }

        private static void ThrowLastError(string message) {
            throw new Win32Exception(Marshal.GetLastWin32Error(), message);
        }
        private static void CloseIfValid(ref IntPtr handle) {
            if (handle != IntPtr.Zero && handle.ToInt64() != -1) {
                CloseHandle(handle);
                handle = IntPtr.Zero;
            }
        }
        private static void ConfigureKillOnClose(IntPtr job, bool enabled) {
            ExtendedLimitInformation info = new ExtendedLimitInformation();
            info.BasicLimitInformation.LimitFlags = enabled ? JobObjectLimitKillOnClose : 0;
            if (!SetInformationJobObject(
                job, 9, ref info, Marshal.SizeOf(typeof(ExtendedLimitInformation)))) {
                ThrowLastError("The worker job limit could not be configured.");
            }
        }
        private static long GetProcessCreationTicks(IntPtr process) {
            FileTime creation;
            FileTime exit;
            FileTime kernel;
            FileTime user;
            if (!GetProcessTimes(process, out creation, out exit, out kernel, out user)) {
                ThrowLastError("The launched process creation time is unavailable.");
            }
            ulong fileTime = ((ulong)creation.High << 32) | creation.Low;
            return DateTime.FromFileTimeUtc(unchecked((long)fileTime)).Ticks;
        }
        private static string GetProcessImagePath(IntPtr process) {
            int length = 32768;
            StringBuilder path = new StringBuilder(length);
            if (!QueryFullProcessImageName(process, 0, path, ref length)) {
                ThrowLastError("The launched process image path is unavailable.");
            }
            return path.ToString();
        }

        public static SupervisedProcess CreateSuspendedInJob(
            string userName, string domain, SecureString password,
            string applicationName, string arguments) {
            SecurityAttributes inheritable = new SecurityAttributes();
            inheritable.Length = Marshal.SizeOf(typeof(SecurityAttributes));
            inheritable.InheritHandle = true;
            IntPtr stdoutRead = IntPtr.Zero;
            IntPtr stdoutWrite = IntPtr.Zero;
            IntPtr stderrRead = IntPtr.Zero;
            IntPtr stderrWrite = IntPtr.Zero;
            IntPtr stdinRead = IntPtr.Zero;
            IntPtr stdinWrite = IntPtr.Zero;
            IntPtr job = IntPtr.Zero;
            ProcessInformation pi = new ProcessInformation();
            try {
                if (!CreatePipe(out stdoutRead, out stdoutWrite, ref inheritable, 0) ||
                    !SetHandleInformation(stdoutRead, HandleFlagInherit, 0) ||
                    !CreatePipe(out stderrRead, out stderrWrite, ref inheritable, 0) ||
                    !SetHandleInformation(stderrRead, HandleFlagInherit, 0) ||
                    !CreatePipe(out stdinRead, out stdinWrite, ref inheritable, 0) ||
                    !SetHandleInformation(stdinWrite, HandleFlagInherit, 0)) {
                    ThrowLastError("The fixed worker pipes could not be created.");
                }
                job = CreateJobObject(IntPtr.Zero, null);
                if (job == IntPtr.Zero) { ThrowLastError("The fixed worker job could not be created."); }
                ConfigureKillOnClose(job, true);
                StartupInfo startup = new StartupInfo();
                startup.Cb = Marshal.SizeOf(typeof(StartupInfo));
                startup.Flags = StartfUseStdHandles;
                startup.StandardInput = stdinRead;
                startup.StandardOutput = stdoutWrite;
                startup.StandardError = stderrWrite;
                StringBuilder commandLine = new StringBuilder(
                    "\"" + applicationName + "\" " + arguments);
                bool created = CreateProcessWithLogonW(
                    userName,
                    String.IsNullOrWhiteSpace(domain) ? null : domain,
                    password,
                    LogonWithProfile,
                    applicationName,
                    commandLine,
                    CreateSuspended | CreateNoWindow,
                    IntPtr.Zero,
                    null,
                    ref startup,
                    out pi);
                CloseIfValid(ref stdoutWrite);
                CloseIfValid(ref stderrWrite);
                CloseIfValid(ref stdinRead);
                CloseIfValid(ref stdinWrite);
                if (!created) { ThrowLastError("The fixed standard-user worker did not start suspended."); }
                if (!AssignProcessToJobObject(job, pi.Process)) {
                    int assignmentError = Marshal.GetLastWin32Error();
                    TerminateProcess(pi.Process, 125);
                    bool rootExited = WaitForSingleObject(pi.Process, 5000) == WaitObject0;
                    if (!rootExited) {
                        throw new InvalidOperationException(
                            "HCR_WORKER_CONTAINMENT_FAILED: the unassigned suspended worker did not terminate.");
                    }
                    throw new Win32Exception(
                        assignmentError,
                        "The suspended fixed worker could not be assigned to its job.");
                }
                SupervisedProcess result = new SupervisedProcess(
                    pi.Process, pi.Thread, job, stdoutRead, stderrRead);
                pi.Process = IntPtr.Zero;
                pi.Thread = IntPtr.Zero;
                job = IntPtr.Zero;
                stdoutRead = IntPtr.Zero;
                stderrRead = IntPtr.Zero;
                return result;
            }
            finally {
                CloseIfValid(ref stdoutWrite);
                CloseIfValid(ref stderrWrite);
                CloseIfValid(ref stdinRead);
                CloseIfValid(ref stdinWrite);
                CloseIfValid(ref stdoutRead);
                CloseIfValid(ref stderrRead);
                CloseIfValid(ref pi.Thread);
                CloseIfValid(ref pi.Process);
                CloseIfValid(ref job);
            }
        }

        public void Resume() {
            if (threadHandle == IntPtr.Zero || ResumeThread(threadHandle) == UInt32.MaxValue) {
                ThrowLastError("The contained fixed worker could not be resumed.");
            }
            CloseIfValid(ref threadHandle);
        }
        public bool WaitForExit(int milliseconds) {
            uint result = WaitForSingleObject(processHandle, (uint)Math.Max(1, milliseconds));
            if (result == WaitObject0) { return true; }
            if (result == WaitTimeout) { return false; }
            ThrowLastError("Waiting for the fixed worker failed.");
            return false;
        }
        public int ExitCode {
            get {
                uint code;
                if (!GetExitCodeProcess(processHandle, out code) || code == StillActive) {
                    ThrowLastError("The fixed worker exit code is unavailable.");
                }
                return unchecked((int)code);
            }
        }
        public uint ActiveProcessCount {
            get {
                BasicAccounting info;
                if (!QueryInformationJobObject(
                    jobHandle, 1, out info, Marshal.SizeOf(typeof(BasicAccounting)), IntPtr.Zero)) {
                    ThrowLastError("The fixed worker job state is unavailable.");
                }
                return info.ActiveProcesses;
            }
        }
        public bool TerminateAndVerify(uint exitCode, int milliseconds) {
            if (ActiveProcessCount != 0) { TerminateJobObject(jobHandle, exitCode); }
            DateTime deadline = DateTime.UtcNow.AddMilliseconds(Math.Max(1, milliseconds));
            while (ActiveProcessCount != 0 && DateTime.UtcNow < deadline) {
                System.Threading.Thread.Sleep(50);
            }
            bool rootExited = WaitForSingleObject(processHandle, 0) == WaitObject0;
            return rootExited && ActiveProcessCount == 0;
        }
        public bool ContainsProcess(int processId) {
            IntPtr candidate = OpenProcess(ProcessQueryLimitedInformation, false, processId);
            if (candidate == IntPtr.Zero) { return false; }
            try {
                bool result;
                return IsProcessInJob(candidate, jobHandle, out result) && result;
            }
            finally { CloseHandle(candidate); }
        }
        public bool ReleaseVerifiedSingleProcess(
            int processId, long expectedCreationTicks, string expectedPath) {
            IntPtr candidate = OpenProcess(
                ProcessQueryLimitedInformation | ProcessSuspendResume | Synchronize,
                false,
                processId);
            if (candidate == IntPtr.Zero) { return false; }
            try {
                bool inJob;
                if (!IsProcessInJob(candidate, jobHandle, out inJob) || !inJob) { return false; }
                if (NtSuspendProcess(candidate) != 0) { return false; }
                uint candidateWait = WaitForSingleObject(candidate, 0);
                if (candidateWait == WaitFailed) {
                    ThrowLastError("The launched process liveness check failed.");
                }
                if (candidateWait != WaitTimeout ||
                    ActiveProcessCount != 1 ||
                    !IsProcessInJob(candidate, jobHandle, out inJob) ||
                    !inJob ||
                    GetProcessCreationTicks(candidate) != expectedCreationTicks ||
                    !String.Equals(
                        GetProcessImagePath(candidate),
                        expectedPath,
                        StringComparison.OrdinalIgnoreCase)) {
                    return false;
                }
                ConfigureKillOnClose(jobHandle, false);
                if (NtResumeProcess(candidate) != 0) {
                    ConfigureKillOnClose(jobHandle, true);
                    return false;
                }
                acceptedProcessReleased = true;
                return true;
            }
            finally {
                // A rejected candidate remains suspended until the caller
                // terminates and verifies the whole job. Only the fully bound
                // sole child is resumed on the success path above.
                CloseHandle(candidate);
            }
        }
        public void Dispose() {
            Exception containmentFailure = null;
            try {
                if (jobHandle != IntPtr.Zero && !acceptedProcessReleased) {
                    bool clean = ActiveProcessCount == 0 &&
                        WaitForSingleObject(processHandle, 0) == WaitObject0;
                    if (!clean) { clean = TerminateAndVerify(125, 5000); }
                    if (!clean) {
                        containmentFailure = new InvalidOperationException(
                            "HCR_WORKER_CONTAINMENT_FAILED: the worker job did not reach zero active processes.");
                    }
                }
            }
            catch (Exception error) {
                containmentFailure = new InvalidOperationException(
                    "HCR_WORKER_CONTAINMENT_FAILED: worker cleanup could not be verified.",
                    error);
            }
            finally {
                if (StandardOutput != null) { StandardOutput.Dispose(); StandardOutput = null; }
                if (StandardError != null) { StandardError.Dispose(); StandardError = null; }
                CloseIfValid(ref threadHandle);
                CloseIfValid(ref processHandle);
                CloseIfValid(ref jobHandle);
            }
            if (containmentFailure != null) { throw containmentFailure; }
        }
    }
}
'@ -ErrorAction Stop
                }
                $powerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
                $arguments = @(
                    '-NoLogo',
                    '-NoProfile',
                    '-NonInteractive',
                    '-ExecutionPolicy',
                    'Bypass',
                    '-File',
                    ('"{0}"' -f $WorkerPath),
                    '-Mode',
                    $WorkerMode,
                    '-InputPath',
                    ('"{0}"' -f $InputPath),
                    '-ExpectedOperationId',
                    $OperationId,
                    '-InvocationId',
                    $InvocationId,
                    '-ExpectedInputSha256',
                    $InputSha256
                )
                $credentialName = [string]$StandardUser.UserName
                $separator = $credentialName.IndexOf('\')
                if ($separator -gt 0) {
                    $domain = $credentialName.Substring(0, $separator)
                    $userName = $credentialName.Substring($separator + 1)
                }
                else {
                    $userName = $credentialName
                    $domain = if ($credentialName.Contains('@')) { $null } else { '.' }
                }
                $inputDocument = Get-Content -LiteralPath $InputPath -Raw -Encoding UTF8 |
                    ConvertFrom-Json -ErrorAction Stop
                $allowsDescendant = $WorkerMode -eq 'RunTestStep' -and
                    $null -ne $inputDocument.PSObject.Properties['step'] -and
                    $null -ne $inputDocument.step -and
                    $null -ne $inputDocument.step.PSObject.Properties['type'] -and
                    @('launchApplication', 'startUiSession') -contains [string]$inputDocument.step.type
                $deadline = [DateTimeOffset]::Parse(
                    $AbsoluteDeadline,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::RoundtripKind
                )
                $localDeadline = [DateTimeOffset]::UtcNow.AddSeconds([Math]::Max(1, $TimeoutSeconds))
                if ($localDeadline -lt $deadline) { $deadline = $localDeadline }
                if ([DateTimeOffset]::UtcNow -ge $deadline) {
                    return [pscustomobject]@{
                        timedOut = $true
                        exitCode = $null
                        terminationVerified = $true
                        stdout = ''
                    }
                }
                $supervised = [Hcr.SupervisedProcess]::CreateSuspendedInJob(
                    $userName,
                    $domain,
                    $StandardUser.Password,
                    $powerShell,
                    ($arguments -join ' ')
                )
                try {
                    $stdoutTask = $supervised.StandardOutput.ReadLineAsync()
                    $stderrTask = $supervised.StandardError.ReadToEndAsync()
                    # CreateProcessWithLogonW returned the primary thread suspended;
                    # CreateSuspendedInJob assigned it before this explicit resume.
                    if ([DateTimeOffset]::UtcNow -ge $deadline) {
                        $terminationVerified = $supervised.TerminateAndVerify(124, 5000)
                        return [pscustomobject]@{
                            timedOut = $true
                            exitCode = $null
                            terminationVerified = [bool]$terminationVerified
                            stdout = ''
                        }
                    }
                    $supervised.Resume()
                    $remainingMilliseconds = [Math]::Max(
                        1,
                        [Math]::Min(
                            [int]::MaxValue,
                            [Math]::Floor(($deadline - [DateTimeOffset]::UtcNow).TotalMilliseconds)
                        )
                    )
                    $completed = $supervised.WaitForExit([int]$remainingMilliseconds)
                    if (-not $completed) {
                        $terminationVerified = $supervised.TerminateAndVerify(124, 5000)
                        return [pscustomobject]@{
                            timedOut = $true
                            exitCode = $null
                            terminationVerified = [bool]$terminationVerified
                            stdout = ''
                        }
                    }
                    if (-not $stdoutTask.Wait(2000) -or
                        (-not $allowsDescendant -and -not $stderrTask.Wait(2000))) {
                        $terminationVerified = $supervised.TerminateAndVerify(125, 5000)
                        return [pscustomobject]@{
                            timedOut = $false
                            exitCode = [int]$supervised.ExitCode
                            terminationVerified = [bool]$terminationVerified
                            containmentFailure = $true
                            reportedTimeout = $false
                            stdout = ''
                        }
                    }
                    $stdout = [string]$stdoutTask.Result
                    $stderr = if ($stderrTask.IsCompleted) { [string]$stderrTask.Result } else { '' }
                    if ([Text.Encoding]::UTF8.GetByteCount($stdout) -gt 1048576 -or
                        [Text.Encoding]::UTF8.GetByteCount($stderr) -gt 65536) {
                        throw 'The fixed worker returned oversized output.'
                    }
                    $preview = $null
                    try { $preview = $stdout | ConvertFrom-Json -ErrorAction Stop }
                    catch { }
                    $reportedTimeout = [bool](
                        $null -ne $preview -and
                        $null -ne $preview.PSObject.Properties['ok'] -and
                        [bool]$preview.ok -and
                        $null -ne $preview.PSObject.Properties['data'] -and
                        $null -ne $preview.data -and
                        $null -ne $preview.data.PSObject.Properties['timedOut'] -and
                        [bool]$preview.data.timedOut
                    )
                    $exitCode = [int]$supervised.ExitCode
                    $bindingValid = $null -ne $preview -and
                        [int]$preview.workerSchemaVersion -eq $ExpectedWorkerSchemaVersion -and
                        [string]$preview.operationId -eq $OperationId -and
                        [string]$preview.invocationId -eq $InvocationId -and
                        [string]$preview.mode -eq $WorkerMode -and
                        [string]$preview.inputSha256 -eq $InputSha256 -and
                        (([bool]$preview.ok -and $exitCode -eq 0) -or
                            (-not [bool]$preview.ok -and $exitCode -eq 1))
                    if (-not $bindingValid -or [DateTimeOffset]::UtcNow -ge $deadline) {
                        $terminationVerified = $supervised.TerminateAndVerify(125, 5000)
                        return [pscustomobject]@{
                            timedOut = $false
                            exitCode = $exitCode
                            terminationVerified = [bool]$terminationVerified
                            containmentFailure = $true
                            reportedTimeout = $false
                            stdout = ''
                        }
                    }
                    if (-not $allowsDescendant -and -not $reportedTimeout) {
                        while ($supervised.ActiveProcessCount -gt 0 -and
                            [DateTimeOffset]::UtcNow -lt $deadline) {
                            Start-Sleep -Milliseconds 50
                        }
                    }
                    $containmentFailure = $false
                    $terminationVerified = $true
                    if ($reportedTimeout -or
                        (-not $allowsDescendant -and $supervised.ActiveProcessCount -gt 0)) {
                        $terminationVerified = $supervised.TerminateAndVerify(124, 5000)
                        $containmentFailure = -not $reportedTimeout
                    }
                    elseif ($allowsDescendant) {
                        $launchPassed = [bool]$preview.ok -and
                            [string]$preview.data.status -eq 'passed'
                        if ($launchPassed) {
                            $launchedPid = [int]$preview.data.process.pid
                            $launchedAt = [DateTimeOffset]::Parse(
                                [string]$preview.data.process.startedAt,
                                [Globalization.CultureInfo]::InvariantCulture,
                                [Globalization.DateTimeStyles]::RoundtripKind
                            ).UtcDateTime.Ticks
                            $launchedPath = [string]$preview.data.process.executablePath
                            if ($launchedPid -le 0 -or
                                [string]::IsNullOrWhiteSpace($launchedPath) -or
                                [DateTimeOffset]::UtcNow -ge $deadline -or
                                -not $supervised.ReleaseVerifiedSingleProcess(
                                    $launchedPid,
                                    $launchedAt,
                                    $launchedPath
                                )) {
                                $terminationVerified = $supervised.TerminateAndVerify(125, 5000)
                                $containmentFailure = $true
                            }
                        }
                        elseif ($supervised.ActiveProcessCount -gt 0) {
                            $terminationVerified = $supervised.TerminateAndVerify(125, 5000)
                            $containmentFailure = $true
                        }
                    }
                    return [pscustomobject]@{
                        timedOut = $false
                        exitCode = $exitCode
                        terminationVerified = $terminationVerified
                        containmentFailure = $containmentFailure
                        reportedTimeout = $reportedTimeout
                        stdout = $stdout
                    }
                }
                catch {
                    $containmentVerified = $false
                    try {
                        $containmentVerified = $null -ne $supervised -and
                            $supervised.TerminateAndVerify(125, 5000)
                    }
                    catch { $containmentVerified = $false }
                    if (-not $containmentVerified) {
                        throw 'HCR_WORKER_CONTAINMENT_FAILED: the exceptional worker path did not terminate cleanly.'
                    }
                    throw
                }
                finally {
                    $supervised.Dispose()
                }
            } `
            -ErrorAction Stop
        if ([bool](Get-HcrPropertyValue $supervision 'timedOut' $false)) {
            if (-not [bool](Get-HcrPropertyValue $supervision 'terminationVerified' $false)) {
                Throw-HcrError 'GUEST_WORKER_CONTAINMENT_FAILED' 'The timed-out fixed worker process tree could not be verified terminated.'
            }
            if ($Mode -eq 'InspectGuest') {
                Throw-HcrError 'GUEST_WORKER_TIMEOUT' 'The fixed guest inspection worker exceeded its bounded timeout.'
            }
            return [pscustomobject][ordered]@{
                status = 'failed'
                summary = 'The fixed declarative guest worker exceeded its bounded timeout.'
                evidence = [pscustomobject]@{ workerTimedOut = $true }
                timedOut = $true
            }
        }
        if ([bool](Get-HcrPropertyValue $supervision 'containmentFailure' $false) -or
            ([bool](Get-HcrPropertyValue $supervision 'reportedTimeout' $false) -and
                -not [bool](Get-HcrPropertyValue $supervision 'terminationVerified' $false))) {
            Throw-HcrError 'GUEST_WORKER_CONTAINMENT_FAILED' 'The fixed worker process tree did not satisfy its containment contract.'
        }
        $document = [string](Get-HcrPropertyValue $supervision 'stdout') |
            ConvertFrom-Json -ErrorAction Stop
        [void](Get-HcrRealGuestRemainingSeconds $Context)
    }
    catch {
        if ($_.Exception.Data.Contains('HcrCode')) { throw }
        if ([string]$_ -match 'HCR_WORKER_CONTAINMENT_FAILED') {
            Throw-HcrError 'GUEST_WORKER_CONTAINMENT_FAILED' 'The fixed worker process tree did not satisfy its containment contract.'
        }
        Throw-HcrError 'GUEST_WORKER_FAILED' 'The supervised fixed guest worker did not return a valid bounded result.'
    }
    if ((Get-HcrPropertyValue $document 'workerSchemaVersion') -ne $expectedWorkerSchemaVersion -or
        [string](Get-HcrPropertyValue $document 'operationId') -ne $Context.operationId -or
        [string](Get-HcrPropertyValue $document 'invocationId') -ne $invocationId -or
        [string](Get-HcrPropertyValue $document 'mode') -ne $Mode -or
        [string](Get-HcrPropertyValue $document 'inputSha256') -ne $inputHash) {
        Throw-HcrError 'GUEST_WORKER_RESULT_INVALID' 'The fixed guest worker returned an unsupported result version.'
    }
    $workerOk = [bool](Get-HcrPropertyValue $document 'ok' $false)
    $exitCode = [int](Get-HcrPropertyValue $supervision 'exitCode' -999)
    if (($workerOk -and $exitCode -ne 0) -or (-not $workerOk -and $exitCode -ne 1)) {
        Throw-HcrError 'GUEST_WORKER_RESULT_INVALID' 'The fixed guest worker result did not match its process exit code.'
    }
    if (-not $workerOk) {
        $workerError = Get-HcrPropertyValue $document 'error'
        $workerCode = [string](Get-HcrPropertyValue $workerError 'code' 'GUEST_WORKER_FAILED')
        if ($workerCode -notmatch '^[A-Z][A-Z0-9_]{1,63}$') { $workerCode = 'GUEST_WORKER_FAILED' }
        Throw-HcrError $workerCode 'The fixed guest worker rejected the operation without exposing guest details.'
    }
    return Get-HcrPropertyValue $document 'data'
}

function Invoke-HcrRealInspectGuest {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $context = $null
    try {
        $context = New-HcrRealGuestContext $Arguments
        $input = [pscustomobject][ordered]@{
            schemaVersion = 1
            operationId = $context.operationId
            expectedTestUserSid = [string](Get-HcrPropertyValue $context.metadata 'testUserSid')
        }
        return Invoke-HcrFixedGuestWorker $context 'InspectGuest' $input 60
    }
    finally {
        Close-HcrRealGuestContext $context
    }
}

function Invoke-HcrRealStageArtifact {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $context = $null
    try {
        $context = New-HcrRealGuestContext $Arguments
        $requested = [string](Get-HcrPropertyValue $Arguments 'guestDestination')
        if (-not (Test-HcrSafeRelativePath $requested)) {
            Throw-HcrError 'INVALID_GUEST_PATH' 'The guest destination must be a safe relative path.'
        }
        $source = Assert-HcrRegularLocalFile ([string](Get-HcrPropertyValue $Arguments 'sourcePath')) 'INVALID_ARTIFACT'
        $declaredHash = [string](Get-HcrPropertyValue $Arguments 'sourceSha256')
        $sourceHashBefore = Get-HcrSha256File $source.FullName
        if ($declaredHash -ne $sourceHashBefore) {
            Throw-HcrError 'ARTIFACT_SOURCE_CHANGED' 'The host artifact changed before supervised staging.'
        }
        $workspace = Initialize-HcrRealGuestWorkspace $context
        [void](Get-HcrRealGuestRemainingSeconds $context)
        $target = Invoke-Command `
            -Session $context.session `
            -ArgumentList ([string](Get-HcrPropertyValue $workspace 'stagingRoot')), $requested `
            -ScriptBlock {
                param([string]$StagingRoot, [string]$RelativePath)
                if ([IO.Path]::IsPathRooted($RelativePath) -or
                    $RelativePath.Contains(':') -or $RelativePath.Contains('%') -or
                    $RelativePath -match '(^|[\\/])\.\.([\\/]|$)') {
                    throw 'The staging path is invalid.'
                }
                $target = [IO.Path]::GetFullPath((Join-Path $StagingRoot $RelativePath))
                $root = [IO.Path]::GetFullPath($StagingRoot).TrimEnd('\', '/') + '\'
                if (-not (($target + '\').StartsWith($root, [StringComparison]::OrdinalIgnoreCase))) {
                    throw 'The staging path escaped its operation root.'
                }
                $rootItem = Get-Item -LiteralPath $StagingRoot -Force -ErrorAction Stop
                if (-not $rootItem.PSIsContainer -or
                    ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw 'The staging root is not an ordinary directory.'
                }
                $current = $StagingRoot
                $segments = @($RelativePath -split '[\\/]')
                for ($index = 0; $index -lt ($segments.Count - 1); $index++) {
                    $segment = $segments[$index]
                    $current = Join-Path $current $segment
                    if (-not (Test-Path -LiteralPath $current)) {
                        try {
                            [void](New-Item -ItemType Directory -Path $current -ErrorAction Stop)
                        }
                        catch {
                            if (-not (Test-Path -LiteralPath $current -PathType Container)) { throw }
                        }
                    }
                    $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
                    if (-not $item.PSIsContainer -or
                        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                        throw 'The staging path contains a non-directory or reparse point.'
                    }
                }
                if (Test-Path -LiteralPath $target) {
                    throw 'The operation-scoped staging destination already exists.'
                }
                return $target
            } `
            -ErrorAction Stop
        Copy-Item `
            -LiteralPath $source.FullName `
            -Destination $target `
            -ToSession $context.session `
            -ErrorAction Stop
        [void](Get-HcrRealGuestRemainingSeconds $context)
        $guest = Invoke-Command -Session $context.session -ArgumentList $target -ScriptBlock {
            param([string]$Path)
            $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'The staged artifact is a reparse point.'
            }
            return [pscustomobject]@{
                sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                size = [int64]$item.Length
            }
        } -ErrorAction Stop
        [void](Get-HcrRealGuestRemainingSeconds $context)
        $sourceHashAfter = Get-HcrSha256File $source.FullName
        if ($sourceHashAfter -ne $sourceHashBefore -or
            [string](Get-HcrPropertyValue $guest 'sha256') -ne $sourceHashBefore -or
            [int64](Get-HcrPropertyValue $guest 'size') -ne [int64]$source.Length) {
            Throw-HcrError 'ARTIFACT_HASH_MISMATCH' 'The operation-scoped guest artifact does not match the stable host source.'
        }
        return [pscustomobject][ordered]@{
            guestDestination = "operations\$($context.operationId)\$requested"
            guestSha256 = $sourceHashBefore
            bytesCopied = [int64]$source.Length
        }
    }
    catch {
        if ($_.Exception.Data.Contains('HcrCode')) { throw }
        Throw-HcrError 'ARTIFACT_STAGE_FAILED' 'The administrator-supervised PowerShell Direct transfer failed.'
    }
    finally {
        Close-HcrRealGuestContext $context
    }
}

function Invoke-HcrRealGuestStep {
    param(
        [Parameter(Mandatory = $true)][object]$Arguments,
        [bool]$Cleanup
    )

    Assert-HcrRealGuestStepContract $Arguments $Cleanup
    $context = $null
    try {
        $context = New-HcrRealGuestContext $Arguments
        $artifact = Get-HcrPropertyValue $Arguments 'artifact'
        $workerSchemaVersion = [int](Get-HcrPropertyValue $Arguments 'schemaVersion' 1)
        $input = [ordered]@{
            schemaVersion = $workerSchemaVersion
            operationId = $context.operationId
            expectedTestUserSid = [string](Get-HcrPropertyValue $context.metadata 'testUserSid')
            step = Copy-HcrObject (Get-HcrPropertyValue $Arguments 'step')
            applications = @(@((Get-HcrPropertyValue $Arguments 'applications' @())) | ForEach-Object { Copy-HcrObject $_ })
            launchedProcesses = @(@((Get-HcrPropertyValue $Arguments 'launchedProcesses' @())) | ForEach-Object { Copy-HcrObject $_ })
            launchedProcess = Copy-HcrObject (Get-HcrPropertyValue $Arguments 'launchedProcess')
            artifact = if ($null -eq $artifact) { $null } else {
                [pscustomobject][ordered]@{
                    guestDestination = [string](Get-HcrPropertyValue $artifact 'guestDestination')
                    sourceSha256 = [string](Get-HcrPropertyValue $artifact 'sourceSha256')
                    guestSha256 = [string](Get-HcrPropertyValue $artifact 'guestSha256')
                }
            }
        }
        if ($workerSchemaVersion -eq 2) {
            $input.workflowKind = [string](Get-HcrPropertyValue $Arguments 'workflowKind')
            $input.fixtures = @(@((Get-HcrPropertyValue $Arguments 'fixtures' @())) |
                ForEach-Object { Copy-HcrObject $_ })
            $input.webDriver = Copy-HcrObject (Get-HcrPropertyValue $Arguments 'webDriver')
            $input.portableArtifact = Copy-HcrObject (Get-HcrPropertyValue $Arguments 'portableArtifact')
            $input.sourceCommit = [string](Get-HcrPropertyValue $Arguments 'sourceCommit')
        }
        $mode = if ($Cleanup) { 'RunCleanupStep' } else { 'RunTestStep' }
        $timeout = [int](Get-HcrPropertyValue (Get-HcrPropertyValue $Arguments 'step') 'timeoutSeconds')
        return Invoke-HcrFixedGuestWorker $context $mode ([pscustomobject]$input) $timeout
    }
    finally {
        Close-HcrRealGuestContext $context
    }
}

function Invoke-HcrRealSetVmPower {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $mutationEntered = $false
    $verifiedVm = $null
    try {
        if (-not (Test-HcrCurrentProcessElevated)) {
            Throw-HcrError 'ELEVATION_REQUIRED' 'The VM power transition requires an elevated host process.'
        }
        $verifiedVm = Assert-HcrRealDispatchVm $Arguments
        $boundary = ConvertTo-HcrRealVmSnapshot $verifiedVm
        if ((Get-HcrVmFingerprint $boundary) -ne
                [string](Get-HcrPropertyValue $Arguments 'expectedVmFingerprint') -or
            [string](Get-HcrPropertyValue $boundary 'state') -ne
                [string](Get-HcrPropertyValue $Arguments 'expectedState')) {
            Throw-HcrError 'PLAN_DRIFT' 'The VM changed at the power mutation boundary.'
        }
        $mutationEntered = $true
        $action = [string](Get-HcrPropertyValue $Arguments 'action')
        if ($action -eq 'start') {
            [void](Start-VM -VM $verifiedVm -ErrorAction Stop)
        }
        elseif ($action -eq 'gracefulShutdown') {
            [void](Stop-VM -VM $verifiedVm -ErrorAction Stop)
        }
        else {
            Throw-HcrError 'INVALID_ARGUMENT' 'The VM power action is unsupported.'
        }
        $refreshed = Get-VM -Id ([Guid]([string](Get-HcrPropertyValue $Arguments 'expectedVmId'))) -ErrorAction Stop
        if ([string]$refreshed.State -ne [string](Get-HcrPropertyValue $Arguments 'targetState')) {
            Throw-HcrError 'POWER_TRANSITION_FAILED' 'The exact target power state was not confirmed.'
        }
        return [pscustomobject][ordered]@{
            previousState = [string](Get-HcrPropertyValue $Arguments 'expectedState')
            currentState = [string]$refreshed.State
            effectState = 'confirmed'
        }
    }
    catch {
        if (-not $mutationEntered -and $_.Exception.Data.Contains('HcrCode')) { throw }
        $effectState = 'indeterminate'
        if ($mutationEntered -and $null -ne $verifiedVm) {
            try {
                $probe = Get-VM -Id $verifiedVm.Id -ErrorAction Stop
                if ([string]$probe.State -eq [string](Get-HcrPropertyValue $Arguments 'targetState')) {
                    $effectState = 'confirmed'
                }
            }
            catch { $effectState = 'indeterminate' }
        }
        if (-not $mutationEntered) {
            Throw-HcrError 'POWER_TRANSITION_FAILED' 'The VM power transition failed before mutation entry.'
        }
        Throw-HcrPartialMutationError `
            'POWER_TRANSITION_FAILED' `
            'The VM power transition failed after entering the mutation boundary.' `
            $effectState `
            ([pscustomobject][ordered]@{
                resourceType = 'vmPower'
                vmId = [string](Get-HcrPropertyValue $Arguments 'expectedVmId')
                vmName = [string](Get-HcrPropertyValue $Arguments 'expectedVmName')
                action = [string](Get-HcrPropertyValue $Arguments 'action')
            }) `
            'The planned VM power transition may have taken effect. Inspect the exact managed VM before creating a new plan.'
    }
}

function Invoke-HcrRealSetVmNetwork {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $mutationEntered = $false
    $verifiedVm = $null
    $recoveryPlanId = [string](Get-HcrPropertyValue $Arguments 'recoveryPlanId')
    $failureCode = if ([string]::IsNullOrWhiteSpace($recoveryPlanId)) {
        'NETWORK_TRANSITION_FAILED'
    }
    else { 'NETWORK_RECOVERY_REQUIRED' }
    $additional = if ([string]::IsNullOrWhiteSpace($recoveryPlanId)) {
        $null
    }
    else { [pscustomobject][ordered]@{ recoveryPlanId = $recoveryPlanId } }
    try {
        if (-not (Test-HcrCurrentProcessElevated)) {
            Throw-HcrError 'ELEVATION_REQUIRED' 'The VM network transition requires an elevated host process.'
        }
        $verifiedVm = Assert-HcrRealDispatchVm $Arguments
        $boundary = ConvertTo-HcrRealVmSnapshot $verifiedVm
        if ((Get-HcrVmNetworkInvariantFingerprint $boundary) -ne
                [string](Get-HcrPropertyValue $Arguments 'expectedVmFingerprint')) {
            Throw-HcrError 'PLAN_DRIFT' 'The VM changed at the network mutation boundary.'
        }
        $primary = Get-HcrVerifiedPrimaryAdapter $boundary
        $expectedAttachment = Get-HcrPropertyValue $Arguments 'expectedAttachment'
        if ([string]$primary.id -ne [string](Get-HcrPropertyValue $Arguments 'expectedAdapterId') -or
            [string]$primary.fingerprint -ne [string](Get-HcrPropertyValue $Arguments 'expectedAdapterFingerprint') -or
            -not (Test-HcrBoundObjectEqual $primary.attachment $expectedAttachment)) {
            Throw-HcrError 'PLAN_DRIFT' 'The primary adapter changed at the network mutation boundary.'
        }
        $rawAdapters = @(Get-VMNetworkAdapter -VM $verifiedVm -ErrorAction Stop | Where-Object {
            [string]$_.Id -eq [string](Get-HcrPropertyValue $Arguments 'expectedAdapterId')
        })
        if ($rawAdapters.Count -ne 1) {
            Throw-HcrError 'PRIMARY_ADAPTER_UNVERIFIED' 'The exact primary adapter is unavailable at the mutation boundary.'
        }
        $targetAttachment = Get-HcrPropertyValue $Arguments 'targetAttachment'
        if ([string](Get-HcrPropertyValue $targetAttachment 'mode') -eq 'disconnected') {
            $mutationEntered = $true
            Disconnect-VMNetworkAdapter -VMNetworkAdapter $rawAdapters[0] -ErrorAction Stop
        }
        else {
            $targetSwitches = @(Get-VMSwitch -Id ([Guid]([string](Get-HcrPropertyValue $targetAttachment 'switchId'))) -ErrorAction Stop)
            if ($targetSwitches.Count -ne 1 -or
                [string]$targetSwitches[0].Name -ne [string](Get-HcrPropertyValue $targetAttachment 'switchName') -or
                [string]$targetSwitches[0].SwitchType -ne [string](Get-HcrPropertyValue $targetAttachment 'switchType')) {
                Throw-HcrError 'PLAN_DRIFT' 'The exact baseline switch changed at the mutation boundary.'
            }
            $mutationEntered = $true
            Connect-VMNetworkAdapter -VMNetworkAdapter $rawAdapters[0] -VMSwitch $targetSwitches[0] -ErrorAction Stop
        }
        $refreshed = ConvertTo-HcrRealVmSnapshot (Get-VM -Id $verifiedVm.Id -ErrorAction Stop)
        $confirmed = Get-HcrVerifiedPrimaryAdapter $refreshed
        if (-not (Test-HcrBoundObjectEqual $confirmed.attachment $targetAttachment)) {
            Throw-HcrError $failureCode 'The exact target network attachment was not confirmed.'
        }
        return [pscustomobject][ordered]@{
            previousAttachment = Copy-HcrObject $primary.attachment
            currentAttachment = Copy-HcrObject $confirmed.attachment
            effectState = 'confirmed'
        }
    }
    catch {
        if (-not $mutationEntered -and $_.Exception.Data.Contains('HcrCode')) { throw }
        if (-not $mutationEntered) {
            Throw-HcrError 'NETWORK_TRANSITION_FAILED' 'The VM network transition failed before mutation entry.'
        }
        Throw-HcrPartialMutationError `
            $failureCode `
            'The VM network transition failed after entering the mutation boundary.' `
            'indeterminate' `
            ([pscustomobject][ordered]@{
                resourceType = 'vmNetwork'
                vmId = [string](Get-HcrPropertyValue $Arguments 'expectedVmId')
                vmName = [string](Get-HcrPropertyValue $Arguments 'expectedVmName')
                adapterId = [string](Get-HcrPropertyValue $Arguments 'expectedAdapterId')
                target = [string](Get-HcrPropertyValue $Arguments 'target')
            }) `
            'The planned adapter transition may have taken effect. Use only the pre-created recovery plan when recovery is required.' `
            $additional
    }
}

function Invoke-HcrRealAdapter {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [AllowNull()][object]$Arguments
    )

    switch ($Operation) {
        'GetHostSnapshot' { return Get-HcrRealHostSnapshot }
        'GetTargetVolume' {
            return Get-HcrRealTargetVolume ([string](Get-HcrPropertyValue $Arguments 'path'))
        }
        'GetSwitch' {
            if (-not (Get-Command Get-VMSwitch -ErrorAction SilentlyContinue)) { return $null }
            $switch = @(Get-VMSwitch -Name ([string](Get-HcrPropertyValue $Arguments 'name')) -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($switch.Count -eq 0) { return $null }
            return [pscustomobject][ordered]@{
                id = [string]$switch[0].Id
                name = [string]$switch[0].Name
                type = [string]$switch[0].SwitchType
            }
        }
        'ListVms' {
            if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
                Throw-HcrError 'HYPERV_UNAVAILABLE' 'The Hyper-V PowerShell module is unavailable.'
            }
            return @(Get-VM -ErrorAction Stop | ForEach-Object { ConvertTo-HcrRealVmSnapshot $_ })
        }
        'GetVm' {
            if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
                Throw-HcrError 'HYPERV_UNAVAILABLE' 'The Hyper-V PowerShell module is unavailable.'
            }
            $vm = @(Get-VM -Name ([string](Get-HcrPropertyValue $Arguments 'name')) -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($vm.Count -eq 0) { return $null }
            return ConvertTo-HcrRealVmSnapshot `
                $vm[0] `
                -RequireOfflineDiskIdentity:([bool](Get-HcrPropertyValue `
                    $Arguments `
                    'requireOfflineDiskIdentity' `
                    $false))
        }
        'CreateVm' {
            $plan = Get-HcrPropertyValue $Arguments 'plan'
            $ownershipId = [string](Get-HcrPropertyValue $Arguments 'ownershipId')
            $createdVm = $null
            $mutationEntered = $false
            $boundPlan = $plan
            try {
                $paths = Get-HcrRevalidatedVmCreatePaths $plan
                $boundPlan = Copy-HcrObject $plan
                $boundPlan.vmRoot = [string]$paths.vmRoot
                $boundPlan.vmPath = [string]$paths.vmPath
                $boundPlan.vhdxPath = [string]$paths.vhdxPath
                $currentVolume = Get-HcrRealTargetVolume ([string]$paths.vmRoot)
                $plannedVolume = Get-HcrPropertyValue $boundPlan 'targetVolume'
                if ([string](Get-HcrPropertyValue $currentVolume 'uniqueId') -ne
                        [string](Get-HcrPropertyValue $plannedVolume 'uniqueId') -or
                    [string](Get-HcrPropertyValue $currentVolume 'root') -ne
                        [string](Get-HcrPropertyValue $plannedVolume 'root') -or
                    [string](Get-HcrPropertyValue $currentVolume 'fileSystem') -ne
                        [string](Get-HcrPropertyValue $plannedVolume 'fileSystem') -or
                    [int64](Get-HcrPropertyValue $currentVolume 'availableBytes') -lt
                        [int64](Get-HcrPropertyValue $plannedVolume 'requiredBytes')) {
                    Throw-HcrError 'PLAN_DRIFT' 'The target-volume binding changed at the VM mutation boundary.'
                }
                $mutationEntered = $true
                $createdVm = New-VM `
                    -Name ([string](Get-HcrPropertyValue $boundPlan 'name')) `
                    -Generation 2 `
                    -Path ([string](Get-HcrPropertyValue $boundPlan 'vmRoot')) `
                    -NewVHDPath ([string](Get-HcrPropertyValue $boundPlan 'vhdxPath')) `
                    -NewVHDSizeBytes ([int64](Get-HcrPropertyValue $boundPlan 'diskSizeGb') * 1GB) `
                    -MemoryStartupBytes ([int64](Get-HcrPropertyValue $boundPlan 'startupMemoryGb') * 1GB) `
                    -SwitchName ([string](Get-HcrPropertyValue $boundPlan 'switchName')) `
                    -ErrorAction Stop
                Set-VMMemory -VM $createdVm -DynamicMemoryEnabled $true `
                    -MinimumBytes 2GB `
                    -StartupBytes ([int64](Get-HcrPropertyValue $boundPlan 'startupMemoryGb') * 1GB) `
                    -MaximumBytes ([int64](Get-HcrPropertyValue $boundPlan 'maximumMemoryGb') * 1GB) `
                    -ErrorAction Stop
                Set-VMProcessor -VM $createdVm -Count ([int](Get-HcrPropertyValue $boundPlan 'processorCount')) -ErrorAction Stop
                Set-VMFirmware -VM $createdVm -EnableSecureBoot On -ErrorAction Stop
                [void](Add-VMDvdDrive -VM $createdVm -Path ([string](Get-HcrPropertyValue $boundPlan 'isoPath')) -ErrorAction Stop)
                Set-VMKeyProtector -VM $createdVm -NewLocalKeyProtector -ErrorAction Stop
                Enable-VMTPM -VM $createdVm -ErrorAction Stop
                Set-VM -VM $createdVm -Notes "hyperv-clean-room/v1:$ownershipId" -ErrorAction Stop
                $refreshed = Get-VM -Id $createdVm.Id -ErrorAction Stop
                return ConvertTo-HcrRealVmSnapshot $refreshed
            }
            catch {
                if (-not $mutationEntered) {
                    if ($_.Exception.Data.Contains('HcrCode')) { throw }
                    Throw-HcrError 'VM_CREATE_FAILED' 'VM creation failed before the mutation boundary.'
                }
                $vmId = if ($null -eq $createdVm) { $null } else { [string]$createdVm.Id }
                $effectState = if ([string]::IsNullOrWhiteSpace($vmId)) { 'indeterminate' } else { 'confirmed' }
                Throw-HcrPartialMutationError `
                    'VM_CREATE_FAILED' `
                    'VM creation failed after entering the host mutation boundary.' `
                    $effectState `
                    ([pscustomobject][ordered]@{
                        resourceType = 'vm'
                        vmId = $vmId
                        vmName = [string](Get-HcrPropertyValue $boundPlan 'name')
                        ownershipId = $ownershipId
                        vmPath = [string](Get-HcrPropertyValue $boundPlan 'vmPath')
                        vhdxPath = [string](Get-HcrPropertyValue $boundPlan 'vhdxPath')
                    }) `
                    'A VM or VHDX may have been created. Inspect only the exact partial identity in error.details; automatic cleanup was not attempted.'
            }
        }
        'SetVmPower' {
            return Invoke-HcrRealSetVmPower $Arguments
        }
        'SetVmNetwork' {
            return Invoke-HcrRealSetVmNetwork $Arguments
        }
        'CreateCheckpoint' {
            $mutationEntered = $false
            $snapshot = $null
            try {
                $verifiedVm = Assert-HcrRealDispatchVm $Arguments
                $mutationEntered = $true
                $snapshot = Checkpoint-VM `
                    -VM $verifiedVm `
                    -SnapshotName ([string](Get-HcrPropertyValue $Arguments 'checkpointName')) `
                    -Passthru `
                    -ErrorAction Stop
                return [pscustomobject][ordered]@{
                    id = [string]$snapshot.Id
                    name = [string]$snapshot.Name
                    parentId = if ($null -eq $snapshot.ParentSnapshotId) { $null } else { [string]$snapshot.ParentSnapshotId }
                    configurationFingerprint = Get-HcrSha256Text "$($snapshot.Id)|$($snapshot.CreationTime.ToUniversalTime().ToString('o'))"
                    createdAt = $snapshot.CreationTime.ToUniversalTime().ToString('o')
                }
            }
            catch {
                if (-not $mutationEntered) {
                    if ($_.Exception.Data.Contains('HcrCode')) { throw }
                    Throw-HcrError 'CHECKPOINT_CREATE_FAILED' 'Checkpoint creation failed before the mutation boundary.'
                }
                $checkpointId = if ($null -eq $snapshot) { $null } else { [string]$snapshot.Id }
                $effectState = if ([string]::IsNullOrWhiteSpace($checkpointId)) { 'indeterminate' } else { 'confirmed' }
                Throw-HcrPartialMutationError `
                    'CHECKPOINT_CREATE_FAILED' `
                    'Checkpoint creation failed after entering the host mutation boundary.' `
                    $effectState `
                    ([pscustomobject][ordered]@{
                        resourceType = 'checkpoint'
                        vmId = [string](Get-HcrPropertyValue $Arguments 'expectedVmId')
                        vmName = [string](Get-HcrPropertyValue $Arguments 'expectedVmName')
                        checkpointId = $checkpointId
                        checkpointName = [string](Get-HcrPropertyValue $Arguments 'checkpointName')
                    }) `
                    'The exact checkpoint may have been created. Inspect the bound VM and checkpoint identity; automatic cleanup was not attempted.'
            }
        }
        'RestoreCheckpoint' {
            $checkpointName = [string](Get-HcrPropertyValue $Arguments 'checkpointName')
            $mutationEntered = $false
            $restoreReturned = $false
            try {
                $verifiedVm = Assert-HcrRealDispatchVm $Arguments
                # The final raw VM and checkpoint objects are acquired once at
                # the mutation boundary. The projection validated below is
                # built from this exact checkpoint inventory, and the matching
                # raw object from that inventory is the object restored.
                $boundaryVm = Get-VM -Id $verifiedVm.Id -ErrorAction Stop
                $boundaryCheckpoints = @(Get-VMSnapshot -VM $boundaryVm -ErrorAction Stop)
                $liveSnapshot = ConvertTo-HcrRealVmSnapshot `
                    $boundaryVm `
                    -RequireOfflineDiskIdentity `
                    -CheckpointInventory $boundaryCheckpoints
                $checkpoint = Assert-HcrRestoreAdapterBindings $liveSnapshot $Arguments
                $snapshots = @($boundaryCheckpoints | Where-Object {
                    [string]$_.Id -eq [string](Get-HcrPropertyValue $checkpoint 'id') -and
                    [string]$_.Name -eq $checkpointName
                })
                if ($snapshots.Count -ne 1) {
                    Throw-HcrError 'PLAN_DRIFT' 'The exact restore checkpoint is unavailable at the mutation boundary.'
                }
                $mutationEntered = $true
                Restore-VMSnapshot -VMSnapshot $snapshots[0] -Confirm:$false -ErrorAction Stop
                $restoreReturned = $true
                return [pscustomobject][ordered]@{
                    checkpointId = [string]$snapshots[0].Id
                    restoredAt = Get-HcrUtcTimestamp
                }
            }
            catch {
                if (-not $mutationEntered) {
                    if ($_.Exception.Data.Contains('HcrCode')) { throw }
                    Throw-HcrError 'CHECKPOINT_RESTORE_FAILED' 'Checkpoint restore failed before the mutation boundary.'
                }
                $effectState = if ($restoreReturned) { 'confirmed' } else { 'indeterminate' }
                Throw-HcrPartialMutationError `
                    'CHECKPOINT_RESTORE_FAILED' `
                    'Checkpoint restore failed after entering the host mutation boundary.' `
                    $effectState `
                    ([pscustomobject][ordered]@{
                        resourceType = 'checkpointRestore'
                        vmId = [string](Get-HcrPropertyValue $Arguments 'expectedVmId')
                        vmName = [string](Get-HcrPropertyValue $Arguments 'expectedVmName')
                        checkpointId = [string](Get-HcrPropertyValue $Arguments 'expectedCheckpointId')
                        checkpointName = $checkpointName
                    }) `
                    'The exact checkpoint restore may have taken effect. Inspect the bound VM and checkpoint identity before further mutation; no automatic recovery was attempted.'
            }
        }
        'ResolveCredentialProfile' {
            $bundle = Get-HcrCredentialBundle `
                ([string](Get-HcrPropertyValue $Arguments 'profileName')) `
                ([string](Get-HcrPropertyValue $Arguments 'vmName'))
            return [pscustomobject][ordered]@{
                name = [string](Get-HcrPropertyValue $Arguments 'profileName')
                vmName = [string](Get-HcrPropertyValue $Arguments 'vmName')
                metadata = $bundle.metadata
            }
        }
        'InspectGuest' {
            return Invoke-HcrRealInspectGuest $Arguments
        }
        'StageArtifact' {
            return Invoke-HcrRealStageArtifact $Arguments
        }
        'RunTestStep' {
            return Invoke-HcrRealGuestStep $Arguments $false
        }
        'RunCleanupStep' {
            return Invoke-HcrRealGuestStep $Arguments $true
        }
        default {
            Throw-HcrError 'ADAPTER_OPERATION_UNSUPPORTED' 'The Hyper-V adapter operation is unsupported.'
        }
    }
}

function Invoke-HcrAdapter {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [AllowNull()][object]$Arguments = $null
    )

    if ((Get-HcrAdapterMode) -eq 'mock') {
        return Invoke-HcrMockAdapter $Operation $Arguments
    }
    return Invoke-HcrRealAdapter $Operation $Arguments
}

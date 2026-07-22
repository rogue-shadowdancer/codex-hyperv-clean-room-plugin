function Get-HcrOwnershipRecordSha256 {
    param([Parameter(Mandatory = $true)][object]$Record)

    return Get-HcrSha256Text (ConvertTo-HcrJson $Record 100)
}

function Test-HcrBoundObjectEqual {
    param(
        [AllowNull()][object]$Left,
        [AllowNull()][object]$Right
    )

    return (ConvertTo-HcrJson $Left 50) -ceq (ConvertTo-HcrJson $Right 50)
}

function Get-HcrNetworkAttachment {
    param([Parameter(Mandatory = $true)][object]$Adapter)

    $switchId = [string](Get-HcrPropertyValue $Adapter 'switchId')
    $switchName = [string](Get-HcrPropertyValue $Adapter 'switchName')
    if ([string]::IsNullOrWhiteSpace($switchId) -and
        [string]::IsNullOrWhiteSpace($switchName)) {
        return [pscustomobject][ordered]@{ mode = 'disconnected' }
    }
    $switchType = [string](Get-HcrPropertyValue $Adapter 'switchType')
    if ([string]::IsNullOrWhiteSpace($switchId) -or
        [string]::IsNullOrWhiteSpace($switchName) -or
        @('Private', 'Internal', 'External') -notcontains $switchType) {
        Throw-HcrError 'PRIMARY_ADAPTER_UNVERIFIED' 'The primary adapter attachment is incomplete.'
    }
    return [pscustomobject][ordered]@{
        mode = 'connected'
        switchId = $switchId
        switchName = $switchName
        switchType = $switchType
    }
}

function Get-HcrNetworkAdapterFingerprint {
    param([Parameter(Mandatory = $true)][object]$Adapter)

    $identity = [ordered]@{
        id = [string](Get-HcrPropertyValue $Adapter 'id')
        name = [string](Get-HcrPropertyValue $Adapter 'name')
        macAddress = [string](Get-HcrPropertyValue $Adapter 'macAddress')
    }
    return Get-HcrSha256Text (ConvertTo-HcrJson $identity 10)
}

function Get-HcrVerifiedPrimaryAdapter {
    param([Parameter(Mandatory = $true)][object]$Vm)

    $adapters = @((Get-HcrPropertyValue $Vm 'networkAdapters' @()))
    if ($adapters.Count -ne 1) {
        Throw-HcrError 'PRIMARY_ADAPTER_UNVERIFIED' 'Exactly one managed primary network adapter is required.'
    }
    $adapter = $adapters[0]
    $id = [string](Get-HcrPropertyValue $adapter 'id')
    $name = [string](Get-HcrPropertyValue $adapter 'name')
    $mac = [string](Get-HcrPropertyValue $adapter 'macAddress')
    if ([string]::IsNullOrWhiteSpace($id) -or
        [string]::IsNullOrWhiteSpace($name) -or
        $mac -notmatch '^[A-F0-9]{12}$') {
        Throw-HcrError 'PRIMARY_ADAPTER_UNVERIFIED' 'The primary network adapter identity is incomplete.'
    }
    return [pscustomobject][ordered]@{
        id = $id
        name = $name
        macAddress = $mac
        fingerprint = Get-HcrNetworkAdapterFingerprint $adapter
        attachment = Get-HcrNetworkAttachment $adapter
        raw = $adapter
    }
}

function Get-HcrVmNetworkInvariantFingerprint {
    param([Parameter(Mandatory = $true)][object]$Vm)

    $primary = Get-HcrVerifiedPrimaryAdapter $Vm
    $fingerprintInput = [ordered]@{
        id = [string](Get-HcrPropertyValue $Vm 'id')
        name = [string](Get-HcrPropertyValue $Vm 'name')
        state = [string](Get-HcrPropertyValue $Vm 'state')
        generation = Get-HcrPropertyValue $Vm 'generation'
        notes = [string](Get-HcrPropertyValue $Vm 'notes')
        vmPath = [string](Get-HcrPropertyValue $Vm 'vmPath')
        vhdxPath = [string](Get-HcrPropertyValue $Vm 'vhdxPath')
        processorCount = Get-HcrPropertyValue $Vm 'processorCount'
        startupMemoryGb = Get-HcrPropertyValue $Vm 'startupMemoryGb'
        maximumMemoryGb = Get-HcrPropertyValue $Vm 'maximumMemoryGb'
        secureBoot = [bool](Get-HcrPropertyValue $Vm 'secureBoot' $false)
        vtpm = [bool](Get-HcrPropertyValue $Vm 'vtpm' $false)
        primaryAdapterFingerprint = [string]$primary.fingerprint
    }
    return Get-HcrSha256Text (ConvertTo-HcrJson $fingerprintInput 20)
}

function Assert-HcrV2HostAvailable {
    param([switch]$RequireElevation)

    $hostSnapshot = Invoke-HcrAdapter 'GetHostSnapshot'
    if (-not [bool](Get-HcrPropertyValue $hostSnapshot 'hyperVCommandsAvailable' $false) -or
        -not [bool](Get-HcrPropertyValue $hostSnapshot 'hypervisorPresent' $false)) {
        Throw-HcrError 'HYPERV_UNAVAILABLE' 'Hyper-V host prerequisites are unavailable.'
    }
    if ($RequireElevation -and
        -not [bool](Get-HcrPropertyValue $hostSnapshot 'elevated' $false)) {
        Throw-HcrError 'ELEVATION_REQUIRED' 'The guarded host transition requires elevation.'
    }
    return $hostSnapshot
}

function New-HcrV2PlanRecord {
    param([Parameter(Mandatory = $true)][object]$Plan)

    $record = New-HcrPlanRecord $Plan
    $record.schemaVersion = 2
    return $record
}

function Invoke-HcrPlanVmPower {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $action = [string](Get-HcrPropertyValue $Arguments 'action')
    $hostSnapshot = Assert-HcrV2HostAvailable
    $owned = Get-HcrRequiredOwnedVm ([string](Get-HcrPropertyValue $Arguments 'vmName'))
    $state = [string](Get-HcrPropertyValue $owned.vm 'state')
    $expected = if ($action -eq 'start') {
        @('Off', 'Running')
    }
    elseif ($action -eq 'gracefulShutdown') {
        @('Running', 'Off')
    }
    else {
        Throw-HcrError 'INVALID_ARGUMENT' 'The power action is not supported.'
    }
    if ($state -ne $expected[0]) {
        Throw-HcrError 'VM_STATE_UNSUPPORTED' 'The VM is not in the exact state required for the requested transition.'
    }
    $created = [DateTimeOffset]::UtcNow
    $plan = [pscustomobject][ordered]@{
        schemaVersion = 2
        planKind = 'vmPower'
        planId = [Guid]::NewGuid().ToString()
        createdAt = $created.ToString('o')
        expiresAt = $created.AddMinutes(15).ToString('o')
        hostFingerprint = Get-HcrHostFingerprint $hostSnapshot
        vmId = [string](Get-HcrPropertyValue $owned.vm 'id')
        vmName = [string](Get-HcrPropertyValue $owned.vm 'name')
        ownershipId = [string](Get-HcrPropertyValue $owned.ownership 'ownershipId')
        ownershipRecordSha256 = Get-HcrOwnershipRecordSha256 $owned.ownership
        vmFingerprint = Get-HcrVmFingerprint $owned.vm
        currentState = $expected[0]
        action = $action
        targetState = $expected[1]
        preconditions = [pscustomobject][ordered]@{
            ownershipVerified = $true
            vmStateSupported = $true
            noTransitionInProgress = $true
        }
    }
    Save-HcrPlanRecord (New-HcrV2PlanRecord $plan)
    return [pscustomobject][ordered]@{
        changed = $false
        data = [pscustomobject][ordered]@{ plan = $plan }
        warnings = @()
    }
}

function Assert-HcrVmPowerPlanDriftFree {
    param([Parameter(Mandatory = $true)][object]$Plan)

    $hostSnapshot = Assert-HcrV2HostAvailable -RequireElevation
    if ((Get-HcrHostFingerprint $hostSnapshot) -ne
        [string](Get-HcrPropertyValue $Plan 'hostFingerprint')) {
        Throw-HcrError 'PLAN_DRIFT' 'The host fingerprint changed after power planning.'
    }
    $owned = Get-HcrRequiredOwnedVm ([string](Get-HcrPropertyValue $Plan 'vmName'))
    if ([string](Get-HcrPropertyValue $owned.vm 'id') -ne
            [string](Get-HcrPropertyValue $Plan 'vmId') -or
        [string](Get-HcrPropertyValue $owned.ownership 'ownershipId') -ne
            [string](Get-HcrPropertyValue $Plan 'ownershipId') -or
        (Get-HcrOwnershipRecordSha256 $owned.ownership) -ne
            [string](Get-HcrPropertyValue $Plan 'ownershipRecordSha256') -or
        (Get-HcrVmFingerprint $owned.vm) -ne
            [string](Get-HcrPropertyValue $Plan 'vmFingerprint') -or
        [string](Get-HcrPropertyValue $owned.vm 'state') -ne
            [string](Get-HcrPropertyValue $Plan 'currentState')) {
        Throw-HcrError 'PLAN_DRIFT' 'The VM power or ownership binding changed after planning.'
    }
    return $owned
}

function Invoke-HcrApplyVmPower {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $record = Consume-HcrPlanRecord ([string](Get-HcrPropertyValue $Arguments 'planId'))
    if ([int](Get-HcrPropertyValue $record 'schemaVersion' 0) -ne 2) {
        Throw-HcrError 'PLAN_INVALID' 'The consumed power plan record has an unsupported schema version.'
    }
    $plan = Assert-HcrPlanUsable $record 'vmPower'
    $owned = Assert-HcrVmPowerPlanDriftFree $plan
    $result = Invoke-HcrAdapter 'SetVmPower' ([pscustomobject][ordered]@{
        action = [string](Get-HcrPropertyValue $plan 'action')
        expectedState = [string](Get-HcrPropertyValue $plan 'currentState')
        targetState = [string](Get-HcrPropertyValue $plan 'targetState')
        expectedVmFingerprint = [string](Get-HcrPropertyValue $plan 'vmFingerprint')
        expectedVmId = [string](Get-HcrPropertyValue $owned.vm 'id')
        expectedVmName = [string](Get-HcrPropertyValue $owned.vm 'name')
        expectedOwnershipId = [string](Get-HcrPropertyValue $owned.ownership 'ownershipId')
        expectedVmPath = [string](Get-HcrPropertyValue $owned.vm 'vmPath')
        expectedVhdxPath = [string](Get-HcrPropertyValue $owned.vm 'vhdxPath')
    })
    if ([string](Get-HcrPropertyValue $result 'previousState') -ne
            [string](Get-HcrPropertyValue $plan 'currentState') -or
        [string](Get-HcrPropertyValue $result 'currentState') -ne
            [string](Get-HcrPropertyValue $plan 'targetState') -or
        [string](Get-HcrPropertyValue $result 'effectState') -ne 'confirmed') {
        Throw-HcrPartialMutationError `
            'POWER_TRANSITION_FAILED' `
            'The power transition returned an unbound final state.' `
            'indeterminate' `
            ([pscustomobject][ordered]@{
                resourceType = 'vmPower'
                vmId = [string](Get-HcrPropertyValue $plan 'vmId')
                vmName = [string](Get-HcrPropertyValue $plan 'vmName')
                action = [string](Get-HcrPropertyValue $plan 'action')
            }) `
            'The planned VM power transition may have taken effect. Inspect the exact managed VM before creating a new plan.'
    }
    return [pscustomobject][ordered]@{
        changed = $true
        data = [pscustomobject][ordered]@{
            planId = [string](Get-HcrPropertyValue $plan 'planId')
            vmId = [string](Get-HcrPropertyValue $plan 'vmId')
            vmName = [string](Get-HcrPropertyValue $plan 'vmName')
            action = [string](Get-HcrPropertyValue $plan 'action')
            previousState = [string](Get-HcrPropertyValue $result 'previousState')
            currentState = [string](Get-HcrPropertyValue $result 'currentState')
            effectState = 'confirmed'
        }
        warnings = @()
    }
}

function Get-HcrOwnedNetworkBaseline {
    param(
        [Parameter(Mandatory = $true)][object]$Owned,
        [Parameter(Mandatory = $true)][object]$Primary
    )

    $baseline = Get-HcrPropertyValue $Owned.ownership 'networkBaseline'
    if ($null -eq $baseline -or
        [string](Get-HcrPropertyValue $baseline 'adapterId') -ne [string]$Primary.id -or
        [string](Get-HcrPropertyValue $baseline 'adapterName') -ne [string]$Primary.name -or
        [string](Get-HcrPropertyValue $baseline 'macAddress') -ne [string]$Primary.macAddress) {
        Throw-HcrError 'BASELINE_UNAVAILABLE' 'The managed primary adapter has no matching recorded baseline.'
    }
    $attachment = Get-HcrPropertyValue $baseline 'attachment'
    if ($null -eq $attachment -or
        [string](Get-HcrPropertyValue $attachment 'mode') -ne 'connected') {
        Throw-HcrError 'BASELINE_UNAVAILABLE' 'The recorded primary-adapter baseline is not connected.'
    }
    return Copy-HcrObject $attachment
}

function New-HcrVmNetworkPlan {
    param(
        [Parameter(Mandatory = $true)][object]$Owned,
        [Parameter(Mandatory = $true)][object]$Primary,
        [Parameter(Mandatory = $true)][object]$Baseline,
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][string]$PlanId,
        [AllowNull()][string]$PairedPlanId,
        [Parameter(Mandatory = $true)][DateTimeOffset]$Created,
        [Parameter(Mandatory = $true)][DateTimeOffset]$Expires,
        [Parameter(Mandatory = $true)][string]$HostFingerprint,
        [Parameter(Mandatory = $true)][object]$CurrentAttachment,
        [Parameter(Mandatory = $true)][string]$Target
    )

    $targetAttachment = if ($Target -eq 'baseline') {
        Copy-HcrObject $Baseline
    }
    else { [pscustomobject][ordered]@{ mode = 'disconnected' } }
    return [pscustomobject][ordered]@{
        schemaVersion = 2
        planKind = 'vmNetwork'
        planRole = $Role
        planId = $PlanId
        pairedPlanId = $PairedPlanId
        createdAt = $Created.ToString('o')
        expiresAt = $Expires.ToString('o')
        hostFingerprint = $HostFingerprint
        vmId = [string](Get-HcrPropertyValue $Owned.vm 'id')
        vmName = [string](Get-HcrPropertyValue $Owned.vm 'name')
        ownershipId = [string](Get-HcrPropertyValue $Owned.ownership 'ownershipId')
        ownershipRecordSha256 = Get-HcrOwnershipRecordSha256 $Owned.ownership
        vmFingerprint = Get-HcrVmNetworkInvariantFingerprint $Owned.vm
        adapter = [pscustomobject][ordered]@{
            id = [string]$Primary.id
            name = [string]$Primary.name
            macAddress = [string]$Primary.macAddress
            fingerprint = [string]$Primary.fingerprint
        }
        baselineAttachment = Copy-HcrObject $Baseline
        currentAttachment = Copy-HcrObject $CurrentAttachment
        target = $Target
        targetAttachment = $targetAttachment
        preconditions = [pscustomobject][ordered]@{
            ownershipVerified = $true
            primaryAdapterVerified = $true
            baselineSwitchPresent = $true
            noAdapterConfigurationDrift = $true
        }
    }
}

function Save-HcrNetworkPlanSet {
    param(
        [Parameter(Mandatory = $true)][object]$ChangePlan,
        [AllowNull()][object]$RecoveryPlan
    )

    if ($null -eq $RecoveryPlan) {
        Save-HcrPlanRecord (New-HcrV2PlanRecord $ChangePlan)
        return
    }
    $changeRecord = New-HcrV2PlanRecord $ChangePlan
    $recoveryRecord = New-HcrV2PlanRecord $RecoveryPlan
    $changeId = [string](Get-HcrPropertyValue $ChangePlan 'planId')
    $plansRoot = Split-Path -Parent (Get-HcrStateSubpath 'plans' "$changeId.json")
    $pairPath = Join-Path $plansRoot ("network-pair-{0}.json" -f $changeId)
    $pair = [pscustomobject][ordered]@{
        schemaVersion = 2
        pairKind = 'vmNetwork'
        change = $changeRecord
        recovery = $recoveryRecord
    }
    [void](Invoke-HcrFileLock 'network-plan-pairs' {
        if (Test-Path -LiteralPath $pairPath) {
            Throw-HcrError 'STATE_BUSY' 'The generated network plan pair already exists.'
        }
        Write-HcrJsonFile $pairPath $pair
    })
}

function Get-HcrNetworkPlanRecord {
    param([Parameter(Mandatory = $true)][string]$PlanId)

    if (-not (Test-HcrUuid $PlanId)) {
        Throw-HcrError 'PLAN_NOT_FOUND' 'The requested plan does not exist.'
    }
    $ordinaryPath = Get-HcrStateSubpath 'plans' "$PlanId.json"
    if (Test-Path -LiteralPath $ordinaryPath -PathType Leaf) {
        $record = Get-HcrPlanRecord $PlanId
        if ([bool](Get-HcrPropertyValue $record 'consumed' $false) -or
            $null -ne (Get-HcrPropertyValue $record 'consumedAt')) {
            Throw-HcrError 'PLAN_ALREADY_CONSUMED' 'The plan has already been consumed.'
        }
        return $record
    }
    return Invoke-HcrFileLock 'network-plan-pairs' {
        $plansRoot = Split-Path -Parent $ordinaryPath
        $pairFiles = @(Get-ChildItem -LiteralPath $plansRoot -File -Filter 'network-pair-*.json')
        if ($pairFiles.Count -gt 4096) {
            Throw-HcrError 'PLAN_INVALID' 'The network plan-pair store exceeds its fixed bound.'
        }
        foreach ($pairFile in $pairFiles) {
            $pair = Read-HcrJsonFile $pairFile.FullName 'PLAN_INVALID'
            if ([int](Get-HcrPropertyValue $pair 'schemaVersion' 0) -ne 2 -or
                [string](Get-HcrPropertyValue $pair 'pairKind') -ne 'vmNetwork') {
                Throw-HcrError 'PLAN_INVALID' 'The network plan-pair store contains an invalid record.'
            }
            foreach ($role in @('change', 'recovery')) {
                $record = Get-HcrPropertyValue $pair $role
                if ($null -eq $record -or
                    [string](Get-HcrPropertyValue (Get-HcrPropertyValue $record 'plan') 'planId') -ne $PlanId) {
                    continue
                }
                if ([bool](Get-HcrPropertyValue $record 'consumed' $false) -or
                    $null -ne (Get-HcrPropertyValue $record 'consumedAt')) {
                    Throw-HcrError 'PLAN_ALREADY_CONSUMED' 'The plan has already been consumed.'
                }
                return Copy-HcrObject $record
            }
        }
        Throw-HcrError 'PLAN_NOT_FOUND' 'The requested plan does not exist.'
    }
}

function Consume-HcrNetworkPlanRecord {
    param(
        [Parameter(Mandatory = $true)][string]$PlanId,
        [Parameter(Mandatory = $true)][string]$ExpectedPlanSha256
    )

    if (-not (Test-HcrUuid $PlanId)) {
        Throw-HcrError 'PLAN_NOT_FOUND' 'The requested plan does not exist.'
    }
    if ($ExpectedPlanSha256 -notmatch '^[a-f0-9]{64}$') {
        Throw-HcrError 'PLAN_INVALID' 'The expected network plan digest is invalid.'
    }
    $ordinaryPath = Get-HcrStateSubpath 'plans' "$PlanId.json"
    if (Test-Path -LiteralPath $ordinaryPath -PathType Leaf) {
        return Invoke-HcrFileLock "plan-$PlanId" {
            $record = Read-HcrJsonFile $ordinaryPath 'PLAN_NOT_FOUND'
            if ([bool](Get-HcrPropertyValue $record 'consumed' $false) -or
                $null -ne (Get-HcrPropertyValue $record 'consumedAt')) {
                Throw-HcrError 'PLAN_ALREADY_CONSUMED' 'The plan has already been consumed.'
            }
            if ((Get-HcrSha256Text (ConvertTo-HcrJson (Get-HcrPropertyValue $record 'plan') 100)) -ne
                $ExpectedPlanSha256) {
                Throw-HcrError 'PLAN_DRIFT' 'The network plan record changed after precondition validation.'
            }
            $record.consumed = $true
            $record.consumedAt = [DateTimeOffset]::UtcNow.ToString('o')
            Save-HcrPlanRecord $record
            return $record
        }
    }
    return Invoke-HcrFileLock 'network-plan-pairs' {
        $plansRoot = Split-Path -Parent $ordinaryPath
        $pairFiles = @(Get-ChildItem -LiteralPath $plansRoot -File -Filter 'network-pair-*.json')
        if ($pairFiles.Count -gt 4096) {
            Throw-HcrError 'PLAN_INVALID' 'The network plan-pair store exceeds its fixed bound.'
        }
        foreach ($pairFile in $pairFiles) {
            $pair = Read-HcrJsonFile $pairFile.FullName 'PLAN_INVALID'
            if ([int](Get-HcrPropertyValue $pair 'schemaVersion' 0) -ne 2 -or
                [string](Get-HcrPropertyValue $pair 'pairKind') -ne 'vmNetwork') {
                Throw-HcrError 'PLAN_INVALID' 'The network plan-pair store contains an invalid record.'
            }
            foreach ($role in @('change', 'recovery')) {
                $record = Get-HcrPropertyValue $pair $role
                if ($null -eq $record -or
                    [string](Get-HcrPropertyValue (Get-HcrPropertyValue $record 'plan') 'planId') -ne $PlanId) {
                    continue
                }
                if ([bool](Get-HcrPropertyValue $record 'consumed' $false) -or
                    $null -ne (Get-HcrPropertyValue $record 'consumedAt')) {
                    Throw-HcrError 'PLAN_ALREADY_CONSUMED' 'The plan has already been consumed.'
                }
                if ((Get-HcrSha256Text (ConvertTo-HcrJson (Get-HcrPropertyValue $record 'plan') 100)) -ne
                    $ExpectedPlanSha256) {
                    Throw-HcrError 'PLAN_DRIFT' 'The network plan record changed after precondition validation.'
                }
                $record.consumed = $true
                $record.consumedAt = [DateTimeOffset]::UtcNow.ToString('o')
                Write-HcrJsonFile $pairFile.FullName $pair
                return Copy-HcrObject $record
            }
        }
        Throw-HcrError 'PLAN_NOT_FOUND' 'The requested plan does not exist.'
    }
}

function Invoke-HcrPlanVmNetwork {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $hostSnapshot = Assert-HcrV2HostAvailable
    $owned = Get-HcrRequiredOwnedVm ([string](Get-HcrPropertyValue $Arguments 'vmName'))
    $primary = Get-HcrVerifiedPrimaryAdapter $owned.vm
    $baseline = Get-HcrOwnedNetworkBaseline $owned $primary
    $baselineSwitch = Invoke-HcrAdapter 'GetSwitch' ([pscustomobject]@{
        name = [string](Get-HcrPropertyValue $baseline 'switchName')
    })
    if ($null -eq $baselineSwitch -or
        [string](Get-HcrPropertyValue $baselineSwitch 'id') -ne
            [string](Get-HcrPropertyValue $baseline 'switchId')) {
        Throw-HcrError 'BASELINE_UNAVAILABLE' 'The recorded baseline virtual switch is unavailable.'
    }
    $target = [string](Get-HcrPropertyValue $Arguments 'target')
    $current = $primary.attachment
    if ($target -eq 'disconnected') {
        if (-not (Test-HcrBoundObjectEqual $current $baseline)) {
            Throw-HcrError 'STATE_BUSY' 'Disconnect planning requires the exact recorded baseline attachment.'
        }
    }
    elseif ($target -eq 'baseline') {
        if ([string](Get-HcrPropertyValue $current 'mode') -ne 'disconnected') {
            Throw-HcrError 'STATE_BUSY' 'Baseline recovery planning requires the primary adapter to be disconnected.'
        }
    }
    else {
        Throw-HcrError 'INVALID_ARGUMENT' 'The network target is not supported.'
    }
    $created = [DateTimeOffset]::UtcNow
    $hostFingerprint = Get-HcrHostFingerprint $hostSnapshot
    $changeId = [Guid]::NewGuid().ToString()
    $recoveryId = if ($target -eq 'disconnected') { [Guid]::NewGuid().ToString() } else { $null }
    $change = New-HcrVmNetworkPlan `
        $owned $primary $baseline 'change' $changeId $recoveryId `
        $created $created.AddMinutes(15) $hostFingerprint $current $target
    $recovery = if ($target -eq 'disconnected') {
        New-HcrVmNetworkPlan `
            $owned $primary $baseline 'recovery' $recoveryId $changeId `
            $created $created.AddHours(24) $hostFingerprint `
            ([pscustomobject][ordered]@{ mode = 'disconnected' }) 'baseline'
    }
    else { $null }
    Save-HcrNetworkPlanSet $change $recovery
    return [pscustomobject][ordered]@{
        changed = $false
        data = [pscustomobject][ordered]@{
            changePlan = $change
            recoveryPlan = $recovery
        }
        warnings = @()
    }
}

function Assert-HcrVmNetworkPlanDriftFree {
    param([Parameter(Mandatory = $true)][object]$Plan)

    $hostSnapshot = Assert-HcrV2HostAvailable -RequireElevation
    if ((Get-HcrHostFingerprint $hostSnapshot) -ne
        [string](Get-HcrPropertyValue $Plan 'hostFingerprint')) {
        Throw-HcrError 'PLAN_DRIFT' 'The host fingerprint changed after network planning.'
    }
    $owned = Get-HcrRequiredOwnedVm ([string](Get-HcrPropertyValue $Plan 'vmName'))
    $primary = Get-HcrVerifiedPrimaryAdapter $owned.vm
    $baseline = Get-HcrOwnedNetworkBaseline $owned $primary
    $planAdapter = Get-HcrPropertyValue $Plan 'adapter'
    if ([string](Get-HcrPropertyValue $owned.vm 'id') -ne
            [string](Get-HcrPropertyValue $Plan 'vmId') -or
        [string](Get-HcrPropertyValue $owned.ownership 'ownershipId') -ne
            [string](Get-HcrPropertyValue $Plan 'ownershipId') -or
        (Get-HcrOwnershipRecordSha256 $owned.ownership) -ne
            [string](Get-HcrPropertyValue $Plan 'ownershipRecordSha256') -or
        (Get-HcrVmNetworkInvariantFingerprint $owned.vm) -ne
            [string](Get-HcrPropertyValue $Plan 'vmFingerprint') -or
        [string]$primary.id -ne [string](Get-HcrPropertyValue $planAdapter 'id') -or
        [string]$primary.fingerprint -ne [string](Get-HcrPropertyValue $planAdapter 'fingerprint') -or
        -not (Test-HcrBoundObjectEqual $baseline (Get-HcrPropertyValue $Plan 'baselineAttachment')) -or
        -not (Test-HcrBoundObjectEqual $primary.attachment (Get-HcrPropertyValue $Plan 'currentAttachment'))) {
        Throw-HcrError 'PLAN_DRIFT' 'The VM, ownership, adapter, baseline, or attachment changed after network planning.'
    }
    $baselineSwitch = Invoke-HcrAdapter 'GetSwitch' ([pscustomobject]@{
        name = [string](Get-HcrPropertyValue $baseline 'switchName')
    })
    if ($null -eq $baselineSwitch -or
        [string](Get-HcrPropertyValue $baselineSwitch 'id') -ne
            [string](Get-HcrPropertyValue $baseline 'switchId')) {
        Throw-HcrError 'PLAN_DRIFT' 'The baseline virtual switch changed after planning.'
    }
    return [pscustomobject][ordered]@{
        owned = $owned
        primary = $primary
        baseline = $baseline
    }
}

function Assert-HcrPairedNetworkRecoveryUsable {
    param(
        [Parameter(Mandatory = $true)][object]$ChangePlan,
        [Parameter(Mandatory = $true)][object]$RecoveryRecord
    )

    if ([int](Get-HcrPropertyValue $RecoveryRecord 'schemaVersion' 0) -ne 2) {
        Throw-HcrError 'PLAN_INVALID' 'The paired recovery record has an unsupported schema version.'
    }
    $recoveryPlan = Assert-HcrPlanUsable $RecoveryRecord 'vmNetwork'
    $changeAdapter = Get-HcrPropertyValue $ChangePlan 'adapter'
    $recoveryAdapter = Get-HcrPropertyValue $recoveryPlan 'adapter'
    $identityFields = @(
        'hostFingerprint',
        'vmId',
        'vmName',
        'ownershipId',
        'ownershipRecordSha256',
        'vmFingerprint'
    )
    $identityMismatch = @($identityFields | Where-Object {
            [string](Get-HcrPropertyValue $ChangePlan $_) -ne
                [string](Get-HcrPropertyValue $recoveryPlan $_)
        }).Count -gt 0
    $changeBaseline = Get-HcrPropertyValue $ChangePlan 'baselineAttachment'
    $changeCurrent = Get-HcrPropertyValue $ChangePlan 'currentAttachment'
    $changeTarget = Get-HcrPropertyValue $ChangePlan 'targetAttachment'
    $recoveryBaseline = Get-HcrPropertyValue $recoveryPlan 'baselineAttachment'
    $recoveryCurrent = Get-HcrPropertyValue $recoveryPlan 'currentAttachment'
    $recoveryTarget = Get-HcrPropertyValue $recoveryPlan 'targetAttachment'
    $adapterMismatch = -not (Test-HcrBoundObjectEqual $changeAdapter $recoveryAdapter)
    $baselineMismatch = -not (Test-HcrBoundObjectEqual $changeBaseline $recoveryBaseline)
    $inverseTargetMismatch = -not (Test-HcrBoundObjectEqual $changeCurrent $recoveryTarget)
    $inverseCurrentMismatch = -not (Test-HcrBoundObjectEqual $changeTarget $recoveryCurrent)
    $changeBaselineMismatch = -not (Test-HcrBoundObjectEqual $changeCurrent $changeBaseline)
    if ([int](Get-HcrPropertyValue $recoveryPlan 'schemaVersion' 0) -ne 2 -or
        [string](Get-HcrPropertyValue $recoveryPlan 'planKind') -ne 'vmNetwork' -or
        [string](Get-HcrPropertyValue $ChangePlan 'planRole') -ne 'change' -or
        [string](Get-HcrPropertyValue $ChangePlan 'target') -ne 'disconnected' -or
        [string](Get-HcrPropertyValue $recoveryPlan 'planRole') -ne 'recovery' -or
        [string](Get-HcrPropertyValue $recoveryPlan 'target') -ne 'baseline' -or
        [string](Get-HcrPropertyValue $ChangePlan 'pairedPlanId') -ne
            [string](Get-HcrPropertyValue $recoveryPlan 'planId') -or
        [string](Get-HcrPropertyValue $recoveryPlan 'pairedPlanId') -ne
            [string](Get-HcrPropertyValue $ChangePlan 'planId') -or
        $identityMismatch -or $adapterMismatch -or $baselineMismatch -or
        $inverseTargetMismatch -or $inverseCurrentMismatch -or
        $changeBaselineMismatch -or
        [string](Get-HcrPropertyValue $changeTarget 'mode') -ne 'disconnected') {
        Throw-HcrError 'PLAN_INVALID' 'The disconnect plan is not bound to an exact usable recovery plan.'
    }
    return $recoveryPlan
}

function Invoke-HcrApplyVmNetwork {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $planId = [string](Get-HcrPropertyValue $Arguments 'planId')
    $previewRecord = Get-HcrNetworkPlanRecord $planId
    $previewPlan = Get-HcrPropertyValue $previewRecord 'plan'
    $planRole = [string](Get-HcrPropertyValue $previewPlan 'planRole')
    if ($planRole -eq 'recovery') {
        if ([int](Get-HcrPropertyValue $previewRecord 'schemaVersion' 0) -ne 2) {
            Throw-HcrError 'PLAN_INVALID' 'The recovery plan record has an unsupported schema version.'
        }
        if ([string](Get-HcrPropertyValue $previewRecord 'planKind') -ne 'vmNetwork' -or
            $null -eq $previewPlan -or
            -not (Test-HcrDateTimeString (Get-HcrPropertyValue $previewPlan 'expiresAt'))) {
            Throw-HcrError 'PLAN_INVALID' 'The recovery plan record is invalid.'
        }
        [void](Assert-HcrVmNetworkPlanDriftFree $previewPlan)
    }
    $expectedPlanSha256 = Get-HcrSha256Text (ConvertTo-HcrJson $previewPlan 100)
    $record = Consume-HcrNetworkPlanRecord $planId $expectedPlanSha256
    if ([int](Get-HcrPropertyValue $record 'schemaVersion' 0) -ne 2) {
        Throw-HcrError 'PLAN_INVALID' 'The consumed network plan record has an unsupported schema version.'
    }
    $plan = Assert-HcrPlanUsable $record 'vmNetwork'
    $bound = Assert-HcrVmNetworkPlanDriftFree $plan
    if ([string](Get-HcrPropertyValue $plan 'planRole') -eq 'change' -and
        [string](Get-HcrPropertyValue $plan 'target') -eq 'disconnected') {
        $pairedRecoveryId = [string](Get-HcrPropertyValue $plan 'pairedPlanId')
        $pairedRecoveryRecord = Get-HcrNetworkPlanRecord $pairedRecoveryId
        [void](Assert-HcrPairedNetworkRecoveryUsable $plan $pairedRecoveryRecord)
    }
    $recoveryPlanId = if (
        [string](Get-HcrPropertyValue $plan 'planRole') -eq 'change' -and
        [string](Get-HcrPropertyValue $plan 'target') -eq 'disconnected'
    ) { [string](Get-HcrPropertyValue $plan 'pairedPlanId') } else { $null }
    $result = Invoke-HcrAdapter 'SetVmNetwork' ([pscustomobject][ordered]@{
        planRole = [string](Get-HcrPropertyValue $plan 'planRole')
        target = [string](Get-HcrPropertyValue $plan 'target')
        expectedAttachment = Get-HcrPropertyValue $plan 'currentAttachment'
        targetAttachment = Get-HcrPropertyValue $plan 'targetAttachment'
        expectedVmFingerprint = [string](Get-HcrPropertyValue $plan 'vmFingerprint')
        expectedAdapterFingerprint = [string](Get-HcrPropertyValue (Get-HcrPropertyValue $plan 'adapter') 'fingerprint')
        expectedAdapterId = [string](Get-HcrPropertyValue (Get-HcrPropertyValue $plan 'adapter') 'id')
        recoveryPlanId = $recoveryPlanId
        expectedVmId = [string](Get-HcrPropertyValue $bound.owned.vm 'id')
        expectedVmName = [string](Get-HcrPropertyValue $bound.owned.vm 'name')
        expectedOwnershipId = [string](Get-HcrPropertyValue $bound.owned.ownership 'ownershipId')
        expectedVmPath = [string](Get-HcrPropertyValue $bound.owned.vm 'vmPath')
        expectedVhdxPath = [string](Get-HcrPropertyValue $bound.owned.vm 'vhdxPath')
    })
    $actualPrevious = Get-HcrPropertyValue $result 'previousAttachment'
    $expectedPrevious = Get-HcrPropertyValue $plan 'currentAttachment'
    $actualCurrent = Get-HcrPropertyValue $result 'currentAttachment'
    $expectedCurrent = Get-HcrPropertyValue $plan 'targetAttachment'
    if (-not (Test-HcrBoundObjectEqual $actualPrevious $expectedPrevious) -or
        -not (Test-HcrBoundObjectEqual $actualCurrent $expectedCurrent) -or
        [string](Get-HcrPropertyValue $result 'effectState') -ne 'confirmed') {
        $details = if ([string]::IsNullOrWhiteSpace($recoveryPlanId)) {
            $null
        }
        else { [pscustomobject][ordered]@{ recoveryPlanId = $recoveryPlanId } }
        Throw-HcrPartialMutationError `
            $(if ($null -eq $details) { 'NETWORK_TRANSITION_FAILED' } else { 'NETWORK_RECOVERY_REQUIRED' }) `
            'The network transition returned an unbound final attachment.' `
            'indeterminate' `
            ([pscustomobject][ordered]@{
                resourceType = 'vmNetwork'
                vmId = [string](Get-HcrPropertyValue $plan 'vmId')
                vmName = [string](Get-HcrPropertyValue $plan 'vmName')
                adapterId = [string](Get-HcrPropertyValue (Get-HcrPropertyValue $plan 'adapter') 'id')
                target = [string](Get-HcrPropertyValue $plan 'target')
            }) `
            'The planned adapter transition may have taken effect. Use only the pre-created recovery plan when recovery is required.' `
            $details
    }
    $recoveryRequired = [string](Get-HcrPropertyValue $plan 'planRole') -eq 'change' -and
        [string](Get-HcrPropertyValue $plan 'target') -eq 'disconnected'
    return [pscustomobject][ordered]@{
        changed = $true
        data = [pscustomobject][ordered]@{
            planId = [string](Get-HcrPropertyValue $plan 'planId')
            pairedPlanId = Get-HcrPropertyValue $plan 'pairedPlanId'
            planRole = [string](Get-HcrPropertyValue $plan 'planRole')
            vmId = [string](Get-HcrPropertyValue $plan 'vmId')
            vmName = [string](Get-HcrPropertyValue $plan 'vmName')
            adapterId = [string](Get-HcrPropertyValue (Get-HcrPropertyValue $plan 'adapter') 'id')
            target = [string](Get-HcrPropertyValue $plan 'target')
            previousAttachment = Get-HcrPropertyValue $result 'previousAttachment'
            currentAttachment = Get-HcrPropertyValue $result 'currentAttachment'
            effectState = 'confirmed'
            recoveryRequired = $recoveryRequired
        }
        warnings = @()
    }
}

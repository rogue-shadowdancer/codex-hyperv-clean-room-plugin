function Get-HcrHostFingerprint {
    param([Parameter(Mandatory = $true)][object]$HostSnapshot)

    $fingerprintInput = [ordered]@{
        computerName = [string](Get-HcrPropertyValue $HostSnapshot 'computerName')
        windowsEdition = [string](Get-HcrPropertyValue $HostSnapshot 'windowsEdition')
        windowsBuild = [string](Get-HcrPropertyValue $HostSnapshot 'windowsBuild')
        architecture = [string](Get-HcrPropertyValue $HostSnapshot 'architecture')
        hyperVCommandsAvailable = [bool](Get-HcrPropertyValue $HostSnapshot 'hyperVCommandsAvailable' $false)
        hypervisorPresent = [bool](Get-HcrPropertyValue $HostSnapshot 'hypervisorPresent' $false)
        elevated = [bool](Get-HcrPropertyValue $HostSnapshot 'elevated' $false)
    }
    return Get-HcrSha256Text (ConvertTo-HcrJson $fingerprintInput 10)
}

function Get-HcrVmFingerprint {
    param([Parameter(Mandatory = $true)][object]$Vm)

    $fingerprintInput = [ordered]@{
        id = [string](Get-HcrPropertyValue $Vm 'id')
        name = [string](Get-HcrPropertyValue $Vm 'name')
        generation = Get-HcrPropertyValue $Vm 'generation'
        notes = [string](Get-HcrPropertyValue $Vm 'notes')
        vmPath = [string](Get-HcrPropertyValue $Vm 'vmPath')
        vhdxPath = [string](Get-HcrPropertyValue $Vm 'vhdxPath')
        processorCount = Get-HcrPropertyValue $Vm 'processorCount'
        startupMemoryGb = Get-HcrPropertyValue $Vm 'startupMemoryGb'
        maximumMemoryGb = Get-HcrPropertyValue $Vm 'maximumMemoryGb'
        switchId = [string](Get-HcrPropertyValue $Vm 'switchId')
        secureBoot = [bool](Get-HcrPropertyValue $Vm 'secureBoot' $false)
        vtpm = [bool](Get-HcrPropertyValue $Vm 'vtpm' $false)
    }
    return Get-HcrSha256Text (ConvertTo-HcrJson $fingerprintInput 20)
}

function Get-HcrCheckpointInventoryFingerprint {
    param([Parameter(Mandatory = $true)][object]$Vm)

    $inventory = @(@((Get-HcrPropertyValue $Vm 'checkpoints' @())) |
        Sort-Object { [string](Get-HcrPropertyValue $_ 'id') } |
        ForEach-Object {
            [ordered]@{
                id = [string](Get-HcrPropertyValue $_ 'id')
                name = [string](Get-HcrPropertyValue $_ 'name')
                parentId = Get-HcrPropertyValue $_ 'parentId'
                configurationFingerprint = [string](Get-HcrPropertyValue $_ 'configurationFingerprint')
                createdAt = [string](Get-HcrPropertyValue $_ 'createdAt')
            }
        })
    return Get-HcrSha256Text (ConvertTo-HcrJson $inventory 30)
}

function Get-HcrCurrentStateFingerprint {
    param([Parameter(Mandatory = $true)][object]$Vm)

    $state = [ordered]@{
        id = [string](Get-HcrPropertyValue $Vm 'id')
        state = [string](Get-HcrPropertyValue $Vm 'state')
        currentStateNonce = [string](Get-HcrPropertyValue $Vm 'currentStateNonce')
    }
    return Get-HcrSha256Text (ConvertTo-HcrJson $state 10)
}

function Get-HcrCheckpointFingerprint {
    param([Parameter(Mandatory = $true)][object]$Checkpoint)

    $state = [ordered]@{
        id = [string](Get-HcrPropertyValue $Checkpoint 'id')
        name = [string](Get-HcrPropertyValue $Checkpoint 'name')
        parentId = Get-HcrPropertyValue $Checkpoint 'parentId'
        configurationFingerprint = [string](Get-HcrPropertyValue $Checkpoint 'configurationFingerprint')
        createdAt = [string](Get-HcrPropertyValue $Checkpoint 'createdAt')
    }
    return Get-HcrSha256Text (ConvertTo-HcrJson $state 10)
}

function Get-HcrOwnershipStatus {
    param([Parameter(Mandatory = $true)][object]$Vm)

    $vmId = [string](Get-HcrPropertyValue $Vm 'id')
    $record = if ([string]::IsNullOrWhiteSpace($vmId)) {
        $null
    }
    else {
        Get-HcrOwnershipRecordByVmId $vmId
    }
    if ($null -eq $record) {
        return [pscustomobject][ordered]@{
            verified = $false
            status = 'unmanaged'
            record = $null
        }
    }
    $ownershipId = [string](Get-HcrPropertyValue $record 'ownershipId')
    $marker = "hyperv-clean-room/v1:$ownershipId"
    $verified = (
        [string](Get-HcrPropertyValue $record 'vmId') -eq $vmId -and
        [string](Get-HcrPropertyValue $record 'vmName') -eq [string](Get-HcrPropertyValue $Vm 'name') -and
        [string](Get-HcrPropertyValue $Vm 'notes') -eq $marker
    )
    if ($verified) {
        try {
            $recordVmRoot = Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $record 'vmRoot'))
            $recordVmPath = Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $record 'vmPath'))
            $recordVhdxPath = Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $record 'vhdxPath'))
            $liveVmPath = Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $Vm 'vmPath'))
            $liveVhdxPath = Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $Vm 'vhdxPath'))
            $verified = $recordVmRoot -eq (Get-HcrNormalizedPath (Split-Path -Parent $recordVmPath)) -and
                $recordVmPath -eq $liveVmPath -and
                $recordVhdxPath -eq $liveVhdxPath
        }
        catch {
            $verified = $false
        }
    }
    return [pscustomobject][ordered]@{
        verified = $verified
        status = if ($verified) { 'verified' } else { 'OWNERSHIP_UNVERIFIED' }
        record = $record
    }
}

function Get-HcrRequiredOwnedVm {
    param([Parameter(Mandatory = $true)][string]$VmName)

    $vm = Invoke-HcrAdapter 'GetVm' ([pscustomobject]@{ name = $VmName })
    if ($null -eq $vm) {
        Throw-HcrError 'VM_NOT_FOUND' 'The requested VM does not exist.'
    }
    $ownership = Get-HcrOwnershipStatus $vm
    if (-not $ownership.verified) {
        Throw-HcrError 'OWNERSHIP_UNVERIFIED' 'VM ownership could not be verified; mutation and guest access are blocked.'
    }
    return [pscustomobject][ordered]@{
        vm = $vm
        ownership = $ownership.record
    }
}

function Assert-HcrVmName {
    param([Parameter(Mandatory = $true)][string]$Name)

    if ($Name -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9._ -]{0,98}[A-Za-z0-9._-])?$' -or
        $Name.EndsWith('.') -or $Name.EndsWith(' ')) {
        Throw-HcrError 'INVALID_ARGUMENT' 'The VM name contains unsafe path characters.'
    }
}

function New-HcrPlanRecord {
    param(
        [Parameter(Mandatory = $true)][object]$Plan,
        [AllowNull()][string]$ConfirmationTokenHash = $null
    )

    $record = [ordered]@{
        schemaVersion = 1
        planId = [string](Get-HcrPropertyValue $Plan 'planId')
        planKind = [string](Get-HcrPropertyValue $Plan 'planKind')
        consumed = $false
        consumedAt = $null
        plan = $Plan
    }
    if (-not [string]::IsNullOrWhiteSpace($ConfirmationTokenHash)) {
        $record.confirmationTokenHash = $ConfirmationTokenHash
    }
    return [pscustomobject]$record
}

function Assert-HcrPlanUsable {
    param(
        [Parameter(Mandatory = $true)][object]$Record,
        [Parameter(Mandatory = $true)][string]$ExpectedKind
    )

    if ((Get-HcrPropertyValue $Record 'planKind') -ne $ExpectedKind) {
        Throw-HcrError 'PLAN_KIND_MISMATCH' 'The consumed plan is not valid for this apply tool.'
    }
    $plan = Get-HcrPropertyValue $Record 'plan'
    if ($null -eq $plan -or -not (Test-HcrDateTimeString (Get-HcrPropertyValue $plan 'expiresAt'))) {
        Throw-HcrError 'PLAN_INVALID' 'The consumed plan record is invalid.'
    }
    if ([DateTimeOffset]::Parse([string](Get-HcrPropertyValue $plan 'expiresAt')).UtcDateTime -le [DateTime]::UtcNow) {
        Throw-HcrError 'PLAN_EXPIRED' 'The consumed plan has expired; create a new plan.'
    }
    return $plan
}

function Invoke-HcrInspectHost {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $hostSnapshot = Invoke-HcrAdapter 'GetHostSnapshot'
    $data = [ordered]@{
        host = $hostSnapshot
        hostFingerprint = Get-HcrHostFingerprint $hostSnapshot
        targetVolume = $null
        conflicts = [ordered]@{
            vmNameExists = $false
            vmPathExists = $false
        }
    }
    if (Test-HcrProperty $Arguments 'vmRoot') {
        $rootItem = Assert-HcrLocalDirectory ([string](Get-HcrPropertyValue $Arguments 'vmRoot')) 'INVALID_VM_ROOT'
        $volume = Invoke-HcrAdapter 'GetTargetVolume' ([pscustomobject]@{ path = $rootItem.FullName })
        $minimumGb = [int](Get-HcrPropertyValue $Arguments 'minimumFreeSpaceGb' 1)
        $data.targetVolume = [ordered]@{
            uniqueId = [string](Get-HcrPropertyValue $volume 'uniqueId')
            root = [string](Get-HcrPropertyValue $volume 'root')
            fileSystem = [string](Get-HcrPropertyValue $volume 'fileSystem')
            availableBytes = [int64](Get-HcrPropertyValue $volume 'availableBytes')
            minimumRequiredBytes = [int64]$minimumGb * 1GB
            meetsMinimum = [int64](Get-HcrPropertyValue $volume 'availableBytes') -ge ([int64]$minimumGb * 1GB)
        }
        if (Test-HcrProperty $Arguments 'vmName') {
            $candidatePath = Join-Path $rootItem.FullName ([string](Get-HcrPropertyValue $Arguments 'vmName'))
            $data.conflicts.vmPathExists = Test-Path -LiteralPath $candidatePath
        }
    }
    if (Test-HcrProperty $Arguments 'vmName') {
        $vm = Invoke-HcrAdapter 'GetVm' ([pscustomobject]@{ name = [string](Get-HcrPropertyValue $Arguments 'vmName') })
        $data.conflicts.vmNameExists = $null -ne $vm
    }
    return [pscustomobject][ordered]@{ changed = $false; data = [pscustomobject]$data; warnings = @() }
}

function Invoke-HcrListVms {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $managedOnly = [bool](Get-HcrPropertyValue $Arguments 'managedOnly' $true)
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($vm in @(Invoke-HcrAdapter 'ListVms')) {
        $ownership = Get-HcrOwnershipStatus $vm
        if ($managedOnly -and -not $ownership.verified) { continue }
        if ($ownership.verified) {
            $results.Add([pscustomobject][ordered]@{
                name = [string](Get-HcrPropertyValue $vm 'name')
                id = [string](Get-HcrPropertyValue $vm 'id')
                state = [string](Get-HcrPropertyValue $vm 'state')
                generation = Get-HcrPropertyValue $vm 'generation'
                ownershipStatus = 'verified'
                ownershipId = [string](Get-HcrPropertyValue $ownership.record 'ownershipId')
            })
        }
        else {
            $results.Add([pscustomobject][ordered]@{
                name = [string](Get-HcrPropertyValue $vm 'name')
                id = [string](Get-HcrPropertyValue $vm 'id')
                state = [string](Get-HcrPropertyValue $vm 'state')
                generation = Get-HcrPropertyValue $vm 'generation'
                ownershipStatus = [string]$ownership.status
            })
        }
    }
    return [pscustomobject][ordered]@{
        changed = $false
        data = [pscustomobject][ordered]@{ managedOnly = $managedOnly; vms = @($results | ForEach-Object { $_ }) }
        warnings = @()
    }
}

function Invoke-HcrInspectVm {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $vm = Invoke-HcrAdapter 'GetVm' ([pscustomobject]@{ name = [string](Get-HcrPropertyValue $Arguments 'vmName') })
    if ($null -eq $vm) { Throw-HcrError 'VM_NOT_FOUND' 'The requested VM does not exist.' }
    $ownership = Get-HcrOwnershipStatus $vm
    return [pscustomobject][ordered]@{
        changed = $false
        data = [pscustomobject][ordered]@{
            vm = $vm
            ownership = [pscustomobject][ordered]@{
                verified = [bool]$ownership.verified
                status = [string]$ownership.status
                ownershipId = if ($null -eq $ownership.record) { $null } else { [string](Get-HcrPropertyValue $ownership.record 'ownershipId') }
            }
        }
        warnings = @()
    }
}

function Invoke-HcrValidateProfile {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $validation = Read-AndValidate-HcrProfile ([string](Get-HcrPropertyValue $Arguments 'profilePath'))
    if (-not $validation.valid) {
        Throw-HcrError 'PROFILE_INVALID' 'The test profile failed validation.' ([ordered]@{ errors = @($validation.errors) })
    }
    return [pscustomobject][ordered]@{
        changed = $false
        data = [pscustomobject][ordered]@{
            valid = $true
            profileId = [string](Get-HcrPropertyValue $validation.profile 'id')
            cleanupBudgetSeconds = [int]$validation.cleanupBudgetSeconds
        }
        warnings = @()
    }
}

function Invoke-HcrValidateEvidenceTool {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $validation = Read-AndValidate-HcrEvidence ([string](Get-HcrPropertyValue $Arguments 'evidencePath'))
    if (-not $validation.valid) {
        Throw-HcrError 'EVIDENCE_INVALID' 'The evidence document failed validation.' ([ordered]@{ errors = @($validation.errors) })
    }
    return [pscustomobject][ordered]@{
        changed = $false
        data = [pscustomobject][ordered]@{
            valid = $true
            evidenceOperationId = [string](Get-HcrPropertyValue $validation.evidence 'operationId')
            derivedOverallStatus = [string]$validation.derivedOverallStatus
        }
        warnings = @()
    }
}

function Invoke-HcrPlanVmCreate {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $name = [string](Get-HcrPropertyValue $Arguments 'name')
    Assert-HcrVmName $name
    $iso = Assert-HcrRegularLocalFile ([string](Get-HcrPropertyValue $Arguments 'isoPath')) 'INVALID_ISO'
    if ($iso.Extension -ine '.iso' -or $iso.Length -lt 1) {
        Throw-HcrError 'INVALID_ISO' 'isoPath must identify a non-empty .iso regular file.'
    }
    $vmRootItem = Assert-HcrLocalDirectory ([string](Get-HcrPropertyValue $Arguments 'vmRoot')) 'INVALID_VM_ROOT'
    $processorCount = [int](Get-HcrPropertyValue $Arguments 'processorCount' 4)
    $startupMemoryGb = [int](Get-HcrPropertyValue $Arguments 'startupMemoryGb' 8)
    $maximumMemoryGb = [int](Get-HcrPropertyValue $Arguments 'maximumMemoryGb' 12)
    $diskSizeGb = [int](Get-HcrPropertyValue $Arguments 'diskSizeGb' 100)
    if ($maximumMemoryGb -lt $startupMemoryGb) {
        Throw-HcrError 'INVALID_ARGUMENT' 'maximumMemoryGb cannot be smaller than startupMemoryGb.'
    }
    $hostSnapshot = Invoke-HcrAdapter 'GetHostSnapshot'
    if (-not [bool](Get-HcrPropertyValue $hostSnapshot 'hyperVCommandsAvailable' $false) -or
        -not [bool](Get-HcrPropertyValue $hostSnapshot 'hypervisorPresent' $false)) {
        Throw-HcrError 'HYPERV_UNAVAILABLE' 'Hyper-V host prerequisites are unavailable.'
    }
    if (-not [bool](Get-HcrPropertyValue $hostSnapshot 'elevated' $false)) {
        Throw-HcrError 'ELEVATION_REQUIRED' 'VM creation requires an elevated server process.'
    }
    $switch = Invoke-HcrAdapter 'GetSwitch' ([pscustomobject]@{ name = [string](Get-HcrPropertyValue $Arguments 'switchName') })
    if ($null -eq $switch) { Throw-HcrError 'SWITCH_NOT_FOUND' 'The requested virtual switch does not exist.' }
    if ($null -ne (Invoke-HcrAdapter 'GetVm' ([pscustomobject]@{ name = $name }))) {
        Throw-HcrError 'VM_ALREADY_EXISTS' 'A VM with the requested name already exists.'
    }
    $vmPath = Get-HcrNormalizedPath (Join-Path $vmRootItem.FullName $name)
    $vhdxPath = Get-HcrNormalizedPath (Join-Path $vmPath "$name.vhdx")
    if (Test-Path -LiteralPath $vmPath) { Throw-HcrError 'VM_PATH_EXISTS' 'The planned VM path already exists.' }
    if (Test-Path -LiteralPath $vhdxPath) { Throw-HcrError 'VHDX_PATH_EXISTS' 'The planned VHDX path already exists.' }
    $volume = Invoke-HcrAdapter 'GetTargetVolume' ([pscustomobject]@{ path = $vmRootItem.FullName })
    $requiredBytes = ([int64]$diskSizeGb * 1GB) + 2GB
    if ([int64](Get-HcrPropertyValue $volume 'availableBytes') -lt $requiredBytes) {
        Throw-HcrError 'INSUFFICIENT_SPACE' 'The target volume lacks the conservative required capacity.'
    }
    $planId = [Guid]::NewGuid().ToString()
    $created = [DateTimeOffset]::UtcNow
    $plan = [pscustomobject][ordered]@{
        schemaVersion = 1
        planKind = 'vmCreate'
        planId = $planId
        createdAt = $created.ToString('o')
        expiresAt = $created.AddMinutes($script:HcrPlanLifetimeMinutes).ToString('o')
        hostFingerprint = Get-HcrHostFingerprint $hostSnapshot
        isoPath = $iso.FullName
        isoSha256 = Get-HcrSha256File $iso.FullName
        isoSizeBytes = [int64]$iso.Length
        isoLastWriteTimeUtc = $iso.LastWriteTimeUtc.ToString('o')
        switchName = [string](Get-HcrPropertyValue $switch 'name')
        switchId = [string](Get-HcrPropertyValue $switch 'id')
        name = $name
        vmRoot = $vmRootItem.FullName
        vmPath = $vmPath
        vhdxPath = $vhdxPath
        targetVolume = [pscustomobject][ordered]@{
            uniqueId = [string](Get-HcrPropertyValue $volume 'uniqueId')
            root = [string](Get-HcrPropertyValue $volume 'root')
            fileSystem = [string](Get-HcrPropertyValue $volume 'fileSystem')
            availableBytes = [int64](Get-HcrPropertyValue $volume 'availableBytes')
            requiredBytes = $requiredBytes
        }
        preconditions = [pscustomobject][ordered]@{
            isoRegularFile = $true
            switchPresent = $true
            vmNameAbsent = $true
            vmPathAbsent = $true
            vhdxPathAbsent = $true
        }
        processorCount = $processorCount
        startupMemoryGb = $startupMemoryGb
        maximumMemoryGb = $maximumMemoryGb
        diskSizeGb = $diskSizeGb
        generation = 2
        secureBoot = $true
        vtpm = $true
    }
    Save-HcrPlanRecord (New-HcrPlanRecord $plan)
    return [pscustomobject][ordered]@{
        changed = $false
        data = [pscustomobject][ordered]@{ plan = $plan }
        warnings = @()
    }
}

function Assert-HcrVmCreatePlanDriftFree {
    param([Parameter(Mandatory = $true)][object]$Plan)

    $hostSnapshot = Invoke-HcrAdapter 'GetHostSnapshot'
    if ((Get-HcrHostFingerprint $hostSnapshot) -ne (Get-HcrPropertyValue $Plan 'hostFingerprint')) {
        Throw-HcrError 'PLAN_DRIFT' 'The host fingerprint changed after planning.'
    }
    $iso = Assert-HcrRegularLocalFile ([string](Get-HcrPropertyValue $Plan 'isoPath')) 'PLAN_DRIFT'
    if ([int64]$iso.Length -ne [int64](Get-HcrPropertyValue $Plan 'isoSizeBytes') -or
        $iso.LastWriteTimeUtc.ToString('o') -ne [string](Get-HcrPropertyValue $Plan 'isoLastWriteTimeUtc') -or
        (Get-HcrSha256File $iso.FullName) -ne [string](Get-HcrPropertyValue $Plan 'isoSha256')) {
        Throw-HcrError 'PLAN_DRIFT' 'The ISO identity changed after planning.'
    }
    $switch = Invoke-HcrAdapter 'GetSwitch' ([pscustomobject]@{ name = [string](Get-HcrPropertyValue $Plan 'switchName') })
    if ($null -eq $switch -or
        [string](Get-HcrPropertyValue $switch 'id') -ne [string](Get-HcrPropertyValue $Plan 'switchId')) {
        Throw-HcrError 'PLAN_DRIFT' 'The virtual-switch identity changed after planning.'
    }
    if ($null -ne (Invoke-HcrAdapter 'GetVm' ([pscustomobject]@{ name = [string](Get-HcrPropertyValue $Plan 'name') }))) {
        Throw-HcrError 'PLAN_DRIFT' 'The planned VM name is no longer absent.'
    }
    foreach ($field in @('vmPath', 'vhdxPath')) {
        if (Test-Path -LiteralPath ([string](Get-HcrPropertyValue $Plan $field))) {
            Throw-HcrError 'PLAN_DRIFT' "The planned $field is no longer absent."
        }
    }
    $volume = Invoke-HcrAdapter 'GetTargetVolume' ([pscustomobject]@{ path = [string](Get-HcrPropertyValue $Plan 'vmRoot') })
    $plannedVolume = Get-HcrPropertyValue $Plan 'targetVolume'
    if ([string](Get-HcrPropertyValue $volume 'uniqueId') -ne
        [string](Get-HcrPropertyValue $plannedVolume 'uniqueId') -or
        [string](Get-HcrPropertyValue $volume 'root') -ne
        [string](Get-HcrPropertyValue $plannedVolume 'root') -or
        [string](Get-HcrPropertyValue $volume 'fileSystem') -ne
        [string](Get-HcrPropertyValue $plannedVolume 'fileSystem')) {
        Throw-HcrError 'PLAN_DRIFT' 'The target-volume identity changed after planning.'
    }
    if ([int64](Get-HcrPropertyValue $volume 'availableBytes') -lt
        [int64](Get-HcrPropertyValue $plannedVolume 'requiredBytes')) {
        Throw-HcrError 'PLAN_DRIFT' 'The target volume no longer has the required capacity.'
    }
}

function Invoke-HcrApplyVmCreate {
    param(
        [Parameter(Mandatory = $true)][object]$Arguments,
        [Parameter(Mandatory = $true)][string]$OperationId
    )

    $record = Consume-HcrPlanRecord ([string](Get-HcrPropertyValue $Arguments 'planId'))
    $plan = Assert-HcrPlanUsable $record 'vmCreate'
    Assert-HcrVmCreatePlanDriftFree $plan
    $ownershipId = [Guid]::NewGuid().ToString()
    $vm = Invoke-HcrAdapter 'CreateVm' ([pscustomobject][ordered]@{
        plan = $plan
        ownershipId = $ownershipId
    })
    if ($null -eq $vm -or [string]::IsNullOrWhiteSpace([string](Get-HcrPropertyValue $vm 'id'))) {
        Throw-HcrError 'VM_CREATE_FAILED' 'The adapter did not return the created VM identity.'
    }
    $expectedMarker = "hyperv-clean-room/v1:$ownershipId"
    if ([string](Get-HcrPropertyValue $vm 'notes') -ne $expectedMarker) {
        Throw-HcrError 'VM_CREATE_FAILED' 'The created VM does not carry the ownership marker.' ([ordered]@{
            vmId = [string](Get-HcrPropertyValue $vm 'id')
            vmName = [string](Get-HcrPropertyValue $vm 'name')
        })
    }
    $ownership = [pscustomobject][ordered]@{
        schemaVersion = 1
        vmId = [string](Get-HcrPropertyValue $vm 'id')
        vmName = [string](Get-HcrPropertyValue $vm 'name')
        vmRoot = [string](Get-HcrPropertyValue $plan 'vmRoot')
        vmPath = [string](Get-HcrPropertyValue $plan 'vmPath')
        vhdxPath = [string](Get-HcrPropertyValue $plan 'vhdxPath')
        creationOperationId = $OperationId
        ownershipId = $ownershipId
        createdAt = Get-HcrUtcTimestamp
        checkpoints = @()
    }
    Save-HcrOwnershipRecord $ownership
    return [pscustomobject][ordered]@{
        changed = $true
        data = [pscustomobject][ordered]@{
            vmId = [string](Get-HcrPropertyValue $vm 'id')
            vmName = [string](Get-HcrPropertyValue $vm 'name')
            ownershipId = $ownershipId
            vmPath = [string](Get-HcrPropertyValue $plan 'vmPath')
            vhdxPath = [string](Get-HcrPropertyValue $plan 'vhdxPath')
        }
        warnings = @()
    }
}

function New-HcrCheckpointBasePlan {
    param(
        [Parameter(Mandatory = $true)][string]$Kind,
        [Parameter(Mandatory = $true)][object]$OwnedVm,
        [Parameter(Mandatory = $true)][string]$CheckpointName
    )

    $hostSnapshot = Invoke-HcrAdapter 'GetHostSnapshot'
    $created = [DateTimeOffset]::UtcNow
    return [ordered]@{
        schemaVersion = 1
        planKind = $Kind
        planId = [Guid]::NewGuid().ToString()
        createdAt = $created.ToString('o')
        expiresAt = $created.AddMinutes($script:HcrPlanLifetimeMinutes).ToString('o')
        hostFingerprint = Get-HcrHostFingerprint $hostSnapshot
        vmId = [string](Get-HcrPropertyValue $OwnedVm.vm 'id')
        vmName = [string](Get-HcrPropertyValue $OwnedVm.vm 'name')
        ownershipId = [string](Get-HcrPropertyValue $OwnedVm.ownership 'ownershipId')
        vmFingerprint = Get-HcrVmFingerprint $OwnedVm.vm
        checkpointName = $CheckpointName
        checkpointInventoryFingerprint = Get-HcrCheckpointInventoryFingerprint $OwnedVm.vm
    }
}

function Get-HcrCheckpointByName {
    param(
        [Parameter(Mandatory = $true)][object]$Vm,
        [Parameter(Mandatory = $true)][string]$CheckpointName
    )

    $matches = @(@((Get-HcrPropertyValue $Vm 'checkpoints' @())) |
        Where-Object { [string](Get-HcrPropertyValue $_ 'name') -eq $CheckpointName })
    if ($matches.Count -gt 1) {
        Throw-HcrError 'CHECKPOINT_AMBIGUOUS' 'More than one checkpoint has the requested name.'
    }
    if ($matches.Count -eq 0) { return $null }
    return $matches[0]
}

function Invoke-HcrPlanCheckpointCreate {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $checkpointName = [string](Get-HcrPropertyValue $Arguments 'checkpointName')
    Assert-HcrVmName $checkpointName
    $owned = Get-HcrRequiredOwnedVm ([string](Get-HcrPropertyValue $Arguments 'vmName'))
    if ($null -ne (Get-HcrCheckpointByName $owned.vm $checkpointName)) {
        Throw-HcrError 'CHECKPOINT_ALREADY_EXISTS' 'A checkpoint with the requested name already exists.'
    }
    $base = New-HcrCheckpointBasePlan 'checkpointCreate' $owned $checkpointName
    $base.checkpointNameAbsent = $true
    $plan = [pscustomobject]$base
    Save-HcrPlanRecord (New-HcrPlanRecord $plan)
    return [pscustomobject][ordered]@{
        changed = $false
        data = [pscustomobject][ordered]@{ plan = $plan }
        warnings = @()
    }
}

function Assert-HcrCheckpointPlanCommonDriftFree {
    param([Parameter(Mandatory = $true)][object]$Plan)

    $hostSnapshot = Invoke-HcrAdapter 'GetHostSnapshot'
    if ((Get-HcrHostFingerprint $hostSnapshot) -ne [string](Get-HcrPropertyValue $Plan 'hostFingerprint')) {
        Throw-HcrError 'PLAN_DRIFT' 'The host fingerprint changed after checkpoint planning.'
    }
    $owned = Get-HcrRequiredOwnedVm ([string](Get-HcrPropertyValue $Plan 'vmName'))
    if ([string](Get-HcrPropertyValue $owned.vm 'id') -ne [string](Get-HcrPropertyValue $Plan 'vmId') -or
        [string](Get-HcrPropertyValue $owned.ownership 'ownershipId') -ne [string](Get-HcrPropertyValue $Plan 'ownershipId') -or
        (Get-HcrVmFingerprint $owned.vm) -ne [string](Get-HcrPropertyValue $Plan 'vmFingerprint') -or
        (Get-HcrCheckpointInventoryFingerprint $owned.vm) -ne [string](Get-HcrPropertyValue $Plan 'checkpointInventoryFingerprint')) {
        Throw-HcrError 'PLAN_DRIFT' 'The VM, ownership, or checkpoint inventory changed after planning.'
    }
    return $owned
}

function Invoke-HcrApplyCheckpointCreate {
    param(
        [Parameter(Mandatory = $true)][object]$Arguments,
        [Parameter(Mandatory = $true)][string]$OperationId
    )

    $record = Consume-HcrPlanRecord ([string](Get-HcrPropertyValue $Arguments 'planId'))
    $plan = Assert-HcrPlanUsable $record 'checkpointCreate'
    $owned = Assert-HcrCheckpointPlanCommonDriftFree $plan
    if ($null -ne (Get-HcrCheckpointByName $owned.vm ([string](Get-HcrPropertyValue $plan 'checkpointName')))) {
        Throw-HcrError 'PLAN_DRIFT' 'The planned checkpoint name is no longer absent.'
    }
    $checkpoint = Invoke-HcrAdapter 'CreateCheckpoint' ([pscustomobject][ordered]@{
        vmName = [string](Get-HcrPropertyValue $plan 'vmName')
        checkpointName = [string](Get-HcrPropertyValue $plan 'checkpointName')
    })
    $entry = [pscustomobject][ordered]@{
        id = [string](Get-HcrPropertyValue $checkpoint 'id')
        name = [string](Get-HcrPropertyValue $checkpoint 'name')
        parentId = Get-HcrPropertyValue $checkpoint 'parentId'
        configurationFingerprint = [string](Get-HcrPropertyValue $checkpoint 'configurationFingerprint')
        createdAt = [string](Get-HcrPropertyValue $checkpoint 'createdAt')
        creationOperationId = $OperationId
    }
    $owned.ownership.checkpoints = @(@((Get-HcrPropertyValue $owned.ownership 'checkpoints' @())) + $entry)
    Save-HcrOwnershipRecord $owned.ownership
    return [pscustomobject][ordered]@{
        changed = $true
        data = [pscustomobject][ordered]@{
            vmId = [string](Get-HcrPropertyValue $plan 'vmId')
            vmName = [string](Get-HcrPropertyValue $plan 'vmName')
            checkpoint = $entry
        }
        warnings = @()
    }
}

function Invoke-HcrPlanCheckpointRestore {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $checkpointName = [string](Get-HcrPropertyValue $Arguments 'checkpointName')
    Assert-HcrVmName $checkpointName
    $owned = Get-HcrRequiredOwnedVm ([string](Get-HcrPropertyValue $Arguments 'vmName'))
    $checkpoint = Get-HcrCheckpointByName $owned.vm $checkpointName
    if ($null -eq $checkpoint) {
        Throw-HcrError 'CHECKPOINT_NOT_FOUND' 'The requested checkpoint does not exist.'
    }
    $token = Get-HcrRandomToken 32
    $base = New-HcrCheckpointBasePlan 'checkpointRestore' $owned $checkpointName
    $base.checkpointId = [string](Get-HcrPropertyValue $checkpoint 'id')
    $base.checkpointFingerprint = Get-HcrCheckpointFingerprint $checkpoint
    $base.currentStateFingerprint = Get-HcrCurrentStateFingerprint $owned.vm
    $base.confirmationToken = $token
    $publicPlan = [pscustomobject]$base
    $persistedPlan = Copy-HcrObject $publicPlan
    $persistedPlan.PSObject.Properties.Remove('confirmationToken')
    $tokenHash = Get-HcrSha256Text $token
    Save-HcrPlanRecord (New-HcrPlanRecord $persistedPlan $tokenHash)
    return [pscustomobject][ordered]@{
        changed = $false
        data = [pscustomobject][ordered]@{ plan = $publicPlan }
        warnings = @('The restore confirmation token is returned once and is not persisted in plaintext.')
    }
}

function Test-HcrFixedTimeTextEqual {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )

    $leftBytes = $script:HcrUtf8NoBom.GetBytes($Left)
    $rightBytes = $script:HcrUtf8NoBom.GetBytes($Right)
    $difference = $leftBytes.Length -bxor $rightBytes.Length
    $length = [Math]::Max($leftBytes.Length, $rightBytes.Length)
    for ($index = 0; $index -lt $length; $index++) {
        $leftValue = if ($index -lt $leftBytes.Length) { $leftBytes[$index] } else { 0 }
        $rightValue = if ($index -lt $rightBytes.Length) { $rightBytes[$index] } else { 0 }
        $difference = $difference -bor ($leftValue -bxor $rightValue)
    }
    return $difference -eq 0
}

function Invoke-HcrApplyCheckpointRestore {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    # The first well-formed call consumes before name, token, expiry, or drift checks.
    $record = Consume-HcrPlanRecord ([string](Get-HcrPropertyValue $Arguments 'planId'))
    $plan = Assert-HcrPlanUsable $record 'checkpointRestore'
    if ([string](Get-HcrPropertyValue $Arguments 'checkpointName') -ne
        [string](Get-HcrPropertyValue $plan 'checkpointName')) {
        Throw-HcrError 'CONFIRMATION_MISMATCH' 'The checkpoint name does not match the consumed restore plan.'
    }
    $providedHash = Get-HcrSha256Text ([string](Get-HcrPropertyValue $Arguments 'confirmationToken'))
    $storedHash = [string](Get-HcrPropertyValue $record 'confirmationTokenHash')
    if ([string]::IsNullOrWhiteSpace($storedHash) -or
        -not (Test-HcrFixedTimeTextEqual $providedHash $storedHash)) {
        Throw-HcrError 'CONFIRMATION_MISMATCH' 'The restore confirmation token is invalid.'
    }
    $owned = Assert-HcrCheckpointPlanCommonDriftFree $plan
    if ((Get-HcrCurrentStateFingerprint $owned.vm) -ne
        [string](Get-HcrPropertyValue $plan 'currentStateFingerprint')) {
        Throw-HcrError 'PLAN_DRIFT' 'The VM current state changed after restore planning.'
    }
    $checkpoint = Get-HcrCheckpointByName $owned.vm ([string](Get-HcrPropertyValue $plan 'checkpointName'))
    if ($null -eq $checkpoint -or
        [string](Get-HcrPropertyValue $checkpoint 'id') -ne [string](Get-HcrPropertyValue $plan 'checkpointId') -or
        (Get-HcrCheckpointFingerprint $checkpoint) -ne [string](Get-HcrPropertyValue $plan 'checkpointFingerprint')) {
        Throw-HcrError 'PLAN_DRIFT' 'The target checkpoint changed after restore planning.'
    }
    $result = Invoke-HcrAdapter 'RestoreCheckpoint' ([pscustomobject][ordered]@{
        vmName = [string](Get-HcrPropertyValue $plan 'vmName')
        checkpointName = [string](Get-HcrPropertyValue $plan 'checkpointName')
    })
    return [pscustomobject][ordered]@{
        changed = $true
        data = [pscustomobject][ordered]@{
            vmId = [string](Get-HcrPropertyValue $plan 'vmId')
            vmName = [string](Get-HcrPropertyValue $plan 'vmName')
            checkpointId = [string](Get-HcrPropertyValue $result 'checkpointId')
            checkpointName = [string](Get-HcrPropertyValue $plan 'checkpointName')
            restoredAt = [string](Get-HcrPropertyValue $result 'restoredAt')
        }
        warnings = @('Checkpoint restore discards the VM state identified by the consumed plan.')
    }
}

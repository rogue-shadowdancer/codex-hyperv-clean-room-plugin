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
        vhdxChainFingerprint = [string](Get-HcrPropertyValue $Vm 'vhdxChainFingerprint')
        automaticCheckpointsEnabled = Get-HcrPropertyValue $Vm 'automaticCheckpointsEnabled'
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

function Get-HcrVhdChainFingerprint {
    param([Parameter(Mandatory = $true)][object[]]$Chain)

    $identity = @($Chain | ForEach-Object {
        $path = Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $_ 'path'))
        $parentPath = [string](Get-HcrPropertyValue $_ 'parentPath')
        [ordered]@{
            path = $path.ToLowerInvariant()
            parentPath = if ([string]::IsNullOrWhiteSpace($parentPath)) {
                $null
            }
            else {
                (Get-HcrNormalizedPath $parentPath).ToLowerInvariant()
            }
            diskIdentifier = ([string](Get-HcrPropertyValue $_ 'diskIdentifier')).ToLowerInvariant()
            virtualSize = [int64](Get-HcrPropertyValue $_ 'virtualSize')
        }
    })
    return Get-HcrSha256Text (ConvertTo-HcrJson $identity 30)
}

function Get-HcrVmStorageOwnershipBinding {
    param(
        [Parameter(Mandatory = $true)][object]$Vm,
        [Parameter(Mandatory = $true)][string]$RecordedVhdxPath
    )

    $unverified = [pscustomobject][ordered]@{
        verified = $false
        mode = 'unverified'
        recordedBaseVhdxPath = $RecordedVhdxPath
        activeVhdxPath = [string](Get-HcrPropertyValue $Vm 'vhdxPath')
        chainFingerprint = $null
    }
    try {
        $recordedBase = Get-HcrNormalizedPath $RecordedVhdxPath
        $activePath = Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $Vm 'vhdxPath'))
        if ($recordedBase -eq $activePath) {
            return [pscustomobject][ordered]@{
                verified = $true
                mode = 'directBase'
                recordedBaseVhdxPath = $recordedBase
                activeVhdxPath = $activePath
                chainFingerprint = $null
            }
        }

        if (-not [bool](Get-HcrPropertyValue $Vm 'vhdxChainVerified' $false)) {
            return $unverified
        }
        $basePath = Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $Vm 'baseVhdxPath'))
        $chain = @((Get-HcrPropertyValue $Vm 'vhdxChain' @()))
        if ($basePath -ne $recordedBase -or
            $chain.Count -lt 2 -or
            $chain.Count -gt 64) {
            return $unverified
        }

        $seen = @{}
        for ($index = 0; $index -lt $chain.Count; $index++) {
            $entry = $chain[$index]
            $entryPath = Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $entry 'path'))
            $key = $entryPath.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { return $unverified }
            $seen[$key] = $true

            $diskIdentifier = [string](Get-HcrPropertyValue $entry 'diskIdentifier')
            $parsedDiskIdentifier = [Guid]::Empty
            if (-not [Guid]::TryParse($diskIdentifier, [ref]$parsedDiskIdentifier) -or
                $parsedDiskIdentifier -eq [Guid]::Empty -or
                $null -eq (Get-HcrPropertyValue $entry 'virtualSize') -or
                [int64](Get-HcrPropertyValue $entry 'virtualSize') -lt 1 -or
                $null -eq (Get-HcrPropertyValue $entry 'physicalFileSize') -or
                [int64](Get-HcrPropertyValue $entry 'physicalFileSize') -lt 1 -or
                $null -eq (Get-HcrPropertyValue $entry 'fileLength') -or
                [int64](Get-HcrPropertyValue $entry 'fileLength') -lt 1) {
                return $unverified
            }

            $parentPath = [string](Get-HcrPropertyValue $entry 'parentPath')
            if ($index -lt ($chain.Count - 1)) {
                if ([string]::IsNullOrWhiteSpace($parentPath)) { return $unverified }
                $nextPath = Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $chain[$index + 1] 'path'))
                if ((Get-HcrNormalizedPath $parentPath) -ne $nextPath) { return $unverified }
            }
            elseif (-not [string]::IsNullOrWhiteSpace($parentPath)) {
                return $unverified
            }
        }

        if ((Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $chain[0] 'path'))) -ne $activePath -or
            (Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $chain[$chain.Count - 1] 'path'))) -ne
                $recordedBase) {
            return $unverified
        }
        $storedFingerprint = [string](Get-HcrPropertyValue $Vm 'vhdxChainFingerprint')
        $computedFingerprint = Get-HcrVhdChainFingerprint $chain
        if ($storedFingerprint -notmatch '^[a-f0-9]{64}$' -or
            $computedFingerprint -cne $storedFingerprint) {
            return $unverified
        }
        return [pscustomobject][ordered]@{
            verified = $true
            mode = 'verifiedDifferencingChain'
            recordedBaseVhdxPath = $recordedBase
            activeVhdxPath = $activePath
            chainFingerprint = $computedFingerprint
        }
    }
    catch {
        return $unverified
    }
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
            storageBinding = [pscustomobject][ordered]@{
                verified = $false
                mode = 'unverified'
                recordedBaseVhdxPath = $null
                activeVhdxPath = [string](Get-HcrPropertyValue $Vm 'vhdxPath')
                chainFingerprint = $null
            }
        }
    }
    $ownershipId = [string](Get-HcrPropertyValue $record 'ownershipId')
    $marker = "hyperv-clean-room/v1:$ownershipId"
    $storageBinding = [pscustomobject][ordered]@{
        verified = $false
        mode = 'unverified'
        recordedBaseVhdxPath = [string](Get-HcrPropertyValue $record 'vhdxPath')
        activeVhdxPath = [string](Get-HcrPropertyValue $Vm 'vhdxPath')
        chainFingerprint = $null
    }
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
            $storageBinding = Get-HcrVmStorageOwnershipBinding $Vm $recordVhdxPath
            $verified = $recordVmRoot -eq (Get-HcrNormalizedPath (Split-Path -Parent $recordVmPath)) -and
                $recordVmPath -eq $liveVmPath -and
                [bool]$storageBinding.verified
        }
        catch {
            $verified = $false
        }
    }
    return [pscustomobject][ordered]@{
        verified = $verified
        status = if ($verified) { 'verified' } else { 'OWNERSHIP_UNVERIFIED' }
        record = $record
        storageBinding = $storageBinding
    }
}

function Get-HcrRequiredOwnedVm {
    param(
        [Parameter(Mandatory = $true)][string]$VmName,
        [switch]$RequireOfflineDiskIdentity
    )

    $vm = Invoke-HcrAdapter 'GetVm' ([pscustomobject]@{
        name = $VmName
        requireOfflineDiskIdentity = [bool]$RequireOfflineDiskIdentity
    })
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

function Get-HcrOwnedVmDispatchIdentity {
    param([Parameter(Mandatory = $true)][object]$OwnedVm)

    return [pscustomobject][ordered]@{
        expectedVmId = [string](Get-HcrPropertyValue $OwnedVm.vm 'id')
        expectedVmName = [string](Get-HcrPropertyValue $OwnedVm.vm 'name')
        expectedOwnershipId = [string](Get-HcrPropertyValue $OwnedVm.ownership 'ownershipId')
        expectedVmPath = [string](Get-HcrPropertyValue $OwnedVm.vm 'vmPath')
        expectedVhdxPath = [string](Get-HcrPropertyValue $OwnedVm.vm 'vhdxPath')
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
        schemaVersion = [int](Get-HcrPropertyValue $Plan 'schemaVersion' 1)
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
    $automaticCheckpointSetting = Get-HcrPropertyValue $vm 'automaticCheckpointsEnabled'
    $automaticCheckpointsDisabled = (
        $automaticCheckpointSetting -is [bool] -and
        -not [bool]$automaticCheckpointSetting
    )
    return [pscustomobject][ordered]@{
        changed = $false
        data = [pscustomobject][ordered]@{
            vm = $vm
            ownership = [pscustomobject][ordered]@{
                verified = [bool]$ownership.verified
                status = [string]$ownership.status
                ownershipId = if ($null -eq $ownership.record) { $null } else { [string](Get-HcrPropertyValue $ownership.record 'ownershipId') }
                storageBinding = [string](Get-HcrPropertyValue $ownership.storageBinding 'mode' 'unverified')
                recordedBaseVhdxPath = Get-HcrPropertyValue $ownership.storageBinding 'recordedBaseVhdxPath'
                activeVhdxPath = Get-HcrPropertyValue $ownership.storageBinding 'activeVhdxPath'
                vhdxChainFingerprint = Get-HcrPropertyValue $ownership.storageBinding 'chainFingerprint'
                automaticCheckpointRecoveryRequired = (
                    [bool]$ownership.verified -and
                    -not $automaticCheckpointsDisabled
                )
            }
        }
        warnings = if (
            [bool]$ownership.verified -and
            -not $automaticCheckpointsDisabled
        ) {
            @('Automatic checkpoints are enabled or unavailable on this managed VM. Review and disable that setting before a future power transition; the plugin will not adopt or rewrite the current differencing chain.')
        }
        else { @() }
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
    $volumeUniqueId = [string](Get-HcrPropertyValue $volume 'uniqueId')
    if ([string]::IsNullOrWhiteSpace($volumeUniqueId)) {
        Throw-HcrError 'TARGET_VOLUME_IDENTITY_UNAVAILABLE' 'The target volume has no stable UniqueId.'
    }
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
            uniqueId = $volumeUniqueId
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

function Get-HcrRevalidatedVmCreatePaths {
    param([Parameter(Mandatory = $true)][object]$Plan)

    $plannedRoot = Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $Plan 'vmRoot'))
    $rootItem = Assert-HcrLocalDirectory $plannedRoot 'PLAN_DRIFT'
    $currentRoot = Get-HcrNormalizedPath $rootItem.FullName
    if (-not [string]::Equals($currentRoot, $plannedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        Throw-HcrError 'PLAN_DRIFT' 'The VM root changed after planning.'
    }
    $name = [string](Get-HcrPropertyValue $Plan 'name')
    $vmPath = Get-HcrNormalizedPath (Join-Path $currentRoot $name)
    $vhdxPath = Get-HcrNormalizedPath (Join-Path $vmPath "$name.vhdx")
    if (-not [string]::Equals(
            $vmPath,
            (Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $Plan 'vmPath'))),
            [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals(
            $vhdxPath,
            (Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $Plan 'vhdxPath'))),
            [StringComparison]::OrdinalIgnoreCase)) {
        Throw-HcrError 'PLAN_DRIFT' 'The derived VM or VHDX path changed after planning.'
    }
    return [pscustomobject][ordered]@{
        vmRoot = $currentRoot
        vmPath = $vmPath
        vhdxPath = $vhdxPath
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
    $paths = Get-HcrRevalidatedVmCreatePaths $Plan
    foreach ($field in @('vmPath', 'vhdxPath')) {
        if (Test-Path -LiteralPath ([string](Get-HcrPropertyValue $paths $field))) {
            Throw-HcrError 'PLAN_DRIFT' "The planned $field is no longer absent."
        }
    }
    $volume = Invoke-HcrAdapter 'GetTargetVolume' ([pscustomobject]@{ path = [string]$paths.vmRoot })
    $plannedVolume = Get-HcrPropertyValue $Plan 'targetVolume'
    $currentUniqueId = [string](Get-HcrPropertyValue $volume 'uniqueId')
    $plannedUniqueId = [string](Get-HcrPropertyValue $plannedVolume 'uniqueId')
    if ([string]::IsNullOrWhiteSpace($currentUniqueId) -or
        [string]::IsNullOrWhiteSpace($plannedUniqueId) -or
        $currentUniqueId -ne $plannedUniqueId -or
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
    $rebound = Copy-HcrObject $Plan
    $rebound.vmRoot = [string]$paths.vmRoot
    $rebound.vmPath = [string]$paths.vmPath
    $rebound.vhdxPath = [string]$paths.vhdxPath
    return $rebound
}

function Invoke-HcrApplyVmCreate {
    param(
        [Parameter(Mandatory = $true)][object]$Arguments,
        [Parameter(Mandatory = $true)][string]$OperationId
    )

    $record = Consume-HcrPlanRecord ([string](Get-HcrPropertyValue $Arguments 'planId'))
    $plan = Assert-HcrPlanUsable $record 'vmCreate'
    $plan = Assert-HcrVmCreatePlanDriftFree $plan
    $ownershipId = [Guid]::NewGuid().ToString()
    $vm = $null
    $adapterReturned = $false
    try {
        $vm = Invoke-HcrAdapter 'CreateVm' ([pscustomobject][ordered]@{
            plan = $plan
            ownershipId = $ownershipId
        })
        $adapterReturned = $true
        if ($null -eq $vm -or [string]::IsNullOrWhiteSpace([string](Get-HcrPropertyValue $vm 'id'))) {
            Throw-HcrError 'VM_CREATE_FAILED' 'The adapter did not return the created VM identity.'
        }
        $expectedMarker = "hyperv-clean-room/v1:$ownershipId"
        if ([string](Get-HcrPropertyValue $vm 'notes') -ne $expectedMarker) {
            Throw-HcrError 'VM_CREATE_FAILED' 'The created VM does not carry the ownership marker.'
        }
        if ((Get-HcrPropertyValue $vm 'automaticCheckpointsEnabled') -isnot [bool] -or
            [bool](Get-HcrPropertyValue $vm 'automaticCheckpointsEnabled')) {
            Throw-HcrError 'VM_CREATE_FAILED' 'The created VM did not verify automatic checkpoints as disabled.'
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
        $primaryAdapter = $null
        try { $primaryAdapter = Get-HcrVerifiedPrimaryAdapter $vm }
        catch {
            if ((Get-HcrExceptionData $_.Exception).code -ne 'PRIMARY_ADAPTER_UNVERIFIED') { throw }
        }
        if ($null -ne $primaryAdapter -and
            [string](Get-HcrPropertyValue $primaryAdapter.attachment 'mode') -eq 'connected') {
            $ownership | Add-Member -NotePropertyName networkBaseline -NotePropertyValue ([pscustomobject][ordered]@{
                adapterId = [string]$primaryAdapter.id
                adapterName = [string]$primaryAdapter.name
                macAddress = [string]$primaryAdapter.macAddress
                attachment = Copy-HcrObject $primaryAdapter.attachment
            })
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
    catch {
        $failure = Get-HcrExceptionData $_.Exception
        if ($null -ne $failure.details -and
            [bool](Get-HcrPropertyValue $failure.details 'mutationEntered' $false)) {
            throw
        }
        if (-not $adapterReturned) { throw }
        $vmId = if ($null -eq $vm) { $null } else { [string](Get-HcrPropertyValue $vm 'id') }
        $effectState = if ([string]::IsNullOrWhiteSpace($vmId)) { 'indeterminate' } else { 'confirmed' }
        Throw-HcrPartialMutationError `
            'VM_CREATE_FAILED' `
            'VM creation completed or may have completed, but final ownership publication failed.' `
            $effectState `
            ([pscustomobject][ordered]@{
                resourceType = 'vm'
                vmId = $vmId
                vmName = [string](Get-HcrPropertyValue $plan 'name')
                ownershipId = $ownershipId
                vmPath = [string](Get-HcrPropertyValue $plan 'vmPath')
                vhdxPath = [string](Get-HcrPropertyValue $plan 'vhdxPath')
            }) `
            'A VM or VHDX may have been created. Inspect only the exact partial identity in error.details; automatic cleanup was not attempted.'
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
    param(
        [Parameter(Mandatory = $true)][object]$Plan,
        [switch]$RequireOfflineDiskIdentity
    )

    $hostSnapshot = Invoke-HcrAdapter 'GetHostSnapshot'
    if ((Get-HcrHostFingerprint $hostSnapshot) -ne [string](Get-HcrPropertyValue $Plan 'hostFingerprint')) {
        Throw-HcrError 'PLAN_DRIFT' 'The host fingerprint changed after checkpoint planning.'
    }
    $owned = Get-HcrRequiredOwnedVm `
        ([string](Get-HcrPropertyValue $Plan 'vmName')) `
        -RequireOfflineDiskIdentity:$RequireOfflineDiskIdentity
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
    $checkpoint = $null
    $adapterReturned = $false
    try {
        $checkpoint = Invoke-HcrAdapter 'CreateCheckpoint' ([pscustomobject][ordered]@{
            vmName = [string](Get-HcrPropertyValue $plan 'vmName')
            checkpointName = [string](Get-HcrPropertyValue $plan 'checkpointName')
            expectedVmId = [string](Get-HcrPropertyValue $owned.vm 'id')
            expectedVmName = [string](Get-HcrPropertyValue $owned.vm 'name')
            expectedOwnershipId = [string](Get-HcrPropertyValue $owned.ownership 'ownershipId')
            expectedVmPath = [string](Get-HcrPropertyValue $owned.vm 'vmPath')
            expectedVhdxPath = [string](Get-HcrPropertyValue $owned.vm 'vhdxPath')
        })
        $adapterReturned = $true
        if ($null -eq $checkpoint -or
            [string]::IsNullOrWhiteSpace([string](Get-HcrPropertyValue $checkpoint 'id')) -or
            [string](Get-HcrPropertyValue $checkpoint 'name') -ne
                [string](Get-HcrPropertyValue $plan 'checkpointName')) {
            Throw-HcrError 'CHECKPOINT_CREATE_FAILED' 'The adapter did not return the exact created checkpoint identity.'
        }
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
    catch {
        $failure = Get-HcrExceptionData $_.Exception
        if ($null -ne $failure.details -and
            [bool](Get-HcrPropertyValue $failure.details 'mutationEntered' $false)) {
            throw
        }
        if (-not $adapterReturned) { throw }
        $checkpointId = if ($null -eq $checkpoint) { $null } else {
            [string](Get-HcrPropertyValue $checkpoint 'id')
        }
        $effectState = if ([string]::IsNullOrWhiteSpace($checkpointId)) { 'indeterminate' } else { 'confirmed' }
        Throw-HcrPartialMutationError `
            'CHECKPOINT_CREATE_FAILED' `
            'Checkpoint creation completed or may have completed, but final ownership publication failed.' `
            $effectState `
            ([pscustomobject][ordered]@{
                resourceType = 'checkpoint'
                vmId = [string](Get-HcrPropertyValue $plan 'vmId')
                vmName = [string](Get-HcrPropertyValue $plan 'vmName')
                checkpointId = $checkpointId
                checkpointName = [string](Get-HcrPropertyValue $plan 'checkpointName')
            }) `
            'The exact checkpoint may have been created. Inspect the bound VM and checkpoint identity; automatic cleanup was not attempted.'
    }
}

function Invoke-HcrPlanCheckpointRestore {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $checkpointName = [string](Get-HcrPropertyValue $Arguments 'checkpointName')
    Assert-HcrVmName $checkpointName
    $owned = Get-HcrRequiredOwnedVm `
        ([string](Get-HcrPropertyValue $Arguments 'vmName')) `
        -RequireOfflineDiskIdentity
    if ([string](Get-HcrPropertyValue $owned.vm 'state') -ne 'Off') {
        Throw-HcrError 'VM_STATE_UNSUPPORTED' 'Checkpoint restore planning requires the managed VM to be Off.'
    }
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
    $owned = Assert-HcrCheckpointPlanCommonDriftFree `
        $plan `
        -RequireOfflineDiskIdentity
    if ([string](Get-HcrPropertyValue $owned.vm 'state') -ne 'Off') {
        Throw-HcrError 'PLAN_DRIFT' 'The VM must remain Off for checkpoint restore.'
    }
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
    $result = $null
    $adapterReturned = $false
    try {
        $result = Invoke-HcrAdapter 'RestoreCheckpoint' ([pscustomobject][ordered]@{
            vmName = [string](Get-HcrPropertyValue $plan 'vmName')
            checkpointName = [string](Get-HcrPropertyValue $plan 'checkpointName')
            expectedVmId = [string](Get-HcrPropertyValue $owned.vm 'id')
            expectedVmName = [string](Get-HcrPropertyValue $owned.vm 'name')
            expectedOwnershipId = [string](Get-HcrPropertyValue $owned.ownership 'ownershipId')
            expectedVmPath = [string](Get-HcrPropertyValue $owned.vm 'vmPath')
            expectedVhdxPath = [string](Get-HcrPropertyValue $owned.vm 'vhdxPath')
            expectedVmState = 'Off'
            expectedCurrentStateFingerprint = [string](Get-HcrPropertyValue $plan 'currentStateFingerprint')
            expectedCheckpointInventoryFingerprint = [string](Get-HcrPropertyValue $plan 'checkpointInventoryFingerprint')
            expectedCheckpointId = [string](Get-HcrPropertyValue $plan 'checkpointId')
            expectedCheckpointFingerprint = [string](Get-HcrPropertyValue $plan 'checkpointFingerprint')
        })
        $adapterReturned = $true
        if ([string](Get-HcrPropertyValue $result 'checkpointId') -ne
                [string](Get-HcrPropertyValue $plan 'checkpointId') -or
            [string]::IsNullOrWhiteSpace([string](Get-HcrPropertyValue $result 'restoredAt'))) {
            Throw-HcrError 'CHECKPOINT_RESTORE_FAILED' 'The adapter did not return the exact restored checkpoint identity.'
        }
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
    catch {
        $failure = Get-HcrExceptionData $_.Exception
        if ($null -ne $failure.details -and
            [bool](Get-HcrPropertyValue $failure.details 'mutationEntered' $false)) {
            throw
        }
        if (-not $adapterReturned) { throw }
        Throw-HcrPartialMutationError `
            'CHECKPOINT_RESTORE_FAILED' `
            'Checkpoint restore completed, but its final result identity could not be verified.' `
            'confirmed' `
            ([pscustomobject][ordered]@{
                resourceType = 'checkpointRestore'
                vmId = [string](Get-HcrPropertyValue $plan 'vmId')
                vmName = [string](Get-HcrPropertyValue $plan 'vmName')
                checkpointId = [string](Get-HcrPropertyValue $plan 'checkpointId')
                checkpointName = [string](Get-HcrPropertyValue $plan 'checkpointName')
            }) `
            'The exact checkpoint restore may have taken effect. Inspect the bound VM and checkpoint identity before further mutation; no automatic recovery was attempted.'
        }
}

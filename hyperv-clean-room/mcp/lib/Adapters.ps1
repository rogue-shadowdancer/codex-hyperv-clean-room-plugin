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

function Invoke-HcrMockAdapter {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [AllowNull()][object]$Arguments
    )

    $state = Read-HcrMockAdapterState
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
            $vmId = [Guid]::NewGuid().ToString()
            $ownershipId = [string](Get-HcrPropertyValue $Arguments 'ownershipId')
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
                secureBoot = $true
                vtpm = $true
                checkpoints = @()
                currentStateNonce = [Guid]::NewGuid().ToString()
            }
            $state.vms = @(@((Get-HcrPropertyValue $state 'vms' @())) + $vm)
            Write-HcrMockAdapterState $state
            return Copy-HcrObject $vm
        }
        'CreateCheckpoint' {
            $vmName = [string](Get-HcrPropertyValue $Arguments 'vmName')
            $checkpointName = [string](Get-HcrPropertyValue $Arguments 'checkpointName')
            $vm = Get-HcrMockVm $state $vmName
            if ($null -eq $vm) { Throw-HcrError 'VM_NOT_FOUND' 'The VM does not exist.' }
            if (@(@((Get-HcrPropertyValue $vm 'checkpoints' @())) |
                Where-Object { (Get-HcrPropertyValue $_ 'name') -eq $checkpointName }).Count -gt 0) {
                Throw-HcrError 'CHECKPOINT_ALREADY_EXISTS' 'The checkpoint already exists.'
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
            return Copy-HcrObject $checkpoint
        }
        'RestoreCheckpoint' {
            $vmName = [string](Get-HcrPropertyValue $Arguments 'vmName')
            $checkpointName = [string](Get-HcrPropertyValue $Arguments 'checkpointName')
            $vm = Get-HcrMockVm $state $vmName
            if ($null -eq $vm) { Throw-HcrError 'VM_NOT_FOUND' 'The VM does not exist.' }
            $checkpoint = @(@((Get-HcrPropertyValue $vm 'checkpoints' @())) |
                Where-Object { (Get-HcrPropertyValue $_ 'name') -eq $checkpointName } |
                Select-Object -First 1)
            if ($checkpoint.Count -eq 0) {
                Throw-HcrError 'CHECKPOINT_NOT_FOUND' 'The checkpoint does not exist.'
            }
            $vm.currentStateNonce = "restored:$((Get-HcrPropertyValue $checkpoint[0] 'id'))"
            Write-HcrMockAdapterState $state
            return [pscustomobject][ordered]@{
                checkpointId = [string](Get-HcrPropertyValue $checkpoint[0] 'id')
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
            return Copy-HcrObject (Get-HcrPropertyValue $state 'guest')
        }
        'StageArtifact' {
            $sourceHash = [string](Get-HcrPropertyValue $Arguments 'sourceSha256')
            $guestHash = if ([bool](Get-HcrPropertyValue $state 'stageHashMismatch' $false)) {
                ('0' * 64)
            }
            else { $sourceHash }
            return [pscustomobject][ordered]@{
                guestDestination = [string](Get-HcrPropertyValue $Arguments 'guestDestination')
                guestSha256 = $guestHash
                bytesCopied = [int64](Get-HcrPropertyValue $Arguments 'size')
            }
        }
        'RunTestStep' {
            $step = Get-HcrPropertyValue $Arguments 'step'
            $id = [string](Get-HcrPropertyValue $step 'id')
            $result = Get-HcrMockConfiguredResult $state 'stepResults' $id "Mock step '$id' passed."
            if ((Get-HcrPropertyValue $step 'type') -eq 'launchApplication' -and
                -not (Test-HcrProperty $result 'process')) {
                $result | Add-Member -NotePropertyName process -NotePropertyValue ([pscustomobject][ordered]@{
                    pid = 4000 + [Math]::Abs($id.GetHashCode() % 1000)
                    identity = "mock-process-$id"
                    application = [string](Get-HcrPropertyValue $step 'application')
                })
            }
            return $result
        }
        'RunCleanupStep' {
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
    $uniqueId = $driveInfo.Name
    $fileSystem = $driveInfo.DriveFormat
    if (Get-Command Get-Volume -ErrorAction SilentlyContinue) {
        try {
            $volume = Get-Volume -DriveLetter $root.Substring(0, 1) -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace([string]$volume.UniqueId)) {
                $uniqueId = [string]$volume.UniqueId
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$volume.FileSystem)) {
                $fileSystem = [string]$volume.FileSystem
            }
        }
        catch {
            # DriveInfo remains an adequate stable fallback.
        }
    }
    return [pscustomobject][ordered]@{
        uniqueId = $uniqueId
        root = $root
        fileSystem = $fileSystem
        availableBytes = [int64]$driveInfo.AvailableFreeSpace
    }
}

function ConvertTo-HcrRealVmSnapshot {
    param([Parameter(Mandatory = $true)][object]$Vm)

    $hardDrive = @(Get-VMHardDiskDrive -VM $Vm -ErrorAction SilentlyContinue | Select-Object -First 1)
    $network = @(Get-VMNetworkAdapter -VM $Vm -ErrorAction SilentlyContinue | Select-Object -First 1)
    $checkpoints = @(Get-VMSnapshot -VM $Vm -ErrorAction SilentlyContinue | ForEach-Object {
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
        secureBoot = if ($null -eq $firmware) { $false } else { [string]$firmware.SecureBoot -eq 'On' }
        vtpm = if ($null -eq $security) { $false } else { [bool]$security.TpmEnabled }
        checkpoints = $checkpoints
        currentStateNonce = Get-HcrSha256Text "$($Vm.Id)|$($Vm.State)|$($Vm.Status)|$($Vm.Uptime.Ticks)"
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
    if (Test-Path -LiteralPath $root -PathType Container) {
        $rootItem = Get-Item -LiteralPath $root -Force
        if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Throw-HcrError 'CREDENTIAL_PROFILE_INVALID' 'The credential root cannot be a reparse point.'
        }
    }
    $directory = Get-HcrNormalizedPath (Join-Path $root $ProfileName)
    if (-not (Test-HcrPathWithin $directory $root) -or
        -not (Test-Path -LiteralPath $directory -PathType Container)) {
        Throw-HcrError 'CREDENTIAL_PROFILE_NOT_FOUND' 'The named credential profile does not exist.'
    }
    $directoryItem = Get-Item -LiteralPath $directory -Force
    if (($directoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Throw-HcrError 'CREDENTIAL_PROFILE_INVALID' 'The credential profile cannot be a reparse point.'
    }
    $metadataPath = Join-Path $directory 'profile.json'
    $adminPath = Join-Path $directory 'orchestration-admin.clixml'
    $userPath = Join-Path $directory 'standard-test-user.clixml'
    $metadata = Read-HcrJsonFile $metadataPath 'CREDENTIAL_PROFILE_INVALID'
    if ((Get-HcrPropertyValue $metadata 'vmName') -ne $VmName) {
        Throw-HcrError 'CREDENTIAL_PROFILE_VM_MISMATCH' 'The credential profile is bound to another VM.'
    }
    foreach ($path in @($adminPath, $userPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Throw-HcrError 'CREDENTIAL_PROFILE_INVALID' 'The credential bundle is incomplete.'
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
            return ConvertTo-HcrRealVmSnapshot $vm[0]
        }
        'CreateVm' {
            $plan = Get-HcrPropertyValue $Arguments 'plan'
            $ownershipId = [string](Get-HcrPropertyValue $Arguments 'ownershipId')
            $createdVm = $null
            try {
                $createdVm = New-VM `
                    -Name ([string](Get-HcrPropertyValue $plan 'name')) `
                    -Generation 2 `
                    -Path ([string](Get-HcrPropertyValue $plan 'vmRoot')) `
                    -NewVHDPath ([string](Get-HcrPropertyValue $plan 'vhdxPath')) `
                    -NewVHDSizeBytes ([int64](Get-HcrPropertyValue $plan 'diskSizeGb') * 1GB) `
                    -MemoryStartupBytes ([int64](Get-HcrPropertyValue $plan 'startupMemoryGb') * 1GB) `
                    -SwitchName ([string](Get-HcrPropertyValue $plan 'switchName')) `
                    -ErrorAction Stop
                Set-VMMemory -VM $createdVm -DynamicMemoryEnabled $true `
                    -MinimumBytes 2GB `
                    -StartupBytes ([int64](Get-HcrPropertyValue $plan 'startupMemoryGb') * 1GB) `
                    -MaximumBytes ([int64](Get-HcrPropertyValue $plan 'maximumMemoryGb') * 1GB) `
                    -ErrorAction Stop
                Set-VMProcessor -VM $createdVm -Count ([int](Get-HcrPropertyValue $plan 'processorCount')) -ErrorAction Stop
                Set-VMFirmware -VM $createdVm -EnableSecureBoot On -ErrorAction Stop
                [void](Add-VMDvdDrive -VM $createdVm -Path ([string](Get-HcrPropertyValue $plan 'isoPath')) -ErrorAction Stop)
                Set-VMKeyProtector -VM $createdVm -NewLocalKeyProtector -ErrorAction Stop
                Enable-VMTPM -VM $createdVm -ErrorAction Stop
                Set-VM -VM $createdVm -Notes "hyperv-clean-room/v1:$ownershipId" -ErrorAction Stop
                $refreshed = Get-VM -Id $createdVm.Id -ErrorAction Stop
                return ConvertTo-HcrRealVmSnapshot $refreshed
            }
            catch {
                $partial = [ordered]@{
                    vmId = if ($null -eq $createdVm) { $null } else { [string]$createdVm.Id }
                    vmName = [string](Get-HcrPropertyValue $plan 'name')
                    vhdxPath = [string](Get-HcrPropertyValue $plan 'vhdxPath')
                }
                Throw-HcrError 'VM_CREATE_FAILED' 'VM creation failed; partial resources were preserved for recovery.' $partial
            }
        }
        'CreateCheckpoint' {
            try {
                $snapshot = Checkpoint-VM `
                    -VMName ([string](Get-HcrPropertyValue $Arguments 'vmName')) `
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
                Throw-HcrError 'CHECKPOINT_CREATE_FAILED' 'Checkpoint creation failed without cleanup.'
            }
        }
        'RestoreCheckpoint' {
            $vmName = [string](Get-HcrPropertyValue $Arguments 'vmName')
            $checkpointName = [string](Get-HcrPropertyValue $Arguments 'checkpointName')
            try {
                $snapshot = Get-VMSnapshot -VMName $vmName -Name $checkpointName -ErrorAction Stop
                Restore-VMSnapshot -VMSnapshot $snapshot -Confirm:$false -ErrorAction Stop
                return [pscustomobject][ordered]@{
                    checkpointId = [string]$snapshot.Id
                    restoredAt = Get-HcrUtcTimestamp
                }
            }
            catch {
                Throw-HcrError 'CHECKPOINT_RESTORE_FAILED' 'Checkpoint restore failed without cleanup.'
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
        { @('InspectGuest', 'StageArtifact', 'RunTestStep', 'RunCleanupStep') -contains $_ } {
            Throw-HcrError 'GUEST_ADAPTER_UNVALIDATED' 'Real guest execution is fail-closed until clean-machine validation; use the test-only mock adapter for Gate 2 tests.'
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

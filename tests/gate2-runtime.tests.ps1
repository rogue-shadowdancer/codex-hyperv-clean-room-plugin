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

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:AssertionCount++
    try {
        & $Action
    }
    catch {
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

function Invoke-WithCurrentUserDeniedAccess {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][Security.AccessControl.FileSystemRights]$Rights,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    $acl = Get-Acl -LiteralPath $Path
    $originalSddl = $acl.Sddl
    $rule = New-Object Security.AccessControl.FileSystemAccessRule(
        [Security.Principal.WindowsIdentity]::GetCurrent().User,
        $Rights,
        [Security.AccessControl.AccessControlType]::Deny
    )
    [void]$acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $Path -AclObject $acl
    try { & $Action }
    finally {
        $restoredAcl = Get-Acl -LiteralPath $Path
        $restoredAcl.SetSecurityDescriptorSddlForm($originalSddl)
        Set-Acl -LiteralPath $Path -AclObject $restoredAcl
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
        elevated = $false
        hyperVAdministratorsTokenEnabled = $true
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
$commonPath = Join-Path $pluginRoot 'mcp\lib\Common.ps1'
$commonSource = Get-Content -LiteralPath $commonPath -Raw -Encoding UTF8
$currentTokenEvidence = Get-HcrCurrentWindowsTokenEvidence
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$currentTokenEvidence.sid)) `
    'The native current-token probe omitted the current SID.'
Assert-True (@('low', 'medium', 'mediumPlus', 'high', 'system') -contains
    [string]$currentTokenEvidence.tokenIntegrity) `
    'The native current-token probe returned an unrecognized integrity label.'
Assert-True ($currentTokenEvidence.isElevated -is [bool]) `
    'The native current-token probe did not return a Boolean elevation value.'
Assert-True ($null -eq $currentTokenEvidence.PSObject.Properties['elevationType']) `
    'The internal token elevation type leaked into the public evidence projection.'

foreach ($integrityCase in @(
    @{ rid = [uint32]0x00001000; label = 'low' }
    @{ rid = [uint32]0x00002000; label = 'medium' }
    @{ rid = [uint32]0x00002100; label = 'mediumPlus' }
    @{ rid = [uint32]0x00003000; label = 'high' }
    @{ rid = [uint32]0x00004000; label = 'system' }
)) {
    Assert-Equal `
        ([HcrTokenEvidenceNative]::ClassifyIntegrityRid($integrityCase.rid)) `
        $integrityCase.label `
        'The shared native token probe classified a recognized integrity RID incorrectly.'
}
foreach ($invalidIntegrityRid in @(
    [uint32]0,
    [uint32]0x00000fff,
    [uint32]0x00001001,
    [uint32]0x00002001,
    [uint32]0x00002010,
    [uint32]0x000020ff,
    [uint32]0x00002101,
    [uint32]0x00002fff,
    [uint32]0x00003001,
    [uint32]0x00004001,
    [uint32]0x00005000
)) {
    Assert-Throws {
        [void][HcrTokenEvidenceNative]::ClassifyIntegrityRid($invalidIntegrityRid)
    } 'The shared native token probe accepted a non-exact integrity RID.'
}
foreach ($acceptedElevation in @(
    @{ type = 1; elevated = $false }
    @{ type = 1; elevated = $true }
    @{ type = 2; elevated = $true }
    @{ type = 3; elevated = $false }
)) {
    [HcrTokenEvidenceNative]::ValidateElevationConsistency(
        $acceptedElevation.type,
        $acceptedElevation.elevated
    )
    Assert-True $true 'The shared native token probe rejected consistent elevation evidence.'
}
foreach ($rejectedElevation in @(
    @{ type = 0; elevated = $false }
    @{ type = 2; elevated = $false }
    @{ type = 3; elevated = $true }
    @{ type = 4; elevated = $true }
)) {
    Assert-Throws {
        [HcrTokenEvidenceNative]::ValidateElevationConsistency(
            $rejectedElevation.type,
            $rejectedElevation.elevated
        )
    } 'The shared native token probe accepted inconsistent elevation evidence.'
}
foreach ($invalidHandleCall in @(
    { [void][HcrTokenEvidenceNative]::GetIntegrityRid([IntPtr]::Zero) }
    { [void][HcrTokenEvidenceNative]::GetIsElevated([IntPtr]::Zero) }
    { [void][HcrTokenEvidenceNative]::GetElevationType([IntPtr]::Zero) }
)) {
    Assert-Throws $invalidHandleCall 'The shared native token probe accepted an invalid token handle.'
}
$mediumIntegritySid = New-Object Security.Principal.SecurityIdentifier('S-1-16-8192')
$mediumIntegritySidBytes = New-Object byte[] $mediumIntegritySid.BinaryLength
$mediumIntegritySid.GetBinaryForm($mediumIntegritySidBytes, 0)
$wrongAuthoritySid = New-Object Security.Principal.SecurityIdentifier('S-1-5-8192')
$wrongAuthoritySidBytes = New-Object byte[] $wrongAuthoritySid.BinaryLength
$wrongAuthoritySid.GetBinaryForm($wrongAuthoritySidBytes, 0)
$multipleSubauthoritySid = New-Object Security.Principal.SecurityIdentifier('S-1-16-1-8192')
$multipleSubauthoritySidBytes = New-Object byte[] $multipleSubauthoritySid.BinaryLength
$multipleSubauthoritySid.GetBinaryForm($multipleSubauthoritySidBytes, 0)
$nativeSidBuffer = [Runtime.InteropServices.Marshal]::AllocHGlobal($mediumIntegritySidBytes.Length)
$nativeLabelBuffer = [Runtime.InteropServices.Marshal]::AllocHGlobal(64)
try {
    [Runtime.InteropServices.Marshal]::Copy(
        $mediumIntegritySidBytes,
        0,
        $nativeSidBuffer,
        $mediumIntegritySidBytes.Length
    )
    [Runtime.InteropServices.Marshal]::WriteIntPtr($nativeLabelBuffer, [IntPtr]::Zero)
    [Runtime.InteropServices.Marshal]::WriteInt32($nativeLabelBuffer, [IntPtr]::Size, 0x20)
    Assert-Throws {
        [void][HcrTokenEvidenceNative]::ReadIntegrityRid($nativeLabelBuffer, 64)
    } 'The shared native token probe accepted an absent mandatory-label SID.'
    [Runtime.InteropServices.Marshal]::WriteIntPtr($nativeLabelBuffer, $nativeSidBuffer)
    Assert-Throws {
        [void][HcrTokenEvidenceNative]::ReadIntegrityRid($nativeLabelBuffer, 64)
    } 'The shared native token probe accepted a SID outside the returned buffer.'
    $embeddedSidPointer = [IntPtr]::Add($nativeLabelBuffer, 16)
    [Runtime.InteropServices.Marshal]::Copy(
        $wrongAuthoritySidBytes,
        0,
        $embeddedSidPointer,
        $wrongAuthoritySidBytes.Length
    )
    [Runtime.InteropServices.Marshal]::WriteIntPtr($nativeLabelBuffer, $embeddedSidPointer)
    Assert-Throws {
        [void][HcrTokenEvidenceNative]::ReadIntegrityRid($nativeLabelBuffer, 64)
    } 'The shared native token probe accepted a non-mandatory SID authority.'
    [Runtime.InteropServices.Marshal]::Copy(
        $multipleSubauthoritySidBytes,
        0,
        $embeddedSidPointer,
        $multipleSubauthoritySidBytes.Length
    )
    Assert-Throws {
        [void][HcrTokenEvidenceNative]::ReadIntegrityRid($nativeLabelBuffer, 64)
    } 'The shared native token probe accepted multiple mandatory-label subauthorities.'
    [Runtime.InteropServices.Marshal]::Copy(
        $mediumIntegritySidBytes,
        0,
        $embeddedSidPointer,
        $mediumIntegritySidBytes.Length
    )
    [Runtime.InteropServices.Marshal]::WriteInt32($nativeLabelBuffer, [IntPtr]::Size, 0)
    Assert-Throws {
        [void][HcrTokenEvidenceNative]::ReadIntegrityRid($nativeLabelBuffer, 64)
    } 'The shared native token probe accepted a label without SE_GROUP_INTEGRITY.'
    [Runtime.InteropServices.Marshal]::WriteInt32($nativeLabelBuffer, [IntPtr]::Size, 0x20)
    Assert-Equal `
        ([HcrTokenEvidenceNative]::ReadIntegrityRid($nativeLabelBuffer, 64)) `
        ([uint32]0x00002000) `
        'The shared native token probe did not read a valid exact-medium label.'
}
finally {
    [Runtime.InteropServices.Marshal]::FreeHGlobal($nativeLabelBuffer)
    [Runtime.InteropServices.Marshal]::FreeHGlobal($nativeSidBuffer)
}
foreach ($requiredNativeSafetySeam in @(
    'ErrorInsufficientBuffer = 122',
    'MaximumTokenInformationLength = 4096',
    'SeGroupIntegrity = 0x00000020',
    'IsValidSid',
    'GetLengthSid',
    'GetSidIdentifierAuthority',
    'ReadIntegrityRid',
    'Marshal.SizeOf(typeof(HcrTokenMandatoryLabel))',
    'sizingError != ErrorInsufficientBuffer',
    'length > MaximumTokenInformationLength',
    '(label.Label.Attributes & SeGroupIntegrity) == 0',
    'Marshal.FreeHGlobal(buffer)'
)) {
    Assert-True ($commonSource -match [regex]::Escape($requiredNativeSafetySeam)) `
        "The shared native token probe is missing the fail-closed seam '$requiredNativeSafetySeam'."
}
$sharedProbeScript = ${function:Get-HcrCurrentWindowsTokenEvidence}
$tokenProbeJob = Start-Job -ScriptBlock $sharedProbeScript
try {
    [void](Wait-Job -Job $tokenProbeJob -Timeout 30)
    Assert-Equal ([string]$tokenProbeJob.State) 'Completed' `
        'The self-contained remoting token probe did not complete in an isolated process.'
    $isolatedTokenResults = @(Receive-Job -Job $tokenProbeJob -ErrorAction Stop)
    Assert-Equal $isolatedTokenResults.Count 1 `
        'The self-contained remoting token probe did not return exactly one result.'
    $isolatedTokenEvidence = $isolatedTokenResults[0]
}
finally {
    Remove-Job -Job $tokenProbeJob -Force -ErrorAction SilentlyContinue
}
Assert-Equal ([string]$isolatedTokenEvidence.sid) ([string]$currentTokenEvidence.sid) `
    'The self-contained remoting token probe changed the current SID.'
Assert-Equal ([string]$isolatedTokenEvidence.tokenIntegrity) `
    ([string]$currentTokenEvidence.tokenIntegrity) `
    'The self-contained remoting token probe changed token integrity.'
Assert-Equal ([bool]$isolatedTokenEvidence.isElevated) ([bool]$currentTokenEvidence.isElevated) `
    'The self-contained remoting token probe changed token elevation.'
$hadComputerName = Test-Path Env:COMPUTERNAME
$savedComputerName = $env:COMPUTERNAME
try {
    Remove-Item Env:COMPUTERNAME -ErrorAction SilentlyContinue
    $script:HcrInitialized = $false
    Initialize-HcrRuntime $pluginRoot
    Assert-Equal ([string]$env:COMPUTERNAME) ([Environment]::MachineName) `
        'Runtime initialization did not repair a missing COMPUTERNAME.'

    $env:COMPUTERNAME = '   '
    $script:HcrInitialized = $false
    Initialize-HcrRuntime $pluginRoot
    Assert-Equal ([string]$env:COMPUTERNAME) ([Environment]::MachineName) `
        'Runtime initialization did not repair a whitespace COMPUTERNAME.'

    $env:COMPUTERNAME = 'HCR-EXPLICIT-COMPUTERNAME'
    $script:HcrInitialized = $false
    Initialize-HcrRuntime $pluginRoot
    Assert-Equal ([string]$env:COMPUTERNAME) 'HCR-EXPLICIT-COMPUTERNAME' `
        'Runtime initialization overwrote an explicit COMPUTERNAME.'
}
finally {
    if ($hadComputerName) { $env:COMPUTERNAME = $savedComputerName }
    else { Remove-Item Env:COMPUTERNAME -ErrorAction SilentlyContinue }
}
$script:HcrInitialized = $false
Initialize-HcrRuntime $pluginRoot
Assert-Equal (@(Get-ChildItem `
        -LiteralPath $stateRoot `
        -Recurse `
        -Force `
        -Filter '.hcr-access-*.tmp').Count) 0 `
    'State-root writable probes left a temporary file behind.'

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

$leastPrivilegeHost = Invoke-TestTool 'inspect_host' ([pscustomobject]@{})
Assert-True $leastPrivilegeHost.ok 'Least-privilege host inspection failed.'
Assert-True (-not [bool]$leastPrivilegeHost.data.host.elevated) `
    'The mock least-privilege host unexpectedly reported elevation.'
Assert-True ([bool]$leastPrivilegeHost.data.host.hyperVAdministratorsTokenEnabled) `
    'The mock Hyper-V Administrators token was not projected.'
Assert-True ([bool]$leastPrivilegeHost.data.host.hyperVAuthorized) `
    'The mock Hyper-V Administrators token was not authorized.'
Assert-Equal ([string]$leastPrivilegeHost.data.host.authorizationMode) `
    'hyperVAdministrators' `
    'The least-privilege authorization mode is incorrect.'
Assert-True (@(Get-HcrPropertyNames $leastPrivilegeHost.data.host) -notcontains 'userName') `
    'Host authorization diagnostics exposed a user name.'
Assert-True (@(Get-HcrPropertyNames $leastPrivilegeHost.data.host) -notcontains 'userSid') `
    'Host authorization diagnostics exposed a user SID.'
Assert-True (@($leastPrivilegeHost.warnings) -notcontains $script:HcrBroaderPrivilegeWarning) `
    'A non-elevated Hyper-V Administrators token emitted the broader-privilege warning.'
$leastPrivilegeFingerprint = [string]$leastPrivilegeHost.data.hostFingerprint

$authorizationState = Read-HcrMockAdapterState
$authorizationState.host.hyperVAdministratorsTokenEnabled = $false
Write-HcrMockAdapterState $authorizationState
$diagnosticOnlyHost = Invoke-TestTool 'inspect_host' ([pscustomobject]@{})
Assert-True $diagnosticOnlyHost.ok 'Unauthorised diagnostic inspect_host was blocked.'
Assert-Equal ([string]$diagnosticOnlyHost.data.host.authorizationMode) 'none' `
    'Unauthorised inspect_host did not report authorizationMode=none.'
Assert-True (-not [bool]$diagnosticOnlyHost.data.host.hyperVAuthorized) `
    'Unauthorised inspect_host reported Hyper-V authorization.'
$unauthorizedList = Invoke-TestTool 'list_vms' ([pscustomobject]@{ managedOnly = $false })
Assert-ErrorCode $unauthorizedList 'HYPERV_AUTHORIZATION_REQUIRED' `
    'list_vms accepted a token without Hyper-V authorization.'
$unauthorizedInspectVm = Invoke-TestTool 'inspect_vm' ([pscustomobject]@{ vmName = 'missing' })
Assert-ErrorCode $unauthorizedInspectVm 'HYPERV_AUTHORIZATION_REQUIRED' `
    'inspect_vm accepted a token without Hyper-V authorization.'
$unauthorizedPlan = Invoke-TestTool 'plan_vm_create' ([pscustomobject]@{
    name = 'unauthorized-plan'
    isoPath = $isoPath
    vmRoot = $vmRoot
    switchName = 'Default Switch'
})
Assert-ErrorCode $unauthorizedPlan 'HYPERV_AUTHORIZATION_REQUIRED' `
    'plan_vm_create accepted a token without Hyper-V authorization.'
$authorizationState = Read-HcrMockAdapterState
$authorizationState.host.hyperVCommandsAvailable = $false
$authorizationState.host.hypervisorPresent = $false
Write-HcrMockAdapterState $authorizationState
$unauthorizedUnavailableList = Invoke-TestTool 'list_vms' ([pscustomobject]@{
    managedOnly = $false
})
Assert-ErrorCode $unauthorizedUnavailableList 'HYPERV_AUTHORIZATION_REQUIRED' `
    'An unavailable host masked the current-token authorization failure.'
$authorizationState = Read-HcrMockAdapterState
$authorizationState.host.hyperVCommandsAvailable = $true
$authorizationState.host.hypervisorPresent = $true
Write-HcrMockAdapterState $authorizationState

$authorizationState = Read-HcrMockAdapterState
$authorizationState.host.elevated = $true
$authorizationState.host.hyperVAdministratorsTokenEnabled = $true
Write-HcrMockAdapterState $authorizationState
$elevatedHost = Invoke-TestTool 'inspect_host' ([pscustomobject]@{})
Assert-Equal ([string]$elevatedHost.data.host.authorizationMode) `
    'elevatedAdministrator' `
    'Elevated Administrator did not take authorization-mode precedence.'
Assert-True (@($elevatedHost.warnings) -contains $script:HcrBroaderPrivilegeWarning) `
    'Elevated compatibility mode omitted the broader-privilege warning.'

$authorizationState = Read-HcrMockAdapterState
$authorizationState.host.elevated = $false
$authorizationState.host.hyperVAdministratorsTokenEnabled = $true
Write-HcrMockAdapterState $authorizationState
$restoredLeastPrivilegeHost = Invoke-TestTool 'inspect_host' ([pscustomobject]@{})
Assert-Equal ([string]$restoredLeastPrivilegeHost.data.hostFingerprint) `
    $leastPrivilegeFingerprint `
    'Authorization projection fields changed the schema-v1 host fingerprint.'
$leastPrivilegeList = Invoke-TestTool 'list_vms' ([pscustomobject]@{ managedOnly = $false })
Assert-True $leastPrivilegeList.ok `
    'list_vms rejected an enabled Hyper-V Administrators token.'

Invoke-WithCurrentUserDeniedAccess `
    $isoPath `
    ([Security.AccessControl.FileSystemRights]::ReadData) `
    {
        $deniedIsoPlan = Invoke-TestTool 'plan_vm_create' ([pscustomobject]@{
            name = 'denied-iso-plan'
            isoPath = $isoPath
            vmRoot = $vmRoot
            switchName = 'Default Switch'
        })
        Assert-ErrorCode $deniedIsoPlan 'ISO_ACCESS_DENIED' `
            'An unreadable ISO did not fail with ISO_ACCESS_DENIED.'
    }

Invoke-WithCurrentUserDeniedAccess `
    $vmRoot `
    ([Security.AccessControl.FileSystemRights]::ListDirectory) `
    {
        $deniedRootPlan = Invoke-TestTool 'plan_vm_create' ([pscustomobject]@{
            name = 'denied-root-plan'
            isoPath = $isoPath
            vmRoot = $vmRoot
            switchName = 'Default Switch'
        })
        Assert-ErrorCode $deniedRootPlan 'VM_ROOT_ACCESS_DENIED' `
            'An inaccessible VM root did not fail with VM_ROOT_ACCESS_DENIED.'
    }

$deniedStateRoot = Join-Path $testRoot 'denied-state-root'
[void](New-Item -ItemType Directory -Path $deniedStateRoot -Force)
$savedStateRootEnvironment = $env:HCR_STATE_ROOT
$savedRuntimeStateRoot = $script:HcrStateRoot
try {
    Invoke-WithCurrentUserDeniedAccess `
        $deniedStateRoot `
        ([Security.AccessControl.FileSystemRights]::CreateDirectories -bor
            [Security.AccessControl.FileSystemRights]::ListDirectory) `
        {
            $env:HCR_STATE_ROOT = $deniedStateRoot
            $script:HcrStateRoot = $null
            Assert-ThrowsHcrCode `
                { [void](Initialize-HcrStateStore) } `
                'STATE_ROOT_ACCESS_DENIED' `
                'An inaccessible state root did not fail with STATE_ROOT_ACCESS_DENIED.'
        }
}
finally {
    $env:HCR_STATE_ROOT = $savedStateRootEnvironment
    $script:HcrStateRoot = $savedRuntimeStateRoot
}

$restrictedChildStateRoot = Join-Path $testRoot 'restricted-child-state-root'
$savedStateRootEnvironment = $env:HCR_STATE_ROOT
$savedRuntimeStateRoot = $script:HcrStateRoot
try {
    $env:HCR_STATE_ROOT = $restrictedChildStateRoot
    $script:HcrStateRoot = $null
    [void](Initialize-HcrStateStore)

    Invoke-WithCurrentUserDeniedAccess `
        (Join-Path $restrictedChildStateRoot 'plans') `
        ([Security.AccessControl.FileSystemRights]::ListDirectory) `
        {
            $script:HcrStateRoot = $null
            Assert-ThrowsHcrCode `
                { [void](Initialize-HcrStateStore) } `
                'STATE_ROOT_ACCESS_DENIED' `
                'A non-enumerable state child did not fail during initialization.'
        }

    Invoke-WithCurrentUserDeniedAccess `
        (Join-Path $restrictedChildStateRoot 'operations') `
        ([Security.AccessControl.FileSystemRights]::CreateFiles) `
        {
            $script:HcrStateRoot = $null
            Assert-ThrowsHcrCode `
                { [void](Initialize-HcrStateStore) } `
                'STATE_ROOT_ACCESS_DENIED' `
                'A non-writable state child did not fail during initialization.'
        }

    $script:HcrStateRoot = $restrictedChildStateRoot
    Invoke-WithCurrentUserDeniedAccess `
        (Join-Path $restrictedChildStateRoot 'ownership') `
        ([Security.AccessControl.FileSystemRights]::CreateFiles) `
        {
            Assert-ThrowsHcrCode `
                {
                    Write-HcrJsonFile `
                        (Join-Path $restrictedChildStateRoot 'ownership\probe.json') `
                        ([pscustomobject]@{ probe = $true })
                } `
                'STATE_ROOT_ACCESS_DENIED' `
                'A post-start state write denial escaped as a generic error.'
        }

    $restrictedReadPath = Join-Path $restrictedChildStateRoot 'ownership\read-probe.json'
    Write-HcrJsonFile $restrictedReadPath ([pscustomobject]@{ probe = $true })
    Invoke-WithCurrentUserDeniedAccess `
        $restrictedReadPath `
        ([Security.AccessControl.FileSystemRights]::ReadData) `
        {
            Assert-ThrowsHcrCode `
                { [void](Read-HcrJsonFile $restrictedReadPath) } `
                'STATE_ROOT_ACCESS_DENIED' `
                'A post-start state read denial escaped as a generic integrity error.'
        }

    $evidenceStagingRoot = Join-Path $restrictedChildStateRoot 'evidence-staging'
    $restrictedOperationRoot = Join-Path $evidenceStagingRoot ([Guid]::NewGuid().ToString())
    Invoke-WithCurrentUserDeniedAccess `
        $evidenceStagingRoot `
        ([Security.AccessControl.FileSystemRights]::CreateDirectories) `
        {
            Assert-ThrowsHcrCode `
                { [void](Initialize-HcrStateManagedDirectory $restrictedOperationRoot) } `
                'STATE_ROOT_ACCESS_DENIED' `
                'A post-start evidence-staging create denial escaped as a generic error.'
        }

    [void](Initialize-HcrStateManagedDirectory $restrictedOperationRoot)
    Write-HcrJsonFile `
        (Join-Path $restrictedOperationRoot 'evidence.json') `
        ([pscustomobject]@{ probe = $true })
    Invoke-WithCurrentUserDeniedAccess `
        $restrictedOperationRoot `
        ([Security.AccessControl.FileSystemRights]::ListDirectory) `
        {
            Assert-ThrowsHcrCode `
                { [void](Get-HcrStateItems $restrictedOperationRoot -Recurse) } `
                'STATE_ROOT_ACCESS_DENIED' `
                'A post-start evidence-staging enumeration denial escaped as a generic error.'
        }
}
finally {
    $env:HCR_STATE_ROOT = $savedStateRootEnvironment
    $script:HcrStateRoot = $savedRuntimeStateRoot
}

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

$authorizationConsumptionPlan = Invoke-TestTool 'plan_vm_create' ([pscustomobject]@{
    name = 'authorization-consumption-vm'
    isoPath = $isoPath
    vmRoot = $vmRoot
    switchName = 'Default Switch'
    diskSizeGb = 40
})
Assert-True $authorizationConsumptionPlan.ok `
    'The authorization-consumption VM-create plan failed.'
$mock = Read-HcrMockAdapterState
$mock.host.elevated = $false
$mock.host.hyperVAdministratorsTokenEnabled = $false
Write-HcrMockAdapterState $mock
$global:HcrMockHostSnapshotCallCount = 0
$unauthorizedVmCreateApply = Invoke-TestTool 'apply_vm_create' ([pscustomobject]@{
    planId = [string]$authorizationConsumptionPlan.data.plan.planId
})
Assert-ErrorCode $unauthorizedVmCreateApply 'HYPERV_AUTHORIZATION_REQUIRED' `
    'VM-create apply ran drift probes before checking current authorization.'
Assert-Equal $global:HcrMockHostSnapshotCallCount 0 `
    'VM-create apply probed the host snapshot before checking current authorization.'
Remove-Variable -Name HcrMockHostSnapshotCallCount -Scope Global -ErrorAction SilentlyContinue
$mock = Read-HcrMockAdapterState
$mock.host.hyperVAdministratorsTokenEnabled = $true
Write-HcrMockAdapterState $mock
$authorizationConsumptionReplay = Invoke-TestTool 'apply_vm_create' ([pscustomobject]@{
    planId = [string]$authorizationConsumptionPlan.data.plan.planId
})
Assert-ErrorCode $authorizationConsumptionReplay 'PLAN_ALREADY_CONSUMED' `
    'A VM-create authorization failure did not preserve plan consumption ordering.'

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
Assert-True ($mock.vms[0].automaticCheckpointsEnabled -is [bool] -and
    -not [bool]$mock.vms[0].automaticCheckpointsEnabled) `
    'A newly created VM did not verify automatic checkpoints as disabled.'
$originalOwnedVm = Copy-HcrObject $mock.vms[0]
$recordedBasePath = [string]$mock.vms[0].vhdxPath
$automaticLeafPath = Join-Path ([string]$mock.vms[0].vmPath) `
    'cleanroom-test_A1B2C3D4-E5F6-47A8-9012-3456789ABCDE.avhdx'
$automaticChain = @(
    [pscustomobject][ordered]@{
        path = $automaticLeafPath
        fileLength = 8388608
        diskIdentifier = [Guid]::NewGuid().ToString()
        virtualSize = 40GB
        physicalFileSize = 8388608
        parentPath = $recordedBasePath
    }
    [pscustomobject][ordered]@{
        path = $recordedBasePath
        fileLength = 4194304
        diskIdentifier = [Guid]::NewGuid().ToString()
        virtualSize = 40GB
        physicalFileSize = 4194304
        parentPath = $null
    }
)
$mock.vms[0].vhdxPath = $automaticLeafPath
$mock.vms[0].baseVhdxPath = $recordedBasePath
$mock.vms[0].vhdxChain = $automaticChain
$mock.vms[0].vhdxChainVerified = $true
$mock.vms[0].vhdxChainFingerprint = Get-HcrVhdChainFingerprint $automaticChain
$mock.vms[0].automaticCheckpointsEnabled = $true
$mock.vms[0].checkpoints = @([pscustomobject][ordered]@{
    id = [Guid]::NewGuid().ToString()
    name = 'Automatic Checkpoint - cleanroom-test'
    parentId = $null
    configurationFingerprint = Get-HcrSha256Text 'automatic-checkpoint'
    createdAt = [DateTimeOffset]::UtcNow.ToString('o')
})
Write-HcrMockAdapterState $mock
$ownershipRecordPath = Get-HcrStateSubpath 'ownership' `
    "$((Get-HcrRecordKey ([string]$mock.vms[0].id))).json"
$ownershipRecordHash = Get-HcrSha256File $ownershipRecordPath
$automaticChainInspect = Invoke-TestTool 'inspect_vm' ([pscustomobject]@{
    vmName = 'cleanroom-test'
})
Assert-True $automaticChainInspect.ok 'The automatic-checkpoint VM could not be inspected.'
Assert-True ([bool]$automaticChainInspect.data.ownership.verified) `
    'A complete automatic-checkpoint chain ending at the recorded base was not ownership verified.'
Assert-Equal ([string]$automaticChainInspect.data.ownership.storageBinding) `
    'verifiedDifferencingChain' `
    'The automatic-checkpoint chain did not report its verified storage-binding mode.'
Assert-True ([bool]$automaticChainInspect.data.ownership.automaticCheckpointRecoveryRequired) `
    'The pre-fix VM did not report that automatic-checkpoint recovery is still required.'
Assert-True (@($automaticChainInspect.warnings | Where-Object {
    $_ -match 'Automatic checkpoints are enabled or unavailable'
}).Count -eq 1) `
    'The pre-fix VM inspection did not return its bounded automatic-checkpoint warning.'
Assert-Equal (Get-HcrSha256File $ownershipRecordPath) $ownershipRecordHash `
    'Read-only differencing-chain recognition rewrote the existing ownership record.'

$automaticChainCheckpointPlan = Invoke-TestTool 'plan_checkpoint_create' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    checkpointName = 'chain-verified-plan'
})
Assert-True $automaticChainCheckpointPlan.ok `
    'A verified automatic-checkpoint chain remained deadlocked at read-only mutation planning.'
$mock = Read-HcrMockAdapterState
$mock | Add-Member `
    -NotePropertyName dispatchOwnershipDrift `
    -NotePropertyValue 'chainFingerprint' `
    -Force
Write-HcrMockAdapterState $mock
$automaticChainDispatchApply = Invoke-TestTool 'apply_checkpoint_create' ([pscustomobject]@{
    planId = [string]$automaticChainCheckpointPlan.data.plan.planId
})
Assert-ErrorCode $automaticChainDispatchApply 'VM_IDENTITY_DRIFT' `
    'A chain fingerprint forged at the ordinary adapter dispatch boundary was accepted.'
$mock = Read-HcrMockAdapterState
$mock.vms[0].vhdxChain = @($automaticChain | ForEach-Object { Copy-HcrObject $_ })
$mock.vms[0].vhdxChainFingerprint = Get-HcrVhdChainFingerprint @($mock.vms[0].vhdxChain)
Write-HcrMockAdapterState $mock

$mock = Read-HcrMockAdapterState
$mock.vms[0].state = 'Running'
Write-HcrMockAdapterState $mock
$automaticChainShutdownPlan = Invoke-HcrToolCall 'plan_vm_power' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    action = 'gracefulShutdown'
})
Assert-Equal ([int]$automaticChainShutdownPlan.schemaVersion) 2 `
    'The rejected automatic-checkpoint shutdown did not use the schema-v2 envelope.'
Assert-ErrorCode $automaticChainShutdownPlan 'VM_STATE_UNSUPPORTED' `
    'A running managed VM with automatic checkpoints enabled was allowed to prepare shutdown.'
$mock = Read-HcrMockAdapterState
$mock.vms[0].state = 'Off'
Write-HcrMockAdapterState $mock
$unsafeAutomaticStart = Invoke-HcrToolCall 'plan_vm_power' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    action = 'start'
})
Assert-Equal ([int]$unsafeAutomaticStart.schemaVersion) 2 `
    'The rejected automatic-checkpoint start did not use the schema-v2 envelope.'
Assert-ErrorCode $unsafeAutomaticStart 'VM_STATE_UNSUPPORTED' `
    'A managed VM with automatic checkpoints enabled was allowed to prepare a start.'

$mock = Read-HcrMockAdapterState
$mock.vms[0].vhdxChain[0].parentPath = Join-Path ([string]$mock.vms[0].vmPath) `
    'unrelated-parent.vhdx'
$mock.vms[0].vhdxChainFingerprint = Get-HcrVhdChainFingerprint @($mock.vms[0].vhdxChain)
Write-HcrMockAdapterState $mock
$brokenLinkInspect = Invoke-TestTool 'inspect_vm' ([pscustomobject]@{
    vmName = 'cleanroom-test'
})
Assert-True (-not [bool]$brokenLinkInspect.data.ownership.verified) `
    'A chain whose parent link did not match the next identity-bearing member was accepted.'

$mock = Read-HcrMockAdapterState
$unrelatedBasePath = Join-Path ([string]$mock.vms[0].vmPath) 'unrelated-base.vhdx'
$mock.vms[0].vhdxChain[0].parentPath = $unrelatedBasePath
$mock.vms[0].vhdxChain[1].path = $unrelatedBasePath
$mock.vms[0].baseVhdxPath = $unrelatedBasePath
$mock.vms[0].vhdxChainFingerprint = Get-HcrVhdChainFingerprint @($mock.vms[0].vhdxChain)
Write-HcrMockAdapterState $mock
$unrelatedChainInspect = Invoke-TestTool 'inspect_vm' ([pscustomobject]@{
    vmName = 'cleanroom-test'
})
Assert-True (-not [bool]$unrelatedChainInspect.data.ownership.verified) `
    'An internally consistent chain ending at an unrelated base VHDX was accepted.'

$mock = Read-HcrMockAdapterState
$mock.vms[0].vhdxChain = $automaticChain
$mock.vms[0].baseVhdxPath = $recordedBasePath
$mock.vms[0].vhdxChainFingerprint = ('0' * 64)
Write-HcrMockAdapterState $mock
$forgedChainHashInspect = Invoke-TestTool 'inspect_vm' ([pscustomobject]@{
    vmName = 'cleanroom-test'
})
Assert-True (-not [bool]$forgedChainHashInspect.data.ownership.verified) `
    'A differencing chain with a forged identity fingerprint was accepted.'

$mock = Read-HcrMockAdapterState
$cycleChain = @($automaticChain | ForEach-Object { Copy-HcrObject $_ })
$cycleChain[$cycleChain.Count - 1].parentPath = $automaticLeafPath
$mock.vms[0].vhdxChain = $cycleChain
$mock.vms[0].vhdxChainFingerprint = Get-HcrVhdChainFingerprint @($cycleChain)
Write-HcrMockAdapterState $mock
$cycleChainInspect = Invoke-TestTool 'inspect_vm' ([pscustomobject]@{
    vmName = 'cleanroom-test'
})
Assert-True (-not [bool]$cycleChainInspect.data.ownership.verified) `
    'A differencing chain whose terminal member linked back to the active leaf was accepted.'

$mock = Read-HcrMockAdapterState
$missingIdentityChain = @($automaticChain | ForEach-Object { Copy-HcrObject $_ })
$missingIdentityChain[0].diskIdentifier = $null
$mock.vms[0].vhdxChain = $missingIdentityChain
$mock.vms[0].vhdxChainFingerprint = Get-HcrVhdChainFingerprint @($missingIdentityChain)
Write-HcrMockAdapterState $mock
$missingIdentityInspect = Invoke-TestTool 'inspect_vm' ([pscustomobject]@{
    vmName = 'cleanroom-test'
})
Assert-True (-not [bool]$missingIdentityInspect.data.ownership.verified) `
    'A differencing chain member without a Hyper-V disk identity was accepted.'

$mock = Read-HcrMockAdapterState
$overlongChain = @()
for ($chainIndex = 0; $chainIndex -lt 65; $chainIndex++) {
    $chainPath = if ($chainIndex -eq 0) {
        $automaticLeafPath
    }
    elseif ($chainIndex -eq 64) {
        $recordedBasePath
    }
    else {
        Join-Path ([string]$mock.vms[0].vmPath) ("chain-member-{0}.avhdx" -f $chainIndex)
    }
    $nextPath = if ($chainIndex -eq 64) {
        $null
    }
    elseif ($chainIndex -eq 63) {
        $recordedBasePath
    }
    else {
        Join-Path ([string]$mock.vms[0].vmPath) ("chain-member-{0}.avhdx" -f ($chainIndex + 1))
    }
    $overlongChain += [pscustomobject][ordered]@{
        path = $chainPath
        fileLength = 4194304
        diskIdentifier = [Guid]::NewGuid().ToString()
        virtualSize = 40GB
        physicalFileSize = 4194304
        parentPath = $nextPath
    }
}
$mock.vms[0].vhdxChain = $overlongChain
$mock.vms[0].vhdxChainFingerprint = Get-HcrVhdChainFingerprint @($overlongChain)
Write-HcrMockAdapterState $mock
$overlongChainInspect = Invoke-TestTool 'inspect_vm' ([pscustomobject]@{
    vmName = 'cleanroom-test'
})
Assert-True (-not [bool]$overlongChainInspect.data.ownership.verified) `
    'A differencing chain exceeding the 64-member verification bound was accepted.'

$mock = Read-HcrMockAdapterState
$mock.vms[0] = $originalOwnedVm
Write-HcrMockAdapterState $mock
Assert-Equal (Get-HcrSha256File $ownershipRecordPath) $ownershipRecordHash `
    'Automatic-checkpoint regression cases modified the existing ownership record.'

$mock = Read-HcrMockAdapterState
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

$authorizationCheckpointPlan = Invoke-TestTool 'plan_checkpoint_create' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    checkpointName = 'authorization-checkpoint'
})
Assert-True $authorizationCheckpointPlan.ok 'Authorization checkpoint plan failed.'
$mock = Read-HcrMockAdapterState
$mock.host.elevated = $false
$mock.host.hyperVAdministratorsTokenEnabled = $false
Write-HcrMockAdapterState $mock
$global:HcrMockHostSnapshotCallCount = 0
$unauthorizedCheckpointApply = Invoke-TestTool 'apply_checkpoint_create' ([pscustomobject]@{
    planId = [string]$authorizationCheckpointPlan.data.plan.planId
})
Assert-ErrorCode $unauthorizedCheckpointApply 'HYPERV_AUTHORIZATION_REQUIRED' `
    'Checkpoint-create apply ran host drift probes before current authorization.'
Assert-Equal $global:HcrMockHostSnapshotCallCount 0 `
    'Checkpoint-create apply probed the host snapshot before current authorization.'
Remove-Variable -Name HcrMockHostSnapshotCallCount -Scope Global -ErrorAction SilentlyContinue
$mock = Read-HcrMockAdapterState
$mock.host.hyperVAdministratorsTokenEnabled = $true
Write-HcrMockAdapterState $mock
$authorizationCheckpointReplay = Invoke-TestTool 'apply_checkpoint_create' ([pscustomobject]@{
    planId = [string]$authorizationCheckpointPlan.data.plan.planId
})
Assert-ErrorCode $authorizationCheckpointReplay 'PLAN_ALREADY_CONSUMED' `
    'Checkpoint-create authorization failure did not preserve plan consumption.'

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

$authorizationRestorePlan = Invoke-TestTool 'plan_checkpoint_restore' ([pscustomobject]@{
    vmName = 'cleanroom-test'
    checkpointName = 'baseline'
})
Assert-True $authorizationRestorePlan.ok 'Authorization restore plan failed.'
$mock = Read-HcrMockAdapterState
$mock.host.elevated = $false
$mock.host.hyperVAdministratorsTokenEnabled = $false
Write-HcrMockAdapterState $mock
$global:HcrMockHostSnapshotCallCount = 0
$unauthorizedRestoreApply = Invoke-TestTool 'apply_checkpoint_restore' ([pscustomobject]@{
    planId = [string]$authorizationRestorePlan.data.plan.planId
    checkpointName = 'baseline'
    confirmationToken = [string]$authorizationRestorePlan.data.plan.confirmationToken
})
Assert-ErrorCode $unauthorizedRestoreApply 'HYPERV_AUTHORIZATION_REQUIRED' `
    'Checkpoint-restore apply ran host drift probes before current authorization.'
Assert-Equal $global:HcrMockHostSnapshotCallCount 0 `
    'Checkpoint-restore apply probed the host snapshot before current authorization.'
Remove-Variable -Name HcrMockHostSnapshotCallCount -Scope Global -ErrorAction SilentlyContinue
$mock = Read-HcrMockAdapterState
$mock.host.hyperVAdministratorsTokenEnabled = $true
Write-HcrMockAdapterState $mock
$authorizationRestoreReplay = Invoke-TestTool 'apply_checkpoint_restore' ([pscustomobject]@{
    planId = [string]$authorizationRestorePlan.data.plan.planId
    checkpointName = 'baseline'
    confirmationToken = [string]$authorizationRestorePlan.data.plan.confirmationToken
})
Assert-ErrorCode $authorizationRestoreReplay 'PLAN_ALREADY_CONSUMED' `
    'Checkpoint-restore authorization failure did not preserve plan consumption.'

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

$mock = Read-HcrMockAdapterState
$restoreBoundaryOriginalVm = Copy-HcrObject `
    @($mock.vms | Where-Object { $_.name -eq 'cleanroom-test' })[0]
$restoreBoundaryVm = @($mock.vms | Where-Object { $_.name -eq 'cleanroom-test' })[0]
$restoreBoundaryVm.vhdxPath = $automaticLeafPath
$restoreBoundaryVm.baseVhdxPath = $recordedBasePath
$restoreBoundaryVm.vhdxChain = @($automaticChain | ForEach-Object { Copy-HcrObject $_ })
$restoreBoundaryVm.vhdxChainVerified = $true
$restoreBoundaryVm.vhdxChainFingerprint = Get-HcrVhdChainFingerprint @($restoreBoundaryVm.vhdxChain)
$restoreBoundaryVm.automaticCheckpointsEnabled = $false
Write-HcrMockAdapterState $mock
foreach ($restoreDispatchDrift in @(
    'state',
    'currentState',
    'checkpointReplacement',
    'inventory',
    'ownershipChainFingerprint'
)) {
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
$mock.vms[0] = $restoreBoundaryOriginalVm
Write-HcrMockAdapterState $mock
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
Assert-True (@($managedList.warnings) -contains $script:HcrMockWarning) `
    'Mock list_vms lost the required test-only warning.'

$mock = Read-HcrMockAdapterState
$global:HcrMockOwnershipProjectionCallCount = 0
$baselineAllVmList = Invoke-TestTool 'list_vms' ([pscustomobject]@{ managedOnly = $false })
Assert-True $baselineAllVmList.ok 'The baseline all-VM list failed before adding an unmanaged VM.'
$expectedManagedCandidateCount = $global:HcrMockOwnershipProjectionCallCount
Assert-True ($expectedManagedCandidateCount -gt 0) `
    'The baseline list did not exercise any managed ownership candidate.'
$unmanagedUnicodeName = [string][char]0x6D4B + [char]0x8BD5 + '-unmanaged'
$unmanagedVm = Copy-HcrObject $mock.vms[0]
$unmanagedVm.id = [Guid]::NewGuid().ToString()
$unmanagedVm.name = $unmanagedUnicodeName
$unmanagedVm.notes = ''
$unmanagedVm.vmPath = Join-Path $vmRoot $unmanagedUnicodeName
$unmanagedVm.vhdxPath = Join-Path $unmanagedVm.vmPath "$unmanagedUnicodeName.vhdx"
$unmanagedVm | Add-Member `
    -NotePropertyName ownershipProjectionUnavailable `
    -NotePropertyValue $true `
    -Force
$mock.vms = @($mock.vms) + @($unmanagedVm)
Write-HcrMockAdapterState $mock
$global:HcrMockOwnershipProjectionCallCount = 0
$allVmList = Invoke-TestTool 'list_vms' ([pscustomobject]@{ managedOnly = $false })
Assert-True $allVmList.ok 'The mixed managed/unmanaged VM listing failed.'
Assert-Equal @($allVmList.data.vms).Count (@($baselineAllVmList.data.vms).Count + 1) `
    'The mixed VM listing returned the wrong summary count.'
Assert-Equal $global:HcrMockOwnershipProjectionCallCount $expectedManagedCandidateCount `
    'An unmanaged VM entered ownership storage projection.'
$unmanagedSummary = @($allVmList.data.vms | Where-Object {
    [string]$_.name -eq $unmanagedUnicodeName
})
Assert-Equal $unmanagedSummary.Count 1 'The Unicode unmanaged VM summary was not preserved.'
Assert-Equal ([string]$unmanagedSummary[0].ownershipStatus) 'unmanaged' `
    'The unmanaged VM summary received the wrong ownership status.'
foreach ($privateListField in @(
    'notes',
    'vmPath',
    'vhdxPath',
    'networkAdapters',
    'checkpoints',
    'firmware',
    'security'
)) {
    Assert-True (@(Get-HcrPropertyNames $unmanagedSummary[0]) -notcontains $privateListField) `
        "list_vms exposed the internal or deep field '$privateListField'."
}
$managedOnlyWithUnmanaged = Invoke-TestTool 'list_vms' ([pscustomobject]@{})
Assert-True (@($managedOnlyWithUnmanaged.data.vms | Where-Object {
    [string]$_.name -eq $unmanagedUnicodeName
}).Count -eq 0) 'managedOnly=true retained an unmanaged VM.'

$mock = Read-HcrMockAdapterState
$candidateVm = @($mock.vms | Where-Object { [string]$_.name -eq 'cleanroom-test' })[0]
$candidateVm | Add-Member `
    -NotePropertyName ownershipProjectionUnavailable `
    -NotePropertyValue $true `
    -Force
Write-HcrMockAdapterState $mock
$global:HcrMockOwnershipProjectionCallCount = 0
$storageUnverifiedList = Invoke-TestTool 'list_vms' ([pscustomobject]@{ managedOnly = $false })
Assert-True $storageUnverifiedList.ok 'Storage-unverified listing did not degrade safely.'
Assert-True (-not [bool]$storageUnverifiedList.changed) `
    'Storage-unverified listing reported changed=true.'
$storageUnverifiedSummary = @($storageUnverifiedList.data.vms | Where-Object {
    [string]$_.name -eq 'cleanroom-test'
})
Assert-Equal $storageUnverifiedSummary.Count 1 `
    'managedOnly=false dropped the storage-unverified summary.'
Assert-Equal ([string]$storageUnverifiedSummary[0].ownershipStatus) 'OWNERSHIP_UNVERIFIED' `
    'An incomplete ownership projection claimed verified ownership.'
$ownershipProjectionWarning =
    'OWNERSHIP_UNVERIFIED: A managed ownership candidate could not be verified at stage ownershipProjection.'
Assert-Equal @($storageUnverifiedList.warnings | Where-Object {
    [string]$_ -eq $ownershipProjectionWarning
}).Count 1 'Storage-unverified listing did not emit exactly one bounded warning.'
$warningJson = ConvertTo-HcrJson $storageUnverifiedList.warnings 10
Assert-True ($warningJson -notmatch [regex]::Escape('cleanroom-test')) `
    'The ownership projection warning exposed a VM name.'
Assert-True ($warningJson -notmatch [regex]::Escape($vmRoot)) `
    'The ownership projection warning exposed a host path.'
$storageUnverifiedManagedOnly = Invoke-TestTool 'list_vms' ([pscustomobject]@{})
Assert-True (@($storageUnverifiedManagedOnly.data.vms | Where-Object {
    [string]$_.name -eq 'cleanroom-test'
}).Count -eq 0) 'managedOnly=true retained a storage-unverified VM.'

$mock = Read-HcrMockAdapterState
$candidateVm = @($mock.vms | Where-Object { [string]$_.name -eq 'cleanroom-test' })[0]
$candidateVm.PSObject.Properties.Remove('ownershipProjectionUnavailable')
$mock.vms = @($mock.vms | Where-Object { [string]$_.name -ne $unmanagedUnicodeName })
Write-HcrMockAdapterState $mock
$candidateVm = @($mock.vms | Where-Object { [string]$_.name -eq 'cleanroom-test' })[0]
$minimalOwnershipProjection = Invoke-HcrMockAdapter `
    'GetVmOwnershipProjection' `
    ([pscustomobject][ordered]@{
        expectedVmId = [string]$candidateVm.id
        expectedVmName = [string]$candidateVm.name
        recordedBaseVhdxPath = [string]$candidateVm.vhdxPath
    })
Assert-True ([bool]$minimalOwnershipProjection.complete) `
    'The matching ownership projection was unavailable.'
Assert-Equal ([string]$minimalOwnershipProjection.vm.notes) ([string]$candidateVm.notes) `
    'The ownership projection did not re-read the live Notes marker.'
foreach ($deepOwnershipField in @(
    'networkAdapters',
    'checkpoints',
    'firmware',
    'security',
    'processorCount',
    'memory'
)) {
    Assert-True (@(Get-HcrPropertyNames $minimalOwnershipProjection.vm) -notcontains $deepOwnershipField) `
        "Ownership projection exposed the deep field '$deepOwnershipField'."
}
$mismatchedOwnershipProjection = Invoke-HcrMockAdapter `
    'GetVmOwnershipProjection' `
    ([pscustomobject][ordered]@{
        expectedVmId = [string]$candidateVm.id
        expectedVmName = 'replacement-name'
        recordedBaseVhdxPath = [string]$candidateVm.vhdxPath
    })
Assert-True (-not [bool]$mismatchedOwnershipProjection.complete) `
    'Ownership projection accepted an expected VM-name mismatch.'
Assert-Equal ([string]$mismatchedOwnershipProjection.stage) 'ownershipProjection' `
    'Ownership projection mismatch lost its bounded stage.'
$staleCandidateSummary = ConvertTo-HcrVmListSummary $candidateVm
$mock = Read-HcrMockAdapterState
$liveCandidateVm = @($mock.vms | Where-Object { [string]$_.id -eq [string]$candidateVm.id })[0]
$liveCandidateVm.notes = 'marker-changed-after-inventory'
Write-HcrMockAdapterState $mock
$global:HcrMockOwnershipProjectionCallCount = 0
$staleMarkerOwnership = Get-HcrListVmOwnershipStatus $staleCandidateSummary
Assert-Equal $global:HcrMockOwnershipProjectionCallCount 1 `
    'The stale-marker TOCTOU test did not enter the rebound ownership projection.'
Assert-True (-not [bool]$staleMarkerOwnership.verified) `
    'A changed live Notes marker retained verified ownership.'
Assert-Equal ([string]$staleMarkerOwnership.status) 'OWNERSHIP_UNVERIFIED' `
    'A changed live Notes marker did not fail closed.'
Assert-True (-not [bool]$staleMarkerOwnership.ownershipProjectionUnavailable) `
    'A complete live projection with a changed marker emitted an unavailable-storage warning.'
$mock = Read-HcrMockAdapterState
$liveCandidateVm = @($mock.vms | Where-Object { [string]$_.id -eq [string]$candidateVm.id })[0]
$liveCandidateVm.notes = [string]$candidateVm.notes
Write-HcrMockAdapterState $mock
Remove-Variable -Name HcrMockOwnershipProjectionCallCount -Scope Global -ErrorAction SilentlyContinue

$mock = Read-HcrMockAdapterState
$mock | Add-Member -NotePropertyName listVmFailureStage -NotePropertyValue 'vmInventory' -Force
Write-HcrMockAdapterState $mock
$inventoryFailure = Invoke-TestTool 'list_vms' ([pscustomobject]@{ managedOnly = $false })
Assert-ErrorCode $inventoryFailure 'HYPERV_UNAVAILABLE' `
    'VM provider failure did not use HYPERV_UNAVAILABLE.'
Assert-True (-not [bool]$inventoryFailure.changed) 'VM provider failure reported changed=true.'
Assert-Equal ([string]$inventoryFailure.error.details.stage) 'vmInventory' `
    'VM provider failure did not identify vmInventory.'
Assert-Equal @(Get-HcrPropertyNames $inventoryFailure.error.details).Count 1 `
    'VM provider failure details are not bounded to the stage.'
$mock = Read-HcrMockAdapterState
$mock.listVmFailureStage = 'vmSummaryProjection'
Write-HcrMockAdapterState $mock
$summaryFailure = Invoke-TestTool 'list_vms' ([pscustomobject]@{ managedOnly = $false })
Assert-ErrorCode $summaryFailure 'INTERNAL_ERROR' `
    'Required VM summary failure did not use INTERNAL_ERROR.'
Assert-True (-not [bool]$summaryFailure.changed) 'VM summary failure reported changed=true.'
Assert-Equal ([string]$summaryFailure.error.details.stage) 'vmSummaryProjection' `
    'VM summary failure did not identify vmSummaryProjection.'
Assert-Equal @(Get-HcrPropertyNames $summaryFailure.error.details).Count 1 `
    'VM summary failure details are not bounded to the stage.'
$failureJson = ConvertTo-HcrJson @($inventoryFailure.error, $summaryFailure.error) 20
Assert-True ($failureJson -notmatch [regex]::Escape($vmRoot)) `
    'A staged list failure exposed a host path.'
Assert-True ($failureJson -notmatch 'S-1-5-') `
    'A staged list failure exposed a SID.'
$mock = Read-HcrMockAdapterState
$mock.PSObject.Properties.Remove('listVmFailureStage')
Write-HcrMockAdapterState $mock

$savedOwnershipRecord = Read-HcrJsonFile $ownershipRecordPath
[IO.File]::WriteAllText(
    $ownershipRecordPath,
    '{invalid ownership json',
    (New-Object System.Text.UTF8Encoding($false))
)
$stateIntegrityList = Invoke-TestTool 'list_vms' ([pscustomobject]@{ managedOnly = $false })
Assert-ErrorCode $stateIntegrityList 'STATE_INTEGRITY_ERROR' `
    'A corrupt keyed ownership record was swallowed during list_vms.'
Assert-True (-not [bool]$stateIntegrityList.changed) `
    'A state-integrity list failure reported changed=true.'
Write-TestJson $ownershipRecordPath $savedOwnershipRecord
Invoke-WithCurrentUserDeniedAccess `
    $ownershipRecordPath `
    ([Security.AccessControl.FileSystemRights]::ReadData) `
    {
        $stateAccessList = Invoke-TestTool 'list_vms' ([pscustomobject]@{ managedOnly = $false })
        Assert-ErrorCode $stateAccessList 'STATE_ROOT_ACCESS_DENIED' `
            'Ownership record access denial was swallowed during list_vms.'
        Assert-True (-not [bool]$stateAccessList.changed) `
            'A state-access list failure reported changed=true.'
    }

$mock = Read-HcrMockAdapterState
$savedMockVms = @($mock.vms | ForEach-Object { Copy-HcrObject $_ })
$mock.vms = @()
Write-HcrMockAdapterState $mock
$emptyAllVmList = Invoke-TestTool 'list_vms' ([pscustomobject]@{ managedOnly = $false })
Assert-True $emptyAllVmList.ok 'The empty all-VM inventory failed.'
Assert-True (-not [bool]$emptyAllVmList.changed) 'The empty all-VM inventory reported changed=true.'
Assert-Equal @($emptyAllVmList.data.vms).Count 0 `
    'managedOnly=false did not preserve an empty VM inventory.'
$emptyManagedVmList = Invoke-TestTool 'list_vms' ([pscustomobject]@{})
Assert-True $emptyManagedVmList.ok 'The empty managed VM inventory failed.'
Assert-Equal @($emptyManagedVmList.data.vms).Count 0 `
    'managedOnly=true did not preserve an empty VM inventory.'
$mock = Read-HcrMockAdapterState
$mock.vms = @($savedMockVms | ForEach-Object { Copy-HcrObject $_ })
Write-HcrMockAdapterState $mock

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
Assert-True ($initializerSource -match
    'Initialize-HcrWindowsPowerShellCredentialEnvironment') `
    'Credential initialization does not normalize its Windows PowerShell module environment.'
$securityBootstrapOffset = $initializerSource.LastIndexOf(
    'Initialize-HcrWindowsPowerShellCredentialEnvironment',
    [StringComparison]::Ordinal
)
$getVmOffset = $initializerSource.IndexOf('Get-VM', [StringComparison]::Ordinal)
$getCredentialOffset = $initializerSource.IndexOf(
    '$administratorCredential = Get-Credential',
    [StringComparison]::Ordinal
)
Assert-True ($securityBootstrapOffset -ge 0 -and
    $securityBootstrapOffset -lt $getVmOffset -and
    $securityBootstrapOffset -lt $getCredentialOffset) `
    'Credential module bootstrap does not precede module autoload and credential prompts.'
Assert-True ($initializerSource -match 'Get-HcrCurrentWindowsTokenEvidence') `
    'Credential initialization does not use the shared native token probe.'
Assert-True ($initializerSource -notmatch 'S-1-16-') `
    'Credential initialization still infers integrity from token groups.'
Assert-True ($initializerSource -match "'isElevated' \`$false") `
    'Credential initialization does not require an elevated administrator token.'
Assert-True ($initializerSource -match "'isElevated' \`$true") `
    'Credential initialization does not reject an elevated test-user token.'
Assert-True ($initializerSource -match 'Publish-HcrCredentialDirectory') `
    'Credential initialization does not use the exact-destination publication helper.'
Assert-True ($initializerSource -notmatch '(?m)^\s*Move-Item\b') `
    'Credential initialization still uses container-merging Move-Item publication.'
$environmentFunctions = @($initializerAst.FindAll({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Initialize-HcrWindowsPowerShellCredentialEnvironment'
}, $true))
Assert-Equal $environmentFunctions.Count 1 `
    'Credential module environment initializer is missing or duplicated.'
$environmentFunctionSource = $environmentFunctions[0].Extent.Text
Assert-True ($environmentFunctionSource -match '\$PSHOME' -and
    $environmentFunctionSource -match "'Microsoft\.PowerShell\.Security'" -and
    $environmentFunctionSource -match "'Microsoft\.PowerShell\.Security\.psd1'") `
    'Credential module bootstrap does not select the in-box manifest under PSHOME.'
Assert-True ($environmentFunctionSource -match "'WindowsPowerShell', 'Modules'") `
    'Credential module bootstrap does not reconstruct Windows PowerShell module paths.'
Assert-True ($environmentFunctionSource -match 'PSVersion\.Minor -ne 1') `
    'Credential module bootstrap does not require exact Windows PowerShell 5.1.'
Assert-True ($environmentFunctionSource -match '(?m)^\s*\$env:PSModulePath\s*=') `
    'Credential module bootstrap does not replace the contaminated child-process module path.'
Assert-True ($environmentFunctionSource -notmatch 'SetEnvironmentVariable') `
    'Credential module bootstrap can write persistent environment state.'

$foreignModuleRoot = Join-Path $testRoot 'foreign-powershell-modules'
$foreignSecurityRoot = Join-Path $foreignModuleRoot `
    'Microsoft.PowerShell.Security\99.0.0.0'
[void](New-Item -ItemType Directory -Path $foreignSecurityRoot -Force)
$foreignSecurityModule = Join-Path $foreignSecurityRoot 'Microsoft.PowerShell.Security.psm1'
$foreignSecurityManifest = Join-Path $foreignSecurityRoot 'Microsoft.PowerShell.Security.psd1'
[IO.File]::WriteAllText(
    $foreignSecurityModule,
    "# Deliberately empty foreign higher-version candidate.`n",
    (New-Object System.Text.UTF8Encoding($false))
)
[IO.File]::WriteAllText(
    $foreignSecurityManifest,
    (@"
@{
    RootModule = 'Microsoft.PowerShell.Security.psm1'
    ModuleVersion = '99.0.0.0'
    GUID = '9d5437bc-dd25-47aa-8870-c47a1f6c327b'
    FunctionsToExport = @()
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
"@),
    (New-Object System.Text.UTF8Encoding($false))
)
$securityBootstrapChild = @"
`$ErrorActionPreference = 'Stop'
$environmentFunctionSource
`$userPathBefore = [Environment]::GetEnvironmentVariable(
    'PSModulePath',
    [EnvironmentVariableTarget]::User
)
`$machinePathBefore = [Environment]::GetEnvironmentVariable(
    'PSModulePath',
    [EnvironmentVariableTarget]::Machine
)
`$foreignVisible = @(
    Get-Module -ListAvailable Microsoft.PowerShell.Security |
        Where-Object { `$_.Version -eq [version]'99.0.0.0' }
).Count -eq 1
Initialize-HcrWindowsPowerShellCredentialEnvironment
`$command = Get-Command Get-Credential -CommandType Cmdlet -ErrorAction Stop
`$module = Get-Module Microsoft.PowerShell.Security |
    Where-Object { `$_.Path -ieq `$command.Module.Path } |
    Select-Object -First 1
[pscustomobject]@{
    foreignVisible = `$foreignVisible
    moduleVersion = [string]`$module.Version
    modulePath = [string]`$module.Path
    commandModulePath = [string]`$command.Module.Path
    foreignPathRemoved = (`$env:PSModulePath -split [regex]::Escape(
        [IO.Path]::PathSeparator
    )) -inotcontains '$($foreignModuleRoot.Replace("'", "''"))'
    psHomeModulesPresent = (`$env:PSModulePath -split [regex]::Escape(
        [IO.Path]::PathSeparator
    )) -icontains (Join-Path `$PSHOME 'Modules')
    userPathUnchanged = [string]::Equals(
        [string]`$userPathBefore,
        [string][Environment]::GetEnvironmentVariable(
            'PSModulePath',
            [EnvironmentVariableTarget]::User
        ),
        [StringComparison]::Ordinal
    )
    machinePathUnchanged = [string]::Equals(
        [string]`$machinePathBefore,
        [string][Environment]::GetEnvironmentVariable(
            'PSModulePath',
            [EnvironmentVariableTarget]::Machine
        ),
        [StringComparison]::Ordinal
    )
} | ConvertTo-Json -Compress
"@
$securityBootstrapEncoded = [Convert]::ToBase64String(
    [Text.Encoding]::Unicode.GetBytes($securityBootstrapChild)
)
$windowsPowerShell = Join-Path $env:SystemRoot `
    'System32\WindowsPowerShell\v1.0\powershell.exe'
$securityBootstrapInfo = New-Object Diagnostics.ProcessStartInfo
$securityBootstrapInfo.FileName = $windowsPowerShell
$securityBootstrapInfo.Arguments =
    "-NoLogo -NoProfile -NonInteractive -EncodedCommand $securityBootstrapEncoded"
$securityBootstrapInfo.UseShellExecute = $false
$securityBootstrapInfo.RedirectStandardOutput = $true
$securityBootstrapInfo.RedirectStandardError = $true
$securityBootstrapInfo.CreateNoWindow = $true
$securityBootstrapInfo.EnvironmentVariables['PSModulePath'] =
    $foreignModuleRoot + [IO.Path]::PathSeparator + [string]$env:PSModulePath
$securityBootstrapProcess = New-Object Diagnostics.Process
$securityBootstrapProcess.StartInfo = $securityBootstrapInfo
[void]$securityBootstrapProcess.Start()
$securityBootstrapExited = $securityBootstrapProcess.WaitForExit(15000)
if (-not $securityBootstrapExited) {
    $securityBootstrapProcess.Kill()
    throw 'Contaminated Windows PowerShell Security bootstrap did not exit.'
}
$securityBootstrapStdout = $securityBootstrapProcess.StandardOutput.ReadToEnd()
$securityBootstrapStderr = $securityBootstrapProcess.StandardError.ReadToEnd()
Assert-True $securityBootstrapExited `
    'Contaminated Windows PowerShell Security bootstrap did not exit cleanly.'
Assert-Equal $securityBootstrapProcess.ExitCode 0 `
    "Contaminated Windows PowerShell Security bootstrap failed: $securityBootstrapStderr"
$securityBootstrapJson = @($securityBootstrapStdout -split "`r?`n" | Where-Object {
    $_ -match '^\{.*\}$'
})
Assert-Equal $securityBootstrapJson.Count 1 `
    'Contaminated Windows PowerShell Security bootstrap returned unexpected output.'
$securityBootstrapResult = $securityBootstrapJson[0] | ConvertFrom-Json
Assert-True ([bool]$securityBootstrapResult.foreignVisible) `
    'Credential Security regression did not expose a foreign higher-version module candidate.'
Assert-Equal ([string]$securityBootstrapResult.moduleVersion) '3.0.0.0' `
    'Credential Security bootstrap selected a foreign module version.'
$expectedSecurityManifest = Join-Path `
    (Split-Path -Parent $windowsPowerShell) `
    'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1'
Assert-True ([string]::Equals(
    [IO.Path]::GetFullPath([string]$securityBootstrapResult.modulePath),
    [IO.Path]::GetFullPath($expectedSecurityManifest),
    [StringComparison]::OrdinalIgnoreCase
)) 'Credential Security bootstrap loaded a module outside Windows PowerShell PSHOME.'
Assert-True ([string]::Equals(
    [IO.Path]::GetFullPath([string]$securityBootstrapResult.commandModulePath),
    [IO.Path]::GetFullPath($expectedSecurityManifest),
    [StringComparison]::OrdinalIgnoreCase
)) 'Get-Credential did not bind to the in-box Windows PowerShell Security module.'
Assert-True ([bool]$securityBootstrapResult.foreignPathRemoved) `
    'Credential module bootstrap retained a foreign PowerShell module path.'
Assert-True ([bool]$securityBootstrapResult.psHomeModulesPresent) `
    'Credential module bootstrap omitted the Windows PowerShell PSHOME module path.'
Assert-True ([bool]$securityBootstrapResult.userPathUnchanged) `
    'Credential module bootstrap changed the user-scoped module path.'
Assert-True ([bool]$securityBootstrapResult.machinePathUnchanged) `
    'Credential module bootstrap changed the machine-scoped module path.'
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
Assert-True ($adapterSource -match 'Get-HcrCurrentWindowsTokenEvidence') `
    'The production adapter does not use the shared native token probe.'
Assert-True ($adapterSource -notmatch 'S-1-16-') `
    'The production adapter still infers integrity from token groups.'
Assert-True ($adapterSource -notmatch 'isElevated = \$true') `
    'The production adapter still hardcodes orchestration elevation.'
Assert-True ($adapterSource -match
    "isElevated = \[bool\]\(Get-HcrPropertyValue \`$administratorProbe 'isElevated'\)") `
    'The production adapter does not project the observed orchestration elevation.'
$deepGetterVm = [pscustomobject][ordered]@{
    Id = [Guid]::NewGuid()
    Name = ([string][char]0x6DF1 + [char]0x5EA6 + '-getter-trap')
    State = 'Off'
    Generation = 2
    Notes = ''
    Path = Join-Path $vmRoot 'deep-getter-trap'
}
$deepGetterVm | Add-Member -MemberType ScriptProperty -Name NetworkAdapters -Value {
    throw 'The list projection touched a deep network getter.'
}
$deepGetterVm | Add-Member -MemberType ScriptProperty -Name Checkpoints -Value {
    throw 'The list projection touched a deep checkpoint getter.'
}
$deepGetterSummary = ConvertTo-HcrVmListSummary $deepGetterVm
Assert-Equal ([string]$deepGetterSummary.name) ([string]$deepGetterVm.Name) `
    'The minimal list projection did not preserve a Unicode VM name.'
Assert-Equal @(ConvertTo-HcrVmListSummaries @()).Count 0 `
    'The minimal list projection did not preserve an empty inventory.'
$multiSummary = @(ConvertTo-HcrVmListSummaries @(
    $deepGetterVm,
    ([pscustomobject][ordered]@{
        Id = [Guid]::NewGuid()
        Name = 'second-summary'
        State = 'Running'
        Generation = 2
        Notes = ''
        Path = Join-Path $vmRoot 'second-summary'
    })
))
Assert-Equal $multiSummary.Count 2 'The minimal list projection lost a multi-VM inventory.'

$realAdapterOffset = $adapterSource.IndexOf('function Invoke-HcrRealAdapter')
Assert-True ($realAdapterOffset -ge 0) 'The production adapter function could not be located.'
$realAdapterSource = $adapterSource.Substring($realAdapterOffset)
$realListCase = [regex]::Match(
    $realAdapterSource,
    "(?s)'ListVms'\s*\{(?<body>.*?)\r?\n\s*\}\r?\n\s*'GetVmOwnershipProjection'"
)
Assert-True $realListCase.Success 'The production ListVms adapter case could not be isolated.'
$realListBody = $realListCase.Groups['body'].Value
Assert-True ($realListBody -match 'ConvertTo-HcrVmListSummaries') `
    'Production ListVms does not use the minimal list projection.'
foreach ($forbiddenListSeam in @(
    'ConvertTo-HcrRealVmSnapshot',
    'Get-VMHardDiskDrive',
    'Get-VMNetworkAdapter',
    'Get-VMSnapshot',
    'Get-VMFirmware',
    'Get-VMSecurity',
    'Get-VHD'
)) {
    Assert-True ($realListBody -notmatch [regex]::Escape($forbiddenListSeam)) `
        "Production ListVms retained the deep seam '$forbiddenListSeam'."
}
$summaryProjectionSource = [regex]::Match(
    $adapterSource,
    '(?s)function ConvertTo-HcrVmListSummary\s*\{(?<body>.*?)\r?\n\}\r?\n\r?\nfunction ConvertTo-HcrVmListSummaries'
)
Assert-True $summaryProjectionSource.Success 'The minimal VM summary projection could not be isolated.'
foreach ($forbiddenSummaryField in @(
    'NetworkAdapter',
    'Switch',
    'Checkpoint',
    'Firmware',
    'Security',
    'HardDisk',
    'Get-VHD'
)) {
    Assert-True ($summaryProjectionSource.Groups['body'].Value -notmatch $forbiddenSummaryField) `
        "The minimal VM summary reads the deep field '$forbiddenSummaryField'."
}
$ownershipProjectionSource = [regex]::Match(
    $adapterSource,
    '(?s)function Get-HcrRealVmOwnershipProjection\s*\{(?<body>.*?)\r?\n\}\r?\n\r?\nfunction ConvertTo-HcrRealVmSnapshot'
)
Assert-True $ownershipProjectionSource.Success `
    'The production ownership projection could not be isolated.'
$ownershipProjectionBody = $ownershipProjectionSource.Groups['body'].Value
foreach ($requiredOwnershipSeam in @(
    'expectedVmId',
    'expectedVmName',
    'Get-VM -Id $parsedVmId',
    'notes = [string]$vm.Notes',
    'Get-VMHardDiskDrive',
    'ownershipProjection'
)) {
    Assert-True ($ownershipProjectionBody -match [regex]::Escape($requiredOwnershipSeam)) `
        "The production ownership projection is missing '$requiredOwnershipSeam'."
}
foreach ($forbiddenOwnershipSeam in @(
    'Get-VMNetworkAdapter',
    'Get-VMSnapshot',
    'Get-VMFirmware',
    'Get-VMSecurity'
)) {
    Assert-True ($ownershipProjectionBody -notmatch [regex]::Escape($forbiddenOwnershipSeam)) `
        "The ownership projection retained the deep seam '$forbiddenOwnershipSeam'."
}
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
Assert-True ($adapterSource -match
    '(?s)\$createdVm = New-VM.*?Set-VM -VM \$createdVm -AutomaticCheckpointsEnabled \$false.*?\$preOwnershipReadback = Get-VM.*?AutomaticCheckpointsEnabled.*?Set-VM -VM \$createdVm -Notes') `
    'Production VM creation does not verify automatic checkpoints as disabled before publishing ownership.'
Assert-True ($adapterSource -match
    '(?s)Get-VM -Id \$createdVm\.Id.*?AutomaticCheckpointsEnabled.*?ConvertTo-HcrRealVmSnapshot') `
    'Production VM creation does not read back automatic-checkpoint disablement before returning.'
foreach ($vhdChainSeam in @(
    'Get-HcrRealVhdChainSnapshot',
    'The VHD chain contains a cycle.',
    'The VHD chain exceeded the bounded depth.',
    'Get-VHD -Path $normalizedPath -ErrorAction Stop',
    'vhdxChainFingerprint',
    'baseVhdxPath'
)) {
    Assert-True ($adapterSource -match [regex]::Escape($vhdChainSeam)) `
        "The production differencing-chain identity seam is missing: $vhdChainSeam."
}
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
Assert-True ($workerSource -notmatch 'S-1-16-') `
    'The fixed guest worker still infers integrity from token groups.'
foreach ($requiredWorkerTokenSeam in @(
    'GetTokenInformation',
    'TokenIntegrityLevel',
    'TokenElevation',
    'TokenElevationType',
    'ErrorInsufficientBuffer = 122',
    'MaximumTokenInformationLength = 4096',
    'SeGroupIntegrity = 0x00000020',
    'IsValidSid',
    'GetLengthSid',
    'GetSidIdentifierAuthority',
    'ClassifyTokenIntegrityRid',
    'ValidateTokenElevationConsistency',
    'ReadTokenIntegrityRid',
    'GUEST_TOKEN_QUERY_FAILED'
)) {
    Assert-True ($workerSource -match [regex]::Escape($requiredWorkerTokenSeam)) `
        "The fixed guest worker is missing the native token seam '$requiredWorkerTokenSeam'."
}
$workerNativeSourceMatch = [regex]::Match(
    $workerSource,
    "(?s)Add-Type -TypeDefinition @'\r?\n(?<source>.*?)\r?\n'@ -ErrorAction Stop"
)
Assert-True $workerNativeSourceMatch.Success `
    'The fixed guest worker native source could not be isolated.'
if ($null -eq ('Hcr.WorkerProcessHandle' -as [type])) {
    Add-Type -TypeDefinition $workerNativeSourceMatch.Groups['source'].Value -ErrorAction Stop
}
foreach ($integrityCase in @(
    @{ rid = [uint32]0x00001000; label = 'low' }
    @{ rid = [uint32]0x00002000; label = 'medium' }
    @{ rid = [uint32]0x00002100; label = 'mediumPlus' }
    @{ rid = [uint32]0x00003000; label = 'high' }
    @{ rid = [uint32]0x00004000; label = 'system' }
)) {
    Assert-Equal `
        ([Hcr.WorkerProcessHandle]::ClassifyTokenIntegrityRid($integrityCase.rid)) `
        $integrityCase.label `
        'The worker classified a recognized integrity RID incorrectly.'
}
foreach ($invalidIntegrityRid in @(
    [uint32]0,
    [uint32]0x00001001,
    [uint32]0x00002010,
    [uint32]0x000020ff,
    [uint32]0x00002101,
    [uint32]0x00003001,
    [uint32]0x00004001,
    [uint32]0x00005000
)) {
    Assert-Throws {
        [void][Hcr.WorkerProcessHandle]::ClassifyTokenIntegrityRid($invalidIntegrityRid)
    } 'The worker accepted a non-exact integrity RID.'
}
foreach ($acceptedElevation in @(
    @{ type = 1; elevated = $false }
    @{ type = 1; elevated = $true }
    @{ type = 2; elevated = $true }
    @{ type = 3; elevated = $false }
)) {
    [Hcr.WorkerProcessHandle]::ValidateTokenElevationConsistency(
        $acceptedElevation.type,
        $acceptedElevation.elevated
    )
    Assert-True $true 'The worker rejected consistent elevation evidence.'
}
foreach ($rejectedElevation in @(
    @{ type = 0; elevated = $false }
    @{ type = 2; elevated = $false }
    @{ type = 3; elevated = $true }
    @{ type = 4; elevated = $true }
)) {
    Assert-Throws {
        [Hcr.WorkerProcessHandle]::ValidateTokenElevationConsistency(
            $rejectedElevation.type,
            $rejectedElevation.elevated
        )
    } 'The worker accepted inconsistent elevation evidence.'
}
foreach ($invalidHandleCall in @(
    { [void][Hcr.WorkerProcessHandle]::GetTokenIntegrityRid([IntPtr]::Zero) }
    { [void][Hcr.WorkerProcessHandle]::GetTokenIsElevated([IntPtr]::Zero) }
    { [void][Hcr.WorkerProcessHandle]::GetTokenElevationType([IntPtr]::Zero) }
)) {
    Assert-Throws $invalidHandleCall 'The worker accepted an invalid token handle.'
}
$nativeSidBuffer = [Runtime.InteropServices.Marshal]::AllocHGlobal($mediumIntegritySidBytes.Length)
$nativeLabelBuffer = [Runtime.InteropServices.Marshal]::AllocHGlobal(64)
try {
    [Runtime.InteropServices.Marshal]::Copy(
        $mediumIntegritySidBytes,
        0,
        $nativeSidBuffer,
        $mediumIntegritySidBytes.Length
    )
    [Runtime.InteropServices.Marshal]::WriteIntPtr($nativeLabelBuffer, [IntPtr]::Zero)
    [Runtime.InteropServices.Marshal]::WriteInt32($nativeLabelBuffer, [IntPtr]::Size, 0x20)
    Assert-Throws {
        [void][Hcr.WorkerProcessHandle]::ReadTokenIntegrityRid($nativeLabelBuffer, 64)
    } 'The worker accepted an absent mandatory-label SID.'
    [Runtime.InteropServices.Marshal]::WriteIntPtr($nativeLabelBuffer, $nativeSidBuffer)
    Assert-Throws {
        [void][Hcr.WorkerProcessHandle]::ReadTokenIntegrityRid($nativeLabelBuffer, 64)
    } 'The worker accepted a SID outside the returned buffer.'
    $embeddedSidPointer = [IntPtr]::Add($nativeLabelBuffer, 16)
    [Runtime.InteropServices.Marshal]::Copy(
        $wrongAuthoritySidBytes,
        0,
        $embeddedSidPointer,
        $wrongAuthoritySidBytes.Length
    )
    [Runtime.InteropServices.Marshal]::WriteIntPtr($nativeLabelBuffer, $embeddedSidPointer)
    Assert-Throws {
        [void][Hcr.WorkerProcessHandle]::ReadTokenIntegrityRid($nativeLabelBuffer, 64)
    } 'The worker accepted a non-mandatory SID authority.'
    [Runtime.InteropServices.Marshal]::Copy(
        $multipleSubauthoritySidBytes,
        0,
        $embeddedSidPointer,
        $multipleSubauthoritySidBytes.Length
    )
    Assert-Throws {
        [void][Hcr.WorkerProcessHandle]::ReadTokenIntegrityRid($nativeLabelBuffer, 64)
    } 'The worker accepted multiple mandatory-label subauthorities.'
    [Runtime.InteropServices.Marshal]::Copy(
        $mediumIntegritySidBytes,
        0,
        $embeddedSidPointer,
        $mediumIntegritySidBytes.Length
    )
    [Runtime.InteropServices.Marshal]::WriteInt32($nativeLabelBuffer, [IntPtr]::Size, 0)
    Assert-Throws {
        [void][Hcr.WorkerProcessHandle]::ReadTokenIntegrityRid($nativeLabelBuffer, 64)
    } 'The worker accepted a label without SE_GROUP_INTEGRITY.'
    [Runtime.InteropServices.Marshal]::WriteInt32($nativeLabelBuffer, [IntPtr]::Size, 0x20)
    Assert-Equal `
        ([Hcr.WorkerProcessHandle]::ReadTokenIntegrityRid($nativeLabelBuffer, 64)) `
        ([uint32]0x00002000) `
        'The worker did not read a valid exact-medium label.'
}
finally {
    [Runtime.InteropServices.Marshal]::FreeHGlobal($nativeLabelBuffer)
    [Runtime.InteropServices.Marshal]::FreeHGlobal($nativeSidBuffer)
}
$workerTokenFunction = @($workerAst.FindAll({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Get-WorkerTokenEvidence'
}, $true))
Assert-Equal $workerTokenFunction.Count 1 `
    'The fixed guest worker token-evidence function is missing or duplicated.'
Invoke-Expression $workerTokenFunction[0].Extent.Text
$workerTokenEvidence = Get-WorkerTokenEvidence
Assert-Equal ([string]$workerTokenEvidence.sid) ([string]$currentTokenEvidence.sid) `
    'The worker token probe changed the current SID.'
Assert-Equal ([string]$workerTokenEvidence.tokenIntegrity) `
    ([string]$currentTokenEvidence.tokenIntegrity) `
    'The worker token probe disagrees with the shared integrity probe.'
Assert-Equal ([bool]$workerTokenEvidence.isElevated) ([bool]$currentTokenEvidence.isElevated) `
    'The worker token probe disagrees with the shared elevation probe.'
Assert-True ($workerSource -match
    "(?s)\`$token = Get-WorkerTokenEvidence.*?\`$Mode -ne 'InspectGuest'.*?GUEST_TEST_USER_PRIVILEGE_INVALID") `
    'Lifecycle modes do not fail closed on an invalid observed token.'
Assert-True ($workerSource -match
    "(?s)\`$data = if \(\`$Mode -eq 'InspectGuest'\).*?Invoke-WorkerInspectGuest \`$token") `
    'InspectGuest no longer reports the observed token independently of lifecycle acceptance.'
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
$serverInfo.EnvironmentVariables.Remove('COMPUTERNAME')
Assert-True (-not $serverInfo.EnvironmentVariables.ContainsKey('COMPUTERNAME')) `
    'The missing-COMPUTERNAME MCP protocol regression did not remove the inherited variable.'
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
    '{"jsonrpc":"2.0","id":36,"method":"tools/list","params":null}',
    '{"jsonrpc":"2.0","id":41,"method":"tools/list","params":{"cursor":1}}',
    '{"jsonrpc":"2.0","id":42,"method":"tools/list","params":{"_meta":"scalar"}}'
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
$server.StandardInput.WriteLine('{"jsonrpc":"2.0","id":43,"method":"tools/list","params":{"_meta":{"progressToken":"catalog-only"},"cursor":"opaque"}}')
$modernListResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-Equal (@($modernListResponse.result.tools).Count) 20 `
    'tools/list rejected MCP-standard _meta or cursor parameters.'

foreach ($invalidToolCallMessage in @(
    '{"jsonrpc":"2.0","id":38,"method":"tools/call","params":"scalar"}',
    '{"jsonrpc":"2.0","id":39,"method":"tools/call","params":{"name":"inspect_host","arguments":{},"unexpected":true}}',
    '{"jsonrpc":"2.0","id":40,"method":"tools/call","params":{"name":"inspect_host","arguments":"scalar"}}',
    '{"jsonrpc":"2.0","id":44,"method":"tools/call","params":{"name":"inspect_host","arguments":{},"_meta":"scalar"}}',
    '{"jsonrpc":"2.0","id":45,"method":"tools/call","params":{"name":"inspect_host","arguments":{},"_meta":[]}}',
    '{"jsonrpc":"2.0","id":46,"method":"tools/call","params":{"name":"inspect_host","arguments":{},"_meta":null}}'
)) {
    $server.StandardInput.WriteLine($invalidToolCallMessage)
    $invalidToolCallResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
    Assert-Equal $invalidToolCallResponse.error.code -32602 `
        'tools/call accepted scalar, unknown, or unstructured parameters or metadata.'
}
$server.StandardInput.WriteLine('{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"inspect_host","arguments":{}}}')
$inspectResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-True (-not $inspectResponse.result.isError) 'MCP inspect_host returned isError.'
$inspectEnvelope = $inspectResponse.result.content[0].text | ConvertFrom-Json
Assert-True $inspectEnvelope.ok 'MCP inspect_host envelope failed.'
Assert-Equal $inspectEnvelope.data.host.computerName 'MOCK-HOST' 'MCP returned wrong mock host.'
$server.StandardInput.WriteLine('{"jsonrpc":"2.0","id":47,"method":"tools/call","params":{"name":"inspect_host","arguments":{},"_meta":{"progressToken":"inspect-mock"}}}')
$inspectMetadataResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-True (-not $inspectMetadataResponse.result.isError) `
    'MCP inspect_host rejected object-shaped request metadata.'
$inspectMetadataEnvelope = $inspectMetadataResponse.result.content[0].text | ConvertFrom-Json
Assert-True ($inspectMetadataEnvelope.ok -and -not [bool]$inspectMetadataEnvelope.changed) `
    'MCP inspect_host request metadata changed tool behavior.'
$server.StandardInput.WriteLine('{"jsonrpc":"2.0","id":48,"method":"tools/call","params":{"name":"list_vms","arguments":{"managedOnly":false},"_meta":{"progressToken":"list-mock"}}}')
$listMetadataResponse = $server.StandardOutput.ReadLine() | ConvertFrom-Json
Assert-True (-not $listMetadataResponse.result.isError) `
    'MCP list_vms rejected object-shaped request metadata.'
$listMetadataEnvelope = $listMetadataResponse.result.content[0].text | ConvertFrom-Json
Assert-True ($listMetadataEnvelope.ok -and -not [bool]$listMetadataEnvelope.changed) `
    'MCP list_vms request metadata changed tool behavior.'
Assert-True (-not [bool]$listMetadataEnvelope.data.managedOnly) `
    'MCP list_vms request metadata leaked into or replaced tool arguments.'
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

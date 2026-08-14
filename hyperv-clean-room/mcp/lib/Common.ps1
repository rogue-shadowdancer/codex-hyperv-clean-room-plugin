Set-StrictMode -Version Latest

$script:HcrPluginVersion = '0.4.1'
$script:HcrSchemaVersion = 1
$script:HcrSchemaVersionV2 = 2
$script:HcrPlanLifetimeMinutes = 15
$script:HcrMockWarning = 'TEST_ONLY_MOCK_ADAPTER: no result in this operation proves real Hyper-V behavior.'
$script:HcrBroaderPrivilegeWarning = 'BROADER_PRIVILEGE_CONTEXT: MCP server is elevated; Hyper-V Administrators is the preferred least-privilege authorization mode.'
$script:HcrSupportedProtocolVersions = @(
    '2024-11-05',
    '2025-03-26',
    '2025-06-18',
    '2025-11-25'
)
$script:HcrToolNames = @(
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
    'record_manual_attestation',
    'plan_vm_power',
    'apply_vm_power',
    'plan_vm_network',
    'apply_vm_network'
)
$script:HcrActionStepTypes = @(
    'stageArtifact',
    'installPackage',
    'launchApplication',
    'stopApplication',
    'uninstallPackage',
    'writeSentinel',
    'wait'
)
$script:HcrAssertionStepTypes = @(
    'assertFile',
    'assertRegistry',
    'assertProcess',
    'assertModule',
    'assertShortcut',
    'assertPort',
    'assertSentinel'
)
$script:HcrCleanupStepTypes = @(
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
$script:HcrV2ActionStepTypes = @(
    'stageArtifact',
    'installPackage',
    'deployPortable',
    'launchApplication',
    'stopApplication',
    'uninstallPackage',
    'writeSentinel',
    'wait',
    'acquireWebDriver',
    'startUiSession',
    'stopUiSession',
    'uiClick',
    'uiSetText',
    'uiPressKey',
    'uiSelectOption',
    'uiUploadFixture',
    'captureUiScreenshot'
)
$script:HcrV2AssertionStepTypes = @(
    'assertFile',
    'assertRegistry',
    'assertProcess',
    'assertModule',
    'assertShortcut',
    'assertPort',
    'assertSentinel',
    'assertUiElement'
)
$script:HcrV2CleanupStepTypes = @(
    'stopApplication',
    'stopUiSession',
    'captureUiScreenshot',
    'wait',
    'assertFile',
    'assertRegistry',
    'assertProcess',
    'assertModule',
    'assertShortcut',
    'assertPort',
    'assertSentinel'
)
$script:HcrV2UiStepTypes = @(
    'acquireWebDriver',
    'startUiSession',
    'stopUiSession',
    'uiClick',
    'uiSetText',
    'uiPressKey',
    'uiSelectOption',
    'uiUploadFixture',
    'assertUiElement',
    'captureUiScreenshot'
)
$script:HcrUtf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-HcrCurrentWindowsTokenEvidence {
    try {
        if ($null -eq ('HcrTokenEvidenceNative' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct HcrSidAndAttributes
{
    public IntPtr Sid;
    public UInt32 Attributes;
}

[StructLayout(LayoutKind.Sequential)]
public struct HcrTokenMandatoryLabel
{
    public HcrSidAndAttributes Label;
}

public static class HcrTokenEvidenceNative
{
    private const Int32 ErrorInsufficientBuffer = 122;
    private const UInt32 MaximumTokenInformationLength = 4096;
    private const UInt32 SeGroupIntegrity = 0x00000020;
    private const Int32 TokenElevationType = 18;
    private const Int32 TokenElevation = 20;
    private const Int32 TokenIntegrityLevel = 25;

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetTokenInformation(
        IntPtr tokenHandle,
        Int32 tokenInformationClass,
        IntPtr tokenInformation,
        UInt32 tokenInformationLength,
        out UInt32 returnLength
    );

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsValidSid(IntPtr sid);

    [DllImport("advapi32.dll")]
    private static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);

    [DllImport("advapi32.dll")]
    private static extern IntPtr GetSidSubAuthority(IntPtr sid, UInt32 subAuthority);

    [DllImport("advapi32.dll")]
    private static extern IntPtr GetSidIdentifierAuthority(IntPtr sid);

    [DllImport("advapi32.dll")]
    private static extern UInt32 GetLengthSid(IntPtr sid);

    public static UInt32 GetIntegrityRid(IntPtr tokenHandle)
    {
        if (tokenHandle == IntPtr.Zero) {
            throw new InvalidOperationException("Token handle is invalid.");
        }

        UInt32 length = 0;
        Boolean sizingSucceeded = GetTokenInformation(
            tokenHandle,
            TokenIntegrityLevel,
            IntPtr.Zero,
            0,
            out length
        );
        Int32 sizingError = Marshal.GetLastWin32Error();
        UInt32 minimumLength = (UInt32)Marshal.SizeOf(typeof(HcrTokenMandatoryLabel));
        if (sizingSucceeded ||
            sizingError != ErrorInsufficientBuffer ||
            length < minimumLength ||
            length > MaximumTokenInformationLength) {
            throw new InvalidOperationException("Token integrity information is unavailable.");
        }

        UInt32 capacity = length;
        IntPtr buffer = Marshal.AllocHGlobal((Int32)capacity);
        try {
            if (!GetTokenInformation(
                    tokenHandle,
                    TokenIntegrityLevel,
                    buffer,
                    capacity,
                    out length
                ) || length < minimumLength || length > capacity) {
                throw new InvalidOperationException("Token integrity information is unavailable.");
            }
            return ReadIntegrityRid(buffer, length);
        }
        finally {
            Marshal.FreeHGlobal(buffer);
        }
    }

    public static UInt32 ReadIntegrityRid(IntPtr tokenInformation, UInt32 tokenInformationLength)
    {
        UInt32 minimumLength = (UInt32)Marshal.SizeOf(typeof(HcrTokenMandatoryLabel));
        if (tokenInformation == IntPtr.Zero ||
            tokenInformationLength < minimumLength ||
            tokenInformationLength > MaximumTokenInformationLength) {
            throw new InvalidOperationException("Token integrity information is invalid.");
        }
        HcrTokenMandatoryLabel label = (HcrTokenMandatoryLabel)Marshal.PtrToStructure(
            tokenInformation,
            typeof(HcrTokenMandatoryLabel)
        );
        if (label.Label.Sid == IntPtr.Zero ||
            (label.Label.Attributes & SeGroupIntegrity) == 0) {
            throw new InvalidOperationException("Token integrity information is invalid.");
        }
        UInt64 bufferStart = unchecked((UInt64)tokenInformation.ToInt64());
        UInt64 bufferEnd = bufferStart + tokenInformationLength;
        UInt64 sidStart = unchecked((UInt64)label.Label.Sid.ToInt64());
        if (bufferEnd < bufferStart ||
            sidStart < bufferStart ||
            sidStart > bufferEnd ||
            bufferEnd - sidStart < 8) {
            throw new InvalidOperationException("Token integrity information is invalid.");
        }
        Byte declaredCount = Marshal.ReadByte(label.Label.Sid, 1);
        if (declaredCount != 1 ||
            bufferEnd - sidStart < 12 ||
            !IsValidSid(label.Label.Sid)) {
            throw new InvalidOperationException("Token integrity information is invalid.");
        }
        UInt32 sidLength = GetLengthSid(label.Label.Sid);
        UInt64 sidEnd = sidStart + sidLength;
        if (sidLength != 12 || sidEnd < sidStart || sidEnd > bufferEnd) {
            throw new InvalidOperationException("Token integrity information is invalid.");
        }
        IntPtr countPointer = GetSidSubAuthorityCount(label.Label.Sid);
        if (countPointer == IntPtr.Zero) {
            throw new InvalidOperationException("Token integrity information is invalid.");
        }
        Byte count = Marshal.ReadByte(countPointer);
        if (count != 1) {
            throw new InvalidOperationException("Token integrity information is invalid.");
        }
        IntPtr authorityPointer = GetSidIdentifierAuthority(label.Label.Sid);
        if (authorityPointer == IntPtr.Zero ||
            Marshal.ReadByte(authorityPointer, 0) != 0 ||
            Marshal.ReadByte(authorityPointer, 1) != 0 ||
            Marshal.ReadByte(authorityPointer, 2) != 0 ||
            Marshal.ReadByte(authorityPointer, 3) != 0 ||
            Marshal.ReadByte(authorityPointer, 4) != 0 ||
            Marshal.ReadByte(authorityPointer, 5) != 16) {
            throw new InvalidOperationException("Token integrity information is invalid.");
        }
        IntPtr ridPointer = GetSidSubAuthority(label.Label.Sid, (UInt32)(count - 1));
        if (ridPointer == IntPtr.Zero) {
            throw new InvalidOperationException("Token integrity information is invalid.");
        }
        return unchecked((UInt32)Marshal.ReadInt32(ridPointer));
    }

    public static String ClassifyIntegrityRid(UInt32 integrityRid)
    {
        switch (integrityRid) {
            case 0x00001000:
                return "low";
            case 0x00002000:
                return "medium";
            case 0x00002100:
                return "mediumPlus";
            case 0x00003000:
                return "high";
            case 0x00004000:
                return "system";
            default:
                throw new InvalidOperationException("Token integrity RID is not recognized.");
        }
    }

    private static Int32 GetTokenInt32(IntPtr tokenHandle, Int32 informationClass)
    {
        UInt32 length = sizeof(Int32);
        IntPtr buffer = Marshal.AllocHGlobal(sizeof(Int32));
        try {
            if (!GetTokenInformation(
                    tokenHandle,
                    informationClass,
                    buffer,
                    length,
                    out length
                ) || length != sizeof(Int32)) {
                throw new InvalidOperationException("Token elevation information is unavailable.");
            }
            return Marshal.ReadInt32(buffer);
        }
        finally {
            Marshal.FreeHGlobal(buffer);
        }
    }

    public static Boolean GetIsElevated(IntPtr tokenHandle)
    {
        Int32 value = GetTokenInt32(tokenHandle, TokenElevation);
        if (value != 0 && value != 1) {
            throw new InvalidOperationException("Token elevation information is invalid.");
        }
        return value == 1;
    }

    public static Int32 GetElevationType(IntPtr tokenHandle)
    {
        Int32 value = GetTokenInt32(tokenHandle, TokenElevationType);
        if (value < 1 || value > 3) {
            throw new InvalidOperationException("Token elevation type is invalid.");
        }
        return value;
    }

    public static void ValidateElevationConsistency(Int32 elevationType, Boolean isElevated)
    {
        if (elevationType < 1 || elevationType > 3 ||
            (elevationType == 2 && !isElevated) ||
            (elevationType == 3 && isElevated)) {
            throw new InvalidOperationException("Token elevation information is inconsistent.");
        }
    }
}
'@ -ErrorAction Stop
        }

        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        try {
            $principal = New-Object Security.Principal.WindowsPrincipal($identity)
            $groups = @($identity.Groups | ForEach-Object { [string]$_.Value })
            $integrityRid = [uint32]([HcrTokenEvidenceNative]::GetIntegrityRid($identity.Token))
            $integrity = [string]([HcrTokenEvidenceNative]::ClassifyIntegrityRid($integrityRid))
            $isElevated = [bool]([HcrTokenEvidenceNative]::GetIsElevated($identity.Token))
            $elevationTypeValue = [HcrTokenEvidenceNative]::GetElevationType($identity.Token)
            [HcrTokenEvidenceNative]::ValidateElevationConsistency($elevationTypeValue, $isElevated)
            return [pscustomobject][ordered]@{
                sid = [string]$identity.User.Value
                hasAdministratorsSid = $groups -contains 'S-1-5-32-544'
                isAdministrator = $principal.IsInRole(
                    [Security.Principal.WindowsBuiltInRole]::Administrator
                )
                isElevated = $isElevated
                tokenIntegrity = $integrity
            }
        }
        finally {
            $identity.Dispose()
        }
    }
    catch {
        throw 'The current Windows access token could not be queried.'
    }
}

function Test-HcrProperty {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Object) {
        return $false
    }
    if ($Object -is [System.Collections.IDictionary]) {
        return $Object.Contains($Name)
    }
    return $null -ne $Object.PSObject.Properties[$Name]
}

function Get-HcrPropertyValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][object]$Default = $null
    )

    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) {
        Write-Output -NoEnumerate $Object[$Name]
        return
    }
    if (Test-HcrProperty $Object $Name) {
        Write-Output -NoEnumerate $Object.PSObject.Properties[$Name].Value
        return
    }
    Write-Output -NoEnumerate $Default
}

function Get-HcrPropertyNames {
    param([AllowNull()][object]$Object)

    if ($null -eq $Object) {
        return @()
    }
    if ($Object -is [System.Collections.IDictionary]) {
        return @($Object.Keys | ForEach-Object { [string]$_ })
    }
    return @($Object.PSObject.Properties | ForEach-Object { $_.Name })
}

function Test-HcrObjectLike {
    param([AllowNull()][object]$Value)

    if ($Value -is [System.Collections.IDictionary]) {
        return $true
    }
    if ($null -eq $Value -or $Value -is [string] -or
        $Value -is [System.Collections.IEnumerable]) {
        return $false
    }
    return $Value -is [psobject]
}

function Test-HcrInteger {
    param([AllowNull()][object]$Value)

    return $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
}

function Test-HcrBoolean {
    param([AllowNull()][object]$Value)
    return $Value -is [bool]
}

function Add-HcrValidationError {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Errors.Count -lt 64) {
        $Errors.Add($Message)
    }
}

function Test-HcrAllowedProperties {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)][string[]]$Allowed,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors
    )

    if (-not (Test-HcrObjectLike $Object)) {
        Add-HcrValidationError $Errors "$Path must be an object."
        return $false
    }
    foreach ($name in (Get-HcrPropertyNames $Object)) {
        if ($Allowed -notcontains $name) {
            Add-HcrValidationError $Errors "$Path contains unsupported field '$name'."
        }
    }
    return $true
}

function Test-HcrRequiredProperties {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)][string[]]$Required,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors
    )

    $ok = $true
    foreach ($name in $Required) {
        if (-not (Test-HcrProperty $Object $name)) {
            Add-HcrValidationError $Errors "$Path is missing required field '$name'."
            $ok = $false
        }
    }
    return $ok
}

function ConvertTo-HcrJson {
    param(
        [AllowNull()][object]$Value,
        [int]$Depth = 100
    )

    return ConvertTo-Json -InputObject $Value -Depth $Depth -Compress
}

function ConvertFrom-HcrJson {
    param(
        [Parameter(Mandatory = $true)][string]$Json,
        [Parameter(Mandatory = $true)][string]$SourceLabel
    )

    try {
        return $Json | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Throw-HcrError 'INVALID_JSON' "$SourceLabel is not valid JSON."
    }
}

function Get-HcrUtcTimestamp {
    return [DateTime]::UtcNow.ToString('o')
}

function Get-HcrSha256Text {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $script:HcrUtf8NoBom.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-HcrEvidenceDocumentDigest {
    param([Parameter(Mandatory = $true)][object]$Evidence)

    return Get-HcrSha256Text (ConvertTo-HcrJson $Evidence 100)
}

function Get-HcrSha256File {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

function Get-HcrSha256Bytes {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]]$Bytes
    )

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString(
                $sha.ComputeHash($Bytes)
            )).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-HcrLocalFileIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$ErrorCode = 'INVALID_FILE'
    )

    if ($null -eq ('HcrFileIdentityNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

[StructLayout(LayoutKind.Sequential)]
public struct HcrByHandleFileInformation
{
    public uint FileAttributes;
    public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
    public uint VolumeSerialNumber;
    public uint FileSizeHigh;
    public uint FileSizeLow;
    public uint NumberOfLinks;
    public uint FileIndexHigh;
    public uint FileIndexLow;
}

public static class HcrFileIdentityNative
{
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetFileInformationByHandle(
        SafeFileHandle file,
        out HcrByHandleFileInformation information);
}
'@ -ErrorAction Stop
    }

    $item = Assert-HcrRegularLocalFile $Path $ErrorCode
    $stream = [IO.File]::Open(
        $item.FullName,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    )
    try {
        $information = New-Object HcrByHandleFileInformation
        if (-not [HcrFileIdentityNative]::GetFileInformationByHandle(
                $stream.SafeFileHandle,
                [ref]$information
            )) {
            Throw-HcrError $ErrorCode 'The local file identity could not be resolved.'
        }
        return '{0:x8}:{1:x8}{2:x8}' -f
            $information.VolumeSerialNumber,
            $information.FileIndexHigh,
            $information.FileIndexLow
    }
    finally {
        $stream.Dispose()
    }
}

function Get-HcrRandomToken {
    param([int]$ByteCount = 32)

    $bytes = New-Object byte[] $ByteCount
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Copy-HcrObject {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return $null
    }
    return (ConvertTo-HcrJson $Value) | ConvertFrom-Json
}

function Throw-HcrError {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message,
        [AllowNull()][object]$Details = $null
    )

    $safeCode = if ($Code -match '^[A-Z][A-Z0-9_]*$') { $Code } else { 'INTERNAL_ERROR' }
    $exception = New-Object InvalidOperationException($Message)
    $exception.Data['HcrCode'] = $safeCode
    if ($null -ne $Details) {
        $exception.Data['HcrDetailsJson'] = ConvertTo-HcrJson $Details 20
    }
    throw $exception
}

function Throw-HcrPartialMutationError {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)]
        [ValidateSet('confirmed', 'indeterminate')]
        [string]$EffectState,
        [Parameter(Mandatory = $true)][object]$PartialIdentity,
        [Parameter(Mandatory = $true)][string]$RecoveryWarning,
        [AllowNull()][object]$AdditionalDetails = $null
    )

    if (-not (Test-HcrObjectLike $PartialIdentity) -or
        [string]::IsNullOrWhiteSpace($RecoveryWarning)) {
        Throw-HcrError 'INTERNAL_ERROR' 'Partial mutation reporting could not be bounded safely.'
    }
    $details = [ordered]@{
        mutationEntered = $true
        effectState = $EffectState
        partialIdentity = Copy-HcrObject $PartialIdentity
        recoveryWarning = $RecoveryWarning
    }
    if ($null -ne $AdditionalDetails) {
        if (-not (Test-HcrObjectLike $AdditionalDetails)) {
            Throw-HcrError 'INTERNAL_ERROR' 'Partial mutation details are not a bounded object.'
        }
        foreach ($name in (Get-HcrPropertyNames $AdditionalDetails)) {
            if ($details.Contains($name)) {
                Throw-HcrError 'INTERNAL_ERROR' 'Partial mutation details attempted to replace a required binding.'
            }
            $details[$name] = Copy-HcrObject (Get-HcrPropertyValue $AdditionalDetails $name)
        }
    }
    Throw-HcrError $Code $Message ([pscustomobject]$details)
}

function Get-HcrExceptionData {
    param([Parameter(Mandatory = $true)][Exception]$Exception)

    $code = 'INTERNAL_ERROR'
    $message = 'The operation failed safely.'
    $details = $null
    if ($Exception.Data.Contains('HcrCode')) {
        $code = [string]$Exception.Data['HcrCode']
        $message = [string]$Exception.Message
        if ($message.Length -gt 2000) {
            $message = $message.Substring(0, 2000)
        }
        if ($Exception.Data.Contains('HcrDetailsJson')) {
            try {
                $details = ([string]$Exception.Data['HcrDetailsJson']) | ConvertFrom-Json
            }
            catch {
                $details = $null
            }
        }
    }
    return [pscustomobject][ordered]@{
        code = $code
        message = $message
        details = $details
    }
}

function New-HcrEnvelope {
    param(
        [Parameter(Mandatory = $true)][bool]$Ok,
        [Parameter(Mandatory = $true)][string]$OperationId,
        [bool]$Changed = $false,
        [AllowNull()][object]$Data = $null,
        [string[]]$Warnings = @(),
        [AllowNull()][object]$EvidencePath = $null,
        [AllowNull()][object]$Error = $null,
        [ValidateSet(1, 2)][int]$SchemaVersion = 1
    )

    if ($null -eq $Data) {
        $Data = [pscustomobject]@{}
    }
    $envelope = [ordered]@{
        schemaVersion = $SchemaVersion
        ok = $Ok
        operationId = $OperationId
        changed = $Changed
        data = $Data
        warnings = @($Warnings | ForEach-Object {
            $text = [string]$_
            if ($text.Length -gt 1000) { $text.Substring(0, 1000) } else { $text }
        })
        evidencePath = $EvidencePath
    }
    if (-not $Ok) {
        $errorObject = [ordered]@{
            code = [string]$Error.code
            message = [string]$Error.message
        }
        if ($null -ne $Error.details) {
            $errorObject.details = $Error.details
        }
        $envelope.error = $errorObject
    }
    return [pscustomobject]$envelope
}

function Test-HcrUuid {
    param([AllowNull()][object]$Value)

    if ($Value -isnot [string]) {
        return $false
    }
    $parsed = [Guid]::Empty
    return [Guid]::TryParse([string]$Value, [ref]$parsed)
}

function Test-HcrDateTimeString {
    param([AllowNull()][object]$Value)

    if ($Value -isnot [string]) {
        return $false
    }
    $parsed = [DateTimeOffset]::MinValue
    return [DateTimeOffset]::TryParse(
        [string]$Value,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$parsed
    )
}

function Test-HcrSafeRelativePath {
    param([AllowNull()][object]$Value)

    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $false
    }
    $path = [string]$Value
    if ($path.Length -gt 512 -or [IO.Path]::IsPathRooted($path) -or
        $path.StartsWith('\\') -or $path.Contains(':') -or
        $path.Contains('%') -or $path.IndexOf([char]0) -ge 0) {
        return $false
    }
    foreach ($segment in ($path -split '[\\/]')) {
        if ([string]::IsNullOrWhiteSpace($segment) -or
            $segment -eq '..' -or $segment -eq '.') {
            return $false
        }
    }
    return $true
}

function Get-HcrNormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        return [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    }
    catch {
        Throw-HcrError 'INVALID_PATH' 'The supplied path cannot be normalized.'
    }
}

function Test-HcrLocalAbsolutePath {
    param([AllowNull()][object]$Value)

    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $false
    }
    $path = [string]$Value
    if (-not [IO.Path]::IsPathRooted($path) -or $path.StartsWith('\\')) {
        return $false
    }
    try {
        [void][IO.Path]::GetFullPath($path)
        return $true
    }
    catch {
        return $false
    }
}

function Assert-HcrNoReparsePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$ErrorCode = 'INVALID_PATH',
        [switch]$AllowMissing
    )

    if (-not (Test-HcrLocalAbsolutePath $Path)) {
        Throw-HcrError $ErrorCode 'The path must be local and absolute.'
    }
    $normalized = Get-HcrNormalizedPath $Path
    $volumeRoot = [IO.Path]::GetPathRoot($normalized)
    if ([string]::IsNullOrWhiteSpace($volumeRoot)) {
        Throw-HcrError $ErrorCode 'The local path volume could not be resolved.'
    }
    $rootItem = Get-Item -LiteralPath $volumeRoot -Force -ErrorAction SilentlyContinue
    if ($null -eq $rootItem -or -not $rootItem.PSIsContainer -or
        ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Throw-HcrError $ErrorCode 'The local path volume root is unavailable or redirected.'
    }
    $relative = $normalized.Substring($volumeRoot.Length).TrimStart('\', '/')
    $current = $volumeRoot
    $segments = @(if (-not [string]::IsNullOrWhiteSpace($relative)) {
        $relative -split '[\\/]'
    })
    for ($index = 0; $index -lt $segments.Count; $index++) {
        $current = Join-Path $current $segments[$index]
        if (-not (Test-Path -LiteralPath $current)) {
            if ($AllowMissing) { break }
            Throw-HcrError $ErrorCode 'A local path component does not exist.'
        }
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Throw-HcrError $ErrorCode 'A reparse point exists in the supplied path.'
        }
        if ($index -lt ($segments.Count - 1) -and -not $item.PSIsContainer) {
            Throw-HcrError $ErrorCode 'A non-directory component exists in the supplied path.'
        }
    }
    return $normalized
}

function Assert-HcrRegularLocalFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$ErrorCode = 'INVALID_FILE'
    )

    if (-not (Test-HcrLocalAbsolutePath $Path)) {
        Throw-HcrError $ErrorCode 'The path must identify a local absolute file.'
    }
    $normalized = Get-HcrNormalizedPath $Path
    if (-not (Test-Path -LiteralPath $normalized -PathType Leaf)) {
        Throw-HcrError $ErrorCode 'The file does not exist.'
    }
    [void](Assert-HcrNoReparsePath $normalized $ErrorCode)
    $item = Get-Item -LiteralPath $normalized -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Throw-HcrError $ErrorCode 'Reparse-point files are not accepted.'
    }
    return $item
}

function Assert-HcrLocalDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$ErrorCode = 'INVALID_DIRECTORY'
    )

    if (-not (Test-HcrLocalAbsolutePath $Path)) {
        Throw-HcrError $ErrorCode 'The path must identify a local absolute directory.'
    }
    $normalized = Get-HcrNormalizedPath $Path
    if (-not (Test-Path -LiteralPath $normalized -PathType Container)) {
        Throw-HcrError $ErrorCode 'The directory does not exist.'
    }
    [void](Assert-HcrNoReparsePath $normalized $ErrorCode)
    $item = Get-Item -LiteralPath $normalized -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Throw-HcrError $ErrorCode 'Reparse-point directories are not accepted.'
    }
    return $item
}

function Test-HcrAccessDeniedException {
    param([Parameter(Mandatory = $true)][Exception]$Exception)

    $current = $Exception
    while ($null -ne $current) {
        if ($current -is [UnauthorizedAccessException] -or
            $current -is [Security.SecurityException] -or
            (($current.HResult -band 0xffff) -in @(5, 32))) {
            return $true
        }
        $current = $current.InnerException
    }
    return $false
}

function Assert-HcrReadableRegularLocalFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$InvalidErrorCode,
        [Parameter(Mandatory = $true)][string]$AccessErrorCode
    )

    try {
        $item = Assert-HcrRegularLocalFile $Path $InvalidErrorCode
        $stream = [IO.File]::Open(
            $item.FullName,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::Read
        )
        try {
            if ($item.Length -gt 0) { [void]$stream.ReadByte() }
        }
        finally { $stream.Dispose() }
        return $item
    }
    catch {
        if (Test-HcrAccessDeniedException $_.Exception) {
            Throw-HcrError $AccessErrorCode 'The current MCP server token cannot read the requested file.'
        }
        throw
    }
}

function Get-HcrSha256AccessibleFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$InvalidErrorCode,
        [Parameter(Mandatory = $true)][string]$AccessErrorCode
    )

    try { return Get-HcrSha256File $Path }
    catch {
        if (Test-HcrAccessDeniedException $_.Exception) {
            Throw-HcrError $AccessErrorCode 'The current MCP server token cannot read the requested file.'
        }
        if ($_.Exception -is [IO.FileNotFoundException] -or
            $_.Exception -is [IO.DirectoryNotFoundException]) {
            Throw-HcrError $InvalidErrorCode 'The requested file disappeared before its identity could be read.'
        }
        throw
    }
}

function Assert-HcrAccessibleLocalDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$InvalidErrorCode,
        [Parameter(Mandatory = $true)][string]$AccessErrorCode
    )

    try {
        $item = Assert-HcrLocalDirectory $Path $InvalidErrorCode
        $enumerator = [IO.Directory]::EnumerateFileSystemEntries($item.FullName).GetEnumerator()
        try { [void]$enumerator.MoveNext() }
        finally {
            if ($enumerator -is [IDisposable]) { $enumerator.Dispose() }
        }
        return $item
    }
    catch {
        if (Test-HcrAccessDeniedException $_.Exception) {
            Throw-HcrError $AccessErrorCode 'The current MCP server token cannot access the requested directory.'
        }
        throw
    }
}

function Test-HcrPathWithin {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $candidateFull = (Get-HcrNormalizedPath $Candidate) + [IO.Path]::DirectorySeparatorChar
    $rootFull = (Get-HcrNormalizedPath $Root) + [IO.Path]::DirectorySeparatorChar
    return $candidateFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
}

function Publish-HcrCredentialDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$PendingDirectory,
        [Parameter(Mandatory = $true)][string]$ProfileDirectory,
        [Parameter(Mandatory = $true)][string]$CredentialRoot
    )

    $root = (Assert-HcrLocalDirectory $CredentialRoot 'CREDENTIAL_ROOT_INVALID').FullName
    $pending = (Assert-HcrLocalDirectory $PendingDirectory 'CREDENTIAL_PROFILE_INVALID').FullName
    $profile = Get-HcrNormalizedPath $ProfileDirectory
    if (-not (Test-HcrPathWithin $pending $root) -or
        -not (Test-HcrPathWithin $profile $root) -or
        (Split-Path -Leaf $pending) -notmatch '^\.pending-[a-f0-9]{32}$' -or
        [IO.Path]::GetPathRoot($pending) -ne [IO.Path]::GetPathRoot($profile)) {
        Throw-HcrError 'CREDENTIAL_PROFILE_INVALID' 'The pending credential bundle is outside its exact publication boundary.'
    }
    try {
        # Directory.Move has exact-destination create-new semantics. Unlike
        # Move-Item, it never treats a raced-in destination as a container.
        [IO.Directory]::Move($pending, $profile)
    }
    catch [IO.IOException] {
        if (Test-Path -LiteralPath $profile) {
            Throw-HcrError 'CREDENTIAL_PROFILE_EXISTS' 'A credential profile with this name already exists.'
        }
        throw
    }
    return $profile
}

function Write-HcrDiagnostic {
    param([Parameter(Mandatory = $true)][string]$Message)

    $safe = $Message -replace '(?i)(password|token|credential)\s*[=:]\s*\S+', '$1=[redacted]'
    if ($safe.Length -gt 1000) {
        $safe = $safe.Substring(0, 1000)
    }
    [Console]::Error.WriteLine($safe)
}

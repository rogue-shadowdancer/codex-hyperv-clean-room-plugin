Set-StrictMode -Version Latest

$script:HcrPluginVersion = '0.2.0'
$script:HcrSchemaVersion = 1
$script:HcrSchemaVersionV2 = 2
$script:HcrPlanLifetimeMinutes = 15
$script:HcrMockWarning = 'TEST_ONLY_MOCK_ADAPTER: no result in this operation proves real Hyper-V behavior.'
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

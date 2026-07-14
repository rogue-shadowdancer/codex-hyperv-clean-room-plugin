Set-StrictMode -Version Latest

$script:HcrSchemaVersion = 1
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
    'record_manual_attestation'
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
        [AllowNull()][object]$Error = $null
    )

    if ($null -eq $Data) {
        $Data = [pscustomobject]@{}
    }
    $envelope = [ordered]@{
        schemaVersion = $script:HcrSchemaVersion
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
        if ($segment -eq '..' -or $segment -eq '') {
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

function Write-HcrDiagnostic {
    param([Parameter(Mandatory = $true)][string]$Message)

    $safe = $Message -replace '(?i)(password|token|credential)\s*[=:]\s*\S+', '$1=[redacted]'
    if ($safe.Length -gt 1000) {
        $safe = $safe.Substring(0, 1000)
    }
    [Console]::Error.WriteLine($safe)
}

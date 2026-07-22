[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('InspectGuest', 'RunTestStep', 'RunCleanupStep')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedOperationId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-f0-9]{32}$')]
    [string]$InvocationId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-f0-9]{64}$')]
    [string]$ExpectedInputSha256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:AllowedStepTypes = @(
    'installPackage',
    'launchApplication',
    'stopApplication',
    'uninstallPackage',
    'assertFile',
    'assertRegistry',
    'assertProcess',
    'assertModule',
    'assertShortcut',
    'assertPort',
    'writeSentinel',
    'assertSentinel',
    'wait'
)
$script:AllowedStepTypesV2 = @(
    'installPackage',
    'deployPortable',
    'launchApplication',
    'stopApplication',
    'uninstallPackage',
    'assertFile',
    'assertRegistry',
    'assertProcess',
    'assertModule',
    'assertShortcut',
    'assertPort',
    'writeSentinel',
    'assertSentinel',
    'wait',
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
$script:AllowedCleanupTypes = @(
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
$script:AllowedCleanupTypesV2 = @(
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

if (-not ('Hcr.WorkerProcessHandle' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Hcr {
    public static class WorkerProcessHandle {
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool TerminateProcess(IntPtr process, uint exitCode);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
        public static bool TerminateAndWait(IntPtr process, uint exitCode, int milliseconds) {
            if (WaitForSingleObject(process, 0) == 0) { return true; }
            if (!TerminateProcess(process, exitCode)) {
                return WaitForSingleObject(process, 0) == 0;
            }
            return WaitForSingleObject(
                process,
                (uint)Math.Max(1, milliseconds)
            ) == 0;
        }
    }
}
'@ -ErrorAction Stop
}

function Test-WorkerProperty {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Get-WorkerProperty {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][object]$Default = $null
    )

    if (Test-WorkerProperty $Object $Name) { return $Object.$Name }
    return $Default
}

function Throw-WorkerError {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $exception = New-Object System.InvalidOperationException($Message)
    $exception.Data['GuestWorkerCode'] = $Code
    throw $exception
}

function Get-WorkerErrorCode {
    param([Parameter(Mandatory = $true)][Exception]$Exception)

    if ($Exception.Data.Contains('GuestWorkerCode')) {
        $code = [string]$Exception.Data['GuestWorkerCode']
        if ($code -match '^[A-Z][A-Z0-9_]{1,63}$') { return $code }
    }
    return 'GUEST_WORKER_FAILED'
}

function Get-WorkerSha256Text {
    param([Parameter(Mandatory = $true)][string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-WorkerSha256File {
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

function Test-WorkerSafeRelativePath {
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
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -eq '..' -or $segment -eq '.') {
            return $false
        }
    }
    return $true
}

function Test-WorkerPathWithin {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $candidateFull = [IO.Path]::GetFullPath($Candidate).TrimEnd('\', '/') + '\'
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + '\'
    return $candidateFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-WorkerNoReparseEscape {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $candidateFull = [IO.Path]::GetFullPath($Candidate).TrimEnd('\', '/')
    if (-not (Test-WorkerPathWithin $candidateFull $rootFull)) {
        Throw-WorkerError 'GUEST_PATH_INVALID' 'The fixed guest worker path escaped its declared root.'
    }
    $relative = $candidateFull.Substring($rootFull.Length).TrimStart('\', '/')
    $current = $rootFull
    if (Test-Path -LiteralPath $current) {
        $rootItem = Get-Item -LiteralPath $current -Force
        if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Throw-WorkerError 'GUEST_REPARSE_FORBIDDEN' 'A fixed guest root is a reparse point.'
        }
    }
    foreach ($segment in ($relative -split '[\\/]')) {
        if ([string]::IsNullOrWhiteSpace($segment)) { continue }
        $current = Join-Path $current $segment
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                Throw-WorkerError 'GUEST_REPARSE_FORBIDDEN' 'A fixed guest path contains a reparse point.'
            }
        }
    }
}

function Initialize-WorkerDirectoryTree {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container) -or
        -not (Test-WorkerSafeRelativePath $RelativePath)) {
        Throw-WorkerError 'GUEST_PATH_INVALID' 'A fixed guest directory root or relative path is invalid.'
    }
    $current = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $rootItem = Get-Item -LiteralPath $current -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Throw-WorkerError 'GUEST_REPARSE_FORBIDDEN' 'A fixed guest directory root is a reparse point.'
    }
    foreach ($segment in ($RelativePath -split '[\\/]')) {
        $current = Join-Path $current $segment
        if (-not (Test-Path -LiteralPath $current)) {
            try {
                [void](New-Item -ItemType Directory -Path $current -ErrorAction Stop)
            }
            catch {
                if (-not (Test-Path -LiteralPath $current -PathType Container)) { throw }
            }
        }
        $item = Get-Item -LiteralPath $current -Force
        if (-not $item.PSIsContainer -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Throw-WorkerError 'GUEST_REPARSE_FORBIDDEN' 'A fixed guest directory contains a non-directory or reparse point.'
        }
    }
    return $current
}

function Resolve-WorkerPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if (-not (Test-WorkerSafeRelativePath $RelativePath)) {
        Throw-WorkerError 'GUEST_PATH_INVALID' 'A declarative relative path is invalid.'
    }
    $candidate = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
    Assert-WorkerNoReparseEscape $candidate $Root
    return $candidate
}

function Get-WorkerOperationRoot {
    param([Parameter(Mandatory = $true)][string]$OperationId)

    $parsed = [Guid]::Empty
    if (-not [Guid]::TryParse($OperationId, [ref]$parsed) -or
        $parsed.ToString() -ne $OperationId.ToLowerInvariant()) {
        Throw-WorkerError 'GUEST_OPERATION_INVALID' 'The guest operation identity is invalid.'
    }
    return Join-Path (
        Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'Codex\hyperv-clean-room\v1\operations'
    ) $OperationId
}

function Get-WorkerTokenEvidence {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdministrator = $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    $groupSids = @($identity.Groups | ForEach-Object { [string]$_.Value })
    $hasAdministratorsSid = $groupSids -contains 'S-1-5-32-544'
    $integrity = if ($groupSids -contains 'S-1-16-16384') {
        'system'
    }
    elseif ($groupSids -contains 'S-1-16-12288') {
        'high'
    }
    elseif ($groupSids -contains 'S-1-16-8448') {
        'mediumPlus'
    }
    elseif ($groupSids -contains 'S-1-16-8192') {
        'medium'
    }
    elseif ($groupSids -contains 'S-1-16-4096') {
        'low'
    }
    else {
        'unknown'
    }
    return [pscustomobject][ordered]@{
        sid = [string]$identity.User.Value
        userName = [string]$identity.Name
        isAdministrator = [bool]$isAdministrator
        hasAdministratorsSid = [bool]$hasAdministratorsSid
        isElevated = [bool]($isAdministrator -or @('high', 'system') -contains $integrity)
        tokenIntegrity = $integrity
        profilePath = [string]$env:USERPROFILE
        profilePathContainsNonAscii = [bool]([string]$env:USERPROFILE -match '[^\x00-\x7f]')
    }
}

function New-WorkerStepResult {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Summary,
        [AllowNull()][object]$Evidence = $null,
        [AllowNull()][object]$Process = $null,
        [bool]$TimedOut = $false
    )

    $result = [ordered]@{
        status = $Status
        summary = if ($Summary.Length -gt 2000) { $Summary.Substring(0, 2000) } else { $Summary }
        evidence = $Evidence
    }
    if ($null -ne $Process) { $result.process = $Process }
    if ($TimedOut) { $result.timedOut = $true }
    return [pscustomobject]$result
}

function Get-WorkerApplication {
    param(
        [Parameter(Mandatory = $true)][object]$Input,
        [Parameter(Mandatory = $true)][string]$ApplicationId
    )

    $matches = @(@((Get-WorkerProperty $Input 'applications' @())) | Where-Object {
        [string](Get-WorkerProperty $_ 'id') -eq $ApplicationId
    })
    if ($matches.Count -ne 1) {
        Throw-WorkerError 'GUEST_APPLICATION_INVALID' 'The declarative application identity is missing or ambiguous.'
    }
    return $matches[0]
}

function Get-WorkerApplicationPath {
    param(
        [Parameter(Mandatory = $true)][object]$Application,
        [AllowNull()][object]$Input = $null
    )

    if ($null -ne $Input -and [int](Get-WorkerProperty $Input 'schemaVersion' 1) -eq 2 -and
        (Get-WorkerProperty $Application 'packageKind') -eq 'portableZip') {
        $active = Get-WorkerPortableActiveDeployment $Application
        return Resolve-WorkerPath ([string](Get-WorkerProperty $active 'slotPath')) `
            ([string](Get-WorkerProperty $Application 'executableRelativePath'))
    }
    return Resolve-WorkerPath ([string]$env:USERPROFILE) `
        ([string](Get-WorkerProperty $Application 'executableRelativePath'))
}

function Test-WorkerBoolean {
    param([AllowNull()][object]$Value)
    return $Value -is [bool]
}

function Test-WorkerInteger {
    param([AllowNull()][object]$Value)
    return $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
}

function Get-WorkerProcessName {
    param([Parameter(Mandatory = $true)][object]$Application)

    $declared = [string](Get-WorkerProperty $Application 'processName')
    if (-not [string]::IsNullOrWhiteSpace($declared)) {
        return [IO.Path]::GetFileNameWithoutExtension($declared)
    }
    return [IO.Path]::GetFileNameWithoutExtension(
        [string](Get-WorkerProperty $Application 'executableRelativePath')
    )
}

function Get-WorkerProcessPath {
    param([Parameter(Mandatory = $true)][Diagnostics.Process]$Process)

    try { return [string]$Process.MainModule.FileName }
    catch { return $null }
}

function New-WorkerProcessIdentity {
    param(
        [Parameter(Mandatory = $true)][Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true)][string]$OperationId,
        [Parameter(Mandatory = $true)][string]$Application,
        [Parameter(Mandatory = $true)][string]$ExpectedPath
    )

    $startedAt = $Process.StartTime.ToUniversalTime()
    $actualPath = Get-WorkerProcessPath $Process
    if ([string]::IsNullOrWhiteSpace($actualPath)) { $actualPath = $ExpectedPath }
    $identity = Get-WorkerSha256Text (
        "$OperationId|$($Process.Id)|$($startedAt.Ticks)|$($actualPath.ToLowerInvariant())"
    )
    return [pscustomobject][ordered]@{
        operationId = $OperationId
        application = $Application
        pid = [int]$Process.Id
        startedAt = $startedAt.ToString('o')
        executablePath = $actualPath
        identity = $identity
    }
}

function Test-WorkerProcessIdentity {
    param(
        [Parameter(Mandatory = $true)][object]$Recorded,
        [Parameter(Mandatory = $true)][string]$OperationId
    )

    if ([string](Get-WorkerProperty $Recorded 'operationId') -ne $OperationId) {
        return [pscustomobject]@{ valid = $false; process = $null }
    }
    $pid = [int](Get-WorkerProperty $Recorded 'pid' 0)
    if ($pid -le 0) { return [pscustomobject]@{ valid = $false; process = $null } }
    $process = @(Get-Process -Id $pid -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($process.Count -eq 0) { return [pscustomobject]@{ valid = $false; process = $null } }
    try {
        # Force and retain one process handle before reading identity. The stop
        # path terminates this exact handle and never performs a second PID lookup.
        $handle = $process[0].Handle
        $startedAt = $process[0].StartTime.ToUniversalTime()
        $actualPath = Get-WorkerProcessPath $process[0]
        $recordedPath = [string](Get-WorkerProperty $Recorded 'executablePath')
        if ([string]::IsNullOrWhiteSpace($actualPath) -or
            -not $actualPath.Equals($recordedPath, [StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{ valid = $false; process = $process[0] }
        }
        $identity = Get-WorkerSha256Text (
            "$OperationId|$pid|$($startedAt.Ticks)|$($actualPath.ToLowerInvariant())"
        )
        return [pscustomobject]@{
            valid = $identity -eq [string](Get-WorkerProperty $Recorded 'identity')
            process = $process[0]
            handle = $handle
        }
    }
    catch {
        return [pscustomobject]@{ valid = $false; process = $process[0] }
    }
}

function Invoke-WorkerBoundedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $process = if ($ArgumentList.Count -gt 0) {
        Start-Process -FilePath $FilePath -ArgumentList $ArgumentList `
            -PassThru -WindowStyle Hidden -ErrorAction Stop
    }
    else {
        Start-Process -FilePath $FilePath -PassThru -WindowStyle Hidden -ErrorAction Stop
    }
    try {
        # Force and retain the process handle before waiting so timeout cleanup
        # cannot race through a later PID lookup.
        $processHandle = [IntPtr]$process.Handle
        if (-not $process.WaitForExit([Math]::Max(1, $TimeoutSeconds) * 1000)) {
            $terminationVerified = [Hcr.WorkerProcessHandle]::TerminateAndWait(
                $processHandle,
                124,
                5000
            )
            if (-not $terminationVerified) {
                Throw-WorkerError `
                    'GUEST_CHILD_CONTAINMENT_FAILED' `
                    'A timed-out package child could not be verified terminated.'
            }
            return [pscustomobject]@{ timedOut = $true; exitCode = $null }
        }
        return [pscustomobject]@{ timedOut = $false; exitCode = [int]$process.ExitCode }
    }
    finally {
        $process.Dispose()
    }
}

function Resolve-WorkerStagedArtifact {
    param(
        [Parameter(Mandatory = $true)][object]$Input,
        [Parameter(Mandatory = $true)][string]$OperationId
    )

    $artifact = Get-WorkerProperty $Input 'artifact'
    $destination = ([string](Get-WorkerProperty $artifact 'guestDestination')).Replace('/', '\')
    $prefix = "operations\$OperationId\"
    if (-not $destination.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        Throw-WorkerError 'GUEST_ARTIFACT_SCOPE_INVALID' 'The staged artifact is not bound to this operation.'
    }
    $relative = $destination.Substring($prefix.Length)
    $stagingRoot = Join-Path (Get-WorkerOperationRoot $OperationId) 'staging'
    $path = Resolve-WorkerPath $stagingRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Throw-WorkerError 'GUEST_ARTIFACT_MISSING' 'The operation-scoped staged artifact is missing.'
    }
    $item = Get-Item -LiteralPath $path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Throw-WorkerError 'GUEST_ARTIFACT_INVALID' 'The staged artifact is a reparse point.'
    }
    $hash = Get-WorkerSha256File $path
    if ($hash -ne [string](Get-WorkerProperty $artifact 'guestSha256')) {
        Throw-WorkerError 'GUEST_ARTIFACT_HASH_MISMATCH' 'The staged artifact changed before execution.'
    }
    return $path
}

function Test-WorkerExpectedPresence {
    param(
        [Parameter(Mandatory = $true)][object]$Step,
        [Parameter(Mandatory = $true)][bool]$Present
    )

    $expected = $true
    if ((Test-WorkerProperty $Step 'expected') -and
        (Get-WorkerProperty $Step 'expected') -is [bool]) {
        $expected = [bool](Get-WorkerProperty $Step 'expected')
    }
    return $Present -eq $expected
}

function Get-WorkerTokenProjection {
    param([Parameter(Mandatory = $true)][object]$Token)

    return [pscustomobject][ordered]@{
        sid = [string](Get-WorkerProperty $Token 'sid')
        isAdministrator = [bool](Get-WorkerProperty $Token 'isAdministrator' $true)
        hasAdministratorsSid = [bool](Get-WorkerProperty $Token 'hasAdministratorsSid' $true)
        isElevated = [bool](Get-WorkerProperty $Token 'isElevated' $true)
        tokenIntegrity = [string](Get-WorkerProperty $Token 'tokenIntegrity' 'unknown')
    }
}

function Invoke-WorkerStopApplication {
    param(
        [Parameter(Mandatory = $true)][object]$Step,
        [Parameter(Mandatory = $true)][object]$Input,
        [Parameter(Mandatory = $true)][string]$OperationId,
        [Parameter(Mandatory = $true)][object]$Token,
        [bool]$Cleanup
    )

    $applicationId = [string](Get-WorkerProperty $Step 'application')
    $recorded = if ($Cleanup) {
        Get-WorkerProperty $Input 'launchedProcess'
    }
    else {
        $matches = @(@((Get-WorkerProperty $Input 'launchedProcesses' @())) | Where-Object {
            [string](Get-WorkerProperty $_ 'application') -eq $applicationId -and
            [string](Get-WorkerProperty $_ 'operationId') -eq $OperationId
        })
        if ($matches.Count -eq 0) { $null } else { $matches[$matches.Count - 1] }
    }
    if ($null -eq $recorded) {
        return New-WorkerStepResult 'failed' `
            'No process launched by this operation is available for the application.' `
            ([pscustomobject]@{ processIdentityRevalidated = $false; token = Get-WorkerTokenProjection $Token })
    }
    $check = Test-WorkerProcessIdentity $recorded $OperationId
    if (-not [bool]$check.valid) {
        if ($null -ne $check.process) { $check.process.Dispose() }
        return New-WorkerStepResult 'failed' `
            'The current-operation process identity could not be revalidated.' `
            ([pscustomobject]@{
                processIdentityRevalidated = $false
                pid = [int](Get-WorkerProperty $recorded 'pid' 0)
                token = Get-WorkerTokenProjection $Token
            })
    }
    $terminationVerified = $false
    try {
        $terminationVerified = [Hcr.WorkerProcessHandle]::TerminateAndWait(
            [IntPtr]$check.handle,
            1,
            5000
        )
        $check.process.Refresh()
        $terminationVerified = [bool]($terminationVerified -and $check.process.HasExited)
    }
    finally {
        $check.process.Dispose()
    }
    if (-not $terminationVerified) {
        return New-WorkerStepResult 'failed' `
            'The validated current-operation process did not terminate cleanly.' `
            ([pscustomobject]@{
                processIdentityRevalidated = $true
                terminationVerified = $false
                pid = [int](Get-WorkerProperty $recorded 'pid')
                identity = [string](Get-WorkerProperty $recorded 'identity')
                token = Get-WorkerTokenProjection $Token
            })
    }
    return New-WorkerStepResult 'passed' `
        'The current-operation process was stopped after identity revalidation.' `
        ([pscustomobject]@{
            processIdentityRevalidated = $true
            terminationVerified = $true
            pid = [int](Get-WorkerProperty $recorded 'pid')
            identity = [string](Get-WorkerProperty $recorded 'identity')
            token = Get-WorkerTokenProjection $Token
        })
}

function Get-WorkerUninstallEntries {
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($root in @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | Select-Object -First 256)) {
            try {
                $value = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                $entries.Add([pscustomobject]@{
                    keyName = [string]$key.PSChildName
                    displayName = [string](Get-WorkerProperty $value 'DisplayName')
                    installLocation = [string](Get-WorkerProperty $value 'InstallLocation')
                    displayIcon = [string](Get-WorkerProperty $value 'DisplayIcon')
                    uninstallString = [string](Get-WorkerProperty $value 'UninstallString')
                    windowsInstaller = [int](Get-WorkerProperty $value 'WindowsInstaller' 0)
                })
            }
            catch {
                # Unreadable entries are omitted from the bounded inventory.
            }
        }
    }
    return @($entries | ForEach-Object { $_ })
}

function Test-WorkerEntryMatchesApplication {
    param(
        [Parameter(Mandatory = $true)][object]$Entry,
        [Parameter(Mandatory = $true)][string]$ApplicationDirectory,
        [Parameter(Mandatory = $true)][string]$ExecutablePath
    )

    $location = [string](Get-WorkerProperty $Entry 'installLocation')
    if (-not [string]::IsNullOrWhiteSpace($location)) {
        try {
            if (Test-WorkerPathWithin ([IO.Path]::GetFullPath($location)) $ApplicationDirectory) {
                return $true
            }
        }
        catch { }
    }
    $icon = [string](Get-WorkerProperty $Entry 'displayIcon')
    if (-not [string]::IsNullOrWhiteSpace($icon)) {
        $iconPath = $icon.Trim().Trim('"') -replace ',\s*-?\d+$', ''
        try {
            if ([IO.Path]::GetFullPath($iconPath).Equals($ExecutablePath, [StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
        catch { }
    }
    return $false
}

function Resolve-WorkerNsisUninstaller {
    param(
        [Parameter(Mandatory = $true)][object]$Entry,
        [Parameter(Mandatory = $true)][string]$ApplicationDirectory
    )

    $raw = [string](Get-WorkerProperty $Entry 'uninstallString')
    $candidate = $null
    if ($raw -match '^\s*"([A-Za-z]:\\[^"\r\n]+\.exe)"\s*$') {
        $candidate = $matches[1]
    }
    elseif ($raw -match '^\s*([A-Za-z]:\\[^"\r\n]+\.exe)\s*$') {
        $candidate = $matches[1]
    }
    if ([string]::IsNullOrWhiteSpace($candidate)) { return $null }
    try { $candidate = [IO.Path]::GetFullPath($candidate) }
    catch { return $null }
    if (-not (Test-WorkerPathWithin $candidate $ApplicationDirectory) -or
        -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        return $null
    }
    try { Assert-WorkerNoReparseEscape $candidate $ApplicationDirectory }
    catch { return $null }
    $item = Get-Item -LiteralPath $candidate -Force
    if ($item.PSIsContainer -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $null }
    return $candidate
}

function Test-WorkerPortableRelativePath {
    param([AllowNull()][object]$Value)

    if (-not (Test-WorkerSafeRelativePath $Value)) { return $false }
    $path = ([string]$Value).Replace('/', '\')
    if ($path -cne $path.Normalize([Text.NormalizationForm]::FormC)) { return $false }
    if ($path.IndexOfAny([IO.Path]::GetInvalidPathChars()) -ge 0) { return $false }
    foreach ($segment in ($path -split '\\')) {
        if ($segment.EndsWith('.') -or $segment.EndsWith(' ') -or
            $segment.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) { return $false }
        $stem = ($segment -split '\.')[0]
        if ($stem -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { return $false }
        foreach ($character in $segment.ToCharArray()) {
            if ([int]$character -lt 32) { return $false }
        }
    }
    return $true
}

function Get-WorkerPortableProductRoot {
    param([Parameter(Mandatory = $true)][object]$Application)

    $id = [string](Get-WorkerProperty $Application 'id')
    if ($id -notmatch '^[a-zA-Z][a-zA-Z0-9-]*$') {
        Throw-WorkerError 'PORTABLE_APPLICATION_INVALID' 'The portable application identity is invalid.'
    }
    return Initialize-WorkerDirectoryTree ([string]$env:LOCALAPPDATA) `
        ("Codex\hyperv-clean-room\v2\portable\{0}" -f $id)
}

function Get-WorkerPortableActiveDeployment {
    param([Parameter(Mandatory = $true)][object]$Application)

    $root = Get-WorkerPortableProductRoot $Application
    $activePath = Join-Path $root 'active.json'
    if (-not (Test-Path -LiteralPath $activePath -PathType Leaf)) {
        Throw-WorkerError 'PORTABLE_DEPLOYMENT_MISSING' 'The portable application has no active deployment.'
    }
    $item = Get-Item -LiteralPath $activePath -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -gt 65536) {
        Throw-WorkerError 'PORTABLE_DEPLOYMENT_INVALID' 'The active portable deployment record is invalid.'
    }
    $active = Get-Content -LiteralPath $activePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $slotPath = [string](Get-WorkerProperty $active 'slotPath')
    if ([int](Get-WorkerProperty $active 'schemaVersion' 0) -ne 2 -or
        [string](Get-WorkerProperty $active 'applicationId') -ne [string](Get-WorkerProperty $Application 'id') -or
        -not (Test-WorkerPathWithin $slotPath $root) -or
        -not (Test-Path -LiteralPath $slotPath -PathType Container)) {
        Throw-WorkerError 'PORTABLE_DEPLOYMENT_INVALID' 'The active portable deployment record failed rebinding.'
    }
    Assert-WorkerNoReparseEscape $slotPath $root
    return $active
}

function Get-WorkerPortableInventory {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return [pscustomobject][ordered]@{ sha256 = Get-WorkerSha256Text '[]'; entries = @(); bytes = 0 }
    }
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    Assert-WorkerNoReparseEscape $rootFull $rootFull
    $entries = New-Object System.Collections.Generic.List[object]
    $bytes = [int64]0
    foreach ($item in @(Get-ChildItem -LiteralPath $rootFull -Force -Recurse | Sort-Object FullName)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Throw-WorkerError 'PORTABLE_DATA_REPARSE_FORBIDDEN' 'Portable data contains a reparse point.'
        }
        $relative = $item.FullName.Substring($rootFull.Length).TrimStart('\', '/').Replace('\', '/')
        if (-not (Test-WorkerPortableRelativePath $relative) -or $entries.Count -ge 4096) {
            Throw-WorkerError 'PORTABLE_DATA_INVALID' 'Portable data exceeds the closed path or entry policy.'
        }
        if ($item.PSIsContainer) {
            $entries.Add([pscustomobject][ordered]@{ path=$relative; kind='directory'; sizeBytes=0; sha256=$null })
        }
        else {
            $bytes += [int64]$item.Length
            if ($bytes -gt 8GB) { Throw-WorkerError 'PORTABLE_DATA_TOO_LARGE' 'Portable data exceeds eight GiB.' }
            $entries.Add([pscustomobject][ordered]@{ path=$relative; kind='file'; sizeBytes=[int64]$item.Length; sha256=Get-WorkerSha256File $item.FullName })
        }
    }
    $json = @($entries | ForEach-Object { $_ }) | ConvertTo-Json -Depth 10 -Compress
    return [pscustomobject][ordered]@{ sha256=Get-WorkerSha256Text $json; entries=@($entries | ForEach-Object { $_ }); bytes=$bytes }
}

function Copy-WorkerPortableData {
    param(
        [Parameter(Mandatory = $true)][object]$Inventory,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    if (-not (Test-Path -LiteralPath $DestinationRoot -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $DestinationRoot)
    }
    foreach ($entry in @((Get-WorkerProperty $Inventory 'entries' @()))) {
        $relative = [string](Get-WorkerProperty $entry 'path')
        $destination = Resolve-WorkerPath $DestinationRoot $relative
        if ((Get-WorkerProperty $entry 'kind') -eq 'directory') {
            if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
                [void](New-Item -ItemType Directory -Path $destination)
            }
            continue
        }
        $source = Resolve-WorkerPath $SourceRoot $relative
        $parent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            [void](New-Item -ItemType Directory -Path $parent -Force)
        }
        Copy-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
        if ((Get-WorkerSha256File $destination) -ne [string](Get-WorkerProperty $entry 'sha256')) {
            Throw-WorkerError 'PORTABLE_DATA_HASH_MISMATCH' 'Copied portable data failed hash verification.'
        }
    }
}

function Read-WorkerPortableManifest {
    param(
        [Parameter(Mandatory = $true)][IO.Compression.ZipArchive]$Archive,
        [Parameter(Mandatory = $true)][object]$Input
    )

    $matches = @($Archive.Entries | Where-Object { $_.FullName -ceq 'portable-manifest.json' })
    if ($matches.Count -ne 1 -or $matches[0].Length -gt 4MB) {
        Throw-WorkerError 'PORTABLE_MANIFEST_INVALID' 'The archive must contain one bounded root portable manifest.'
    }
    $stream = $matches[0].Open()
    try {
        $memory = New-Object IO.MemoryStream
        try { $stream.CopyTo($memory); $bytes=$memory.ToArray() } finally { $memory.Dispose() }
    }
    finally { $stream.Dispose() }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
    $declared = [string](Get-WorkerProperty (Get-WorkerProperty $Input 'portableArtifact') 'portableManifestSha256')
    if ($hash -ne $declared) { Throw-WorkerError 'PORTABLE_MANIFEST_HASH_MISMATCH' 'The portable manifest hash does not match the profile.' }
    $json = (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes)
    $manifest = $json | ConvertFrom-Json -ErrorAction Stop
    $required = @('schemaVersion','productId','productVersion','architecture','sourceCommit','sourceDirty','buildRunId','unsigned','distributionMode','entryPointRelativePath','dataDirectoryRelativePath','portableArguments','archivePolicy','identities','files')
    foreach ($name in $required) { if (-not (Test-WorkerProperty $manifest $name)) { Throw-WorkerError 'PORTABLE_MANIFEST_INVALID' 'The portable manifest is incomplete.' } }
    if (@($manifest.PSObject.Properties).Count -ne $required.Count -or
        -not (Test-WorkerInteger $manifest.schemaVersion) -or [int]$manifest.schemaVersion -ne 2 -or
        [string]$manifest.productId -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' -or
        [string]$manifest.productVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$' -or
        [string]$manifest.architecture -ne 'x64' -or [string]$manifest.sourceCommit -notmatch '^[a-f0-9]{40}$' -or
        [string]$manifest.buildRunId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' -or
        -not (Test-WorkerBoolean $manifest.sourceDirty) -or $manifest.sourceDirty -ne $false -or
        -not (Test-WorkerBoolean $manifest.unsigned) -or $manifest.unsigned -ne $true -or
        [string]$manifest.distributionMode -ne 'portable' -or [string]$manifest.dataDirectoryRelativePath -ne 'data' -or
        @($manifest.portableArguments).Count -ne 1 -or [string]$manifest.portableArguments[0] -ne '--portable' -or
        -not (Test-WorkerPortableRelativePath ([string]$manifest.entryPointRelativePath)) -or
        [string]$manifest.sourceCommit -ne [string](Get-WorkerProperty $Input 'sourceCommit')) {
        Throw-WorkerError 'PORTABLE_MANIFEST_INVALID' 'The portable manifest violates the frozen identity contract.'
    }
    $policy=$manifest.archivePolicy
    $policyFields=@('maxEntries','maxExpandedBytes','maxCompressionRatio','rejectLinks','rejectReparsePoints','rejectAlternateDataStreams','caseInsensitiveUniquePaths')
    if (@($policy.PSObject.Properties).Count -ne $policyFields.Count -or
        @($policyFields | Where-Object { -not (Test-WorkerProperty $policy $_) }).Count -ne 0 -or
        -not (Test-WorkerInteger $policy.maxEntries) -or
        -not (Test-WorkerInteger $policy.maxExpandedBytes) -or
        -not (Test-WorkerInteger $policy.maxCompressionRatio) -or
        [int]$policy.maxEntries -ne 4096 -or [int64]$policy.maxExpandedBytes -ne 8GB -or [int]$policy.maxCompressionRatio -ne 200 -or
        -not (Test-WorkerBoolean $policy.rejectLinks) -or $policy.rejectLinks -ne $true -or
        -not (Test-WorkerBoolean $policy.rejectReparsePoints) -or $policy.rejectReparsePoints -ne $true -or
        -not (Test-WorkerBoolean $policy.rejectAlternateDataStreams) -or $policy.rejectAlternateDataStreams -ne $true -or
        -not (Test-WorkerBoolean $policy.caseInsensitiveUniquePaths) -or $policy.caseInsensitiveUniquePaths -ne $true) {
        Throw-WorkerError 'PORTABLE_MANIFEST_INVALID' 'The portable archive policy is not the frozen policy.'
    }
    $identityFields=@('webView2','maaFramework')
    if (@($manifest.identities.PSObject.Properties).Count -ne $identityFields.Count -or
        @($identityFields | Where-Object { -not (Test-WorkerProperty $manifest.identities $_) }).Count -ne 0) {
        Throw-WorkerError 'PORTABLE_MANIFEST_INVALID' 'The portable component identity set is not closed.'
    }
    foreach ($identityName in $identityFields) {
        $identity = Get-WorkerProperty $manifest.identities $identityName
        if (@($identity.PSObject.Properties).Count -ne 2 -or
            -not (Test-WorkerProperty $identity 'version') -or
            -not (Test-WorkerProperty $identity 'inventorySha256') -or
            [string]::IsNullOrWhiteSpace([string]$identity.version) -or
            ([string]$identity.version).Length -gt 128 -or
            [string]$identity.inventorySha256 -notmatch '^[a-f0-9]{64}$') {
            Throw-WorkerError 'PORTABLE_MANIFEST_INVALID' 'A portable component identity is invalid.'
        }
    }
    $webDriver = Get-WorkerProperty $Input 'webDriver'
    if ([string]$manifest.identities.webView2.version -ne [string](Get-WorkerProperty $webDriver 'browserVersion')) {
        Throw-WorkerError 'PORTABLE_MANIFEST_INVALID' 'The portable fixed WebView2 version does not match the fixed driver contract.'
    }
    return [pscustomobject][ordered]@{ document=$manifest; sha256=$hash }
}

function Invoke-WorkerDeployPortable {
    param(
        [Parameter(Mandatory = $true)][object]$Step,
        [Parameter(Mandatory = $true)][object]$Input,
        [Parameter(Mandatory = $true)][string]$OperationId,
        [Parameter(Mandatory = $true)][object]$Token
    )

    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $application=Get-WorkerApplication $Input ([string](Get-WorkerProperty $Step 'application'))
    if ((Get-WorkerProperty $application 'packageKind') -ne 'portableZip') { Throw-WorkerError 'PORTABLE_APPLICATION_INVALID' 'deployPortable requires a portableZip application.' }
    $archivePath=Resolve-WorkerStagedArtifact $Input $OperationId
    $stream=[IO.File]::Open($archivePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $archive=$null
    try {
        $archive=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Read,$false)
        if ($archive.Entries.Count -gt 4096) { Throw-WorkerError 'PORTABLE_ARCHIVE_TOO_MANY_ENTRIES' 'The portable archive exceeds 4096 entries.' }
        $manifestBound=Read-WorkerPortableManifest $archive $Input
        $manifest=$manifestBound.document
        $manifestFiles=@($manifest.files)
        if($manifestFiles.Count-lt1-or$manifestFiles.Count-gt4096){Throw-WorkerError 'PORTABLE_MANIFEST_INVALID' 'The portable file inventory count is invalid.'}
        $declared=@{}; foreach($file in $manifestFiles){
            $path=([string]$file.path).Replace('\','/')
            if (@($file.PSObject.Properties).Count -ne 3 -or
                -not (Test-WorkerProperty $file 'path') -or
                -not (Test-WorkerProperty $file 'sizeBytes') -or
                -not (Test-WorkerProperty $file 'sha256') -or
                -not (Test-WorkerPortableRelativePath $path) -or
                $path -ieq 'portable-manifest.json' -or $declared.ContainsKey($path)) { Throw-WorkerError 'PORTABLE_MANIFEST_INVALID' 'The portable file inventory contains an unsafe or colliding path.' }
            if ($path -ieq 'data' -or
                $path.StartsWith('data/', [StringComparison]::OrdinalIgnoreCase)) {
                Throw-WorkerError 'PORTABLE_MUTABLE_DATA_FORBIDDEN' 'The portable payload cannot declare mutable data entries.'
            }
            if ([string]$file.sha256 -notmatch '^[a-f0-9]{64}$' -or -not(Test-WorkerInteger $file.sizeBytes) -or [int64]$file.sizeBytes -lt 0 -or [int64]$file.sizeBytes -gt 2GB){Throw-WorkerError 'PORTABLE_MANIFEST_INVALID' 'A portable file identity is invalid.'}
            $declared[$path]=$file
        }
        $productRoot=Get-WorkerPortableProductRoot $application
        $slotsRoot=Initialize-WorkerDirectoryTree $productRoot 'slots'
        $slotId=[Guid]::NewGuid().ToString();$staging=Join-Path $slotsRoot ('.staging-'+$OperationId+'-'+$slotId);[void](New-Item -ItemType Directory -Path $staging)
        $seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase);$expanded=[int64]0
        foreach($entry in @($archive.Entries)){
            $relative=$entry.FullName.Replace('\','/').TrimEnd('/')
            if ([string]::IsNullOrWhiteSpace($relative)) { continue }
            if (-not (Test-WorkerPortableRelativePath $relative) -or -not $seen.Add($relative)) { Throw-WorkerError 'PORTABLE_ARCHIVE_PATH_INVALID' 'The portable archive contains an unsafe or colliding path.' }
            $unixMode=([uint32]$entry.ExternalAttributes -shr 16) -band 0xF000
            if ($unixMode -eq 0xA000) { Throw-WorkerError 'PORTABLE_ARCHIVE_LINK_FORBIDDEN' 'The portable archive contains a link.' }
            if (([uint32]$entry.ExternalAttributes -band 0x400) -ne 0) { Throw-WorkerError 'PORTABLE_ARCHIVE_LINK_FORBIDDEN' 'The portable archive contains a Windows reparse point.' }
            if ([string]::IsNullOrEmpty($entry.Name)) {
                $prefix=$relative.TrimEnd('/')+'/'
                if (@($declared.Keys | Where-Object { $_.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
                    Throw-WorkerError 'PORTABLE_ARCHIVE_UNDECLARED_ENTRY' 'The portable archive contains an undeclared directory.'
                }
                [void](Initialize-WorkerDirectoryTree $staging $relative)
                continue
            }
            if ($relative -ine 'portable-manifest.json' -and -not $declared.ContainsKey($relative)) { Throw-WorkerError 'PORTABLE_ARCHIVE_UNDECLARED_ENTRY' 'The portable archive contains an undeclared file.' }
            if ($entry.CompressedLength -eq 0 -and $entry.Length -gt 0 -or ($entry.CompressedLength -gt 0 -and ([double]$entry.Length/[double]$entry.CompressedLength) -gt 200)){Throw-WorkerError 'PORTABLE_ARCHIVE_RATIO_INVALID' 'The portable archive compression ratio exceeds 200:1.'}
            $expanded+=[int64]$entry.Length;if($expanded -gt 8GB){Throw-WorkerError 'PORTABLE_ARCHIVE_TOO_LARGE' 'The portable archive exceeds eight GiB expanded.'}
            $target=Resolve-WorkerPath $staging $relative;$parent=Split-Path -Parent $target;if(-not(Test-Path -LiteralPath $parent -PathType Container)){[void](New-Item -ItemType Directory -Path $parent -Force)}
            $entryStream=$entry.Open();$targetStream=[IO.File]::Open($target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try{$entryStream.CopyTo($targetStream)}finally{$targetStream.Dispose();$entryStream.Dispose()}
            if($relative -ine 'portable-manifest.json'){$identity=$declared[$relative];if((Get-Item -LiteralPath $target).Length -ne [int64]$identity.sizeBytes -or (Get-WorkerSha256File $target) -ne [string]$identity.sha256){Throw-WorkerError 'PORTABLE_ARCHIVE_HASH_MISMATCH' 'An extracted portable file failed size or hash verification.'}}
        }
        foreach($declaredPath in @($declared.Keys)){if(-not$seen.Contains($declaredPath)){Throw-WorkerError 'PORTABLE_ARCHIVE_MISSING_ENTRY' 'The portable archive is missing a declared file.'}}
        $previousHash=$null
        try{$active=Get-WorkerPortableActiveDeployment $application;$sourceData=Resolve-WorkerPath ([string]$active.slotPath) 'data';$sourceInventory=Get-WorkerPortableInventory $sourceData;$previousHash=$sourceInventory.sha256;Copy-WorkerPortableData $sourceInventory $sourceData (Join-Path $staging 'data');$deployedInventory=Get-WorkerPortableInventory (Join-Path $staging 'data');if($deployedInventory.sha256 -ne $previousHash){Throw-WorkerError 'PORTABLE_DATA_HASH_MISMATCH' 'Portable data preservation inventory changed.'}}catch{if((Get-WorkerErrorCode $_.Exception)-ne'PORTABLE_DEPLOYMENT_MISSING'){throw};[void](New-Item -ItemType Directory -Path (Join-Path $staging 'data') -Force);$deployedInventory=Get-WorkerPortableInventory (Join-Path $staging 'data')}
        $slotPath=Join-Path $slotsRoot $slotId;Move-Item -LiteralPath $staging -Destination $slotPath
        $record=[ordered]@{schemaVersion=2;applicationId=[string]$application.id;productId=[string]$manifest.productId;slotId=$slotId;slotPath=$slotPath;deploymentId=[Guid]::NewGuid().ToString();deployedAt=[DateTimeOffset]::UtcNow.ToString('o');portableZipSha256=[string](Get-WorkerProperty (Get-WorkerProperty $Input 'artifact') 'guestSha256');portableManifestSha256=$manifestBound.sha256;dataInventorySha256=$deployedInventory.sha256}
        $activePath=Join-Path $productRoot 'active.json';$tempPath=Join-Path $productRoot ('active-'+[Guid]::NewGuid().ToString('N')+'.tmp');[IO.File]::WriteAllText($tempPath,(($record|ConvertTo-Json -Depth 20 -Compress)+"`n"),$script:Utf8NoBom)
        if(Test-Path -LiteralPath $activePath){$backup=Join-Path $productRoot ('active-backup-'+[Guid]::NewGuid().ToString('N')+'.json');[IO.File]::Replace($tempPath,$activePath,$backup,$true)}else{Move-Item -LiteralPath $tempPath -Destination $activePath}
        return New-WorkerStepResult 'passed' 'The verified portable payload was atomically published with data preservation.' ([pscustomobject]@{deploymentId=$record.deploymentId;deploymentFingerprint=Get-WorkerSha256Text ($record|ConvertTo-Json -Depth 20 -Compress);dataPreserved=$true;previousDataInventorySha256=$previousHash;deployedDataInventorySha256=$deployedInventory.sha256;portableManifestSha256=$manifestBound.sha256;fixedWebView2Version=[string]$manifest.identities.webView2.version;token=Get-WorkerTokenProjection $Token})
    }
    finally{if($null-ne$archive){$archive.Dispose()};$stream.Dispose()}
}

function Get-WorkerLoopbackEphemeralPort {
    $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
    try { $listener.Start(); return [int]$listener.LocalEndpoint.Port }
    finally { $listener.Stop() }
}

function Get-WorkerWebDriverRoot {
    param([Parameter(Mandatory = $true)][string]$OperationId)
    return Initialize-WorkerDirectoryTree (Get-WorkerOperationRoot $OperationId) 'webdriver'
}

function Get-WorkerWebDriverStatePath {
    param([Parameter(Mandatory = $true)][string]$OperationId)
    return Join-Path (Get-WorkerWebDriverRoot $OperationId) 'ui-session.json'
}

function Test-WorkerMicrosoftDriverUri {
    param([Parameter(Mandatory = $true)][Uri]$Uri)
    return $Uri.Scheme -ceq 'https' -and (
        $Uri.Host -ceq 'msedgedriver.microsoft.com' -or
        $Uri.Host.EndsWith('.microsoft.com', [StringComparison]::OrdinalIgnoreCase) -or
        $Uri.Host.EndsWith('.microsoftedgeinsider.com', [StringComparison]::OrdinalIgnoreCase)
    )
}

function Invoke-WorkerFixedDownload {
    param(
        [Parameter(Mandatory = $true)][Uri]$InitialUri,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][int64]$MaximumBytes
    )

    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
    $handler = New-Object Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $false
    $client = New-Object Net.Http.HttpClient($handler)
    try {
        $uri = $InitialUri
        for ($redirect = 0; $redirect -le 5; $redirect++) {
            if (-not (Test-WorkerMicrosoftDriverUri $uri)) { Throw-WorkerError 'WEBDRIVER_REDIRECT_FORBIDDEN' 'The fixed driver endpoint left the Microsoft HTTPS allowlist.' }
            $response = $client.GetAsync($uri, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            try {
                if ([int]$response.StatusCode -ge 300 -and [int]$response.StatusCode -lt 400) {
                    $location = $response.Headers.Location
                    if ($null -eq $location) { Throw-WorkerError 'WEBDRIVER_DOWNLOAD_FAILED' 'A fixed driver redirect has no location.' }
                    $uri = if ($location.IsAbsoluteUri) { $location } else { New-Object Uri($uri, $location) }
                    continue
                }
                if (-not $response.IsSuccessStatusCode) { Throw-WorkerError 'WEBDRIVER_DOWNLOAD_FAILED' 'The fixed driver endpoint returned a failure status.' }
                $declaredLength = $response.Content.Headers.ContentLength
                if ($null -ne $declaredLength -and [int64]$declaredLength -gt $MaximumBytes) { Throw-WorkerError 'WEBDRIVER_ARCHIVE_TOO_LARGE' 'The fixed driver archive exceeds its declared size.' }
                $source = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                $target = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try {
                    $buffer = New-Object byte[] 65536; $total=[int64]0
                    while (($count=$source.Read($buffer,0,$buffer.Length)) -gt 0) { $total += $count; if ($total -gt $MaximumBytes) { Throw-WorkerError 'WEBDRIVER_ARCHIVE_TOO_LARGE' 'The fixed driver archive exceeded its declared size while streaming.' }; $target.Write($buffer,0,$count) }
                }
                finally { $target.Dispose(); $source.Dispose() }
                return
            }
            finally { $response.Dispose() }
        }
        Throw-WorkerError 'WEBDRIVER_REDIRECT_FORBIDDEN' 'The fixed driver endpoint exceeded the redirect limit.'
    }
    finally { $client.Dispose(); $handler.Dispose() }
}

function Test-WorkerPeX64 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) { return $false }
        $stream.Position = 0x3C
        $offset = $reader.ReadInt32()
        if ($offset -lt 64 -or $offset -gt ($stream.Length - 6)) { return $false }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x00004550) { return $false }
        return $reader.ReadUInt16() -eq 0x8664
    }
    finally { $reader.Dispose(); $stream.Dispose() }
}

function Invoke-WorkerAcquireWebDriver {
    param(
        [Parameter(Mandatory = $true)][object]$Input,
        [Parameter(Mandatory = $true)][string]$OperationId,
        [Parameter(Mandatory = $true)][object]$Token
    )
    $manifest=Get-WorkerProperty $Input 'webDriver';$version=[string](Get-WorkerProperty $manifest 'driverVersion');$acquisition=Get-WorkerProperty $manifest 'acquisition';$executableIdentity=Get-WorkerProperty $manifest 'executable'
    if($version-notmatch'^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'-or$version-ne[string](Get-WorkerProperty $manifest 'browserVersion')-or[string](Get-WorkerProperty $acquisition 'source')-ne'microsoftFixedEndpoint'){Throw-WorkerError 'WEBDRIVER_MANIFEST_INVALID' 'The fixed driver manifest is incompatible.'}
    $root=Get-WorkerWebDriverRoot $OperationId;$archivePath=Join-Path $root 'edgedriver_win64.zip';$driverPath=Join-Path $root 'msedgedriver.exe'
    if(-not(Test-Path -LiteralPath $archivePath -PathType Leaf)){Invoke-WorkerFixedDownload ([Uri]("https://msedgedriver.microsoft.com/{0}/edgedriver_win64.zip"-f$version)) $archivePath ([int64](Get-WorkerProperty $acquisition 'archiveSizeBytes'))}
    if((Get-Item -LiteralPath $archivePath).Length-ne[int64](Get-WorkerProperty $acquisition 'archiveSizeBytes')-or(Get-WorkerSha256File $archivePath)-ne[string](Get-WorkerProperty $acquisition 'archiveSha256')){Throw-WorkerError 'WEBDRIVER_ARCHIVE_HASH_MISMATCH' 'The fixed driver archive identity does not match.'}
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $archive=[IO.Compression.ZipFile]::OpenRead($archivePath)
    try{
        $declaredFiles=@{};foreach($file in @((Get-WorkerProperty $manifest 'files'))){$path=([string](Get-WorkerProperty $file 'path')).Replace('\','/');if(-not(Test-WorkerPortableRelativePath $path)-or$declaredFiles.ContainsKey($path)){Throw-WorkerError 'WEBDRIVER_ARCHIVE_INVALID' 'A driver archive path is unsafe or colliding.'};$declaredFiles[$path]=$file}
        $seenFiles=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach($entry in @($archive.Entries)){$entryPath=$entry.FullName.Replace('\','/').TrimEnd('/');if([string]::IsNullOrWhiteSpace($entryPath)){continue};if(-not(Test-WorkerPortableRelativePath $entryPath)){Throw-WorkerError 'WEBDRIVER_ARCHIVE_INVALID' 'A driver archive path is unsafe.'};if([string]::IsNullOrEmpty($entry.Name)){$prefix=$entryPath+'/';if(@($declaredFiles.Keys|Where-Object{$_.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)}).Count-eq0){Throw-WorkerError 'WEBDRIVER_ARCHIVE_INVALID' 'The driver archive contains an undeclared directory.'};continue};if(-not$declaredFiles.ContainsKey($entryPath)-or-not$seenFiles.Add($entryPath)){Throw-WorkerError 'WEBDRIVER_ARCHIVE_INVALID' 'The driver archive contains an undeclared or colliding file.'}}
        foreach($path in @($declaredFiles.Keys)){$file=$declaredFiles[$path];$matches=@($archive.Entries|Where-Object{$_.FullName.Replace('\','/').TrimEnd('/')-ceq$path});if($matches.Count-ne1){Throw-WorkerError 'WEBDRIVER_ARCHIVE_INVALID' 'The driver archive inventory is incomplete.'};$target=Resolve-WorkerPath $root $path;$parent=Split-Path -Parent $target;if(-not(Test-Path -LiteralPath $parent -PathType Container)){[void](New-Item -ItemType Directory -Path $parent -Force)};if(-not(Test-Path -LiteralPath $target)){[IO.Compression.ZipFileExtensions]::ExtractToFile($matches[0],$target,$false)};if((Get-Item -LiteralPath $target).Length-ne[int64](Get-WorkerProperty $file 'sizeBytes')-or(Get-WorkerSha256File $target)-ne[string](Get-WorkerProperty $file 'sha256')){Throw-WorkerError 'WEBDRIVER_FILE_HASH_MISMATCH' 'A driver file failed identity verification.'}}
    }finally{$archive.Dispose()}
    if((Get-Item -LiteralPath $driverPath).Length-ne[int64](Get-WorkerProperty $executableIdentity 'sizeBytes')-or(Get-WorkerSha256File $driverPath)-ne[string](Get-WorkerProperty $executableIdentity 'sha256')-or-not(Test-WorkerPeX64 $driverPath)){Throw-WorkerError 'WEBDRIVER_EXECUTABLE_INVALID' 'The fixed driver executable identity is invalid.'}
    $signature=Get-AuthenticodeSignature -FilePath $driverPath;if([string]$signature.Status-ne'Valid'-or[string]$signature.SignerCertificate.Subject-notmatch'Microsoft Corporation'){Throw-WorkerError 'WEBDRIVER_SIGNATURE_INVALID' 'The fixed driver Microsoft signature is invalid.'}
    return New-WorkerStepResult 'passed' 'The fixed Microsoft EdgeDriver supply chain was verified.' ([pscustomobject]@{archiveSha256=Get-WorkerSha256File $archivePath;executableSha256=Get-WorkerSha256File $driverPath;driverVersion=$version;loopbackOnly=$true;token=Get-WorkerTokenProjection $Token})
}

function Invoke-WorkerWebDriverRequest {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][ValidateSet('GET','POST','DELETE')][string]$Method,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [AllowNull()][object]$Body=$null,
        [ValidateRange(1, 100000)][int]$TimeoutMilliseconds=100000
    )
    if($RelativePath-notmatch'^/[a-zA-Z0-9_./-]{1,512}$'){Throw-WorkerError 'UI_PROTOCOL_PATH_INVALID' 'The internal fixed WebDriver path is invalid.'}
    $port=[int](Get-WorkerProperty $State 'port');if($port-lt1-or$port-gt65535){Throw-WorkerError 'UI_SESSION_INVALID' 'The owned WebDriver port is invalid.'}
    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop;$handler=New-Object Net.Http.HttpClientHandler;$handler.AllowAutoRedirect=$false;$client=New-Object Net.Http.HttpClient($handler)
    $client.Timeout=[TimeSpan]::FromMilliseconds($TimeoutMilliseconds)
    try{$uri=[Uri]("http://127.0.0.1:{0}{1}"-f$port,$RelativePath);$httpMethod=New-Object Net.Http.HttpMethod($Method);$request=New-Object Net.Http.HttpRequestMessage($httpMethod,$uri);if($null-ne$Body){$json=$Body|ConvertTo-Json -Depth 20 -Compress;if([Text.Encoding]::UTF8.GetByteCount($json)-gt65536){Throw-WorkerError 'UI_PROTOCOL_BODY_TOO_LARGE' 'The fixed UI request exceeded its bound.'};$request.Content=New-Object Net.Http.StringContent($json,[Text.Encoding]::UTF8,'application/json')};$response=$client.SendAsync($request).GetAwaiter().GetResult();try{$text=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult();if([Text.Encoding]::UTF8.GetByteCount($text)-gt1048576){Throw-WorkerError 'UI_PROTOCOL_RESPONSE_TOO_LARGE' 'The fixed UI response exceeded one MiB.'};if(-not$response.IsSuccessStatusCode){Throw-WorkerError 'UI_PROTOCOL_FAILED' 'The fixed WebDriver request failed.'};if([string]::IsNullOrWhiteSpace($text)){return$null};return$text|ConvertFrom-Json -ErrorAction Stop}finally{$response.Dispose();$request.Dispose()}}
    finally{$client.Dispose();$handler.Dispose()}
}

function Read-WorkerWebDriverState {
    param([Parameter(Mandatory=$true)][string]$OperationId)
    $path=Get-WorkerWebDriverStatePath $OperationId;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){Throw-WorkerError 'UI_SESSION_MISSING' 'The owned UI session state is missing.'};$state=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -ErrorAction Stop;if([int]$state.schemaVersion-ne2-or[string]$state.operationId-ne$OperationId-or[string]$state.sessionId-notmatch'^[A-Za-z0-9-]{1,256}$'){Throw-WorkerError 'UI_SESSION_INVALID' 'The owned UI session state is invalid.'};return$state
}

function Get-WorkerWebDriverElement {
    param([Parameter(Mandatory=$true)][object]$State,[Parameter(Mandatory=$true)][string]$TestId)
    if($TestId-notmatch'^[a-z0-9]+(?:-[a-z0-9]+)*$'){Throw-WorkerError 'UI_TEST_ID_INVALID' 'The closed data-testid identity is invalid.'}
    $response=Invoke-WorkerWebDriverRequest $State POST ("/session/{0}/element"-f$State.sessionId) ([ordered]@{using='css selector';value=('[data-testid="{0}"]'-f$TestId)})
    $value=Get-WorkerProperty $response 'value';$property=@($value.PSObject.Properties|Where-Object{$_.Name-eq'element-6066-11e4-a52e-4f735466cecf'});if($property.Count-ne1-or[string]$property[0].Value-notmatch'^[A-Za-z0-9-]{1,256}$'){Throw-WorkerError 'UI_ELEMENT_NOT_FOUND' 'The declared data-testid element was not uniquely resolved.'};return[string]$property[0].Value
}

function Invoke-WorkerStartUiSession {
    param([Parameter(Mandatory=$true)][object]$Step,[Parameter(Mandatory=$true)][object]$Input,[Parameter(Mandatory=$true)][string]$OperationId,[Parameter(Mandatory=$true)][object]$Token)
    $driverPath=Join-Path (Get-WorkerWebDriverRoot $OperationId) 'msedgedriver.exe';if(-not(Test-Path -LiteralPath $driverPath -PathType Leaf)){Throw-WorkerError 'WEBDRIVER_NOT_ACQUIRED' 'The fixed driver must be acquired before UI session start.'}
    $applicationId=[string](Get-WorkerProperty $Step 'application');$applicationProcesses=@((Get-WorkerProperty $Input 'launchedProcesses' @())|Where-Object{[string](Get-WorkerProperty $_ 'application')-eq$applicationId});if($applicationProcesses.Count-ne1){Throw-WorkerError 'UI_APPLICATION_NOT_BOUND' 'The UI session requires one current-operation application process.'};$debugPort=[int](Get-WorkerProperty $applicationProcesses[0] 'uiDebugPort');if($debugPort-lt1-or$debugPort-gt65535){Throw-WorkerError 'UI_APPLICATION_NOT_BOUND' 'The application WebView2 debug port is unavailable.'}
    $port=Get-WorkerLoopbackEphemeralPort;$process=Start-Process -FilePath $driverPath -ArgumentList @("--port=$port",'--host=127.0.0.1') -PassThru -WindowStyle Hidden -ErrorAction Stop
    $driverHandle=[IntPtr]$process.Handle;$started=$false
    try{
        Start-Sleep -Milliseconds 500
        $state=[pscustomobject][ordered]@{schemaVersion=2;operationId=$OperationId;port=$port;sessionId='pending';driverPid=[int]$process.Id;driverStartedAt=$process.StartTime.ToUniversalTime().ToString('o');driverPath=$driverPath;applicationId=$applicationId;debugPort=$debugPort}
        $response=Invoke-WorkerWebDriverRequest $state POST '/session' ([ordered]@{capabilities=[ordered]@{alwaysMatch=[ordered]@{browserName='MicrosoftEdge';'ms:edgeOptions'=[ordered]@{debuggerAddress=("127.0.0.1:$debugPort")}}}})
        $sessionId=[string](Get-WorkerProperty (Get-WorkerProperty $response 'value') 'sessionId')
        if($sessionId-notmatch'^[A-Za-z0-9-]{1,256}$'){Throw-WorkerError 'UI_SESSION_START_FAILED' 'The fixed WebDriver session identity is invalid.'}
        $state.sessionId=$sessionId;[IO.File]::WriteAllText((Get-WorkerWebDriverStatePath $OperationId),(($state|ConvertTo-Json -Depth 20 -Compress)+"`n"),$script:Utf8NoBom)
        $record=New-WorkerProcessIdentity $process $OperationId '__webdriver__' $driverPath;$started=$true
        return New-WorkerStepResult 'passed' 'The owned loopback-only fixed WebDriver session started.' ([pscustomobject]@{sessionOwned=$true;loopbackOnly=$true;application=$applicationId;token=Get-WorkerTokenProjection $Token}) $record
    }
    finally{
        if(-not$started-and-not[Hcr.WorkerProcessHandle]::TerminateAndWait($driverHandle,125,5000)){Throw-WorkerError 'UI_DRIVER_CONTAINMENT_FAILED' 'A failed UI-session start left an uncontained driver process.'}
        $process.Dispose()
    }
}

function Invoke-WorkerUiStep {
    param([Parameter(Mandatory=$true)][object]$Step,[Parameter(Mandatory=$true)][object]$Input,[Parameter(Mandatory=$true)][string]$OperationId,[Parameter(Mandatory=$true)][object]$Token)
    $type=[string](Get-WorkerProperty $Step 'type');$state=Read-WorkerWebDriverState $OperationId
    if($type-eq'stopUiSession'){
        $driver=Get-Process -Id ([int]$state.driverPid) -ErrorAction SilentlyContinue
        if($null-eq$driver){
            return New-WorkerStepResult 'passed' 'The owned fixed WebDriver process had already exited.' ([pscustomobject]@{sessionOwned=$true;sessionDeleteSucceeded=$false;driverContained=$true;driverAlreadyExited=$true;token=Get-WorkerTokenProjection $Token})
        }
        $driverHandle=[IntPtr]$driver.Handle
        $actual=Get-WorkerProcessPath $driver
        $started=$driver.StartTime.ToUniversalTime().ToString('o')
        if(-not$actual.Equals([string]$state.driverPath,[StringComparison]::OrdinalIgnoreCase)-or$started-ne[string]$state.driverStartedAt){$driver.Dispose();Throw-WorkerError 'UI_DRIVER_IDENTITY_DRIFT' 'The owned driver process identity changed.'}
        $sessionDeleteSucceeded=$false;$sessionDeleteError=$null
        $stepTimeoutMilliseconds=[int](Get-WorkerProperty $Step 'timeoutSeconds' 1)*1000
        $protocolTimeoutMilliseconds=[Math]::Max(100,[Math]::Min(2000,$stepTimeoutMilliseconds-600))
        try{
            try{
                [void](Invoke-WorkerWebDriverRequest $state DELETE ("/session/{0}"-f$state.sessionId) $null $protocolTimeoutMilliseconds)
                $sessionDeleteSucceeded=$true
            }
            catch{$sessionDeleteError=Get-WorkerErrorCode $_.Exception}
        }
        finally{
            $driverContained=[Hcr.WorkerProcessHandle]::TerminateAndWait($driverHandle,0,500)
            $driver.Dispose()
            if(-not$driverContained){Throw-WorkerError 'UI_DRIVER_STOP_FAILED' 'The exact owned driver process did not stop.'}
        }
        $summary=if($sessionDeleteSucceeded){'The owned fixed WebDriver session and driver stopped.'}else{'The fixed session DELETE failed, but the exact owned WebDriver process was contained.'}
        return New-WorkerStepResult 'passed' $summary ([pscustomobject]@{sessionOwned=$true;sessionDeleteSucceeded=$sessionDeleteSucceeded;sessionDeleteError=$sessionDeleteError;driverContained=$true;driverAlreadyExited=$false;token=Get-WorkerTokenProjection $Token})
    }
    if($type-eq'captureUiScreenshot'){$name=[string](Get-WorkerProperty $Step 'evidenceName');if($name-notmatch'^[a-z0-9]+(?:-[a-z0-9]+)*$'){Throw-WorkerError 'UI_EVIDENCE_NAME_INVALID' 'The screenshot evidence name is invalid.'};$response=Invoke-WorkerWebDriverRequest $state GET ("/session/{0}/screenshot"-f$state.sessionId);$base64=[string](Get-WorkerProperty $response 'value');$bytes=[Convert]::FromBase64String($base64);if($bytes.Length-gt16MB){Throw-WorkerError 'UI_SCREENSHOT_TOO_LARGE' 'The UI screenshot exceeded its bound.'};$root=Initialize-WorkerDirectoryTree (Get-WorkerOperationRoot $OperationId) 'screenshots';$path=Join-Path $root ($name+'.png');[IO.File]::WriteAllBytes($path,$bytes);return New-WorkerStepResult 'passed' 'The bounded UI screenshot was captured.' ([pscustomobject]@{evidenceName=$name;sizeBytes=$bytes.Length;sha256=Get-WorkerSha256File $path;token=Get-WorkerTokenProjection $Token})}
    $element=Get-WorkerWebDriverElement $state ([string](Get-WorkerProperty $Step 'testId'));$base=("/session/{0}/element/{1}"-f$state.sessionId,$element)
    if($type-eq'uiClick'){[void](Invoke-WorkerWebDriverRequest $state POST ($base+'/click') ([ordered]@{}))}
    elseif($type-eq'uiSetText'){[void](Invoke-WorkerWebDriverRequest $state POST ($base+'/clear') ([ordered]@{}));$text=[string](Get-WorkerProperty $Step 'text');if($text.Length-gt4096){Throw-WorkerError 'UI_TEXT_TOO_LONG' 'The fixed non-secret UI text exceeds its bound.'};[void](Invoke-WorkerWebDriverRequest $state POST ($base+'/value') ([ordered]@{text=$text;value=@($text)}))}
    elseif($type-eq'uiPressKey'){$keys=@{Enter=[char]0xE007;Escape=[char]0xE00C;Tab=[char]0xE004;ArrowUp=[char]0xE013;ArrowDown=[char]0xE015;ArrowLeft=[char]0xE012;ArrowRight=[char]0xE014};$key=[string](Get-WorkerProperty $Step 'key');if(-not$keys.ContainsKey($key)){Throw-WorkerError 'UI_KEY_FORBIDDEN' 'The key is outside the closed set.'};$value=[string]$keys[$key];[void](Invoke-WorkerWebDriverRequest $state POST ($base+'/value') ([ordered]@{text=$value;value=@($value)}))}
    elseif($type-eq'uiSelectOption'){$value=[string](Get-WorkerProperty $Step 'value');if($value.Length-gt1024){Throw-WorkerError 'UI_OPTION_INVALID' 'The option literal exceeds its bound.'};$options=Invoke-WorkerWebDriverRequest $state POST ($base+'/elements') ([ordered]@{using='tag name';value='option'});$matched=$null;foreach($option in @((Get-WorkerProperty $options 'value' @()))){$property=@($option.PSObject.Properties|Where-Object{$_.Name-eq'element-6066-11e4-a52e-4f735466cecf'});if($property.Count-ne1){continue};$optionId=[string]$property[0].Value;$textResponse=Invoke-WorkerWebDriverRequest $state GET ("/session/{0}/element/{1}/text"-f$state.sessionId,$optionId);if([string](Get-WorkerProperty $textResponse 'value')-ceq$value){if($null-ne$matched){Throw-WorkerError 'UI_OPTION_AMBIGUOUS' 'The fixed option literal matched more than once.'};$matched=$optionId}};if($null-eq$matched){Throw-WorkerError 'UI_OPTION_NOT_FOUND' 'The fixed option literal was not found.'};[void](Invoke-WorkerWebDriverRequest $state POST ("/session/{0}/element/{1}/click"-f$state.sessionId,$matched) ([ordered]@{}))}
    elseif($type-eq'uiUploadFixture'){$fixtureId=[string](Get-WorkerProperty $Step 'fixtureId');$matches=@((Get-WorkerProperty $Input 'fixtures' @())|Where-Object{[string](Get-WorkerProperty $_ 'id')-eq$fixtureId});if($matches.Count-ne1){Throw-WorkerError 'UI_FIXTURE_INVALID' 'The declared fixture identity is unavailable.'};$destination=[string](Get-WorkerProperty $matches[0] 'guestDestination');$prefix="operations\$OperationId\";if(-not$destination.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){Throw-WorkerError 'UI_FIXTURE_INVALID' 'The staged fixture is outside the operation.'};$path=Resolve-WorkerPath (Join-Path (Get-WorkerOperationRoot $OperationId) 'staging') $destination.Substring($prefix.Length);if((Get-WorkerSha256File $path)-ne[string](Get-WorkerProperty $matches[0] 'guestSha256')){Throw-WorkerError 'UI_FIXTURE_HASH_MISMATCH' 'The staged UI fixture hash changed.'};[void](Invoke-WorkerWebDriverRequest $state POST ($base+'/value') ([ordered]@{text=$path;value=@($path)}))}
    elseif($type-eq'assertUiElement'){$assertion=[string](Get-WorkerProperty $Step 'state');$actual=$null;$expected=[string](Get-WorkerProperty $Step 'expected');if(@('visible','hidden')-contains$assertion){$actual=[bool](Get-WorkerProperty (Invoke-WorkerWebDriverRequest $state GET ($base+'/displayed')) 'value');$passed=if($assertion-eq'visible'){$actual}else{-not$actual}}elseif(@('enabled','disabled')-contains$assertion){$actual=[bool](Get-WorkerProperty (Invoke-WorkerWebDriverRequest $state GET ($base+'/enabled')) 'value');$passed=if($assertion-eq'enabled'){$actual}else{-not$actual}}elseif(@('checked','unchecked')-contains$assertion){$actual=[bool](Get-WorkerProperty (Invoke-WorkerWebDriverRequest $state GET ($base+'/selected')) 'value');$passed=if($assertion-eq'checked'){$actual}else{-not$actual}}elseif(@('textEquals','textContains')-contains$assertion){$actual=[string](Get-WorkerProperty (Invoke-WorkerWebDriverRequest $state GET ($base+'/text')) 'value');$passed=if($assertion-eq'textEquals'){$actual-ceq$expected}else{$actual.Contains($expected)}}elseif($assertion-eq'valueEquals'){$actual=[string](Get-WorkerProperty (Invoke-WorkerWebDriverRequest $state GET ($base+'/property/value')) 'value');$passed=$actual-ceq$expected}else{Throw-WorkerError 'UI_ASSERTION_FORBIDDEN' 'The UI assertion is outside the closed set.'};return New-WorkerStepResult $(if($passed){'passed'}else{'failed'}) 'The closed data-testid UI assertion was evaluated.' ([pscustomobject]@{state=$assertion;matched=[bool]$passed;token=Get-WorkerTokenProjection $Token})}
    else{Throw-WorkerError 'UI_STEP_TYPE_FORBIDDEN' 'The fixed UI dispatcher rejected the step type.'}
    return New-WorkerStepResult 'passed' 'The closed data-testid UI step completed.' ([pscustomobject]@{testId=[string](Get-WorkerProperty $Step 'testId');stepType=$type;token=Get-WorkerTokenProjection $Token})
}

function Invoke-WorkerStep {
    param(
        [Parameter(Mandatory = $true)][object]$Step,
        [Parameter(Mandatory = $true)][object]$Input,
        [Parameter(Mandatory = $true)][string]$OperationId,
        [Parameter(Mandatory = $true)][object]$Token,
        [bool]$Cleanup
    )

    $type = [string](Get-WorkerProperty $Step 'type')
    $schemaVersion = [int](Get-WorkerProperty $Input 'schemaVersion' 1)
    $allowed = if ($schemaVersion -eq 2) {
        if ($Cleanup) { $script:AllowedCleanupTypesV2 } else { $script:AllowedStepTypesV2 }
    }
    elseif ($Cleanup) { $script:AllowedCleanupTypes } else { $script:AllowedStepTypes }
    if ($allowed -notcontains $type) {
        Throw-WorkerError 'GUEST_STEP_TYPE_FORBIDDEN' 'The fixed guest worker rejected the step type.'
    }
    $timeout = [int](Get-WorkerProperty $Step 'timeoutSeconds' 0)
    $maximum = if ($Cleanup) { 120 } else { 900 }
    if ($timeout -lt 1 -or $timeout -gt $maximum) {
        Throw-WorkerError 'GUEST_STEP_TIMEOUT_INVALID' 'The fixed guest worker rejected the timeout.'
    }

    if ($type -eq 'stopApplication') {
        return Invoke-WorkerStopApplication $Step $Input $OperationId $Token $Cleanup
    }
    if ($type -eq 'acquireWebDriver') {
        return Invoke-WorkerAcquireWebDriver $Input $OperationId $Token
    }
    if ($type -eq 'startUiSession') {
        return Invoke-WorkerStartUiSession $Step $Input $OperationId $Token
    }
    if (@(
        'stopUiSession', 'uiClick', 'uiSetText', 'uiPressKey',
        'uiSelectOption', 'uiUploadFixture', 'assertUiElement',
        'captureUiScreenshot'
    ) -contains $type) {
        return Invoke-WorkerUiStep $Step $Input $OperationId $Token
    }
    if ($type -eq 'wait') {
        $milliseconds = [Math]::Max(1, ($timeout * 1000) - 250)
        Start-Sleep -Milliseconds $milliseconds
        return New-WorkerStepResult 'passed' 'The bounded declarative wait completed.' `
            ([pscustomobject]@{ waitedMilliseconds = $milliseconds; token = Get-WorkerTokenProjection $Token })
    }
    if ($type -eq 'deployPortable') {
        return Invoke-WorkerDeployPortable $Step $Input $OperationId $Token
    }
    if ($type -eq 'installPackage') {
        $application = Get-WorkerApplication $Input ([string](Get-WorkerProperty $Step 'application'))
        $artifactPath = Resolve-WorkerStagedArtifact $Input $OperationId
        $installerType = [string](Get-WorkerProperty $application 'installerType')
        $filePath = $null
        $arguments = @()
        if ($installerType -eq 'nsis') {
            $filePath = $artifactPath
            $arguments = @('/S', '/CURRENTUSER')
        }
        elseif ($installerType -eq 'msi') {
            $filePath = Join-Path $env:SystemRoot 'System32\msiexec.exe'
            $arguments = @('/i', ('"{0}"' -f $artifactPath), '/qn', '/norestart', 'ALLUSERS=2', 'MSIINSTALLPERUSER=1')
        }
        else {
            Throw-WorkerError 'GUEST_INSTALLER_TYPE_FORBIDDEN' 'The fixed installer type is not supported.'
        }
        $execution = Invoke-WorkerBoundedProcess $filePath $arguments $timeout
        if ([bool]$execution.timedOut) {
            return New-WorkerStepResult 'failed' 'The fixed package installer timed out.' `
                ([pscustomobject]@{ installerType = $installerType; token = Get-WorkerTokenProjection $Token }) $null $true
        }
        $passed = [int]$execution.exitCode -eq 0
        return New-WorkerStepResult $(if ($passed) { 'passed' } else { 'failed' }) `
            $(if ($passed) { 'The fixed current-user install completed.' } else { 'The fixed current-user installer returned a nonzero exit code.' }) `
            ([pscustomobject]@{
                installerType = $installerType
                exitCode = [int]$execution.exitCode
                artifactSha256 = Get-WorkerSha256File $artifactPath
                token = Get-WorkerTokenProjection $Token
            })
    }
    if ($type -eq 'launchApplication') {
        $applicationId = [string](Get-WorkerProperty $Step 'application')
        $application = Get-WorkerApplication $Input $applicationId
        $executable = Get-WorkerApplicationPath $application $Input
        if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
            return New-WorkerStepResult 'failed' 'The declared application executable does not exist.' `
                ([pscustomobject]@{ application = $applicationId; token = Get-WorkerTokenProjection $Token })
        }
        $item = Get-Item -LiteralPath $executable -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Throw-WorkerError 'GUEST_EXECUTABLE_REPARSE_FORBIDDEN' 'The declared executable is a reparse point.'
        }
        $portableLaunch = $schemaVersion -eq 2 -and
            (Get-WorkerProperty $application 'packageKind') -eq 'portableZip'
        $arguments = if ($portableLaunch) { @('--portable') } else { @() }
        $uiDebugPort = if ($portableLaunch) { Get-WorkerLoopbackEphemeralPort } else { $null }
        $priorWebView2Arguments = $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS
        try {
            if ($portableLaunch) {
                $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = "--remote-debugging-port=$uiDebugPort"
            }
            $process = if ($arguments.Count -gt 0) {
                Start-Process -FilePath $executable -ArgumentList $arguments -PassThru -WindowStyle Hidden -ErrorAction Stop
            }
            else {
                Start-Process -FilePath $executable -PassThru -WindowStyle Hidden -ErrorAction Stop
            }
        }
        finally {
            $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = $priorWebView2Arguments
        }
        Start-Sleep -Milliseconds 250
        $process.Refresh()
        if ($process.HasExited) {
            return New-WorkerStepResult 'failed' 'The declared application exited during launch verification.' `
                ([pscustomobject]@{ exitCode = [int]$process.ExitCode; token = Get-WorkerTokenProjection $Token })
        }
        $recorded = New-WorkerProcessIdentity $process $OperationId $applicationId $executable
        if ($portableLaunch) {
            $recorded | Add-Member -NotePropertyName uiDebugPort -NotePropertyValue $uiDebugPort -Force
        }
        return New-WorkerStepResult 'passed' 'The declared application launched under the standard test user.' `
            ([pscustomobject]@{ pid = $recorded.pid; identity = $recorded.identity; token = Get-WorkerTokenProjection $Token }) `
            $recorded
    }
    if ($type -eq 'uninstallPackage') {
        $application = Get-WorkerApplication $Input ([string](Get-WorkerProperty $Step 'application'))
        $executable = Get-WorkerApplicationPath $application $Input
        $applicationDirectory = Split-Path -Parent $executable
        $entries = @(Get-WorkerUninstallEntries | Where-Object {
            Test-WorkerEntryMatchesApplication $_ $applicationDirectory $executable
        })
        $discovery = [string](Get-WorkerProperty $application 'uninstallerDiscovery')
        $filePath = $null
        $arguments = @()
        if ($discovery -eq 'msiProduct') {
            $matches = @($entries | Where-Object {
                [int](Get-WorkerProperty $_ 'windowsInstaller' 0) -eq 1 -and
                [string](Get-WorkerProperty $_ 'keyName') -match '^\{[0-9A-Fa-f-]{36}\}$'
            })
            if ($matches.Count -ne 1) {
                return New-WorkerStepResult 'failed' 'A unique fixed MSI product identity was not found.' `
                    ([pscustomobject]@{ candidateCount = $matches.Count; token = Get-WorkerTokenProjection $Token })
            }
            $filePath = Join-Path $env:SystemRoot 'System32\msiexec.exe'
            $arguments = @('/x', [string](Get-WorkerProperty $matches[0] 'keyName'), '/qn', '/norestart')
        }
        elseif ($discovery -eq 'hkcuUninstall') {
            $targets = @($entries | ForEach-Object {
                Resolve-WorkerNsisUninstaller $_ $applicationDirectory
            } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
            if ($targets.Count -ne 1) {
                return New-WorkerStepResult 'failed' 'A unique constrained HKCU uninstaller was not found.' `
                    ([pscustomobject]@{ candidateCount = $targets.Count; token = Get-WorkerTokenProjection $Token })
            }
            $filePath = [string]$targets[0]
            $arguments = @('/S')
        }
        else {
            Throw-WorkerError 'GUEST_UNINSTALL_DISCOVERY_FORBIDDEN' 'The fixed uninstall discovery type is unsupported.'
        }
        $execution = Invoke-WorkerBoundedProcess $filePath $arguments $timeout
        if ([bool]$execution.timedOut) {
            return New-WorkerStepResult 'failed' 'The fixed package uninstaller timed out.' `
                ([pscustomobject]@{ discovery = $discovery; token = Get-WorkerTokenProjection $Token }) $null $true
        }
        $passed = [int]$execution.exitCode -eq 0
        return New-WorkerStepResult $(if ($passed) { 'passed' } else { 'failed' }) `
            $(if ($passed) { 'The constrained current-user uninstall completed.' } else { 'The constrained uninstaller returned a nonzero exit code.' }) `
            ([pscustomobject]@{ discovery = $discovery; exitCode = [int]$execution.exitCode; token = Get-WorkerTokenProjection $Token })
    }
    if (@('assertFile', 'assertShortcut') -contains $type) {
        $relative = [string](Get-WorkerProperty $Step 'path')
        $path = Resolve-WorkerPath ([string]$env:USERPROFILE) $relative
        $present = Test-Path -LiteralPath $path -PathType Leaf
        $passed = Test-WorkerExpectedPresence $Step $present
        return New-WorkerStepResult $(if ($passed) { 'passed' } else { 'failed' }) `
            $(if ($passed) { 'The declarative file-presence assertion matched.' } else { 'The declarative file-presence assertion did not match.' }) `
            ([pscustomobject]@{ relativePath = $relative.Replace('\\', '/'); present = $present; token = Get-WorkerTokenProjection $Token })
    }
    if ($type -eq 'assertRegistry') {
        $relative = [string](Get-WorkerProperty $Step 'registryPath')
        if (-not (Test-WorkerSafeRelativePath $relative)) {
            Throw-WorkerError 'GUEST_REGISTRY_PATH_INVALID' 'The HKCU-relative registry path is invalid.'
        }
        $registryPath = 'HKCU:\' + $relative.Replace('/', '\')
        $keyPresent = Test-Path -LiteralPath $registryPath
        $name = [string](Get-WorkerProperty $Step 'registryName')
        $valuePresent = $false
        $actual = $null
        if ($keyPresent -and -not [string]::IsNullOrWhiteSpace($name)) {
            try {
                $properties = Get-ItemProperty -LiteralPath $registryPath -Name $name -ErrorAction Stop
                $actual = Get-WorkerProperty $properties $name
                $valuePresent = $true
            }
            catch { $valuePresent = $false }
        }
        $passed = if ([string]::IsNullOrWhiteSpace($name)) {
            Test-WorkerExpectedPresence $Step $keyPresent
        }
        elseif (Test-WorkerProperty $Step 'expected') {
            $valuePresent -and [object]::Equals($actual, (Get-WorkerProperty $Step 'expected'))
        }
        else { $valuePresent }
        return New-WorkerStepResult $(if ($passed) { 'passed' } else { 'failed' }) `
            $(if ($passed) { 'The HKCU assertion matched.' } else { 'The HKCU assertion did not match.' }) `
            ([pscustomobject]@{ keyPresent = $keyPresent; valuePresent = $valuePresent; registryName = $name; token = Get-WorkerTokenProjection $Token })
    }
    if ($type -eq 'assertProcess') {
        $applicationId = [string](Get-WorkerProperty $Step 'application')
        $processName = [string](Get-WorkerProperty $Step 'processName')
        if (-not [string]::IsNullOrWhiteSpace($applicationId)) {
            $processName = Get-WorkerProcessName (Get-WorkerApplication $Input $applicationId)
        }
        if ($processName -notmatch '^[a-zA-Z0-9._-]+$') {
            Throw-WorkerError 'GUEST_PROCESS_NAME_INVALID' 'The declarative process name is invalid.'
        }
        $processName = [IO.Path]::GetFileNameWithoutExtension($processName)
        $processes = @(Get-Process -Name $processName -ErrorAction SilentlyContinue | Select-Object -First 64)
        $present = $processes.Count -gt 0
        $passed = Test-WorkerExpectedPresence $Step $present
        return New-WorkerStepResult $(if ($passed) { 'passed' } else { 'failed' }) `
            $(if ($passed) { 'The process assertion matched.' } else { 'The process assertion did not match.' }) `
            ([pscustomobject]@{ processName = $processName; pids = @($processes | ForEach-Object { [int]$_.Id }); token = Get-WorkerTokenProjection $Token })
    }
    if ($type -eq 'assertModule') {
        $application = Get-WorkerApplication $Input ([string](Get-WorkerProperty $Step 'application'))
        $executable = Get-WorkerApplicationPath $application $Input
        $moduleRelative = [string](Get-WorkerProperty $Step 'moduleRelativePath')
        $modulePath = Resolve-WorkerPath (Split-Path -Parent $executable) $moduleRelative
        $loaded = $false
        $processName = Get-WorkerProcessName $application
        foreach ($process in @(Get-Process -Name $processName -ErrorAction SilentlyContinue | Select-Object -First 32)) {
            try {
                if (@($process.Modules | Where-Object {
                    [string]$_.FileName -eq $modulePath
                }).Count -gt 0) { $loaded = $true; break }
            }
            catch {
                # Inaccessible module inventories do not become passed evidence.
            }
        }
        $passed = Test-WorkerExpectedPresence $Step $loaded
        return New-WorkerStepResult $(if ($passed) { 'passed' } else { 'failed' }) `
            $(if ($passed) { 'The loaded-module assertion matched.' } else { 'The loaded-module assertion did not match.' }) `
            ([pscustomobject]@{ moduleRelativePath = $moduleRelative.Replace('\\', '/'); loaded = $loaded; token = Get-WorkerTokenProjection $Token })
    }
    if ($type -eq 'assertPort') {
        $port = [int](Get-WorkerProperty $Step 'port')
        if ($port -lt 1 -or $port -gt 65535) {
            Throw-WorkerError 'GUEST_PORT_INVALID' 'The declarative TCP port is invalid.'
        }
        $ip = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
        $present = @($ip.GetActiveTcpListeners() | Where-Object { $_.Port -eq $port }).Count -gt 0
        $passed = Test-WorkerExpectedPresence $Step $present
        return New-WorkerStepResult $(if ($passed) { 'passed' } else { 'failed' }) `
            $(if ($passed) { 'The TCP-listener assertion matched.' } else { 'The TCP-listener assertion did not match.' }) `
            ([pscustomobject]@{ port = $port; listening = $present; token = Get-WorkerTokenProjection $Token })
    }
    if (@('writeSentinel', 'assertSentinel') -contains $type) {
        $sentinelId = [string](Get-WorkerProperty $Step 'sentinelId')
        if ($sentinelId -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
            Throw-WorkerError 'GUEST_SENTINEL_INVALID' 'The declarative sentinel identity is invalid.'
        }
        $sentinelRoot = Initialize-WorkerDirectoryTree `
            ([string]$env:LOCALAPPDATA) `
            ("Codex\hyperv-clean-room\v1\sentinels\{0}" -f $OperationId)
        $sentinelPath = Resolve-WorkerPath $sentinelRoot ($sentinelId + '.json')
        if ($type -eq 'writeSentinel') {
            $document = [ordered]@{
                schemaVersion = 1
                operationId = $OperationId
                sentinelId = $sentinelId
                userSid = [string](Get-WorkerProperty $Token 'sid')
                createdAt = [DateTimeOffset]::UtcNow.ToString('o')
            }
            [IO.File]::WriteAllText(
                $sentinelPath,
                (($document | ConvertTo-Json -Depth 5 -Compress) + "`n"),
                $script:Utf8NoBom
            )
            return New-WorkerStepResult 'passed' 'The operation-scoped sentinel was written.' `
                ([pscustomobject]@{ sentinelId = $sentinelId; token = Get-WorkerTokenProjection $Token })
        }
        $valid = $false
        if (Test-Path -LiteralPath $sentinelPath -PathType Leaf) {
            try {
                $sentinel = Get-Content -LiteralPath $sentinelPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
                $valid = [string](Get-WorkerProperty $sentinel 'operationId') -eq $OperationId -and
                    [string](Get-WorkerProperty $sentinel 'sentinelId') -eq $sentinelId
            }
            catch { $valid = $false }
        }
        $passed = Test-WorkerExpectedPresence $Step $valid
        return New-WorkerStepResult $(if ($passed) { 'passed' } else { 'failed' }) `
            $(if ($passed) { 'The operation-scoped sentinel assertion matched.' } else { 'The operation-scoped sentinel assertion did not match.' }) `
            ([pscustomobject]@{ sentinelId = $sentinelId; presentAndBound = $valid; token = Get-WorkerTokenProjection $Token })
    }
    Throw-WorkerError 'GUEST_STEP_TYPE_FORBIDDEN' 'The fixed guest worker has no handler for the step.'
}

function Get-WorkerPathSummary {
    param([AllowNull()][object]$Value)

    $text = [string]$Value
    $entries = @($text -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    return [pscustomobject][ordered]@{
        entryCount = $entries.Count
        hasEmptyEntry = [bool]($text -match '(^;|;;|;$)')
        containsNonAscii = [bool]($text -match '[^\x00-\x7f]')
        sha256 = Get-WorkerSha256Text $text
    }
}

function Get-WorkerInstalledProducts {
    $products = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @(Get-WorkerUninstallEntries | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string](Get-WorkerProperty $_ 'displayName'))
    } | Sort-Object displayName | Select-Object -First 200)) {
        $products.Add([pscustomobject][ordered]@{
            displayName = [string](Get-WorkerProperty $entry 'displayName')
            installerKind = if ([int](Get-WorkerProperty $entry 'windowsInstaller' 0) -eq 1) { 'msi' } else { 'other' }
        })
    }
    return @($products | ForEach-Object { $_ })
}

function Get-WorkerWebView2Inventory {
    $versions = New-Object System.Collections.Generic.List[string]
    foreach ($root in @(
        'HKCU:\Software\Microsoft\EdgeUpdate\Clients',
        'HKLM:\Software\Microsoft\EdgeUpdate\Clients',
        'HKLM:\Software\WOW6432Node\Microsoft\EdgeUpdate\Clients'
    )) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | Select-Object -First 64)) {
            try {
                $value = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                $name = [string](Get-WorkerProperty $value 'name')
                $version = [string](Get-WorkerProperty $value 'pv')
                if ($name -match 'WebView2' -and -not [string]::IsNullOrWhiteSpace($version)) {
                    $versions.Add($version)
                }
            }
            catch { }
        }
    }
    return [pscustomobject][ordered]@{
        installed = $versions.Count -gt 0
        versions = @($versions | Select-Object -Unique | Select-Object -First 16)
    }
}

function Invoke-WorkerInspectGuest {
    param([Parameter(Mandatory = $true)][object]$Token)

    $currentVersion = Get-ItemProperty `
        -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' `
        -ErrorAction SilentlyContinue
    $userPath = $null
    $systemPath = $null
    try { $userPath = (Get-ItemProperty -LiteralPath 'HKCU:\Environment' -Name Path -ErrorAction Stop).Path }
    catch { $userPath = '' }
    try {
        $systemPath = (Get-ItemProperty `
            -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' `
            -Name Path `
            -ErrorAction Stop).Path
    }
    catch { $systemPath = '' }
    $dpi = $null
    try {
        $desktop = Get-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -ErrorAction Stop
        $dpi = [pscustomobject][ordered]@{
            logPixels = Get-WorkerProperty $desktop 'LogPixels'
            scalingEnabled = [bool]([int](Get-WorkerProperty $desktop 'Win8DpiScaling' 0) -ne 0)
            interactiveOutcomeRequiresManualAttestation = $true
        }
    }
    catch {
        $dpi = [pscustomobject][ordered]@{
            logPixels = $null
            scalingEnabled = $false
            interactiveOutcomeRequiresManualAttestation = $true
        }
    }
    $commands = @('git', 'dotnet', 'node', 'npm', 'python', 'py', 'devenv', 'msbuild')
    $commandInventory = @($commands | ForEach-Object {
        [pscustomobject][ordered]@{
            name = $_
            available = $null -ne (Get-Command $_ -CommandType Application -ErrorAction SilentlyContinue)
        }
    })
    $products = @(Get-WorkerInstalledProducts)
    $webView2 = Get-WorkerWebView2Inventory
    $build = [string](Get-WorkerProperty $currentVersion 'CurrentBuildNumber' ([Environment]::OSVersion.Version.Build))
    $ubr = Get-WorkerProperty $currentVersion 'UBR'
    if ($null -ne $ubr -and -not [string]::IsNullOrWhiteSpace([string]$ubr)) {
        $build = "$build.$ubr"
    }
    $architecture = switch ([string]$env:PROCESSOR_ARCHITECTURE) {
        'AMD64' { 'x64' }
        'x64' { 'x64' }
        default {
            Throw-WorkerError 'GUEST_ARCHITECTURE_UNSUPPORTED' 'The fixed guest worker requires x64 Windows.'
        }
    }
    return [pscustomobject][ordered]@{
        windowsEdition = [string](Get-WorkerProperty $currentVersion 'ProductName' ([Environment]::OSVersion.VersionString))
        windowsBuild = $build
        displayVersion = [string](Get-WorkerProperty $currentVersion 'DisplayVersion')
        architecture = $architecture
        userName = [string](Get-WorkerProperty $Token 'userName')
        userSid = [string](Get-WorkerProperty $Token 'sid')
        isAdministrator = [bool](Get-WorkerProperty $Token 'isAdministrator' $true)
        hasAdministratorsSid = [bool](Get-WorkerProperty $Token 'hasAdministratorsSid' $true)
        isElevated = [bool](Get-WorkerProperty $Token 'isElevated' $true)
        tokenIntegrity = [string](Get-WorkerProperty $Token 'tokenIntegrity' 'unknown')
        profilePath = [string](Get-WorkerProperty $Token 'profilePath')
        profilePathContainsNonAscii = [bool](Get-WorkerProperty $Token 'profilePathContainsNonAscii' $false)
        dpi = $dpi
        installedProducts = $products
        webView2 = $webView2
        forbiddenDeveloperCommands = $commandInventory
        userPathSummary = Get-WorkerPathSummary $userPath
        systemPathSummary = Get-WorkerPathSummary $systemPath
        configuredProductTraces = [pscustomobject][ordered]@{
            currentUserUninstallEntryCount = $products.Count
            webView2Installed = [bool]$webView2.installed
        }
    }
}

function Write-WorkerResult {
    param([Parameter(Mandatory = $true)][object]$Document)

    $bytes = $script:Utf8NoBom.GetBytes(
        (($Document | ConvertTo-Json -Depth 30 -Compress) + "`n")
    )
    if ($bytes.Length -gt 1048576) {
        Throw-WorkerError 'GUEST_WORKER_OUTPUT_INVALID' 'The fixed worker result exceeds one MiB.'
    }
    $stream = [Console]::OpenStandardOutput()
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()
}

$exitCode = 0
try {
    $inputFull = [IO.Path]::GetFullPath($InputPath)
    $inputDirectory = Split-Path -Parent $inputFull
    if (-not (Test-Path -LiteralPath $inputFull -PathType Leaf) -or
        (Split-Path -Leaf $inputDirectory) -ne 'control' -or
        (Split-Path -Leaf $inputFull) -notmatch '^input-[a-f0-9]{32}\.json$') {
        Throw-WorkerError 'GUEST_WORKER_INPUT_INVALID' 'The fixed worker input path is not server controlled.'
    }
    $inputItem = Get-Item -LiteralPath $inputFull -Force
    if (($inputItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        $inputItem.Length -gt 1048576) {
        Throw-WorkerError 'GUEST_WORKER_INPUT_INVALID' 'The fixed worker input file is invalid.'
    }
    if ((Get-WorkerSha256File $inputFull) -ne $ExpectedInputSha256) {
        Throw-WorkerError 'GUEST_WORKER_INPUT_CHANGED' 'The fixed worker input hash changed before execution.'
    }
    $input = Get-Content -LiteralPath $inputFull -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $workerSchemaVersion = [int](Get-WorkerProperty $input 'schemaVersion' 0)
    if (@(1, 2) -notcontains $workerSchemaVersion) {
        Throw-WorkerError 'GUEST_WORKER_INPUT_INVALID' 'The fixed worker input version is unsupported.'
    }
    $operationId = [string](Get-WorkerProperty $input 'operationId')
    $operationRoot = Get-WorkerOperationRoot $operationId
    if ($operationId -ne $ExpectedOperationId -or
        [string](Get-WorkerProperty $input 'invocationId') -ne $InvocationId -or
        [string](Get-WorkerProperty $input 'mode') -ne $Mode -or
        -not (Test-WorkerPathWithin $inputFull $operationRoot)) {
        Throw-WorkerError 'GUEST_WORKER_SCOPE_INVALID' 'The fixed worker input is not bound to this invocation.'
    }
    Assert-WorkerNoReparseEscape $inputFull $operationRoot
    $token = Get-WorkerTokenEvidence
    $expectedSid = [string](Get-WorkerProperty $input 'expectedTestUserSid')
    if ([string]::IsNullOrWhiteSpace($expectedSid) -or
        [string](Get-WorkerProperty $token 'sid') -ne $expectedSid) {
        Throw-WorkerError 'GUEST_TEST_USER_MISMATCH' 'The worker token does not match the credential profile test-user SID.'
    }
    if ($Mode -ne 'InspectGuest' -and (
        [bool](Get-WorkerProperty $token 'isAdministrator' $true) -or
        [bool](Get-WorkerProperty $token 'hasAdministratorsSid' $true) -or
        [bool](Get-WorkerProperty $token 'isElevated' $true) -or
        [string](Get-WorkerProperty $token 'tokenIntegrity') -ne 'medium'
    )) {
        Throw-WorkerError 'GUEST_TEST_USER_PRIVILEGE_INVALID' 'The fixed worker requires a medium-integrity standard-user token.'
    }
    $data = if ($Mode -eq 'InspectGuest') {
        Invoke-WorkerInspectGuest $token
    }
    else {
        $step = Get-WorkerProperty $input 'step'
        try {
            Invoke-WorkerStep $step $input $operationId $token ($Mode -eq 'RunCleanupStep')
        }
        catch {
            $code = Get-WorkerErrorCode $_.Exception
            New-WorkerStepResult 'failed' "Fixed declarative guest step failed: $code." `
                ([pscustomobject]@{ errorCode = $code; token = Get-WorkerTokenProjection $token })
        }
    }
    Write-WorkerResult ([pscustomobject][ordered]@{
        workerSchemaVersion = $workerSchemaVersion
        operationId = $ExpectedOperationId
        invocationId = $InvocationId
        mode = $Mode
        inputSha256 = $ExpectedInputSha256
        ok = $true
        data = $data
    })
}
catch {
    $exitCode = 1
    try {
        Write-WorkerResult ([pscustomobject][ordered]@{
            workerSchemaVersion = if ($null -ne (Get-Variable -Name workerSchemaVersion -ErrorAction SilentlyContinue)) { $workerSchemaVersion } else { 1 }
            operationId = $ExpectedOperationId
            invocationId = $InvocationId
            mode = $Mode
            inputSha256 = $ExpectedInputSha256
            ok = $false
            error = [pscustomobject][ordered]@{
                code = Get-WorkerErrorCode $_.Exception
                message = 'The fixed guest worker failed without exposing guest details.'
            }
        })
    }
    catch {
        # The supervisor reports a bounded missing-output error.
    }
}
exit $exitCode

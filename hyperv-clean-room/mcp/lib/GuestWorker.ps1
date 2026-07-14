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
    param([Parameter(Mandatory = $true)][object]$Application)

    return Resolve-WorkerPath ([string]$env:USERPROFILE) `
        ([string](Get-WorkerProperty $Application 'executableRelativePath'))
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

    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList `
        -PassThru -WindowStyle Hidden -ErrorAction Stop
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

function Invoke-WorkerStep {
    param(
        [Parameter(Mandatory = $true)][object]$Step,
        [Parameter(Mandatory = $true)][object]$Input,
        [Parameter(Mandatory = $true)][string]$OperationId,
        [Parameter(Mandatory = $true)][object]$Token,
        [bool]$Cleanup
    )

    $type = [string](Get-WorkerProperty $Step 'type')
    $allowed = if ($Cleanup) { $script:AllowedCleanupTypes } else { $script:AllowedStepTypes }
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
    if ($type -eq 'wait') {
        $milliseconds = [Math]::Max(1, ($timeout * 1000) - 250)
        Start-Sleep -Milliseconds $milliseconds
        return New-WorkerStepResult 'passed' 'The bounded declarative wait completed.' `
            ([pscustomobject]@{ waitedMilliseconds = $milliseconds; token = Get-WorkerTokenProjection $Token })
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
        $executable = Get-WorkerApplicationPath $application
        if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
            return New-WorkerStepResult 'failed' 'The declared application executable does not exist.' `
                ([pscustomobject]@{ application = $applicationId; token = Get-WorkerTokenProjection $Token })
        }
        $item = Get-Item -LiteralPath $executable -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Throw-WorkerError 'GUEST_EXECUTABLE_REPARSE_FORBIDDEN' 'The declared executable is a reparse point.'
        }
        $process = Start-Process -FilePath $executable -PassThru -WindowStyle Hidden -ErrorAction Stop
        Start-Sleep -Milliseconds 250
        $process.Refresh()
        if ($process.HasExited) {
            return New-WorkerStepResult 'failed' 'The declared application exited during launch verification.' `
                ([pscustomobject]@{ exitCode = [int]$process.ExitCode; token = Get-WorkerTokenProjection $Token })
        }
        $recorded = New-WorkerProcessIdentity $process $OperationId $applicationId $executable
        return New-WorkerStepResult 'passed' 'The declared application launched under the standard test user.' `
            ([pscustomobject]@{ pid = $recorded.pid; identity = $recorded.identity; token = Get-WorkerTokenProjection $Token }) `
            $recorded
    }
    if ($type -eq 'uninstallPackage') {
        $application = Get-WorkerApplication $Input ([string](Get-WorkerProperty $Step 'application'))
        $executable = Get-WorkerApplicationPath $application
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
        $executable = Get-WorkerApplicationPath $application
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
    if ([int](Get-WorkerProperty $input 'schemaVersion' 0) -ne 1) {
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
        workerSchemaVersion = 1
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
            workerSchemaVersion = 1
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

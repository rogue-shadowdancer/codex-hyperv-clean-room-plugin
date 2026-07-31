function Get-HcrStateRoot {
    if (-not [string]::IsNullOrWhiteSpace($env:HCR_STATE_ROOT)) {
        if (-not (Test-HcrLocalAbsolutePath $env:HCR_STATE_ROOT)) {
            Throw-HcrError 'INVALID_STATE_ROOT' 'HCR_STATE_ROOT must be a local absolute path.'
        }
        return Get-HcrNormalizedPath $env:HCR_STATE_ROOT
    }
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        Throw-HcrError 'STATE_ROOT_UNAVAILABLE' 'LOCALAPPDATA is unavailable.'
    }
    return Get-HcrNormalizedPath (Join-Path $env:LOCALAPPDATA 'Codex\hyperv-clean-room\v1')
}

function Get-HcrCredentialRoot {
    if (-not [string]::IsNullOrWhiteSpace($env:HCR_CREDENTIAL_ROOT)) {
        if (-not (Test-HcrLocalAbsolutePath $env:HCR_CREDENTIAL_ROOT)) {
            Throw-HcrError 'INVALID_CREDENTIAL_ROOT' 'HCR_CREDENTIAL_ROOT must be a local absolute path.'
        }
        return Get-HcrNormalizedPath $env:HCR_CREDENTIAL_ROOT
    }
    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
        Throw-HcrError 'CREDENTIAL_ROOT_UNAVAILABLE' 'APPDATA is unavailable.'
    }
    return Get-HcrNormalizedPath (Join-Path $env:APPDATA 'Codex\hyperv-clean-room\credentials')
}

function Initialize-HcrLocalDirectoryPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$ErrorCode = 'INVALID_STATE_ROOT'
    )

    $normalized = Assert-HcrNoReparsePath $Path $ErrorCode -AllowMissing
    $volumeRoot = [IO.Path]::GetPathRoot($normalized)
    $relative = $normalized.Substring($volumeRoot.Length).TrimStart('\', '/')
    $current = $volumeRoot
    foreach ($segment in @($relative -split '[\\/]')) {
        if ([string]::IsNullOrWhiteSpace($segment)) { continue }
        $current = Join-Path $current $segment
        if (-not (Test-Path -LiteralPath $current)) {
            try { [void](New-Item -ItemType Directory -Path $current -ErrorAction Stop) }
            catch {
                if (-not (Test-Path -LiteralPath $current -PathType Container)) { throw }
            }
        }
        [void](Assert-HcrLocalDirectory $current $ErrorCode)
    }
    return $normalized
}

function Throw-HcrStateRootAccessDenied {
    Throw-HcrError `
        'STATE_ROOT_ACCESS_DENIED' `
        'The current MCP server token cannot initialize or access the state root.'
}

function Test-HcrStateAccessDeniedException {
    param([Parameter(Mandatory = $true)][Exception]$Exception)

    $current = $Exception
    while ($null -ne $current) {
        if ($current -is [UnauthorizedAccessException] -or
            $current -is [Security.SecurityException] -or
            (($current.HResult -band 0xffff) -eq 5)) {
            return $true
        }
        $current = $current.InnerException
    }
    return $false
}

function Assert-HcrWritableStateDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Assert-HcrAccessibleLocalDirectory `
        $Path `
        'INVALID_STATE_ROOT' `
        'STATE_ROOT_ACCESS_DENIED'
    $probe = Join-Path $item.FullName ('.hcr-access-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    $stream = $null
    try {
        $stream = New-Object IO.FileStream(
            $probe,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None,
            1,
            [IO.FileOptions]::DeleteOnClose
        )
        $stream.WriteByte(0)
    }
    catch {
        if (Test-HcrStateAccessDeniedException $_.Exception) {
            Throw-HcrStateRootAccessDenied
        }
        throw
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if (Test-Path `
                -LiteralPath $probe `
                -PathType Leaf `
                -ErrorAction SilentlyContinue) {
            Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        }
    }
    return $item
}

function Initialize-HcrStateStore {
    $root = Get-HcrStateRoot
    try {
        [void](Initialize-HcrLocalDirectoryPath $root)
        $requiredPaths = @($root)
        foreach ($relative in @('plans', 'operations', 'ownership', 'evidence-staging', 'locks')) {
            $path = Join-Path $root $relative
            [void](Initialize-HcrLocalDirectoryPath $path)
            $requiredPaths += $path
        }
        foreach ($requiredPath in $requiredPaths) {
            [void](Assert-HcrWritableStateDirectory $requiredPath)
        }
    }
    catch {
        if (Test-HcrStateAccessDeniedException $_.Exception) {
            Throw-HcrStateRootAccessDenied
        }
        throw
    }
    $script:HcrStateRoot = $root
    return $root
}

function Get-HcrStateSubpath {
    param(
        [Parameter(Mandatory = $true)][string]$Area,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($script:HcrStateRoot)) {
        [void](Initialize-HcrStateStore)
    }
    return Join-Path (Join-Path $script:HcrStateRoot $Area) $Name
}

function Test-HcrStateManagedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($script:HcrStateRoot)) { return $false }
    try { return Test-HcrPathWithin $Path $script:HcrStateRoot }
    catch { return $false }
}

function Invoke-HcrStateIo {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    if (-not (Test-HcrStateManagedPath $Path)) {
        Throw-HcrError 'INTERNAL_ERROR' 'A state I/O path escaped the managed state root.'
    }
    try { return & $Action }
    catch {
        if (Test-HcrStateAccessDeniedException $_.Exception) {
            Throw-HcrStateRootAccessDenied
        }
        throw
    }
}

function Initialize-HcrStateManagedDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    return Invoke-HcrStateIo $Path {
        $normalized = Initialize-HcrLocalDirectoryPath $Path 'STATE_INTEGRITY_ERROR'
        [void](Assert-HcrWritableStateDirectory $normalized)
        return $normalized
    }
}

function Test-HcrStatePathExists {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateSet('Any', 'Container', 'Leaf')][string]$PathType = 'Any'
    )

    return Invoke-HcrStateIo $Path {
        if ($PathType -eq 'Any') {
            return Test-Path -LiteralPath $Path -ErrorAction Stop
        }
        return Test-Path -LiteralPath $Path -PathType $PathType -ErrorAction Stop
    }
}

function Get-HcrStateItems {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [switch]$Recurse,
        [switch]$File
    )

    return @(Invoke-HcrStateIo $Directory {
        Get-ChildItem `
            -LiteralPath $Directory `
            -Force `
            -Recurse:$Recurse `
            -File:$File `
            -ErrorAction Stop
    })
}

function Assert-HcrStateRegularFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$ErrorCode = 'STATE_INTEGRITY_ERROR'
    )

    return Invoke-HcrStateIo $Path {
        Assert-HcrRegularLocalFile $Path $ErrorCode
    }
}

function Get-HcrStateFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return Invoke-HcrStateIo $Path { Get-HcrSha256File $Path }
}

function Copy-HcrStateFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not (Test-HcrStateManagedPath $Source)) {
        Throw-HcrError 'INTERNAL_ERROR' 'An evidence source escaped the managed state root.'
    }
    try {
        Copy-Item -LiteralPath $Source -Destination $Destination -ErrorAction Stop
    }
    catch {
        $copyException = $_.Exception
        try {
            # Reopen the source after a failed copy. Persistent source ACL
            # denial is a state-root failure; destination failures retain the
            # original output-path error instead of being misclassified.
            [void](Get-HcrStateFileSha256 $Source)
        }
        catch {
            if ($_.Exception.Data.Contains('HcrCode') -and
                [string]$_.Exception.Data['HcrCode'] -eq 'STATE_ROOT_ACCESS_DENIED') {
                throw
            }
        }
        throw $copyException
    }
}

function Test-HcrStateFileExists {
    param([Parameter(Mandatory = $true)][string]$Path)

    try { return Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction Stop }
    catch {
        if (Test-HcrStateAccessDeniedException $_.Exception) {
            Throw-HcrStateRootAccessDenied
        }
        throw
    }
}

function Get-HcrStateFiles {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Filter
    )

    try {
        [void](Assert-HcrAccessibleLocalDirectory `
            $Directory `
            'STATE_INTEGRITY_ERROR' `
            'STATE_ROOT_ACCESS_DENIED')
        return @(Get-ChildItem `
            -LiteralPath $Directory `
            -File `
            -Filter $Filter `
            -ErrorAction Stop)
    }
    catch {
        if (Test-HcrStateAccessDeniedException $_.Exception) {
            Throw-HcrStateRootAccessDenied
        }
        throw
    }
}

function Write-HcrJsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowNull()][object]$Value
    )

    $temporary = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    $backup = "$Path.$([Guid]::NewGuid().ToString('N')).bak"
    try {
        $parent = Split-Path -Parent $Path
        [void](Initialize-HcrLocalDirectoryPath $parent 'STATE_INTEGRITY_ERROR')
        if (Test-Path -LiteralPath $Path -ErrorAction Stop) {
            [void](Assert-HcrNoReparsePath $Path 'STATE_INTEGRITY_ERROR')
        }
        $json = (ConvertTo-HcrJson $Value 100) + "`n"
        [IO.File]::WriteAllText($temporary, $json, $script:HcrUtf8NoBom)
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [IO.File]::Replace($temporary, $Path, $backup)
            if (Test-Path -LiteralPath $backup -PathType Leaf) {
                Remove-Item -LiteralPath $backup -Force
            }
        }
        else {
            [IO.File]::Move($temporary, $Path)
        }
    }
    catch {
        if ((Test-HcrStateManagedPath $Path) -and
            (Test-HcrStateAccessDeniedException $_.Exception)) {
            Throw-HcrStateRootAccessDenied
        }
        throw
    }
    finally {
        if (Test-Path `
                -LiteralPath $temporary `
                -PathType Leaf `
                -ErrorAction SilentlyContinue) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path `
                -LiteralPath $backup `
                -PathType Leaf `
                -ErrorAction SilentlyContinue) {
            Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-HcrJsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$MissingCode = 'STATE_NOT_FOUND'
    )

    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction Stop)) {
            Throw-HcrError $MissingCode 'The requested state record does not exist.'
        }
        $item = Assert-HcrRegularLocalFile $Path 'STATE_INTEGRITY_ERROR'
        if ($item.Length -gt 16MB) {
            Throw-HcrError 'STATE_INTEGRITY_ERROR' 'A state record exceeds the size limit.'
        }
        return Get-Content `
            -LiteralPath $Path `
            -Raw `
            -Encoding UTF8 `
            -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        if ((Test-HcrStateManagedPath $Path) -and
            (Test-HcrStateAccessDeniedException $_.Exception)) {
            Throw-HcrStateRootAccessDenied
        }
        if ($_.Exception.Data.Contains('HcrCode')) { throw }
        Throw-HcrError 'STATE_INTEGRITY_ERROR' 'A state record contains invalid JSON.'
    }
}

function Invoke-HcrFileLock {
    param(
        [Parameter(Mandatory = $true)][string]$LockName,
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [int]$TimeoutMilliseconds = 5000
    )

    if ($LockName -notmatch '^[a-zA-Z0-9._-]+$') {
        Throw-HcrError 'INTERNAL_ERROR' 'The state lock name is invalid.'
    }
    $lockPath = Get-HcrStateSubpath 'locks' "$LockName.lock"
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    $stream = $null
    while ($null -eq $stream -and [DateTime]::UtcNow -lt $deadline) {
        try {
            $stream = New-Object IO.FileStream(
                $lockPath,
                [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,
                [IO.FileShare]::None
            )
        }
        catch [IO.IOException] {
            [Threading.Thread]::Sleep(25)
        }
        catch {
            if (Test-HcrStateAccessDeniedException $_.Exception) {
                Throw-HcrStateRootAccessDenied
            }
            throw
        }
    }
    if ($null -eq $stream) {
        Throw-HcrError 'STATE_BUSY' 'The state record is busy; retry later.'
    }
    try {
        return & $Action
    }
    finally {
        $stream.Dispose()
    }
}

function Save-HcrPlanRecord {
    param([Parameter(Mandatory = $true)][object]$Record)

    $planId = [string](Get-HcrPropertyValue $Record 'planId')
    if (-not (Test-HcrUuid $planId)) {
        Throw-HcrError 'INTERNAL_ERROR' 'Cannot persist a plan without a valid plan ID.'
    }
    $json = ConvertTo-HcrJson $Record 100
    if ($json -match '"confirmationToken"\s*:') {
        Throw-HcrError 'INTERNAL_ERROR' 'Restore-token plaintext cannot be persisted.'
    }
    Write-HcrJsonFile (Get-HcrStateSubpath 'plans' "$planId.json") $Record
}

function Get-HcrPlanRecord {
    param([Parameter(Mandatory = $true)][string]$PlanId)

    if (-not (Test-HcrUuid $PlanId)) {
        Throw-HcrError 'INVALID_ARGUMENT' 'planId must be a UUID.'
    }
    return Read-HcrJsonFile (Get-HcrStateSubpath 'plans' "$PlanId.json") 'PLAN_NOT_FOUND'
}

function Consume-HcrPlanRecord {
    param([Parameter(Mandatory = $true)][string]$PlanId)

    if (-not (Test-HcrUuid $PlanId)) {
        Throw-HcrError 'INVALID_ARGUMENT' 'planId must be a UUID.'
    }
    $path = Get-HcrStateSubpath 'plans' "$PlanId.json"
    if (-not (Test-HcrStateFileExists $path)) {
        Throw-HcrError 'PLAN_NOT_FOUND' 'The requested plan does not exist.'
    }
    return Invoke-HcrFileLock "plan-$PlanId" {
        $record = Read-HcrJsonFile $path 'PLAN_NOT_FOUND'
        if ([bool](Get-HcrPropertyValue $record 'consumed' $false)) {
            Throw-HcrError 'PLAN_ALREADY_CONSUMED' 'The plan has already been consumed.'
        }
        $record.consumed = $true
        $record.consumedAt = Get-HcrUtcTimestamp
        Save-HcrPlanRecord $record
        return $record
    }
}

function Get-HcrRecordKey {
    param([Parameter(Mandatory = $true)][string]$Identity)
    return Get-HcrSha256Text $Identity.ToLowerInvariant()
}

function Save-HcrOwnershipRecord {
    param([Parameter(Mandatory = $true)][object]$Record)

    $vmId = [string](Get-HcrPropertyValue $Record 'vmId')
    if ([string]::IsNullOrWhiteSpace($vmId)) {
        Throw-HcrError 'INTERNAL_ERROR' 'Cannot persist ownership without a VM ID.'
    }
    $key = Get-HcrRecordKey $vmId
    Write-HcrJsonFile (Get-HcrStateSubpath 'ownership' "$key.json") $Record
}

function Get-HcrOwnershipRecords {
    $directory = Get-HcrStateSubpath 'ownership' '_placeholder'
    $directory = Split-Path -Parent $directory
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($file in @(Get-HcrStateFiles $directory '*.json')) {
        try {
            $records.Add((Read-HcrJsonFile $file.FullName 'OWNERSHIP_NOT_FOUND'))
        }
        catch {
            if ($_.Exception.Data.Contains('HcrCode') -and
                [string]$_.Exception.Data['HcrCode'] -eq 'STATE_ROOT_ACCESS_DENIED') {
                throw
            }
            Write-HcrDiagnostic "Ignored an unreadable ownership record: $($file.Name)"
        }
    }
    return @($records | ForEach-Object { $_ })
}

function Get-HcrOwnershipRecordByVmId {
    param([Parameter(Mandatory = $true)][string]$VmId)

    $path = Get-HcrStateSubpath 'ownership' "$((Get-HcrRecordKey $VmId)).json"
    if (-not (Test-HcrStateFileExists $path)) {
        return $null
    }
    return Read-HcrJsonFile $path 'OWNERSHIP_NOT_FOUND'
}

function Get-HcrOwnershipRecordByName {
    param([Parameter(Mandatory = $true)][string]$VmName)

    foreach ($record in @(Get-HcrOwnershipRecords)) {
        if ([string](Get-HcrPropertyValue $record 'vmName') -eq $VmName) {
            return $record
        }
    }
    return $null
}

function Save-HcrOperationRecord {
    param([Parameter(Mandatory = $true)][object]$Record)

    $operationId = [string](Get-HcrPropertyValue $Record 'operationId')
    if (-not (Test-HcrUuid $operationId)) {
        Throw-HcrError 'INTERNAL_ERROR' 'Cannot persist an operation without a valid ID.'
    }
    Write-HcrJsonFile (Get-HcrStateSubpath 'operations' "$operationId.json") $Record
}

function Get-HcrOperationRecord {
    param([Parameter(Mandatory = $true)][string]$OperationId)

    if (-not (Test-HcrUuid $OperationId)) {
        Throw-HcrError 'INVALID_ARGUMENT' 'operationId must be a UUID.'
    }
    return Read-HcrJsonFile (Get-HcrStateSubpath 'operations' "$OperationId.json") 'OPERATION_NOT_FOUND'
}

function Update-HcrOperationRecord {
    param(
        [Parameter(Mandatory = $true)][string]$OperationId,
        [Parameter(Mandatory = $true)][scriptblock]$Update
    )

    return Invoke-HcrFileLock "operation-$OperationId" {
        $record = Get-HcrOperationRecord $OperationId
        $updated = & $Update $record
        if ($null -eq $updated) {
            $updated = $record
        }
        Save-HcrOperationRecord $updated
        return $updated
    }
}

function Get-HcrEvidenceStagingRoot {
    param([Parameter(Mandatory = $true)][string]$OperationId)

    if (-not (Test-HcrUuid $OperationId)) {
        Throw-HcrError 'INTERNAL_ERROR' 'Invalid operation ID for evidence staging.'
    }
    return Get-HcrStateSubpath 'evidence-staging' $OperationId
}

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

function Initialize-HcrStateStore {
    $root = Get-HcrStateRoot
    [void](Initialize-HcrLocalDirectoryPath $root)
    foreach ($relative in @('plans', 'operations', 'ownership', 'evidence-staging', 'locks')) {
        $path = Join-Path $root $relative
        [void](Initialize-HcrLocalDirectoryPath $path)
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

function Write-HcrJsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowNull()][object]$Value
    )

    $parent = Split-Path -Parent $Path
    [void](Initialize-HcrLocalDirectoryPath $parent 'STATE_INTEGRITY_ERROR')
    if (Test-Path -LiteralPath $Path) {
        [void](Assert-HcrNoReparsePath $Path 'STATE_INTEGRITY_ERROR')
    }
    $json = (ConvertTo-HcrJson $Value 100) + "`n"
    $temporary = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    $backup = "$Path.$([Guid]::NewGuid().ToString('N')).bak"
    try {
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
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $backup -PathType Leaf) {
            Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-HcrJsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$MissingCode = 'STATE_NOT_FOUND'
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Throw-HcrError $MissingCode 'The requested state record does not exist.'
    }
    $item = Assert-HcrRegularLocalFile $Path 'STATE_INTEGRITY_ERROR'
    if ($item.Length -gt 16MB) {
        Throw-HcrError 'STATE_INTEGRITY_ERROR' 'A state record exceeds the size limit.'
    }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
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
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
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
    foreach ($file in @(Get-ChildItem -LiteralPath $directory -Filter '*.json' -File -ErrorAction Stop)) {
        try {
            $records.Add((Read-HcrJsonFile $file.FullName 'OWNERSHIP_NOT_FOUND'))
        }
        catch {
            Write-HcrDiagnostic "Ignored an unreadable ownership record: $($file.Name)"
        }
    }
    return @($records | ForEach-Object { $_ })
}

function Get-HcrOwnershipRecordByVmId {
    param([Parameter(Mandatory = $true)][string]$VmId)

    $path = Get-HcrStateSubpath 'ownership' "$((Get-HcrRecordKey $VmId)).json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
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

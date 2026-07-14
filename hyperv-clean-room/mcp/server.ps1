[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$script:HcrInitialized = $false

$runtimeFiles = @(
    'Common.ps1',
    'State.ps1',
    'ToolSchemas.ps1',
    'Validation.ps1',
    'Adapters.ps1',
    'Tools.Host.ps1',
    'Tools.Guest.ps1',
    'Runtime.ps1'
)
foreach ($runtimeFile in $runtimeFiles) {
    . (Join-Path (Join-Path $PSScriptRoot 'lib') $runtimeFile)
}

try {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [Console]::InputEncoding = $utf8
    [Console]::OutputEncoding = $utf8
    Initialize-HcrRuntime (Split-Path -Parent $PSScriptRoot)
}
catch {
    $startupFailure = Get-HcrExceptionData $_.Exception
    Write-HcrDiagnostic "MCP startup failed safely: $($startupFailure.code)."
    exit 78
}

function Write-HcrJsonRpcMessage {
    param([Parameter(Mandatory = $true)][object]$Message)
    [Console]::Out.WriteLine((ConvertTo-HcrJson $Message 100))
    [Console]::Out.Flush()
}

function New-HcrJsonRpcError {
    param(
        [AllowNull()][object]$Id,
        [Parameter(Mandatory = $true)][int]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )

    return [pscustomobject][ordered]@{
        jsonrpc = '2.0'
        id = $Id
        error = [pscustomobject][ordered]@{
            code = $Code
            message = $Message
        }
    }
}

function Test-HcrJsonRpcId {
    param([AllowNull()][object]$Id)

    if ($null -eq $Id) { return $true }
    if ($Id -is [string]) { return $true }
    if ($Id -is [bool]) { return $false }
    return $Id -is [byte] -or $Id -is [sbyte] -or
        $Id -is [int16] -or $Id -is [uint16] -or
        $Id -is [int32] -or $Id -is [uint32] -or
        $Id -is [int64] -or $Id -is [uint64] -or
        $Id -is [single] -or $Id -is [double] -or $Id -is [decimal]
}

function Test-HcrClosedParameterObject {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Allowed,
        [AllowEmptyCollection()]
        [string[]]$Required = @()
    )

    if (-not (Test-HcrObjectLike $Value)) { return $false }
    foreach ($name in (Get-HcrPropertyNames $Value)) {
        if ($Allowed -notcontains $name) { return $false }
    }
    foreach ($name in $Required) {
        if (-not (Test-HcrProperty $Value $name)) { return $false }
    }
    return $true
}

function Test-HcrInitializeParameters {
    param([AllowNull()][object]$Value)

    if (-not (Test-HcrClosedParameterObject `
            $Value `
            @('protocolVersion', 'capabilities', 'clientInfo') `
            @('protocolVersion', 'capabilities', 'clientInfo'))) {
        return $false
    }
    $protocolVersion = Get-HcrPropertyValue $Value 'protocolVersion'
    $capabilities = Get-HcrPropertyValue $Value 'capabilities'
    $clientInfo = Get-HcrPropertyValue $Value 'clientInfo'
    if ($protocolVersion -isnot [string] -or
        [string]::IsNullOrWhiteSpace([string]$protocolVersion) -or
        -not (Test-HcrObjectLike $capabilities) -or
        -not (Test-HcrObjectLike $clientInfo)) {
        return $false
    }
    foreach ($field in @('name', 'version')) {
        $fieldValue = Get-HcrPropertyValue $clientInfo $field
        if ($fieldValue -isnot [string] -or
            [string]::IsNullOrWhiteSpace([string]$fieldValue)) {
            return $false
        }
    }
    return $true
}

function Get-HcrNegotiatedProtocolVersion {
    param([Parameter(Mandatory = $true)][string]$Requested)

    if ($Requested -notmatch '^\d{4}-\d{2}-\d{2}$') {
        return $null
    }
    $candidates = @($script:HcrSupportedProtocolVersions |
        Where-Object { [string]::CompareOrdinal($_, $Requested) -le 0 } |
        Sort-Object -Descending)
    if ($candidates.Count -eq 0) { return $null }
    return $candidates[0]
}

$initializeResponded = $false
$clientInitialized = $false
$negotiatedProtocolVersion = $null

while ($true) {
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { break }
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line.TrimStart().StartsWith('[')) {
        Write-HcrJsonRpcMessage (New-HcrJsonRpcError $null -32600 'Batch requests are not supported')
        continue
    }

    try {
        $request = $line | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-HcrJsonRpcMessage (New-HcrJsonRpcError $null -32700 'Parse error')
        continue
    }
    if ($request -is [System.Collections.IEnumerable] -and
        $request -isnot [string] -and
        $request -isnot [System.Collections.IDictionary]) {
        Write-HcrJsonRpcMessage (New-HcrJsonRpcError $null -32600 'Batch requests are not supported')
        continue
    }
    if (-not (Test-HcrObjectLike $request)) {
        Write-HcrJsonRpcMessage (New-HcrJsonRpcError $null -32600 'Invalid Request')
        continue
    }
    $hasId = Test-HcrProperty $request 'id'
    $id = Get-HcrPropertyValue $request 'id'
    if ($hasId -and -not (Test-HcrJsonRpcId $id)) {
        Write-HcrJsonRpcMessage (New-HcrJsonRpcError $null -32600 'Invalid Request')
        continue
    }
    if ((Get-HcrPropertyValue $request 'jsonrpc') -ne '2.0' -or
        (Get-HcrPropertyValue $request 'method') -isnot [string]) {
        Write-HcrJsonRpcMessage (New-HcrJsonRpcError $(if ($hasId) { $id } else { $null }) -32600 'Invalid Request')
        continue
    }
    $method = [string](Get-HcrPropertyValue $request 'method')
    $parameters = Get-HcrPropertyValue $request 'params' ([pscustomobject]@{})
    if (-not (Test-HcrObjectLike $parameters)) {
        if ($hasId) {
            Write-HcrJsonRpcMessage (New-HcrJsonRpcError $id -32602 'Invalid method parameters')
        }
        continue
    }

    if (-not $hasId) {
        if ($method -eq 'notifications/initialized' -and
            $initializeResponded -and
            (Test-HcrClosedParameterObject -Value $parameters -Allowed @())) {
            $clientInitialized = $true
        }
        # Other notifications are intentionally ignored without protocol output.
        continue
    }

    try {
        switch ($method) {
            'initialize' {
                if ($initializeResponded) {
                    Write-HcrJsonRpcMessage (New-HcrJsonRpcError $id -32600 'Initialize may be called only once')
                    continue
                }
                if (-not (Test-HcrInitializeParameters $parameters)) {
                    Write-HcrJsonRpcMessage (New-HcrJsonRpcError $id -32602 'Invalid initialize parameters')
                    continue
                }
                $requested = [string](Get-HcrPropertyValue $parameters 'protocolVersion')
                $negotiatedProtocolVersion = Get-HcrNegotiatedProtocolVersion $requested
                if ($null -eq $negotiatedProtocolVersion) {
                    Write-HcrJsonRpcMessage (New-HcrJsonRpcError $id -32602 'No supported MCP protocol version is at or below the requested version')
                    continue
                }
                $initializeResponded = $true
                Write-HcrJsonRpcMessage ([pscustomobject][ordered]@{
                    jsonrpc = '2.0'
                    id = $id
                    result = [pscustomobject][ordered]@{
                        protocolVersion = $negotiatedProtocolVersion
                        capabilities = [pscustomobject][ordered]@{
                            tools = [pscustomobject][ordered]@{ listChanged = $false }
                        }
                        serverInfo = [pscustomobject][ordered]@{
                            name = 'hyperv-clean-room'
                            version = '0.1.0'
                        }
                    }
                })
                continue
            }
            'ping' {
                if (-not (Test-HcrClosedParameterObject -Value $parameters -Allowed @())) {
                    Write-HcrJsonRpcMessage (New-HcrJsonRpcError $id -32602 'Invalid ping parameters')
                    continue
                }
                Write-HcrJsonRpcMessage ([pscustomobject][ordered]@{
                    jsonrpc = '2.0'; id = $id; result = [pscustomobject]@{}
                })
                continue
            }
            'tools/list' {
                if (-not (Test-HcrClosedParameterObject -Value $parameters -Allowed @())) {
                    Write-HcrJsonRpcMessage (New-HcrJsonRpcError $id -32602 'Invalid tools-list parameters')
                    continue
                }
                if (-not $clientInitialized) {
                    Write-HcrJsonRpcMessage (New-HcrJsonRpcError $id -32002 'Client initialization is incomplete')
                    continue
                }
                Write-HcrJsonRpcMessage ([pscustomobject][ordered]@{
                    jsonrpc = '2.0'
                    id = $id
                    result = [pscustomobject][ordered]@{ tools = @(Get-HcrToolDefinitions) }
                })
                continue
            }
            'tools/call' {
                if (-not $clientInitialized) {
                    Write-HcrJsonRpcMessage (New-HcrJsonRpcError $id -32002 'Client initialization is incomplete')
                    continue
                }
                if (-not (Test-HcrClosedParameterObject `
                        $parameters `
                        @('name', 'arguments') `
                        @('name')) -or
                    (Get-HcrPropertyValue $parameters 'name') -isnot [string] -or
                    ((Test-HcrProperty $parameters 'arguments') -and
                        -not (Test-HcrObjectLike (Get-HcrPropertyValue $parameters 'arguments')))) {
                    Write-HcrJsonRpcMessage (New-HcrJsonRpcError $id -32602 'Invalid tool-call parameters')
                    continue
                }
                $toolName = [string](Get-HcrPropertyValue $parameters 'name')
                $toolArguments = Get-HcrPropertyValue $parameters 'arguments' ([pscustomobject]@{})
                $envelope = Invoke-HcrToolCall $toolName $toolArguments `
                    3>$null 4>$null 5>$null 6>$null
                Write-HcrJsonRpcMessage ([pscustomobject][ordered]@{
                    jsonrpc = '2.0'
                    id = $id
                    result = [pscustomobject][ordered]@{
                        content = @([pscustomobject][ordered]@{
                            type = 'text'
                            text = ConvertTo-HcrJson $envelope 100
                        })
                        isError = -not [bool](Get-HcrPropertyValue $envelope 'ok')
                    }
                })
                continue
            }
            default {
                Write-HcrJsonRpcMessage (New-HcrJsonRpcError $id -32601 'Method not found')
                continue
            }
        }
    }
    catch {
        Write-HcrDiagnostic 'A JSON-RPC request failed safely.'
        Write-HcrJsonRpcMessage (New-HcrJsonRpcError $id -32603 'Internal error')
    }
}

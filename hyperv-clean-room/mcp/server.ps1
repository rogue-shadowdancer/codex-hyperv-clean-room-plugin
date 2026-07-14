[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
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
    $hasId = Test-HcrProperty $request 'id'
    $id = Get-HcrPropertyValue $request 'id'
    if ((Get-HcrPropertyValue $request 'jsonrpc') -ne '2.0' -or
        (Get-HcrPropertyValue $request 'method') -isnot [string]) {
        if ($hasId) {
            Write-HcrJsonRpcMessage (New-HcrJsonRpcError $id -32600 'Invalid Request')
        }
        continue
    }
    $method = [string](Get-HcrPropertyValue $request 'method')
    $parameters = Get-HcrPropertyValue $request 'params' ([pscustomobject]@{})

    if (-not $hasId) {
        if ($method -eq 'notifications/initialized' -and $initializeResponded) {
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
                if (-not (Test-HcrObjectLike $parameters)) {
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
                Write-HcrJsonRpcMessage ([pscustomobject][ordered]@{
                    jsonrpc = '2.0'; id = $id; result = [pscustomobject]@{}
                })
                continue
            }
            'tools/list' {
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
                if (-not (Test-HcrObjectLike $parameters) -or
                    (Get-HcrPropertyValue $parameters 'name') -isnot [string]) {
                    Write-HcrJsonRpcMessage (New-HcrJsonRpcError $id -32602 'Invalid tool-call parameters')
                    continue
                }
                $toolName = [string](Get-HcrPropertyValue $parameters 'name')
                $toolArguments = Get-HcrPropertyValue $parameters 'arguments' ([pscustomobject]@{})
                $envelope = Invoke-HcrToolCall $toolName $toolArguments
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

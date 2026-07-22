[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$installedRoot = [IO.Path]::GetFullPath((Join-Path $HOME 'plugins\hyperv-clean-room')).TrimEnd('\')
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'hyperv-clean-room')).TrimEnd('\')
$serverPath = Join-Path $installedRoot 'mcp\server.ps1'
$stateRoot = Join-Path $repoRoot '.artifacts\gate4-installed-copy\state'
$credentialRoot = Join-Path $repoRoot '.artifacts\gate4-installed-copy\credentials'
$missingIso = Join-Path $repoRoot (
    '.artifacts\gate4-installed-copy\missing-' + [Guid]::NewGuid().ToString('N') + '.iso'
)

function Assert-InstalledCopy {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) { throw $Message }
}

Assert-InstalledCopy (Test-Path -LiteralPath $serverPath -PathType Leaf) `
    "Installed MCP server is missing: $serverPath"
$resolvedServer = (Resolve-Path -LiteralPath $serverPath).Path
$installedPrefix = $installedRoot + '\'
Assert-InstalledCopy ($resolvedServer.StartsWith(
        $installedPrefix,
        [StringComparison]::OrdinalIgnoreCase
    )) 'MCP smoke server path does not start in the installed copy.'
Assert-InstalledCopy (-not $resolvedServer.StartsWith(
        $sourceRoot + '\',
        [StringComparison]::OrdinalIgnoreCase
    )) 'MCP smoke attempted to start the repository source copy.'

$requests = @(
    [ordered]@{
        jsonrpc = '2.0'
        id = 1
        method = 'initialize'
        params = [ordered]@{
            protocolVersion = '2025-11-25'
            capabilities = [ordered]@{}
            clientInfo = [ordered]@{ name = 'gate4-installed-copy'; version = '1.0.0' }
        }
    },
    [ordered]@{
        jsonrpc = '2.0'
        method = 'notifications/initialized'
        params = [ordered]@{}
    },
    [ordered]@{
        jsonrpc = '2.0'
        id = 2
        method = 'tools/list'
        params = [ordered]@{}
    },
    [ordered]@{
        jsonrpc = '2.0'
        id = 3
        method = 'tools/call'
        params = [ordered]@{
            name = 'inspect_host'
            arguments = [ordered]@{}
        }
    },
    [ordered]@{
        jsonrpc = '2.0'
        id = 4
        method = 'tools/call'
        params = [ordered]@{
            name = 'plan_vm_create'
            arguments = [ordered]@{
                name = 'hcr-gate4-installed-readonly-probe'
                isoPath = $missingIso
                vmRoot = $repoRoot
                switchName = 'not-consulted-for-missing-iso'
            }
        }
    }
)

$startInfo = New-Object Diagnostics.ProcessStartInfo
$startInfo.FileName = 'powershell.exe'
$startInfo.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
    $resolvedServer + '"'
$startInfo.WorkingDirectory = $installedRoot
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
$startInfo.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
$startInfo.EnvironmentVariables['HCR_ADAPTER_MODE'] = 'hyperv'
$startInfo.EnvironmentVariables['HCR_TEST_MODE'] = '0'
$startInfo.EnvironmentVariables['HCR_STATE_ROOT'] = $stateRoot
$startInfo.EnvironmentVariables['HCR_CREDENTIAL_ROOT'] = $credentialRoot
foreach ($name in @('HCR_MOCK_ADAPTER_PATH')) {
    if ($startInfo.EnvironmentVariables.ContainsKey($name)) {
        $startInfo.EnvironmentVariables.Remove($name)
    }
}

$process = New-Object Diagnostics.Process
$process.StartInfo = $startInfo
$stdinEncoding = New-Object Text.UTF8Encoding($false)
$originalConsoleInputEncoding = [Console]::InputEncoding
try {
    [Console]::InputEncoding = $stdinEncoding
    Assert-InstalledCopy $process.Start() 'Installed MCP server process did not start.'
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    foreach ($request in $requests) {
        $process.StandardInput.WriteLine(($request | ConvertTo-Json -Depth 20 -Compress))
    }
    $process.StandardInput.Close()
}
finally {
    [Console]::InputEncoding = $originalConsoleInputEncoding
}
if (-not $process.WaitForExit(60000)) {
    try { $process.Kill() } catch {}
    throw 'Installed MCP server did not exit within 60 seconds.'
}
$stdout = [string]$stdoutTask.Result
$stderr = [string]$stderrTask.Result
Assert-InstalledCopy ($process.ExitCode -eq 0) `
    "Installed MCP server exited with $($process.ExitCode): $stderr"
Assert-InstalledCopy ($stderr.Length -le 4096) 'Installed MCP server stderr was not bounded.'

$responseLines = @($stdout -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
Assert-InstalledCopy ($responseLines.Count -eq 4) `
    "Installed MCP server returned $($responseLines.Count) response lines instead of four."
$responses = @{}
foreach ($line in $responseLines) {
    try { $response = $line | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'Installed MCP server returned non-JSON protocol output.' }
    Assert-InstalledCopy ($null -ne $response.id) 'Installed MCP response is missing an ID.'
    $responses[[int]$response.id] = $response
}
Assert-InstalledCopy ($responses.Count -eq 4) 'Installed MCP response IDs were duplicated.'

$initialize = $responses[1]
Assert-InstalledCopy ([string]$initialize.result.protocolVersion -ceq '2025-11-25') `
    'Installed MCP server negotiated the wrong protocol version.'
$tools = @($responses[2].result.tools)
Assert-InstalledCopy ($tools.Count -eq 20) `
    "Installed MCP server exposed $($tools.Count) tools instead of 20."
Assert-InstalledCopy (@($tools.name | Sort-Object -Unique).Count -eq 20) `
    'Installed MCP server exposed duplicate tool names.'

$inspectResponse = $responses[3]
Assert-InstalledCopy (-not [bool]$inspectResponse.result.isError) `
    'Installed inspect_host response was projected as an MCP error.'
$inspectEnvelope = [string]$inspectResponse.result.content[0].text | ConvertFrom-Json -ErrorAction Stop
Assert-InstalledCopy ([bool]$inspectEnvelope.ok -and -not [bool]$inspectEnvelope.changed) `
    'Installed inspect_host did not remain successful and read-only.'
Assert-InstalledCopy (@($inspectEnvelope.warnings | Where-Object { $_ -match 'MOCK_ADAPTER' }).Count -eq 0) `
    'Installed inspect_host unexpectedly used mock evidence.'

$planResponse = $responses[4]
Assert-InstalledCopy ([bool]$planResponse.result.isError) `
    'Installed missing-ISO plan rejection was not projected as an MCP error.'
$planEnvelope = [string]$planResponse.result.content[0].text | ConvertFrom-Json -ErrorAction Stop
Assert-InstalledCopy (-not [bool]$planEnvelope.ok -and -not [bool]$planEnvelope.changed -and
    [string]$planEnvelope.error.code -ceq 'INVALID_ISO') `
    'Installed missing-ISO plan did not fail before mutation with INVALID_ISO.'

[ordered]@{
    ok = $true
    gate = 4
    serverStartedFrom = $resolvedServer
    workingDirectory = $installedRoot
    toolCount = $tools.Count
    inspectHost = 'passed-read-only'
    missingIso = 'INVALID_ISO'
    adapter = 'hyperv'
    realGuestOperations = 0
    realHyperVMutations = 0
} | ConvertTo-Json -Compress

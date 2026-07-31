[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PluginRoot,

    [ValidateNotNullOrEmpty()]
    [string]$ExpectedVersion = '0.4.0',

    [ValidateNotNullOrEmpty()]
    [string]$EnvironmentId = 'local',

    [ValidateRange(5, 120)]
    [int]$TimeoutSeconds = 45,

    [switch]$MockToolCallSmoke,

    [string]$PythonExecutable
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $PSScriptRoot 'validate_codex_app_server_catalog.py'
if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) {
    throw "Missing Codex app-server catalog validator: $validator"
}

$pythonArguments = @()
if ([string]::IsNullOrWhiteSpace($PythonExecutable)) {
    $preparedPython = Join-Path $repoRoot '.artifacts\test-python\python\python.exe'
    if (Test-Path -LiteralPath $preparedPython -PathType Leaf) {
        $PythonExecutable = $preparedPython
    }
    else {
        $pyLauncher = Get-Command 'C:\Windows\py.exe' -ErrorAction SilentlyContinue
        if ($null -eq $pyLauncher) {
            throw 'No prepared test Python or C:\Windows\py.exe is available.'
        }
        $PythonExecutable = $pyLauncher.Source
        $pythonArguments += '-3'
    }
}

$pythonArguments += @(
    $validator,
    '--plugin-root', [IO.Path]::GetFullPath($PluginRoot),
    '--expected-version', $ExpectedVersion,
    '--environment-id', $EnvironmentId,
    '--timeout-seconds', [string]$TimeoutSeconds
)
if ($MockToolCallSmoke) {
    $pythonArguments += '--mock-tool-call-smoke'
}

& $PythonExecutable @pythonArguments
if ($LASTEXITCODE -ne 0) {
    throw "Selected-plugin Codex app-server catalog validation failed with exit code $LASTEXITCODE."
}

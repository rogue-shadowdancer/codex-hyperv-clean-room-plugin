[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PluginRoot,
    [Parameter(Mandatory = $true)][string]$ToolName,
    [Parameter(Mandatory = $true)][string]$ArgumentsPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:HcrInitialized = $false

foreach ($runtimeFile in @(
        'Common.ps1',
        'State.ps1',
        'ToolSchemas.ps1',
        'Validation.ps1',
        'Validation.V2.ps1',
        'Adapters.ps1',
        'Tools.Host.ps1',
        'Tools.Host.V2.ps1',
        'Tools.Guest.ps1',
        'Tools.Guest.V2.ps1',
        'Runtime.ps1'
    )) {
    . (Join-Path (Join-Path (Join-Path $PluginRoot 'mcp') 'lib') $runtimeFile)
}
Initialize-HcrRuntime $PluginRoot
$arguments = Get-Content -LiteralPath $ArgumentsPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -ErrorAction Stop
$result = Invoke-HcrToolCall $ToolName $arguments
[Console]::Out.WriteLine((ConvertTo-HcrJson $result 100))

[CmdletBinding()]
param(
    [string]$MarketplacePath = (
        Join-Path $HOME '.agents\plugins\marketplace.json'
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Read-Json {
    param([Parameter(Mandatory = $true)][string]$Path)

    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) `
        "Required JSON file is missing: $Path"
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$pluginRoot = Join-Path $repoRoot 'hyperv-clean-room'
$manifestPath = Join-Path $pluginRoot '.codex-plugin\plugin.json'
$mcpPath = Join-Path $pluginRoot '.mcp.json'
$skillPath = Join-Path `
    $pluginRoot `
    'skills\manage-hyperv-clean-room\SKILL.md'

$manifest = Read-Json $manifestPath
$mcp = Read-Json $mcpPath

Assert-True ($manifest.name -eq 'hyperv-clean-room') `
    'Plugin name must be hyperv-clean-room.'
Assert-True ([string]$manifest.version -cmatch `
    '^0\.2\.0(?:\+codex\.[a-z0-9]+(?:-[a-z0-9]+)*)?$') `
    'The plugin version must preserve base 0.2.0 with at most one Codex cachebuster.'
Assert-True ($manifest.author.name -eq 'rogue-shadowdancer') `
    'Unexpected plugin author.'
Assert-True ($manifest.license -eq 'GPL-3.0-only') `
    'The public plugin must declare GPL-3.0-only.'
Assert-True ($manifest.skills -eq './skills/') `
    'Plugin skills path is not canonical.'
Assert-True ($manifest.mcpServers -eq './.mcp.json') `
    'Plugin MCP path is not canonical.'
Assert-True ($null -eq $manifest.PSObject.Properties['apps']) `
    'The plugin must not declare an app in Gate 1.'

$servers = @($mcp.mcpServers.PSObject.Properties)
Assert-True ($servers.Count -eq 1) `
    'Exactly one MCP server must be declared.'
$server = $servers[0].Value
Assert-True ($servers[0].Name -eq 'hyperv-clean-room') `
    'Unexpected MCP server name.'
Assert-True ($server.command -eq 'powershell.exe') `
    'The MCP server must use Windows PowerShell.'
Assert-True ($server.cwd -eq '.') `
    'The MCP server working directory must be the plugin root.'
$serverScriptArgument = @($server.args) | Select-Object -Last 1
$serverPath = [IO.Path]::GetFullPath((Join-Path $pluginRoot $serverScriptArgument))
Assert-True ($serverPath.StartsWith(
        [IO.Path]::GetFullPath($pluginRoot),
        [StringComparison]::OrdinalIgnoreCase
    )) 'The MCP server path escapes the plugin root.'
Assert-True (Test-Path -LiteralPath $serverPath -PathType Leaf) `
    'The configured MCP server file does not exist.'

$schemaFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $pluginRoot 'schemas') `
        -Filter '*.schema.json' -File
)
Assert-True ($schemaFiles.Count -eq 5) `
    'Gate 1.1 must contain exactly five public schemas.'
$productionPythonFiles = @(
    Get-ChildItem -LiteralPath $pluginRoot -Recurse -Filter '*.py' -File
)
Assert-True ($productionPythonFiles.Count -eq 0) `
    'The production plugin must not depend on Python.'
foreach ($schema in $schemaFiles) {
    $parsed = Read-Json $schema.FullName
    Assert-True ($parsed.'$schema' -eq 'https://json-schema.org/draft/2020-12/schema') `
        "Unexpected JSON Schema dialect: $($schema.Name)"
    Assert-True ([bool]$parsed.'$id') `
        "Schema is missing an id: $($schema.Name)"
    Assert-True ($parsed.properties.schemaVersion.const -eq 1) `
        "Public schema does not freeze schemaVersion 1: $($schema.Name)"
}

Assert-True (Test-Path -LiteralPath $skillPath -PathType Leaf) `
    'Companion skill is missing.'
$skillText = Get-Content -LiteralPath $skillPath -Raw -Encoding UTF8
Assert-True ($skillText -match '(?s)^---\s+name:\s*manage-hyperv-clean-room\s+description:.+?\s+---') `
    'Companion skill frontmatter is incomplete.'
Assert-True ($skillText -match 'Use the plugin''s MCP tools as the authority') `
    'The companion skill does not make the MCP authority explicit.'

$sourceFiles = @(
    Get-ChildItem -LiteralPath $repoRoot -Recurse -File | Where-Object {
        $_.FullName -notmatch '[\\/]\.git[\\/]' -and
        $_.FullName -notmatch '[\\/]\.artifacts[\\/]'
    }
)
$todoToken = '[' + 'TODO:'
$placeholderHits = @(
    $sourceFiles | Select-String -SimpleMatch $todoToken -ErrorAction Stop
)
Assert-True ($placeholderHits.Count -eq 0) `
    'Scaffold TODO placeholders remain.'
$tbdHits = @(
    $sourceFiles |
        Where-Object { $_.Extension -eq '.md' } |
        Select-String -Pattern '\bTBD\b' -CaseSensitive -ErrorAction Stop
)
Assert-True ($tbdHits.Count -eq 0) `
    'Documentation contains a TBD placeholder.'

$powerShellFiles = @(
    $sourceFiles | Where-Object { $_.Extension -eq '.ps1' }
)
$parseFailures = New-Object System.Collections.Generic.List[string]
foreach ($file in $powerShellFiles) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$errors
    )
    foreach ($parseError in @($errors)) {
        $parseFailures.Add("$($file.Name): $($parseError.Message)")
    }
}
Assert-True ($parseFailures.Count -eq 0) `
    "PowerShell parse failures: $($parseFailures -join '; ')"

$marketplace = Read-Json $MarketplacePath
Assert-True ($marketplace.name -eq 'personal') `
    'Unexpected personal marketplace name.'
$entries = @($marketplace.plugins | Where-Object { $_.name -eq 'hyperv-clean-room' })
Assert-True ($entries.Count -eq 1) `
    'The personal marketplace must contain exactly one plugin entry.'
$entry = $entries[0]
Assert-True ($entry.source.source -eq 'local') `
    'Marketplace source must be local.'
Assert-True ($entry.source.path -eq './plugins/hyperv-clean-room') `
    'Marketplace source path is not canonical.'
Assert-True ($entry.policy.installation -eq 'AVAILABLE') `
    'Marketplace installation policy must be AVAILABLE.'
Assert-True ($entry.policy.authentication -eq 'ON_INSTALL') `
    'Marketplace authentication policy must be ON_INSTALL.'
Assert-True ($entry.category -eq 'Developer Tools') `
    'Marketplace category must be Developer Tools.'

[ordered]@{
    ok = $true
    gate = '1.1'
    plugin = $manifest.name
    version = $manifest.version
    schemas = $schemaFiles.Count
    productionPythonFiles = $productionPythonFiles.Count
    powerShellFiles = $powerShellFiles.Count
    marketplaceEntry = $entry.name
    mutationsPerformed = $false
} | ConvertTo-Json -Depth 5

[CmdletBinding()]
param([switch]$AllowDirtyPluginSource)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$pluginRoot = Join-Path $repoRoot 'hyperv-clean-room'
$preparedRuntimePath = Join-Path $repoRoot '.artifacts\test-python\runtime.json'
$pluginValidator = Join-Path $HOME '.codex\skills\.system\plugin-creator\scripts\validate_plugin.py'

function Assert-Gate4Validation {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) { throw $Message }
}

if (-not $AllowDirtyPluginSource) {
    $payloadStatus = @(& git -C $repoRoot status --porcelain=v1 `
            --untracked-files=all -- hyperv-clean-room 2>$null)
    Assert-Gate4Validation ($LASTEXITCODE -eq 0 -and $payloadStatus.Count -eq 0) `
        'Final Gate 4 validation requires hyperv-clean-room/** to match HEAD exactly.'
}

$null = & (Join-Path $PSScriptRoot 'validate-gate2.ps1')
$sourceResult = & (Join-Path $PSScriptRoot 'validate-install-source.ps1') -RequireCachebuster |
    ConvertFrom-Json -ErrorAction Stop
$null = & (Join-Path $repoRoot 'tests\gate4-installation.tests.ps1')
$installResult = & (Join-Path $PSScriptRoot 'check_install.ps1') |
    ConvertFrom-Json -ErrorAction Stop
$smokeResult = & (Join-Path $repoRoot 'tests\gate4-installed-copy.tests.ps1') |
    ConvertFrom-Json -ErrorAction Stop

Assert-Gate4Validation ($installResult.installed -and $installResult.owned -and
    $installResult.matches -and $installResult.marketplaceVisible) `
    'Gate 4 requires installed, owned, matches, and marketplaceVisible to all be true.'
Assert-Gate4Validation ([int]$installResult.marketplaceEntryCount -eq 1) `
    'Gate 4 requires exactly one personal marketplace entry.'
Assert-Gate4Validation ([string]$installResult.sourceVersion -ceq
    [string]$installResult.installedVersion) 'Source and installed versions differ.'
Assert-Gate4Validation ([string]$installResult.sourceCommit -ceq
    [string]$installResult.installedSourceCommit) 'Source and installed commits differ.'
Assert-Gate4Validation (-not [string]::IsNullOrWhiteSpace([string]$installResult.cachebuster) -and
    [string]$installResult.cachebuster -ceq [string]$installResult.installedCachebuster) `
    'Source and installed cachebusters differ or are missing.'
Assert-Gate4Validation ([int]$smokeResult.toolCount -eq 20) `
    'Installed-copy smoke did not expose exactly 20 tools.'
Assert-Gate4Validation ([string]$smokeResult.runtimeVersion -ceq '0.2.0') `
    'Installed-copy smoke did not report the exact 0.2.0 base runtime version.'
Assert-Gate4Validation ([string]$smokeResult.serverStartedFrom -like
    (Join-Path $HOME 'plugins\hyperv-clean-room\*')) `
    'Installed-copy smoke did not start from the personal plugin path.'
Assert-Gate4Validation ([string]$smokeResult.inspectHost -ceq 'passed-read-only' -and
    [string]$smokeResult.missingIso -ceq 'INVALID_ISO' -and
    [int]$smokeResult.realHyperVMutations -eq 0) `
    'Installed-copy host acceptance was not bounded and mutation-free.'

Assert-Gate4Validation (Test-Path -LiteralPath $preparedRuntimePath -PathType Leaf) `
    'Prepared test Python metadata is required for plugin-creator validation.'
Assert-Gate4Validation (Test-Path -LiteralPath $pluginValidator -PathType Leaf) `
    'plugin-creator validate_plugin.py is unavailable.'
$runtime = Get-Content -LiteralPath $preparedRuntimePath -Raw -Encoding UTF8 |
    ConvertFrom-Json -ErrorAction Stop
$pythonArguments = @($runtime.pythonArguments | ForEach-Object { [string]$_ })
$oldPythonPath = $env:PYTHONPATH
$oldNoUserSite = $env:PYTHONNOUSERSITE
try {
    $env:PYTHONPATH = [string]$runtime.dependencyPath
    $env:PYTHONNOUSERSITE = '1'
    $pluginValidation = @(& ([string]$runtime.pythonCommand) @pythonArguments -S `
            $pluginValidator $pluginRoot 2>&1)
    Assert-Gate4Validation ($LASTEXITCODE -eq 0) `
        "plugin-creator validation failed: $($pluginValidation -join ' ')"
}
finally {
    $env:PYTHONPATH = $oldPythonPath
    $env:PYTHONNOUSERSITE = $oldNoUserSite
}

[ordered]@{
    ok = $true
    gate = 4
    installed = [bool]$installResult.installed
    owned = [bool]$installResult.owned
    matches = [bool]$installResult.matches
    marketplaceVisible = [bool]$installResult.marketplaceVisible
    marketplaceEntryCount = [int]$installResult.marketplaceEntryCount
    sourceVersion = [string]$installResult.sourceVersion
    installedVersion = [string]$installResult.installedVersion
    sourceCommit = [string]$installResult.sourceCommit
    cachebuster = [string]$installResult.cachebuster
    sourceFileCount = [int]$sourceResult.fileCount
    toolCount = [int]$smokeResult.toolCount
    installedCopyServer = [string]$smokeResult.serverStartedFrom
    runtimeVersion = [string]$smokeResult.runtimeVersion
    inspectHost = [string]$smokeResult.inspectHost
    missingIso = [string]$smokeResult.missingIso
    pluginCreatorValidated = $true
    commitBound = -not [bool]$AllowDirtyPluginSource
    realGuestOperations = 0
    realHyperVMutations = 0
} | ConvertTo-Json -Compress

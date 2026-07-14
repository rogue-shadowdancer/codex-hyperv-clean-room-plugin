[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $repoRoot 'hyperv-clean-room'
$targetRoot = Join-Path $HOME 'plugins\hyperv-clean-room'
$marketplacePath = Join-Path $HOME '.agents\plugins\marketplace.json'
$pluginCreatorRoot = Join-Path $HOME '.codex\skills\.system\plugin-creator'
$scaffoldRoot = Join-Path (Join-Path $repoRoot '.artifacts') (
    'plugin-creator-marketplace-' + [Guid]::NewGuid().ToString('N')
)
. (Join-Path $PSScriptRoot 'install-common.ps1')

$inventory = Get-HcrSourceInventory -SourceRoot $sourceRoot
$null = Install-HcrPluginPayload -SourceInventory $inventory -TargetRoot $targetRoot

$creator = Join-Path $pluginCreatorRoot 'scripts\create_basic_plugin.py'
$reader = Join-Path $pluginCreatorRoot 'scripts\read_marketplace_name.py'
Assert-HcrInstallCondition (Test-Path -LiteralPath $creator -PathType Leaf) `
    "plugin-creator scaffold helper is missing: $creator"
Assert-HcrInstallCondition (Test-Path -LiteralPath $reader -PathType Leaf) `
    "plugin-creator marketplace reader is missing: $reader"
$pythonLauncher = Join-Path $env:SystemRoot 'py.exe'
Assert-HcrInstallCondition (Test-Path -LiteralPath $pythonLauncher -PathType Leaf) `
    'The Windows Python launcher required by plugin-creator is unavailable.'

Invoke-HcrRepositoryScratchAction `
    -RepositoryRoot $repoRoot `
    -ScratchRoot $scaffoldRoot `
    -Action {
    param($validatedScaffoldRoot)

    & $pythonLauncher -3 $creator $script:HcrPluginName `
        --path $validatedScaffoldRoot `
        --with-marketplace `
        --marketplace-path $marketplacePath `
        --install-policy AVAILABLE `
        --auth-policy ON_INSTALL `
        --category 'Developer Tools' `
        --force
    Assert-HcrInstallCondition ($LASTEXITCODE -eq 0) `
        'plugin-creator failed to update the personal marketplace.'

    $marketplaceName = @(& $pythonLauncher -3 $reader --marketplace-path $marketplacePath)
    Assert-HcrInstallCondition ($LASTEXITCODE -eq 0 -and $marketplaceName.Count -eq 1 -and
        [string]$marketplaceName[0] -ceq 'personal') `
        'plugin-creator did not resolve the expected personal marketplace name.'

    $codex = Get-Command codex -ErrorAction Stop
    $installResult = @(& $codex.Source plugin add 'hyperv-clean-room@personal' --json 2>&1)
    Assert-HcrInstallCondition ($LASTEXITCODE -eq 0) `
        "codex plugin add failed: $($installResult -join ' ')"
}

$check = Get-HcrInstallCheck `
    -SourceInventory $inventory `
    -TargetRoot $targetRoot `
    -MarketplacePath $marketplacePath
Assert-HcrInstallCondition ($check.installed -and $check.owned -and
    $check.matches -and $check.marketplaceVisible) `
    "Post-install validation failed: $($check | ConvertTo-Json -Depth 10 -Compress)"
$check | ConvertTo-Json -Depth 10 -Compress

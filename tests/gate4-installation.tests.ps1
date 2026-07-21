[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $repoRoot 'hyperv-clean-room'
$testRoot = Join-Path $repoRoot '.artifacts\gate4-installation-tests'
. (Join-Path $repoRoot 'scripts\install-common.ps1')

$script:assertions = 0
function Assert-Gate4 {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:assertions++
    if (-not $Condition) { throw $Message }
}

if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
$null = New-Item -ItemType Directory -Path $testRoot
try {
    $inventory = Get-HcrSourceInventory -SourceRoot $sourceRoot
    Assert-Gate4 ($inventory.pluginName -ceq 'hyperv-clean-room') `
        'Source validation returned the wrong plugin name.'
    Assert-Gate4 ($inventory.baseVersion -ceq '0.2.0') `
        'Source validation returned the wrong base version.'
    Assert-Gate4 ($inventory.fileCount -eq 31) `
        'Source validation did not freeze the 31-file schema-v2 payload.'
    Assert-Gate4 (@($inventory.files | Where-Object {
                [IO.Path]::IsPathRooted([string]$_.path) -or
                [string]$_.path -match '\\|(^|/)\.\.?(/|$)'
            }).Count -eq 0) 'Source inventory contains an unsafe relative path.'
    Assert-Gate4 (@($inventory.files | Where-Object {
                [long]$_.size -lt 0 -or [string]$_.sha256 -notmatch '^[0-9a-f]{64}$'
            }).Count -eq 0) 'Source inventory contains an invalid size or SHA-256.'
    $caseCollisionRejected = $false
    try { Assert-HcrUniqueRelativePaths -Paths @('Path/File.json', 'path/file.json') }
    catch { $caseCollisionRejected = $true }
    Assert-Gate4 $caseCollisionRejected `
        'Ordinal-ignore-case relative-path collision was not rejected.'

    $sourceAdsPath = Join-Path $sourceRoot '.mcp.json'
    Add-Content -LiteralPath $sourceAdsPath -Stream gate4Probe -Value 'hidden-source-state'
    $sourceAdsRejected = $false
    try {
        try { $null = Get-HcrSourceInventory -SourceRoot $sourceRoot }
        catch { $sourceAdsRejected = $true }
    }
    finally {
        Remove-Item -LiteralPath $sourceAdsPath -Stream gate4Probe -Force
    }
    Assert-Gate4 $sourceAdsRejected 'Source validation did not reject an alternate data stream.'

    $unowned = Join-Path $testRoot 'unowned'
    $null = New-Item -ItemType Directory -Path $unowned
    $sentinel = Join-Path $unowned 'user-owned.txt'
    [IO.File]::WriteAllText($sentinel, 'preserve', $script:HcrUtf8NoBom)
    $unownedRejected = $false
    try {
        $null = Install-HcrPluginPayload -SourceInventory $inventory -TargetRoot $unowned
    }
    catch { $unownedRejected = $true }
    Assert-Gate4 $unownedRejected 'Installer did not reject an unowned target.'
    Assert-Gate4 ((Get-Content -LiteralPath $sentinel -Raw) -ceq 'preserve') `
        'Installer changed an unowned target.'
    Assert-Gate4 (-not (Test-Path -LiteralPath (
                Join-Path $unowned '.codex-plugin\install-ownership.json'
            ))) 'Installer planted an ownership marker in an unowned target.'

    $owned = Join-Path $testRoot 'owned'
    $manifest = Install-HcrPluginPayload -SourceInventory $inventory -TargetRoot $owned
    Assert-Gate4 ($manifest.files.Count -eq 31) `
        'Install manifest does not contain the complete payload.'
    Assert-Gate4 ([string]$manifest.sourceCommit -ceq [string]$inventory.sourceCommit) `
        'Install manifest source commit is wrong.'
    Assert-Gate4 ([string]$manifest.sourceVersion -ceq [string]$inventory.sourceVersion) `
        'Install manifest source version is wrong.'
    $state = Get-HcrInstalledPayloadState -SourceInventory $inventory -TargetRoot $owned
    Assert-Gate4 ($state.installed -and $state.owned -and $state.matches) `
        "Fresh owned install did not match: $($state.error)"

    $installedManifest = Read-HcrInstallJson (
        Join-Path $owned '.codex-plugin\install-manifest.json'
    )
    $manifestRows = @($installedManifest.files)
    Assert-Gate4 ($manifestRows.Count -eq 31) `
        'Serialized install manifest file count is wrong.'
    Assert-Gate4 (@($manifestRows | Where-Object {
                [IO.Path]::IsPathRooted([string]$_.path) -or
                [long]$_.size -lt 0 -or
                [string]$_.sha256 -notmatch '^[0-9a-f]{64}$'
            }).Count -eq 0) 'Serialized install manifest is not relative-path/size/SHA-256 bounded.'

    Add-Content -LiteralPath (Join-Path $owned '.codex-plugin\plugin.json') -Value 'tamper'
    $tampered = Get-HcrInstalledPayloadState -SourceInventory $inventory -TargetRoot $owned
    Assert-Gate4 (-not $tampered.matches) 'Installed hash tampering was not detected.'
    $null = Install-HcrPluginPayload -SourceInventory $inventory -TargetRoot $owned
    $repaired = Get-HcrInstalledPayloadState -SourceInventory $inventory -TargetRoot $owned
    Assert-Gate4 $repaired.matches 'Owned reinstall did not repair a tracked payload file.'

    $installedAdsPath = Join-Path $owned '.mcp.json'
    Add-Content -LiteralPath $installedAdsPath -Stream gate4Probe -Value 'hidden-installed-state'
    $installedAds = Get-HcrInstalledPayloadState -SourceInventory $inventory -TargetRoot $owned
    Assert-Gate4 (-not $installedAds.matches) `
        'Installed validation did not reject an alternate data stream.'
    $adsReinstallRejected = $false
    try { $null = Install-HcrPluginPayload -SourceInventory $inventory -TargetRoot $owned }
    catch { $adsReinstallRejected = $true }
    Assert-Gate4 $adsReinstallRejected `
        'Installer did not reject an alternate data stream in the owned target.'
    Remove-Item -LiteralPath $installedAdsPath -Stream gate4Probe -Force
    $null = Install-HcrPluginPayload -SourceInventory $inventory -TargetRoot $owned

    $outsideSentinel = Join-Path $testRoot 'hard-link-sentinel.json'
    [IO.File]::WriteAllText($outsideSentinel, 'outside-preserve', $script:HcrUtf8NoBom)
    $linkedPayload = Join-Path $owned '.codex-plugin\plugin.json'
    Remove-Item -LiteralPath $linkedPayload -Force
    $null = New-Item -ItemType HardLink -Path $linkedPayload -Target $outsideSentinel
    $hardLinkRejected = $false
    try { $null = Install-HcrPluginPayload -SourceInventory $inventory -TargetRoot $owned }
    catch { $hardLinkRejected = $true }
    Assert-Gate4 $hardLinkRejected 'Installer did not reject a hard-linked payload file.'
    Assert-Gate4 ((Get-Content -LiteralPath $outsideSentinel -Raw) -ceq 'outside-preserve') `
        'Installer followed a hard link and changed an outside sentinel.'
    Remove-Item -LiteralPath $linkedPayload -Force
    Copy-Item -LiteralPath (Join-Path $sourceRoot '.codex-plugin\plugin.json') `
        -Destination $linkedPayload
    $null = Install-HcrPluginPayload -SourceInventory $inventory -TargetRoot $owned

    $junctionPhysical = Join-Path $testRoot 'junction-physical'
    $junctionParent = Join-Path $testRoot 'junction-parent'
    $null = New-Item -ItemType Directory -Path $junctionPhysical
    $null = New-Item -ItemType Junction -Path $junctionParent -Target $junctionPhysical
    $junctionTarget = Join-Path $junctionParent 'redirected-install'
    $junctionRejected = $false
    try { $null = Install-HcrPluginPayload -SourceInventory $inventory -TargetRoot $junctionTarget }
    catch { $junctionRejected = $true }
    Assert-Gate4 $junctionRejected 'Installer did not reject a junction in the target ancestor chain.'
    Assert-Gate4 (-not (Test-Path -LiteralPath (Join-Path $junctionPhysical 'redirected-install'))) `
        'Installer wrote through a junction before rejecting the target.'

    $scratchRepo = Join-Path $testRoot 'scratch-repo'
    $scratchOutside = Join-Path $testRoot 'scratch-outside'
    $null = New-Item -ItemType Directory -Path $scratchRepo
    $null = New-Item -ItemType Directory -Path $scratchOutside
    $redirectedScratchPhysical = Join-Path `
        $scratchOutside `
        'plugin-creator-marketplace-probe'
    $null = New-Item -ItemType Directory -Path $redirectedScratchPhysical
    $scratchSentinel = Join-Path $redirectedScratchPhysical 'outside-sentinel.txt'
    [IO.File]::WriteAllText($scratchSentinel, 'preserve-outside', $script:HcrUtf8NoBom)
    $null = New-Item -ItemType Junction `
        -Path (Join-Path $scratchRepo '.artifacts') `
        -Target $scratchOutside
    $redirectedScratch = Join-Path $scratchRepo '.artifacts\plugin-creator-marketplace-probe'
    $scratchJunctionRejected = $false
    $scratchActionProbe = @{ invoked = $false }
    try {
        Invoke-HcrRepositoryScratchAction `
            -RepositoryRoot $scratchRepo `
            -ScratchRoot $redirectedScratch `
            -Action {
            param($unusedScratchRoot)
            $scratchActionProbe.invoked = $true
        }
    }
    catch { $scratchJunctionRejected = $true }
    Assert-Gate4 $scratchJunctionRejected `
        'Plugin-creator scratch validation did not reject an ancestor junction.'
    Assert-Gate4 (-not $scratchActionProbe.invoked) `
        'Plugin-creator scratch action was invoked through an ancestor junction.'
    Assert-Gate4 (Test-Path -LiteralPath $redirectedScratchPhysical -PathType Container) `
        'Plugin-creator scratch validation recursively removed an outside directory.'
    Assert-Gate4 ((Get-Content -LiteralPath $scratchSentinel -Raw) -ceq 'preserve-outside') `
        'Plugin-creator scratch validation changed an outside sentinel.'

    $unexpectedPath = Join-Path $owned 'unexpected.txt'
    [IO.File]::WriteAllText($unexpectedPath, 'do-not-delete', $script:HcrUtf8NoBom)
    $unexpectedRejected = $false
    try {
        $null = Install-HcrPluginPayload -SourceInventory $inventory -TargetRoot $owned
    }
    catch { $unexpectedRejected = $true }
    Assert-Gate4 $unexpectedRejected 'Installer did not reject an unexpected installed file.'
    Assert-Gate4 ((Get-Content -LiteralPath $unexpectedPath -Raw) -ceq 'do-not-delete') `
        'Installer deleted or changed an unexpected installed file.'
    Remove-Item -LiteralPath $unexpectedPath -Force

    $markerPath = Join-Path $owned '.codex-plugin\install-ownership.json'
    $marker = Read-HcrInstallJson $markerPath
    $marker.owner = 'someone-else/v1'
    Write-HcrInstallJson -Path $markerPath -Value $marker
    $markerRejected = $false
    try {
        $null = Install-HcrPluginPayload -SourceInventory $inventory -TargetRoot $owned
    }
    catch { $markerRejected = $true }
    Assert-Gate4 $markerRejected 'Installer did not reject a foreign ownership marker.'

    $installScript = Get-Content -LiteralPath (
        Join-Path $repoRoot 'scripts\install_plugin.ps1'
    ) -Raw -Encoding UTF8
    Assert-Gate4 ($installScript.Contains('create_basic_plugin.py') -and
        $installScript.Contains('read_marketplace_name.py') -and
        $installScript.Contains("plugin add 'hyperv-clean-room@personal'")) `
        'Installer does not use the required plugin-creator and Codex CLI workflow.'
    Assert-Gate4 ($installScript -notmatch '(?i)(Set-Content|WriteAllText).*marketplace') `
        'Installer appears to hand-edit marketplace state.'

    [ordered]@{
        ok = $true
        gate = 4
        assertions = $script:assertions
        sourceFiles = $inventory.fileCount
        overwriteProtection = $true
        hardLinksRejected = $true
        ancestorJunctionsRejected = $true
        scaffoldJunctionsRejected = $true
        alternateDataStreamsRejected = $true
        caseInsensitiveCollisionsRejected = $true
        manifestFields = @('path', 'size', 'sha256')
        realHyperVMutations = 0
    } | ConvertTo-Json -Compress
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

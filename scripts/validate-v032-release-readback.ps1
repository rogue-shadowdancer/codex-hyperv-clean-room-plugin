[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$Repository = 'rogue-shadowdancer/codex-hyperv-clean-room-plugin',

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-f0-9]{40}$')]
    [string]$ExpectedMasterCommit,

    [ValidateNotNullOrEmpty()]
    [string]$InstallRoot = (Join-Path $HOME 'plugins\hyperv-clean-room'),

    [ValidateNotNullOrEmpty()]
    [string]$MarketplacePath = (Join-Path $HOME '.agents\plugins\marketplace.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-HcrReadback {
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

function Get-HcrGitBlobBytes {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string]$ObjectSpec
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $script:GitCommand.Source
    $startInfo.Arguments = (
        '-C "{0}" cat-file blob "{1}"' -f
        $RepositoryRoot.Replace('"', '\"'),
        $ObjectSpec.Replace('"', '\"')
    )
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $memory = New-Object IO.MemoryStream
    try {
        Assert-HcrReadback $process.Start() `
            "Could not start git cat-file for $ObjectSpec."
        $process.StandardOutput.BaseStream.CopyTo($memory)
        $errorText = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        Assert-HcrReadback ($process.ExitCode -eq 0) `
            "git cat-file failed for $ObjectSpec`: $errorText"
        return ,$memory.ToArray()
    }
    finally {
        $memory.Dispose()
        $process.Dispose()
    }
}

function Get-HcrSha256Bytes {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString(
                $sha256.ComputeHash($Bytes)
            )).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Invoke-HcrGhApi {
    param([Parameter(Mandatory = $true)][string]$Endpoint)

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $script:GhCommand.Source api $Endpoint 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($exitCode -ne 0) {
        $detail = if ($output.Count -gt 0) { [string]$output[-1] } else { 'no detail' }
        throw "GitHub readback failed for $Endpoint`: $detail"
    }
    return (($output -join [Environment]::NewLine) | ConvertFrom-Json)
}

function Get-HcrAnnotatedTagIdentity {
    param([Parameter(Mandatory = $true)][string]$Tag)

    $reference = Invoke-HcrGhApi "repos/$Repository/git/ref/tags/$Tag"
    Assert-HcrReadback ([string]$reference.object.type -ceq 'tag') `
        "$Tag is not an annotated tag."
    $tagObjectSha = [string]$reference.object.sha
    Assert-HcrReadback ($tagObjectSha -cmatch '^[a-f0-9]{40}$') `
        "$Tag returned an invalid tag-object SHA."
    $tagObject = Invoke-HcrGhApi "repos/$Repository/git/tags/$tagObjectSha"
    Assert-HcrReadback ([string]$tagObject.object.type -ceq 'commit') `
        "$Tag does not peel directly to a commit."
    $peeledCommit = [string]$tagObject.object.sha
    Assert-HcrReadback ($peeledCommit -cmatch '^[a-f0-9]{40}$') `
        "$Tag returned an invalid peeled commit."

    return [pscustomobject][ordered]@{
        tag = $Tag
        tagObject = $tagObjectSha
        peeledCommit = $peeledCommit
    }
}

function Assert-HcrHistoricalRelease {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Baseline
    )

    $identity = Get-HcrAnnotatedTagIdentity $Baseline.tag
    Assert-HcrReadback ($identity.tagObject -ceq $Baseline.tagObject) `
        "$($Baseline.tag) tag object moved."
    Assert-HcrReadback ($identity.peeledCommit -ceq $Baseline.peeledCommit) `
        "$($Baseline.tag) peeled commit moved."

    $release = Invoke-HcrGhApi "repos/$Repository/releases/tags/$($Baseline.tag)"
    Assert-HcrReadback ([long]$release.id -eq [long]$Baseline.releaseId) `
        "$($Baseline.tag) Release identity changed."
    Assert-HcrReadback ([string]$release.tag_name -ceq $Baseline.tag) `
        "$($Baseline.tag) Release tag changed."
    Assert-HcrReadback (-not [bool]$release.draft -and -not [bool]$release.prerelease) `
        "$($Baseline.tag) Release flags changed."
    Assert-HcrReadback (@($release.assets).Count -eq 0) `
        "$($Baseline.tag) Release gained uploaded assets."
    Assert-HcrReadback ([string]$release.name -ceq $Baseline.name) `
        "$($Baseline.tag) Release name changed."
    Assert-HcrReadback ([string]$release.target_commitish -ceq
            $Baseline.targetCommitish) `
        "$($Baseline.tag) Release target descriptor changed."
    Assert-HcrReadback ([string]$release.created_at -ceq $Baseline.createdAt) `
        "$($Baseline.tag) Release creation identity changed."
    Assert-HcrReadback ([string]$release.published_at -ceq $Baseline.publishedAt) `
        "$($Baseline.tag) Release publication identity changed."

    return [pscustomobject][ordered]@{
        tag = $Baseline.tag
        tagObject = $identity.tagObject
        peeledCommit = $identity.peeledCommit
        releaseId = [long]$release.id
        releaseTarget = [string]$release.target_commitish
        createdAt = [string]$release.created_at
        publishedAt = [string]$release.published_at
        assets = @($release.assets).Count
    }
}

$script:GhCommand = Get-Command gh -ErrorAction Stop
$codexCommand = Get-Command codex -ErrorAction Stop
$gitCommand = Get-Command git -ErrorAction Stop
$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $repoRoot 'hyperv-clean-room'
. (Join-Path $PSScriptRoot 'install-common.ps1')

$branch = Invoke-HcrGhApi "repos/$Repository/branches/master"
$masterCommit = [string]$branch.commit.sha
Assert-HcrReadback ($masterCommit -cmatch '^[a-f0-9]{40}$') `
    'Protected master returned an invalid commit SHA.'
Assert-HcrReadback ([bool]$branch.protected) `
    'The GitHub master branch is not protected.'
Assert-HcrReadback ($masterCommit -ceq $ExpectedMasterCommit) `
    "Protected master $masterCommit does not equal expected $ExpectedMasterCommit."

$currentTag = Get-HcrAnnotatedTagIdentity 'v0.3.2'
Assert-HcrReadback ($currentTag.peeledCommit -ceq $masterCommit) `
    'Annotated v0.3.2 does not peel to protected master.'

$currentRelease = Invoke-HcrGhApi "repos/$Repository/releases/tags/v0.3.2"
Assert-HcrReadback ([string]$currentRelease.tag_name -ceq 'v0.3.2') `
    'The v0.3.2 Release tag is incorrect.'
Assert-HcrReadback ([string]$currentRelease.name -ceq 'v0.3.2') `
    'The v0.3.2 Release name is incorrect.'
Assert-HcrReadback ([string]$currentRelease.target_commitish -ceq $masterCommit) `
    'The v0.3.2 Release target does not equal protected master.'
Assert-HcrReadback (-not [bool]$currentRelease.draft -and
        -not [bool]$currentRelease.prerelease) `
    'The v0.3.2 Release is draft or prerelease.'
Assert-HcrReadback (-not [string]::IsNullOrWhiteSpace(
        [string]$currentRelease.published_at)) `
    'The v0.3.2 Release is not published.'
Assert-HcrReadback (@($currentRelease.assets).Count -eq 0) `
    'The v0.3.2 source-only Release has uploaded assets.'

$historicalBaselines = @(
    [pscustomobject]@{
        tag = 'v0.1.1'
        tagObject = '5edafb08c16a20d2994b4049367d481c67d56d57'
        peeledCommit = '4bed14c8a7df068fcd8e827418e7c20527a2f271'
        releaseId = 354281298
        name = 'v0.1.1'
        targetCommitish = 'master'
        createdAt = '2026-07-15T08:04:14Z'
        publishedAt = '2026-07-15T08:05:46Z'
    },
    [pscustomobject]@{
        tag = 'v0.2.0'
        tagObject = '05ef3f5f61c78865e399eeb7e1673383dccc2db4'
        peeledCommit = '642f20d1d74a54ecbb08115b1a921ca65ef01fb8'
        releaseId = 357961129
        name = 'v0.2.0'
        targetCommitish = 'master'
        createdAt = '2026-07-22T11:12:41Z'
        publishedAt = '2026-07-22T11:15:30Z'
    },
    [pscustomobject]@{
        tag = 'v0.3.0'
        tagObject = 'c4046176e848a0fe8afde58eac35b0f62fed098f'
        peeledCommit = '47151fdbe99346ec87af09460c79d0864978eabd'
        releaseId = 361734463
        name = 'v0.3.0'
        targetCommitish = 'master'
        createdAt = '2026-07-29T12:19:15Z'
        publishedAt = '2026-07-29T12:21:34Z'
    },
    [pscustomobject]@{
        tag = 'v0.3.1'
        tagObject = '7e063dab8634b3208b8298864cb81ff0c36e3e72'
        peeledCommit = '8c97145c8c629f393c8411d84bd7e180b39ff339'
        releaseId = 362034753
        name = 'v0.3.1'
        targetCommitish = '8c97145c8c629f393c8411d84bd7e180b39ff339'
        createdAt = '2026-07-29T20:32:52Z'
        publishedAt = '2026-07-29T20:34:59Z'
    }
)
$historical = @($historicalBaselines | ForEach-Object {
        Assert-HcrHistoricalRelease $_
    })

$previousNoReplaceObjects = [Environment]::GetEnvironmentVariable(
    'GIT_NO_REPLACE_OBJECTS',
    [EnvironmentVariableTarget]::Process
)
$sourceInventory = $null
try {
    $env:GIT_NO_REPLACE_OBJECTS = '1'
    $repoHead = [string](& $gitCommand.Source -C $repoRoot rev-parse HEAD)
    Assert-HcrReadback ($LASTEXITCODE -eq 0 -and
            $repoHead.Trim() -ceq $ExpectedMasterCommit) `
        'The release-readback checkout HEAD does not equal ExpectedMasterCommit.'
    $sourceStatus = @(& $gitCommand.Source -C $repoRoot status `
            --porcelain=v1 --untracked-files=all -- hyperv-clean-room)
    Assert-HcrReadback ($LASTEXITCODE -eq 0 -and $sourceStatus.Count -eq 0) `
        ('The reviewed plugin source has index, worktree, or untracked changes: ' +
            ($sourceStatus -join '; '))
    $verboseIndex = @(& $gitCommand.Source -C $repoRoot ls-files -v `
            -- hyperv-clean-room)
    $assumeUnchanged = @($verboseIndex | Where-Object {
            [string]$_ -cmatch '^[a-z] '
        })
    Assert-HcrReadback ($LASTEXITCODE -eq 0 -and $assumeUnchanged.Count -eq 0) `
        ('The reviewed plugin source contains assume-unchanged index flags: ' +
            ($assumeUnchanged -join '; '))
    $taggedIndex = @(& $gitCommand.Source -C $repoRoot ls-files -t `
            -- hyperv-clean-room)
    $skipWorktree = @($taggedIndex | Where-Object {
            [string]$_ -cmatch '^S '
        })
    Assert-HcrReadback ($LASTEXITCODE -eq 0 -and $skipWorktree.Count -eq 0) `
        ('The reviewed plugin source contains skip-worktree index flags: ' +
            ($skipWorktree -join '; '))

    $sourceInventory = Get-HcrSourceInventory `
        -SourceRoot $sourceRoot `
        -RequireCachebuster
    Assert-HcrReadback ([string]$sourceInventory.sourceCommit -ceq
            $ExpectedMasterCommit) `
        'The reviewed source checkout does not equal ExpectedMasterCommit.'
    Assert-HcrReadback ([string]$sourceInventory.sourceVersion -ceq
            '0.3.2+codex.20260731014242') `
        'The reviewed source checkout is not the single frozen v0.3.2 build.'
    foreach ($payload in @($sourceInventory.files)) {
        $payloadPath = [string]$payload.path
        $repositoryPath = "hyperv-clean-room/$payloadPath"
        $workingPath = Join-Path $sourceRoot $payloadPath.Replace('/', '\')
        $committedBytes = Get-HcrGitBlobBytes `
            -RepositoryRoot $repoRoot `
            -ObjectSpec "$ExpectedMasterCommit`:$repositoryPath"
        if ($payloadPath.EndsWith('.ps1', [StringComparison]::OrdinalIgnoreCase)) {
            $strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
            $committedText = $strictUtf8.GetString($committedBytes)
            Assert-HcrReadback (-not $committedText.Contains("`r")) `
                "Reviewed PowerShell blob is not LF-normalized: $repositoryPath"
            $expectedBytes = $strictUtf8.GetBytes(
                $committedText.Replace("`n", "`r`n")
            )
        }
        elseif ($payloadPath -cmatch '\.(json|md|ya?ml)$') {
            $expectedBytes = $committedBytes
        }
        else {
            throw "Unsupported v0.3.2 payload type: $repositoryPath"
        }
        $workingBytes = [IO.File]::ReadAllBytes($workingPath)
        $expectedHash = Get-HcrSha256Bytes $expectedBytes
        $workingHash = Get-HcrSha256Bytes $workingBytes
        Assert-HcrReadback ($workingHash -ceq $expectedHash -and
                $workingHash -ceq [string]$payload.sha256) `
            "Working payload bytes differ from the reviewed commit: $repositoryPath"
    }
}
finally {
    if ($null -eq $previousNoReplaceObjects) {
        Remove-Item Env:\GIT_NO_REPLACE_OBJECTS -ErrorAction SilentlyContinue
    }
    else {
        $env:GIT_NO_REPLACE_OBJECTS = $previousNoReplaceObjects
    }
}

$resolvedInstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$installCheck = Get-HcrInstallCheck `
    -SourceInventory $sourceInventory `
    -TargetRoot $resolvedInstallRoot `
    -MarketplacePath $MarketplacePath
Assert-HcrReadback ([bool]$installCheck.installed -and
        [bool]$installCheck.owned -and
        [bool]$installCheck.matches) `
    "Installed payload/ownership closure failed: $($installCheck.payloadError)"
Assert-HcrReadback ([bool]$installCheck.marketplaceVisible -and
        [int]$installCheck.marketplaceEntryCount -eq 1) `
    "Installed marketplace/Codex closure failed: $($installCheck.marketplaceError)"
Assert-HcrReadback ([int]$installCheck.sourceFileCount -eq 31) `
    'Reviewed source inventory payload count is not 31.'

$installManifestPath = Join-Path $resolvedInstallRoot '.codex-plugin\install-manifest.json'
Assert-HcrReadback (Test-Path -LiteralPath $installManifestPath -PathType Leaf) `
    "Missing install manifest: $installManifestPath"
$installManifest = Get-Content -LiteralPath $installManifestPath -Raw |
    ConvertFrom-Json
Assert-HcrReadback ([string]$installManifest.pluginName -ceq 'hyperv-clean-room') `
    'The installed manifest names the wrong plugin.'
Assert-HcrReadback ([string]$installManifest.sourceCommit -ceq $masterCommit) `
    'Installed sourceCommit does not equal protected master.'
Assert-HcrReadback ([string]$installManifest.sourceVersion -ceq
        '0.3.2+codex.20260731014242') `
    'Installed sourceVersion is not the frozen v0.3.2 build.'
Assert-HcrReadback (@($installManifest.files).Count -eq 31) `
    'Installed manifest payload count is not 31.'
$ordinaryInstallFiles = @(Get-ChildItem -LiteralPath $resolvedInstallRoot `
        -File -Recurse -Force)
Assert-HcrReadback ($ordinaryInstallFiles.Count -eq 33) `
    'Installed ordinary-file inventory count is not 33.'

Assert-HcrReadback (Test-Path -LiteralPath $MarketplacePath -PathType Leaf) `
    "Missing personal marketplace: $MarketplacePath"
$marketplace = Get-Content -LiteralPath $MarketplacePath -Raw | ConvertFrom-Json
$marketplaceEntries = @($marketplace.plugins | Where-Object {
        [string]$_.name -ceq 'hyperv-clean-room'
    })
Assert-HcrReadback ($marketplaceEntries.Count -eq 1) `
    'Personal marketplace does not contain exactly one Hyper-V Clean Room entry.'

$previousPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $pluginListOutput = @(& $codexCommand.Source plugin list --json 2>&1)
    $pluginListExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousPreference
}
if ($pluginListExitCode -ne 0) {
    $detail = if ($pluginListOutput.Count -gt 0) {
        [string]$pluginListOutput[-1]
    }
    else { 'no detail' }
    throw "Codex plugin readback failed: $detail"
}
$pluginList = ($pluginListOutput -join [Environment]::NewLine) | ConvertFrom-Json
$installedEntries = @($pluginList.installed | Where-Object {
        [string]$_.pluginId -ceq 'hyperv-clean-room@personal'
    })
Assert-HcrReadback ($installedEntries.Count -eq 1) `
    'Codex does not report exactly one personal Hyper-V Clean Room installation.'
$installedEntry = $installedEntries[0]
Assert-HcrReadback ([bool]$installedEntry.installed -and [bool]$installedEntry.enabled) `
    'The personal Hyper-V Clean Room plugin is not installed and enabled.'
Assert-HcrReadback ([string]$installedEntry.version -ceq
        [string]$installManifest.sourceVersion) `
    'Codex plugin version does not match install-manifest sourceVersion.'
Assert-HcrReadback ([IO.Path]::GetFullPath([string]$installedEntry.source.path) -ieq
        $resolvedInstallRoot) `
    'Codex plugin source path does not match the installed root.'

[ordered]@{
    ok = $true
    repository = $Repository
    protectedMaster = $masterCommit
    tag = $currentTag.tag
    tagObject = $currentTag.tagObject
    tagPeeledCommit = $currentTag.peeledCommit
    releaseId = [long]$currentRelease.id
    releaseTarget = [string]$currentRelease.target_commitish
    releaseDraft = [bool]$currentRelease.draft
    releasePrerelease = [bool]$currentRelease.prerelease
    releaseAssets = @($currentRelease.assets).Count
    installedVersion = [string]$installManifest.sourceVersion
    installedSourceCommit = [string]$installManifest.sourceCommit
    payloadFiles = @($installManifest.files).Count
    ordinaryInstallFiles = $ordinaryInstallFiles.Count
    marketplaceEntries = $marketplaceEntries.Count
    codexInstalled = [bool]$installedEntry.installed
    codexEnabled = [bool]$installedEntry.enabled
    historical = $historical
} | ConvertTo-Json -Depth 6 -Compress

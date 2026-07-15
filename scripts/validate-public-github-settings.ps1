[CmdletBinding()]
param(
    [string]$Repository = 'rogue-shadowdancer/codex-hyperv-clean-room-plugin'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedDescription = 'Guarded Windows Hyper-V clean-room and package lifecycle testing for Codex via typed MCP tools.'
$expectedTopics = @(
    'clean-room',
    'codex-plugin',
    'hyper-v',
    'mcp-server',
    'package-testing',
    'powershell',
    'test-automation',
    'virtualization',
    'windows'
)
$requiredCheck = 'public-release-validation'
$gh = Get-Command gh -ErrorAction Stop

function Assert-PublicSetting {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw $Message }
}

function Invoke-GhRead {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $gh.Source @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "gh read failed: $($output -join ' ')"
    }
    return [pscustomobject]@{
        exitCode = $exitCode
        text = [string]($output -join [Environment]::NewLine)
    }
}

$viewRead = Invoke-GhRead -Arguments @(
    'repo', 'view', $Repository, '--json',
    'nameWithOwner,url,visibility,isPrivate,defaultBranchRef,description,homepageUrl,hasIssuesEnabled,hasWikiEnabled,hasProjectsEnabled,hasDiscussionsEnabled,repositoryTopics,licenseInfo'
)
$view = $viewRead.text | ConvertFrom-Json -ErrorAction Stop
Assert-PublicSetting ([string]$view.nameWithOwner -ceq $Repository) `
    'Repository owner/name differs from the release contract.'
Assert-PublicSetting (-not [bool]$view.isPrivate -and
    [string]$view.visibility -ceq 'PUBLIC') 'Repository is not public.'
Assert-PublicSetting ([string]$view.defaultBranchRef.name -ceq 'master') `
    'Default branch is not master.'
Assert-PublicSetting ([string]$view.description -ceq $expectedDescription) `
    'Repository description differs from the release contract.'
Assert-PublicSetting ([string]::IsNullOrEmpty([string]$view.homepageUrl)) `
    'Repository homepage must remain empty.'
Assert-PublicSetting ([bool]$view.hasIssuesEnabled -and
    -not [bool]$view.hasWikiEnabled -and
    -not [bool]$view.hasProjectsEnabled -and
    -not [bool]$view.hasDiscussionsEnabled) `
    'Repository feature settings differ from the release contract.'
Assert-PublicSetting ([string]$view.licenseInfo.spdxId -ceq 'GPL-3.0') `
    'GitHub did not detect GNU GPL v3.'
$actualTopics = @($view.repositoryTopics | ForEach-Object {
        [string]$_.name
    } | Sort-Object)
Assert-PublicSetting ($actualTopics.Count -eq $expectedTopics.Count -and
    @(Compare-Object $expectedTopics $actualTopics).Count -eq 0) `
    'Repository topics differ from the exact release set.'

$pagesRead = Invoke-GhRead -Arguments @(
    'api', "repos/$Repository/pages"
) -AllowFailure
Assert-PublicSetting ($pagesRead.exitCode -ne 0 -and
    $pagesRead.text -match '(?i)(HTTP 404|Not Found)') `
    'GitHub Pages is enabled or its disabled state could not be proven.'

$vulnerabilityRead = Invoke-GhRead -Arguments @(
    'api', "repos/$Repository/private-vulnerability-reporting"
)
$vulnerability = $vulnerabilityRead.text | ConvertFrom-Json -ErrorAction Stop
Assert-PublicSetting ([bool]$vulnerability.enabled) `
    'Private vulnerability reporting is not enabled.'

$protectionRead = Invoke-GhRead -Arguments @(
    'api', "repos/$Repository/branches/master/protection"
)
$protection = $protectionRead.text | ConvertFrom-Json -ErrorAction Stop
$contexts = @($protection.required_status_checks.contexts |
    ForEach-Object { [string]$_ } | Sort-Object)
Assert-PublicSetting ([bool]$protection.required_status_checks.strict -and
    $contexts.Count -eq 1 -and $contexts[0] -ceq $requiredCheck) `
    'Required status-check protection differs from the release contract.'
Assert-PublicSetting (-not [bool]$protection.enforce_admins.enabled) `
    'Branch protection must use enforce_admins false.'
$reviews = $protection.required_pull_request_reviews
Assert-PublicSetting ($null -ne $reviews -and
    -not [bool]$reviews.dismiss_stale_reviews -and
    -not [bool]$reviews.require_code_owner_reviews -and
    [int]$reviews.required_approving_review_count -eq 1 -and
    -not [bool]$reviews.require_last_push_approval) `
    'Pull-request review protection differs from the release contract.'
Assert-PublicSetting ([bool]$protection.required_conversation_resolution.enabled) `
    'Conversation resolution is not required.'
Assert-PublicSetting (-not [bool]$protection.allow_force_pushes.enabled -and
    -not [bool]$protection.allow_deletions.enabled -and
    -not [bool]$protection.required_linear_history.enabled -and
    -not [bool]$protection.block_creations.enabled -and
    -not [bool]$protection.lock_branch.enabled -and
    -not [bool]$protection.allow_fork_syncing.enabled) `
    'Branch Boolean protections differ from the release contract.'
$restrictionProperty = $protection.PSObject.Properties['restrictions']
Assert-PublicSetting ($null -ne $restrictionProperty -and
    $null -eq $restrictionProperty.Value) 'Branch restrictions must be null.'

$signatureRead = Invoke-GhRead -Arguments @(
    'api', "repos/$Repository/branches/master/protection/required_signatures"
) -AllowFailure
Assert-PublicSetting ($signatureRead.exitCode -ne 0 -and
    $signatureRead.text -match '(?i)(HTTP 404|Not Found)') `
    'Signed commits must remain an explicit disabled setting for v0.1.1.'

[ordered]@{
    ok = $true
    repository = $Repository
    visibility = 'PUBLIC'
    description = $expectedDescription
    homepage = ''
    topics = $expectedTopics
    issues = $true
    wiki = $false
    projects = $false
    discussions = $false
    pages = $false
    privateVulnerabilityReporting = $true
    requiredStatusCheck = $requiredCheck
    strictStatusChecks = $true
    approvals = 1
    conversationResolution = $true
    enforceAdmins = $false
    forcePushes = $false
    deletions = $false
    requiredSignatures = $false
} | ConvertTo-Json -Depth 5 -Compress

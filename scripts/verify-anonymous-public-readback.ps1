[CmdletBinding()]
param(
    [string]$ExpectedSha = (& git -C (Split-Path -Parent $PSScriptRoot) rev-parse HEAD)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($ExpectedSha -notmatch '^[0-9a-f]{40}$') {
    throw 'ExpectedSha must be a complete lowercase Git commit ID.'
}
$repoRoot = Split-Path -Parent $PSScriptRoot
$artifactRoot = Join-Path $repoRoot '.artifacts\public-release\anonymous'
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null
$curl = Get-Command curl.exe -ErrorAction Stop
$repository = 'rogue-shadowdancer/codex-hyperv-clean-room-plugin'
$apiBase = "https://api.github.com/repos/$repository"

function Get-AnonymousFile {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [switch]$Api
    )

    $arguments = @(
        '-fsSL', '--retry', '3', '--retry-all-errors',
        '-H', 'User-Agent: hyperv-clean-room-public-readback'
    )
    if ($Api) { $arguments += @('-H', 'Accept: application/vnd.github+json') }
    $arguments += @('-o', $OutputPath, $Url)
    & $curl.Source @arguments
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
        throw "Anonymous HTTP read failed: $Url"
    }
}

$repoJsonPath = Join-Path $artifactRoot 'repository.json'
$branchJsonPath = Join-Path $artifactRoot 'master.json'
Get-AnonymousFile -Url $apiBase -OutputPath $repoJsonPath -Api
Get-AnonymousFile -Url "$apiBase/branches/master" -OutputPath $branchJsonPath -Api
$repositoryState = [IO.File]::ReadAllText($repoJsonPath, $strictUtf8) |
    ConvertFrom-Json -ErrorAction Stop
$branchState = [IO.File]::ReadAllText($branchJsonPath, $strictUtf8) |
    ConvertFrom-Json -ErrorAction Stop
if ([bool]$repositoryState.private -or [string]$repositoryState.visibility -cne 'public') {
    throw 'Anonymous repository API does not report public visibility.'
}
if ([string]$repositoryState.default_branch -cne 'master') {
    throw 'Anonymous repository API reports an unexpected default branch.'
}
if ([string]$repositoryState.license.spdx_id -cne 'GPL-3.0') {
    throw 'Anonymous repository API did not detect GNU GPL v3.'
}
if ([string]$branchState.commit.sha -cne $ExpectedSha) {
    throw 'Anonymous master SHA differs from the expected release commit.'
}

$chineseCenterMarker = -join @(
    [char]0x7B80, [char]0x4F53, [char]0x4E2D, [char]0x6587
)
$profileGuideMarker = -join @(
    [char]0x6D4B, [char]0x8BD5, ' profile ',
    [char]0x7F16, [char]0x5199, [char]0x6307, [char]0x5357
)
$required = [ordered]@{
    'README.md' = 'v0.1.1 GPL public release'
    'LICENSE' = 'GNU GENERAL PUBLIC LICENSE'
    'hyperv-clean-room/.codex-plugin/plugin.json' = 'GPL-3.0-only'
    'hyperv-clean-room/skills/manage-hyperv-clean-room/SKILL.md' = 'Hyper-V'
    'docs/README.md' = $chineseCenterMarker
    'docs/profile-authoring.md' = $profileGuideMarker
}
$readFiles = 0
foreach ($entry in $required.GetEnumerator()) {
    $safeName = ([string]$entry.Key -replace '[^A-Za-z0-9._-]', '_')
    $path = Join-Path $artifactRoot $safeName
    $url = "https://raw.githubusercontent.com/$repository/$ExpectedSha/$($entry.Key)"
    Get-AnonymousFile -Url $url -OutputPath $path
    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw "Anonymous source has a UTF-8 BOM: $($entry.Key)"
    }
    $text = $strictUtf8.GetString($bytes)
    foreach ($marker in @(
            [char]0xFFFD, [char]0x00C3, [char]0x00C2,
            [char]0x9225, [char]0x951B, [char]0x9286
        )) {
        if ($text.Contains([string]$marker)) {
            throw "Anonymous source has mojibake: $($entry.Key)"
        }
    }
    if ($text.IndexOf([string]$entry.Value, [StringComparison]::Ordinal) -lt 0) {
        throw "Anonymous source is missing its expected marker: $($entry.Key)"
    }
    if ([string]$entry.Key -ceq 'LICENSE') {
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -cne '3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986') {
            throw 'Anonymous LICENSE differs from the canonical GNU GPL v3 text.'
        }
    }
    $readFiles++
}

[ordered]@{
    ok = $true
    anonymous = $true
    visibility = 'public'
    defaultBranch = 'master'
    headSha = $ExpectedSha
    licenseSpdx = 'GPL-3.0'
    strictUtf8Files = $readFiles
    bomFiles = 0
    mojibakeFiles = 0
} | ConvertTo-Json -Compress

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$requiredDocuments = @(
    'README.md',
    'SECURITY.md',
    'TASK_HANDOFF.md',
    'docs\README.md',
    'docs\specification.md',
    'docs\profile-authoring.md',
    'docs\architecture.md',
    'docs\installation.md',
    'docs\maintenance.md',
    'docs\operations.md',
    'docs\evidence.md',
    'docs\security.md',
    'docs\troubleshooting.md'
)
$requiredPhrases = [ordered]@{
    'docs\architecture.md' = @('PowerShell Direct', 'trust boundar', 'operation-scoped', '16')
    'docs\installation.md' = @('install_plugin.ps1', 'check_install.ps1', 'ownership', 'marketplaceVisible', 'SHA-256')
    'docs\maintenance.md' = @('update_plugin_cachebuster.py', 'plugin add', 'sourceCommit', 'new Codex task')
    'docs\operations.md' = @('inspect_host', 'Initialize-GuestCredential.ps1', 'prepare-test-python.ps1', 'real Hyper-V mutation')
    'docs\evidence.md' = @('sourceSha256', 'guestSha256', 'cleanupTriggered', 'manual')
    'docs\security.md' = @('DPAPI', 'plaintext', 'reparse', 'arbitrary')
    'docs\troubleshooting.md' = @('prepare-test-python.ps1', 'INVALID_ISO', 'ARTIFACT_HASH_MISMATCH', 'PowerShell Direct')
    'SECURITY.md' = @('report', 'credential', 'VM', 'supported')
}
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
$texts = @{}
$errors = New-Object System.Collections.Generic.List[string]

function Get-MarkdownAnchors {
    param([Parameter(Mandatory = $true)][string]$Text)

    $anchors = @{}
    $counts = @{}
    foreach ($match in [regex]::Matches($Text, '(?m)^\s{0,3}#{1,6}\s+(?<heading>.+?)\s*#*\s*$')) {
        $heading = [string]$match.Groups['heading'].Value
        $heading = [regex]::Replace($heading, '<[^>]+>', '')
        $heading = $heading.Replace('`', '').ToLowerInvariant()
        $slug = [regex]::Replace($heading, '[^\p{L}\p{Nd}_\- ]', '')
        $slug = [regex]::Replace($slug.Trim(), '\s', '-')
        if ([string]::IsNullOrWhiteSpace($slug)) { continue }
        $count = if ($counts.ContainsKey($slug)) { [int]$counts[$slug] } else { 0 }
        $anchor = if ($count -eq 0) { $slug } else { "$slug-$count" }
        $counts[$slug] = $count + 1
        $anchors[$anchor] = $true
    }
    foreach ($match in [regex]::Matches(
        $Text,
        '(?i)<a\s+[^>]*(?:id|name)\s*=\s*["''](?<anchor>[^"'']+)["''][^>]*>'
    )) {
        $anchors[[string]$match.Groups['anchor'].Value] = $true
    }
    return $anchors
}

foreach ($relative in $requiredDocuments) {
    $path = Join-Path $repoRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $errors.Add("Missing required document: $relative")
        continue
    }
    try {
        $bytes = [IO.File]::ReadAllBytes($path)
        $text = $strictUtf8.GetString($bytes)
    }
    catch {
        $errors.Add("Document is not strict UTF-8: $relative")
        continue
    }
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) {
        $errors.Add("Document has a UTF-8 BOM: $relative")
    }
    foreach ($marker in @(
        [char]0xFFFD,
        [char]0x00C3,
        [char]0x00C2,
        [char]0x9225,
        [char]0x951B,
        [char]0x9286
    )) {
        if ($text.Contains([string]$marker)) {
            $errors.Add("Document contains a mojibake marker '$marker': $relative")
        }
    }
    $texts[$relative] = $text
}

foreach ($entry in $requiredPhrases.GetEnumerator()) {
    if (-not $texts.ContainsKey($entry.Key)) { continue }
    foreach ($phrase in $entry.Value) {
        if ($texts[$entry.Key].IndexOf($phrase, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            $errors.Add("Document '$($entry.Key)' is missing required topic '$phrase'.")
        }
    }
}

$linkCount = 0
foreach ($relative in $requiredDocuments) {
    if (-not $texts.ContainsKey($relative)) { continue }
    $sourcePath = Join-Path $repoRoot $relative
    $sourceDirectory = Split-Path -Parent $sourcePath
    foreach ($match in [regex]::Matches($texts[$relative], '\[[^\]]+\]\((?<target>[^)]+)\)')) {
        $target = [string]$match.Groups['target'].Value
        if ($target.StartsWith('<') -and $target.EndsWith('>')) {
            $target = $target.Substring(1, $target.Length - 2)
        }
        if ([string]::IsNullOrWhiteSpace($target) -or
            $target -match '^[a-zA-Z][a-zA-Z0-9+.-]*:') {
            continue
        }
        $targetParts = @($target -split '#', 2)
        $pathPart = $targetParts[0]
        $fragment = if ($targetParts.Count -gt 1) {
            [Uri]::UnescapeDataString([string]$targetParts[1])
        }
        else { '' }
        $pathPart = [Uri]::UnescapeDataString($pathPart)
        $linkCount++
        $resolved = if ([string]::IsNullOrWhiteSpace($pathPart)) {
            [IO.Path]::GetFullPath($sourcePath)
        }
        else {
            [IO.Path]::GetFullPath((Join-Path $sourceDirectory $pathPart))
        }
        $repoPrefix = [IO.Path]::GetFullPath($repoRoot).TrimEnd('\', '/') + '\'
        if (-not (($resolved + '\').StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase))) {
            $errors.Add("Local link escapes the repository: $relative -> $target")
            continue
        }
        if (-not (Test-Path -LiteralPath $resolved)) {
            $errors.Add("Broken local link: $relative -> $target")
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace($fragment)) {
            if ([IO.Path]::GetExtension($resolved) -ine '.md') {
                $errors.Add("Fragment link does not target Markdown: $relative -> $target")
                continue
            }
            $targetText = if ($resolved -eq $sourcePath) {
                $texts[$relative]
            }
            else {
                $strictUtf8.GetString([IO.File]::ReadAllBytes($resolved))
            }
            $anchors = Get-MarkdownAnchors $targetText
            if (-not $anchors.ContainsKey($fragment)) {
                $errors.Add("Broken local fragment: $relative -> $target")
            }
        }
    }
}

if ($errors.Count -gt 0) {
    $bounded = @($errors | Select-Object -First 20)
    throw ("Documentation validation failed ({0} issue(s)): {1}" -f `
        $errors.Count, ($bounded -join ' | '))
}

[ordered]@{
    ok = $true
    documents = $requiredDocuments.Count
    localLinks = $linkCount
    strictUtf8 = $true
    mojibakeMarkers = 0
} | ConvertTo-Json -Compress

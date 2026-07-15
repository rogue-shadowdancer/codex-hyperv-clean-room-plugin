[CmdletBinding()]
param(
    [string]$Repository = 'rogue-shadowdancer/codex-hyperv-clean-room-plugin',
    [switch]$PolicySelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
$allowedEmail = '78423508+rogue-shadowdancer@users.noreply.github.com'
$emailPattern = [regex]'(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
$secretAssignmentPattern = [regex](
    '(?im)(?:^|\t)\s*\$?(?<key>password|passwd|secret)\s*[:=]\s*' +
    '(?<value>[^\r\n\t]+)'
)
$patterns = [ordered]@{
    'private key' = '-----BEGIN [A-Z ]+ PRIVATE KEY-----'
    'GitHub token' = '\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b'
    'AWS access key' = '\bAKIA[0-9A-Z]{16}\b'
    'API key' = '\bsk-[A-Za-z0-9_-]{20,}\b'
    'credentialed URL' = '(?i)https?://[^/:\s]+:[^@\s/]+@'
    'private Windows user path' = '(?i)\b[A-Z]:\\Users\\(?!(?:runneradmin|Default|Public)(?:\\|$))'
    'private workspace path' = '(?i)\b[A-Z]:\\study\\'
    'private Unix user path' = '(?i)/(?:Users|home)/(?!(?:runner|dependabot|github)(?:/|$))[^/\s]+'
    'Birdsgone path or state' = '(?i)(?:^|[\\/])birdsgone(?:[\\/]|\b)'
    'VM or image state file' = '(?i)(?:^|[\\/\s])[^\s\\/]+\.(?:iso|vhd|vhdx|avhd|avhdx|vmcx|vmgs|vmrs|vsv|clixml)(?:\b|\s)'
    'machine-state directory' = '(?i)(?:^|[\\/])(?:artifacts|cache|caches|checkpoint|checkpoints|credentials|evidence|install-state|installed-copy|installed-state|log|logs|plans|vm|vm-state|vms)(?:[\\/]|$)'
    'log state file' = '(?i)(?:^|[\\/\s])[^\s\\/]+\.log(?:\b|\s)'
    'evidence control file' = '(?i)(?:^|[\\/\s])(?:evidence|inventory)\.json(?:\b|\s)'
    'installed control file' = '(?i)(?:install-manifest|install-ownership)\.json(?:\b|\s)'
}

function Test-HcrSafeSecretValue {
    param([Parameter(Mandatory = $true)][string]$Value)

    $candidate = $Value.Trim().TrimEnd(',', ';')
    if ($candidate.Length -ge 2 -and
        (($candidate[0] -eq [char]0x22 -and $candidate[$candidate.Length - 1] -eq [char]0x22) -or
         ($candidate[0] -eq [char]0x27 -and $candidate[$candidate.Length - 1] -eq [char]0x27))) {
        $candidate = $candidate.Substring(1, $candidate.Length - 2)
    }
    $folded = $candidate.Trim().ToLowerInvariant()
    if ($folded -in @('', 'null', 'none', '~', 'redacted', '<redacted>',
            '[redacted]', '***redacted***') -or $candidate -match '^\*{3,}$') {
        return $true
    }
    return [bool]($candidate -match '^\$\{[A-Za-z_][A-Za-z0-9_]*\}$' -or
        $candidate -match '^\$env:[A-Za-z_][A-Za-z0-9_]*$' -or
        $candidate -match '^\$[A-Za-z_][A-Za-z0-9_]*$' -or
        $candidate -match '^%[A-Za-z_][A-Za-z0-9_]*%$' -or
        $candidate -match '^\{\{[^{}]+\}\}$' -or
        $candidate -match '^\$\{\{[^{}]+\}\}$' -or
        $candidate -match '(?i)^(?:env|secret|vault):(?://)?[A-Za-z_][A-Za-z0-9_./-]*$' -or
        $candidate -match '(?i)^(?:process\.env\.|secrets\.)[A-Za-z_][A-Za-z0-9_]*$')
}

function Get-HcrActionsLogFindings {
    param([Parameter(Mandatory = $true)][string]$Text)

    $findings = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $patterns.GetEnumerator()) {
        if ([regex]::IsMatch($Text, [string]$entry.Value)) {
            $findings.Add([string]$entry.Key)
        }
    }
    foreach ($match in $emailPattern.Matches($Text)) {
        if ([string]$match.Value -ine $allowedEmail) {
            $findings.Add('non-public email')
        }
    }
    foreach ($match in $secretAssignmentPattern.Matches($Text)) {
        if (-not (Test-HcrSafeSecretValue ([string]$match.Groups['value'].Value))) {
            $findings.Add("plaintext $($match.Groups['key'].Value) literal")
        }
    }
    return @($findings | Sort-Object -Unique)
}

if ($PolicySelfTest) {
    $allowed = @(
        ('C:' + '\Users\runneradmin\work\repo'),
        ('C:' + '\Users\Default\profile'),
        ('C:' + '\Users\Public\Documents'),
        ('/' + 'home/' + 'runner/work/repo'),
        ('/' + 'home/' + 'dependabot/dependabot-updates'),
        'D:\a\repo\.artifacts\test-python',
        ('pass' + 'word: <redacted>'),
        ('sec' + 'ret=${{ secrets.VALUE }}')
    )
    foreach ($text in $allowed) {
        $found = @(Get-HcrActionsLogFindings $text)
        if ($found.Count -ne 0) {
            throw "Actions hygiene policy rejected a safe fixture: $($found -join ', ')"
        }
    }
    $rejected = @(
        ('C:' + '\Users\runneradmin-private\secret'),
        ('C:' + '\Users\Default-user\secret'),
        ('/' + 'home/' + 'runner-private/secret'),
        ('/' + 'home/' + 'github.old/secret'),
        ('pass' + 'word=hunter' + '2'),
        'checkpoint\stock\state.txt',
        'cache\result.txt',
        'logs\output.txt',
        'artifacts\output.txt',
        'vm\owned\state.txt',
        ('https://' + 'user:value' + '@example.test/repo')
    )
    foreach ($text in $rejected) {
        $found = @(Get-HcrActionsLogFindings $text)
        if ($found.Count -eq 0) {
            throw 'Actions hygiene policy accepted an unsafe fixture.'
        }
    }
    [ordered]@{
        ok = $true
        allowedFixtures = $allowed.Count
        rejectedFixtures = $rejected.Count
        exactRunnerSegments = $true
        secretLiteralPolicy = $true
        machineStatePolicy = $true
    } | ConvertTo-Json -Compress
    return
}

$logRoot = Join-Path $repoRoot '.artifacts\public-release\actions'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$gh = Get-Command gh -ErrorAction Stop

$totalOutput = @(& $gh.Source api (
        "repos/$Repository/actions/runs?per_page=1"
    ) --jq '.total_count' 2>&1)
if ($LASTEXITCODE -ne 0 -or $totalOutput.Count -ne 1 -or
    [string]$totalOutput[0] -notmatch '^[0-9]+$') {
    throw 'Unable to read the authoritative Actions run count.'
}
$expectedRunCount = [int]$totalOutput[0]
if ($expectedRunCount -gt 1000) {
    throw 'Actions history exceeds the bounded 1000-run scanner limit.'
}

$runJson = @(& $gh.Source run list --repo $Repository --limit 1000 --json (
        'databaseId,status,conclusion,url,name,workflowName,headSha,headBranch,event'
    ) 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to enumerate GitHub Actions history: $($runJson -join ' ')"
}
$parsedRuns = ([string]($runJson -join [Environment]::NewLine)) |
    ConvertFrom-Json -ErrorAction Stop
$runs = @($parsedRuns | ForEach-Object { $_ })
if ($runs.Count -ne $expectedRunCount -or $runs.Count -eq 0) {
    throw "Actions run enumeration is incomplete: expected $expectedRunCount, got $($runs.Count)."
}

$totalLines = 0
$totalBytes = 0L
foreach ($run in $runs) {
    if ([string]$run.status -cne 'completed') {
        throw "Actions run $($run.databaseId) is not complete."
    }
    $lines = @(& $gh.Source run view ([string]$run.databaseId) `
            --repo $Repository --log 2>&1)
    if ($LASTEXITCODE -ne 0 -or $lines.Count -eq 0) {
        throw "Actions log is unavailable for run $($run.databaseId)."
    }
    $text = ($lines | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    $path = Join-Path $logRoot ("run-$($run.databaseId).log")
    [IO.File]::WriteAllText($path, $text + [Environment]::NewLine, $strictUtf8)
    $totalLines += $lines.Count
    $totalBytes += ([IO.FileInfo]$path).Length

    $findings = @(Get-HcrActionsLogFindings $text)
    if ($findings.Count -gt 0) {
        throw "Actions hygiene found $($findings[0]) in run $($run.databaseId)."
    }
}

[ordered]@{
    ok = $true
    repository = $Repository
    runsScanned = $runs.Count
    authoritativeRunCount = $expectedRunCount
    logLinesScanned = $totalLines
    logBytesScanned = $totalBytes
    sensitiveFindings = 0
    credentialedUrls = 0
    privatePaths = 0
    forbiddenStateFiles = 0
    logRoot = $logRoot
} | ConvertTo-Json -Compress

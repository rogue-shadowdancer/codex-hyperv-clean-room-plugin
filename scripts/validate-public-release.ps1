[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$logRoot = Join-Path $repoRoot '.artifacts\public-release\local'
$runtimePath = Join-Path $repoRoot '.artifacts\test-python\runtime.json'
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$windowsPowerShell = Join-Path $env:SystemRoot (
    'System32\WindowsPowerShell\v1.0\powershell.exe'
)

function Invoke-ReleaseCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $Action 2>&1 | ForEach-Object { $lines.Add([string]$_) }
    }
    catch {
        $lines.Add(($_ | Out-String).TrimEnd())
        $path = Join-Path $logRoot ($Name + '.log')
        [IO.File]::WriteAllLines($path, $lines, $strictUtf8)
        $tail = @($lines | Select-Object -Last 12) -join [Environment]::NewLine
        throw "Release check '$Name' failed. Log: $path`n$tail"
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    $path = Join-Path $logRoot ($Name + '.log')
    [IO.File]::WriteAllLines($path, $lines, $strictUtf8)
    Write-Output "PASS $Name"
}

function Invoke-IsolatedPowerShellScript {
    param([Parameter(Mandatory = $true)][string]$Path)

    & $windowsPowerShell -NoLogo -NoProfile -NonInteractive `
        -ExecutionPolicy Bypass -File $Path
    if ($LASTEXITCODE -ne 0) {
        throw "Isolated PowerShell validator failed with exit code $LASTEXITCODE`: $Path"
    }
}

if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
    throw 'Run scripts\prepare-test-python.ps1 before public-release validation.'
}
$runtime = Get-Content -LiteralPath $runtimePath -Raw -Encoding UTF8 |
    ConvertFrom-Json -ErrorAction Stop
$pythonCommand = [string]$runtime.pythonCommand
$pythonArguments = @($runtime.pythonArguments | ForEach-Object { [string]$_ })
$pluginValidator = Join-Path $HOME (
    '.codex\skills\.system\plugin-creator\scripts\validate_plugin.py'
)
$skillValidator = Join-Path $HOME (
    '.codex\skills\.system\skill-creator\scripts\quick_validate.py'
)
foreach ($path in @($pythonCommand, $pluginValidator, $skillValidator)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required release validator is unavailable: $path"
    }
}

$oldPythonPath = $env:PYTHONPATH
$oldNoUserSite = $env:PYTHONNOUSERSITE
try {
    $env:PYTHONPATH = [string]$runtime.dependencyPath
    $env:PYTHONNOUSERSITE = '1'

    Invoke-ReleaseCheck -Name 'powershell-parser' -Action {
        $raw = & git -C $repoRoot ls-files -z --cached --others --exclude-standard
        if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed.' }
        $paths = @(([string]$raw -split [char]0) | Where-Object {
                $_ -and [IO.Path]::GetExtension($_) -ieq '.ps1'
            })
        $errors = New-Object System.Collections.Generic.List[string]
        foreach ($relative in $paths) {
            $tokens = $null
            $parseErrors = $null
            [void][Management.Automation.Language.Parser]::ParseFile(
                (Join-Path $repoRoot $relative),
                [ref]$tokens,
                [ref]$parseErrors
            )
            foreach ($error in @($parseErrors)) {
                $errors.Add(('{0}:{1}: {2}' -f $relative,
                        $error.Extent.StartLineNumber, $error.Message))
            }
        }
        if ($errors.Count -gt 0) { throw ($errors -join [Environment]::NewLine) }
        [ordered]@{ ok = $true; scripts = $paths.Count } |
            ConvertTo-Json -Compress
    }

    Invoke-ReleaseCheck -Name 'repository-formats' -Action {
        & $pythonCommand @pythonArguments -S (
            Join-Path $repoRoot 'tests\repository_format_tests.py'
        )
        if ($LASTEXITCODE -ne 0) { throw 'repository format validation failed.' }
    }

    Invoke-ReleaseCheck -Name 'git-diff-check' -Action {
        & git -C $repoRoot diff --check
        if ($LASTEXITCODE -ne 0) { throw 'git diff --check failed.' }
        & git -C $repoRoot diff --cached --check
        if ($LASTEXITCODE -ne 0) { throw 'git diff --cached --check failed.' }
    }

    Invoke-ReleaseCheck -Name 'plugin-validator' -Action {
        & $pythonCommand @pythonArguments -S $pluginValidator (
            Join-Path $repoRoot 'hyperv-clean-room'
        )
        if ($LASTEXITCODE -ne 0) { throw 'plugin validation failed.' }
    }

    Invoke-ReleaseCheck -Name 'skill-validator' -Action {
        & $pythonCommand @pythonArguments -S $skillValidator (
            Join-Path $repoRoot 'hyperv-clean-room\skills\manage-hyperv-clean-room'
        )
        if ($LASTEXITCODE -ne 0) { throw 'skill validation failed.' }
    }

    Invoke-ReleaseCheck -Name 'gate1' -Action {
        Invoke-IsolatedPowerShellScript (
            Join-Path $PSScriptRoot 'validate-gate1.ps1'
        )
    }
    Invoke-ReleaseCheck -Name 'gate2' -Action {
        Invoke-IsolatedPowerShellScript (
            Join-Path $PSScriptRoot 'validate-gate2.ps1'
        )
    }
    Invoke-ReleaseCheck -Name 'documentation' -Action {
        Invoke-IsolatedPowerShellScript (
            Join-Path $PSScriptRoot 'validate-docs.ps1'
        )
    }
    Invoke-ReleaseCheck -Name 'publication-policy-regressions' -Action {
        & $pythonCommand @pythonArguments -S (
            Join-Path $repoRoot 'tests\publication_hygiene_policy_tests.py'
        )
        if ($LASTEXITCODE -ne 0) { throw 'publication policy regressions failed.' }
    }
    Invoke-ReleaseCheck -Name 'actions-log-policy-regressions' -Action {
        Invoke-IsolatedPowerShellScript (
            Join-Path $repoRoot 'tests\actions-log-hygiene.tests.ps1'
        )
    }
    Invoke-ReleaseCheck -Name 'publication-tree-history-identity' -Action {
        & $pythonCommand @pythonArguments -S (
            Join-Path $repoRoot 'tests\publication_hygiene_tests.py'
        )
        if ($LASTEXITCODE -ne 0) { throw 'publication hygiene failed.' }
    }
    Invoke-ReleaseCheck -Name 'public-release-contract' -Action {
        & $pythonCommand @pythonArguments -S (
            Join-Path $repoRoot 'tests\public_release_contract_tests.py'
        )
        if ($LASTEXITCODE -ne 0) { throw 'public-release contract failed.' }
    }
    Invoke-ReleaseCheck -Name 'gate4-ci-safe' -Action {
        Invoke-IsolatedPowerShellScript (
            Join-Path $PSScriptRoot 'validate-gate4-ci.ps1'
        )
    }
}
finally {
    $env:PYTHONPATH = $oldPythonPath
    $env:PYTHONNOUSERSITE = $oldNoUserSite
}

[ordered]@{
    ok = $true
    gate = '5.1'
    checks = 13
    logRoot = $logRoot
    realGuestOperations = 0
    realHyperVMutations = 0
} | ConvertTo-Json -Compress

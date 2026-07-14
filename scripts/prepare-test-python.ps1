[CmdletBinding()]
param(
    [string]$PythonCommand,
    [string[]]$PythonArguments = @(),
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$requirementsPath = Join-Path $repoRoot 'requirements-dev.txt'
$artifactRoot = Join-Path $repoRoot '.artifacts\test-python'
$runtimePath = Join-Path $artifactRoot 'runtime.json'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-PythonProbe {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments
    )

    $commandInfo = Get-Command $Command -ErrorAction SilentlyContinue
    if ($null -eq $commandInfo) { return $null }
    $executable = if (-not [string]::IsNullOrWhiteSpace([string]$commandInfo.Source)) {
        [string]$commandInfo.Source
    }
    else { [string]$commandInfo.Path }
    if ([string]::IsNullOrWhiteSpace($executable)) { return $null }
    $probeCode = @'
import json
import platform
import sys
import sysconfig
print(json.dumps({
    'version': platform.python_version(),
    'major': sys.version_info.major,
    'minor': sys.version_info.minor,
    'implementation': platform.python_implementation(),
    'cacheTag': sys.implementation.cache_tag,
    'platformTag': sysconfig.get_platform(),
    'machine': platform.machine(),
    'executable': sys.executable,
}, sort_keys=True))
'@
    try {
        $output = & $executable @Arguments -c $probeCode 2>$null
        if ($LASTEXITCODE -ne 0 -or @($output).Count -ne 1) { return $null }
        $probe = [string]$output | ConvertFrom-Json -ErrorAction Stop
        if ([int]$probe.major -ne 3 -or [int]$probe.minor -lt 10) { return $null }
        return [pscustomobject][ordered]@{
            command = $executable
            arguments = @($Arguments)
            version = [string]$probe.version
            implementation = [string]$probe.implementation
            cacheTag = [string]$probe.cacheTag
            platformTag = [string]$probe.platformTag
            machine = [string]$probe.machine
            executable = [string]$probe.executable
        }
    }
    catch {
        return $null
    }
}

if (-not (Test-Path -LiteralPath $requirementsPath -PathType Leaf)) {
    throw 'requirements-dev.txt is missing; the isolated test environment cannot be prepared.'
}
if ([string]::IsNullOrWhiteSpace($PythonCommand)) {
    $probe = Get-PythonProbe -Command 'python' -Arguments @()
    if ($null -eq $probe) {
        $probe = Get-PythonProbe -Command 'py.exe' -Arguments @('-3.10')
    }
    if ($null -eq $probe) {
        $probe = Get-PythonProbe -Command 'py.exe' -Arguments @('-3')
    }
}
else {
    $probe = Get-PythonProbe -Command $PythonCommand -Arguments $PythonArguments
}
if ($null -eq $probe) {
    throw 'No supported Python 3.10+ interpreter was found. Pass -PythonCommand and optional -PythonArguments explicitly.'
}

$requirementsHash = (Get-FileHash -LiteralPath $requirementsPath -Algorithm SHA256).Hash.ToLowerInvariant()
$abiLabel = (($probe.cacheTag + '-' + $probe.platformTag) -replace '[^a-zA-Z0-9._-]', '-').ToLowerInvariant()
$dependencyPath = Join-Path (Join-Path (Join-Path $artifactRoot $abiLabel) $requirementsHash.Substring(0, 16)) 'site-packages'
$expectedPackages = [ordered]@{
    attrs = '26.1.0'
    jsonschema = '4.26.0'
    'jsonschema-specifications' = '2025.9.1'
    pyyaml = '6.0.3'
    referencing = '0.37.0'
    'rpds-py' = '0.30.0'
    'typing-extensions' = '4.16.0'
}
$expectedJson = $expectedPackages | ConvertTo-Json -Compress
$expectedBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($expectedJson))
$verifyCode = @'
import base64
import importlib.metadata as metadata
import json
import re
import sys
expected = json.loads(base64.b64decode(sys.argv[1]).decode('utf-8'))
dependency_path = sys.argv[2]
actual_items = []
for distribution in metadata.distributions(path=[dependency_path]):
    name = distribution.metadata.get('Name')
    if name:
        actual_items.append((re.sub(r'[-_.]+', '-', name).lower(), distribution.version))
if len(actual_items) != len(set(name for name, _ in actual_items)):
    raise SystemExit('prepared dependency directory contains duplicate distributions')
actual = dict(actual_items)
if actual != expected:
    raise SystemExit('prepared dependency inventory does not exactly match requirements-dev.txt')
import jsonschema
import yaml
print(json.dumps(actual, sort_keys=True))
'@

$ready = $false
if (-not $Force -and (Test-Path -LiteralPath $dependencyPath -PathType Container)) {
    $oldPythonPath = $env:PYTHONPATH
    $oldNoUserSite = $env:PYTHONNOUSERSITE
    try {
        $env:PYTHONPATH = $dependencyPath
        $env:PYTHONNOUSERSITE = '1'
        $null = & $probe.command @($probe.arguments) -S -c `
            $verifyCode $expectedBase64 $dependencyPath 2>$null
        $ready = $LASTEXITCODE -eq 0
    }
    finally {
        $env:PYTHONPATH = $oldPythonPath
        $env:PYTHONNOUSERSITE = $oldNoUserSite
    }
}

if (-not $ready) {
    $artifactFull = [IO.Path]::GetFullPath($artifactRoot).TrimEnd('\', '/') + '\'
    $dependencyFull = [IO.Path]::GetFullPath($dependencyPath)
    if (-not (($dependencyFull + '\').StartsWith(
        $artifactFull,
        [StringComparison]::OrdinalIgnoreCase
    ))) {
        throw 'The development dependency cache escaped the repository artifact root.'
    }
    if (Test-Path -LiteralPath $dependencyFull) {
        Remove-Item -LiteralPath $dependencyFull -Recurse -Force -ErrorAction Stop
    }
    [void](New-Item -ItemType Directory -Path $dependencyFull -ErrorAction Stop)
    $oldDisablePip = $env:PIP_DISABLE_PIP_VERSION_CHECK
    $oldNoInput = $env:PIP_NO_INPUT
    try {
        $env:PIP_DISABLE_PIP_VERSION_CHECK = '1'
        $env:PIP_NO_INPUT = '1'
        & $probe.command @($probe.arguments) -m pip install `
            --disable-pip-version-check `
            --no-input `
            --no-deps `
            --only-binary=:all: `
            --upgrade `
            --target $dependencyPath `
            --requirement $requirementsPath
        if ($LASTEXITCODE -ne 0) {
            throw 'Pinned development dependencies could not be installed into the ABI-isolated artifact directory.'
        }
    }
    finally {
        $env:PIP_DISABLE_PIP_VERSION_CHECK = $oldDisablePip
        $env:PIP_NO_INPUT = $oldNoInput
    }
}

$oldPythonPath = $env:PYTHONPATH
$oldNoUserSite = $env:PYTHONNOUSERSITE
try {
    $env:PYTHONPATH = $dependencyPath
    $env:PYTHONNOUSERSITE = '1'
    $verified = & $probe.command @($probe.arguments) -S -c `
        $verifyCode $expectedBase64 $dependencyPath 2>$null
    if ($LASTEXITCODE -ne 0 -or @($verified).Count -ne 1) {
        throw 'The ABI-isolated development dependency readback failed.'
    }
}
finally {
    $env:PYTHONPATH = $oldPythonPath
    $env:PYTHONNOUSERSITE = $oldNoUserSite
}

if (-not (Test-Path -LiteralPath $artifactRoot -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $artifactRoot -Force)
}
$preparedAt = [DateTimeOffset]::UtcNow.ToString('o')
$preserveRuntime = $false
if ($ready -and (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
    try {
        $existingRuntime = Get-Content -LiteralPath $runtimePath -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop
        $existingArguments = [string]::Join(
            [char]0x1F,
            [string[]]@($existingRuntime.pythonArguments | ForEach-Object { [string]$_ })
        )
        $currentArguments = [string]::Join([char]0x1F, [string[]]@($probe.arguments))
        $preserveRuntime = [int]$existingRuntime.schemaVersion -eq 1 -and
            [string]$existingRuntime.pythonCommand -ieq $probe.command -and
            $existingArguments -ceq $currentArguments -and
            [string]$existingRuntime.pythonExecutable -ieq $probe.executable -and
            [string]$existingRuntime.pythonVersion -ceq $probe.version -and
            [string]$existingRuntime.implementation -ceq $probe.implementation -and
            [string]$existingRuntime.cacheTag -ceq $probe.cacheTag -and
            [string]$existingRuntime.platformTag -ceq $probe.platformTag -and
            [string]$existingRuntime.machine -ceq $probe.machine -and
            [string]$existingRuntime.abiLabel -ceq $abiLabel -and
            [string]$existingRuntime.dependencyPath -ieq ([IO.Path]::GetFullPath($dependencyPath)) -and
            [string]$existingRuntime.requirementsPath -ieq ([IO.Path]::GetFullPath($requirementsPath)) -and
            [string]$existingRuntime.requirementsSha256 -ceq $requirementsHash -and
            -not [string]::IsNullOrWhiteSpace([string]$existingRuntime.preparedAt)
        if ($preserveRuntime) { $preparedAt = [string]$existingRuntime.preparedAt }
    }
    catch {
        $preserveRuntime = $false
    }
}
$runtime = [ordered]@{
    schemaVersion = 1
    pythonCommand = $probe.command
    pythonArguments = @($probe.arguments)
    pythonExecutable = $probe.executable
    pythonVersion = $probe.version
    implementation = $probe.implementation
    cacheTag = $probe.cacheTag
    platformTag = $probe.platformTag
    machine = $probe.machine
    abiLabel = $abiLabel
    dependencyPath = [IO.Path]::GetFullPath($dependencyPath)
    requirementsPath = [IO.Path]::GetFullPath($requirementsPath)
    requirementsSha256 = $requirementsHash
    preparedAt = $preparedAt
}
if (-not $preserveRuntime) {
    [IO.File]::WriteAllText(
        $runtimePath,
        (($runtime | ConvertTo-Json -Depth 10) + "`n"),
        $utf8NoBom
    )
}

[ordered]@{
    ok = $true
    pythonVersion = $probe.version
    abiLabel = $abiLabel
    requirementsSha256 = $requirementsHash
    dependencyPath = [IO.Path]::GetFullPath($dependencyPath)
    reused = $ready
} | ConvertTo-Json -Compress

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}$')]
    [string]$ProfileName,

    [Parameter(Mandatory = $true)]
    [ValidateLength(1, 100)]
    [string]$VmName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Join-Path $PSScriptRoot 'lib') 'Common.ps1')
. (Join-Path (Join-Path $PSScriptRoot 'lib') 'State.ps1')

if (-not (Get-Command Invoke-Command -ErrorAction SilentlyContinue) -or
    -not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
    throw 'PowerShell Direct and the Hyper-V PowerShell module are required.'
}
if ($null -eq (Get-VM -Name $VmName -ErrorAction SilentlyContinue)) {
    throw 'The requested VM does not exist.'
}

$administratorCredential = Get-Credential `
    -Message 'Enter the guest orchestration administrator credential.'
$testUserCredential = Get-Credential `
    -Message 'Enter the distinct standard guest test-user credential.'

$identityProbe = {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    [pscustomobject][ordered]@{
        sid = [string]$identity.User.Value
        isAdministrator = $principal.IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator
        )
    }
}

try {
    $administratorIdentity = Invoke-Command `
        -VMName $VmName `
        -Credential $administratorCredential `
        -ScriptBlock $identityProbe `
        -ErrorAction Stop
}
catch {
    throw 'The orchestration administrator could not open a PowerShell Direct session.'
}

$session = $null
try {
    $session = New-PSSession `
        -VMName $VmName `
        -Credential $administratorCredential `
        -ErrorAction Stop
    $testUserIdentity = Invoke-Command -Session $session -ArgumentList $testUserCredential -ScriptBlock {
        param([pscredential]$StandardCredential)

        $probeRoot = Join-Path $env:ProgramData (
            'Codex\hyperv-clean-room\credential-probe\' + [Guid]::NewGuid().ToString('N')
        )
        [void](New-Item -ItemType Directory -Path $probeRoot -Force)
        $probeScript = Join-Path $probeRoot 'probe.ps1'
        $probeOutput = Join-Path $probeRoot 'identity.json'
        $probeContent = @'
param([string]$OutputPath)
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$result = [ordered]@{
    sid = [string]$identity.User.Value
    isAdministrator = $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText(
    $OutputPath,
    ($result | ConvertTo-Json -Compress),
    $utf8
)
'@
        [IO.File]::WriteAllText(
            $probeScript,
            $probeContent,
            (New-Object System.Text.UTF8Encoding($false))
        )
        $arguments = @(
            '-NoLogo',
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            ('"{0}"' -f $probeScript),
            '-OutputPath',
            ('"{0}"' -f $probeOutput)
        )
        $process = Start-Process `
            -FilePath 'powershell.exe' `
            -Credential $StandardCredential `
            -LoadUserProfile `
            -ArgumentList $arguments `
            -Wait `
            -PassThru `
            -WindowStyle Hidden
        if ($process.ExitCode -ne 0 -or
            -not (Test-Path -LiteralPath $probeOutput -PathType Leaf)) {
            throw 'The standard-user identity probe failed.'
        }
        $result = Get-Content -LiteralPath $probeOutput -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop
        Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue
        return $result
    } -ErrorAction Stop
}
catch {
    throw 'The standard test user could not be validated under administrator supervision.'
}
finally {
    if ($null -ne $session) {
        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    }
}

if (-not [bool](Get-HcrPropertyValue $administratorIdentity 'isAdministrator' $false)) {
    throw 'The orchestration identity is not a guest administrator.'
}
if ([bool](Get-HcrPropertyValue $testUserIdentity 'isAdministrator' $true)) {
    throw 'The test identity must be a standard non-administrator user.'
}
$administratorSid = [string](Get-HcrPropertyValue $administratorIdentity 'sid')
$testUserSid = [string](Get-HcrPropertyValue $testUserIdentity 'sid')
if ([string]::IsNullOrWhiteSpace($administratorSid) -or
    [string]::IsNullOrWhiteSpace($testUserSid) -or
    $administratorSid -eq $testUserSid) {
    throw 'The two credential roles must have distinct validated SIDs.'
}

$credentialRoot = Get-HcrCredentialRoot
if (-not (Test-Path -LiteralPath $credentialRoot -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $credentialRoot -Force)
}
$credentialRootItem = Get-Item -LiteralPath $credentialRoot -Force
if (($credentialRootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'The credential root cannot be a reparse point.'
}
$profileDirectory = Get-HcrNormalizedPath (Join-Path $credentialRoot $ProfileName)
if (-not (Test-HcrPathWithin $profileDirectory $credentialRoot)) {
    throw 'The profile path escapes the credential root.'
}
if (Test-Path -LiteralPath $profileDirectory) {
    throw 'A credential profile with this name already exists.'
}
[void](New-Item -ItemType Directory -Path $profileDirectory)

$administratorCredential | Export-Clixml `
    -LiteralPath (Join-Path $profileDirectory 'orchestration-admin.clixml') `
    -Depth 4
$testUserCredential | Export-Clixml `
    -LiteralPath (Join-Path $profileDirectory 'standard-test-user.clixml') `
    -Depth 4
$metadata = [ordered]@{
    schemaVersion = 1
    profileName = $ProfileName
    vmName = $VmName
    administratorSid = $administratorSid
    testUserSid = $testUserSid
    createdAt = Get-HcrUtcTimestamp
}
[IO.File]::WriteAllText(
    (Join-Path $profileDirectory 'profile.json'),
    (($metadata | ConvertTo-Json -Depth 5 -Compress) + "`n"),
    (New-Object System.Text.UTF8Encoding($false))
)

[pscustomobject][ordered]@{
    ok = $true
    profileName = $ProfileName
    vmName = $VmName
    rolesValidated = $true
    dpapiScope = 'current-user-current-machine'
}

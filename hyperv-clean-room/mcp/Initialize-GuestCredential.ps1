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
    $groups = @($identity.Groups | ForEach-Object { [string]$_.Value })
    $integrity = if ($groups -contains 'S-1-16-16384') { 'system' }
        elseif ($groups -contains 'S-1-16-12288') { 'high' }
        elseif ($groups -contains 'S-1-16-8448') { 'mediumPlus' }
        elseif ($groups -contains 'S-1-16-8192') { 'medium' }
        elseif ($groups -contains 'S-1-16-4096') { 'low' }
        else { 'unknown' }
    [pscustomobject][ordered]@{
        sid = [string]$identity.User.Value
        hasAdministratorsSid = $groups -contains 'S-1-5-32-544'
        isAdministrator = $principal.IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator
        )
        tokenIntegrity = $integrity
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

try {
    $testUserIdentity = Invoke-Command `
        -VMName $VmName `
        -Credential $testUserCredential `
        -ScriptBlock $identityProbe `
        -ErrorAction Stop
}
catch {
    throw 'The standard test user could not open the fixed PowerShell Direct identity probe.'
}

if (-not [bool](Get-HcrPropertyValue $administratorIdentity 'isAdministrator' $false) -or
    -not [bool](Get-HcrPropertyValue $administratorIdentity 'hasAdministratorsSid' $false) -or
    @('high', 'system') -notcontains [string](Get-HcrPropertyValue $administratorIdentity 'tokenIntegrity')) {
    throw 'The orchestration identity is not a guest administrator.'
}
if ([bool](Get-HcrPropertyValue $testUserIdentity 'isAdministrator' $true) -or
    [bool](Get-HcrPropertyValue $testUserIdentity 'hasAdministratorsSid' $true) -or
    [string](Get-HcrPropertyValue $testUserIdentity 'tokenIntegrity') -ne 'medium') {
    throw 'The test identity must be outside Administrators and have exact medium integrity.'
}
$administratorSid = [string](Get-HcrPropertyValue $administratorIdentity 'sid')
$testUserSid = [string](Get-HcrPropertyValue $testUserIdentity 'sid')
if ([string]::IsNullOrWhiteSpace($administratorSid) -or
    [string]::IsNullOrWhiteSpace($testUserSid) -or
    $administratorSid -eq $testUserSid) {
    throw 'The two credential roles must have distinct validated SIDs.'
}

function Assert-HcrPrivateCredentialAcl {
    param([Parameter(Mandatory = $true)][string]$Path)

    $expectedSids = @(
        [Security.Principal.WindowsIdentity]::GetCurrent().User.Value,
        'S-1-5-18',
        'S-1-5-32-544'
    )
    $readback = Get-Acl -LiteralPath $Path -ErrorAction Stop
    if (-not $readback.AreAccessRulesProtected) {
        throw 'A credential directory still inherits parent permissions.'
    }
    $owner = $readback.GetOwner([Security.Principal.SecurityIdentifier])
    if ([string]$owner.Value -ne $expectedSids[0]) {
        throw 'A credential directory owner is not the current Windows user.'
    }
    $rules = @($readback.GetAccessRules(
        $true,
        $true,
        [Security.Principal.SecurityIdentifier]
    ))
    $expectedInheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
        [Security.AccessControl.InheritanceFlags]::ObjectInherit
    if ($rules.Count -ne $expectedSids.Count) {
        throw 'A credential directory contains an unexpected number of access rules.'
    }
    foreach ($sidValue in $expectedSids) {
        $matches = @($rules | Where-Object {
            -not $_.IsInherited -and
            $_.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
            [string]$_.IdentityReference.Value -eq $sidValue -and
            $_.FileSystemRights -eq [Security.AccessControl.FileSystemRights]::FullControl -and
            $_.InheritanceFlags -eq $expectedInheritance -and
            $_.PropagationFlags -eq [Security.AccessControl.PropagationFlags]::None
        })
        if ($matches.Count -ne 1) {
            throw 'A credential directory full-control ACL is missing or duplicated.'
        }
    }
    if (@($rules | Where-Object {
        $_.IsInherited -or
        $_.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or
        $expectedSids -notcontains [string]$_.IdentityReference.Value
    }).Count -ne 0) {
        throw 'A credential directory contains an unexpected access rule.'
    }
}

function Set-HcrPrivateCredentialAcl {
    param([Parameter(Mandatory = $true)][string]$Path)

    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner($currentSid)
    foreach ($sidValue in @(
        $currentSid.Value,
        'S-1-5-18',
        'S-1-5-32-544'
    )) {
        $sid = New-Object Security.Principal.SecurityIdentifier($sidValue)
        $rule = New-Object Security.AccessControl.FileSystemAccessRule(
            $sid,
            [Security.AccessControl.FileSystemRights]::FullControl,
            [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow
        )
        [void]$acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
    Assert-HcrPrivateCredentialAcl $Path
}

$appDataRoot = (Assert-HcrLocalDirectory $env:APPDATA 'CREDENTIAL_ROOT_INVALID').FullName
$credentialRoot = $appDataRoot
foreach ($segment in @('Codex', 'hyperv-clean-room', 'credentials')) {
    $credentialRoot = Join-Path $credentialRoot $segment
    if (-not (Test-Path -LiteralPath $credentialRoot)) {
        try { [void](New-Item -ItemType Directory -Path $credentialRoot -ErrorAction Stop) }
        catch {
            if (-not (Test-Path -LiteralPath $credentialRoot -PathType Container)) { throw }
        }
    }
    [void](Assert-HcrLocalDirectory $credentialRoot 'CREDENTIAL_ROOT_INVALID')
}
if ((Get-HcrNormalizedPath $credentialRoot) -ne (Get-HcrNormalizedPath (Get-HcrCredentialRoot))) {
    throw 'The credential root resolved to an unexpected path.'
}
Set-HcrPrivateCredentialAcl $credentialRoot
$profileDirectory = Get-HcrNormalizedPath (Join-Path $credentialRoot $ProfileName)
if (-not (Test-HcrPathWithin $profileDirectory $credentialRoot)) {
    throw 'The profile path escapes the credential root.'
}
if (Test-Path -LiteralPath $profileDirectory) {
    throw 'A credential profile with this name already exists.'
}
$temporaryDirectory = Get-HcrNormalizedPath (
    Join-Path $credentialRoot ('.pending-' + [Guid]::NewGuid().ToString('N'))
)
if (-not (Test-HcrPathWithin $temporaryDirectory $credentialRoot)) {
    throw 'The temporary credential profile path escaped its root.'
}
$published = $false
try {
    [void](New-Item -ItemType Directory -Path $temporaryDirectory -ErrorAction Stop)
    Set-HcrPrivateCredentialAcl $temporaryDirectory
    $administratorPath = Join-Path $temporaryDirectory 'orchestration-admin.clixml'
    $testUserPath = Join-Path $temporaryDirectory 'standard-test-user.clixml'
    $metadataPath = Join-Path $temporaryDirectory 'profile.json'
    $administratorCredential | Export-Clixml -LiteralPath $administratorPath -Depth 4
    $testUserCredential | Export-Clixml -LiteralPath $testUserPath -Depth 4
    $metadata = [ordered]@{
        schemaVersion = 1
        profileName = $ProfileName
        vmName = $VmName
        administratorSid = $administratorSid
        testUserSid = $testUserSid
        createdAt = Get-HcrUtcTimestamp
    }
    [IO.File]::WriteAllText(
        $metadataPath,
        (($metadata | ConvertTo-Json -Depth 5 -Compress) + "`n"),
        (New-Object System.Text.UTF8Encoding($false))
    )
    foreach ($path in @($administratorPath, $testUserPath, $metadataPath)) {
        $item = Assert-HcrRegularLocalFile $path 'CREDENTIAL_PROFILE_INVALID'
        if ($item.Length -lt 1 -or $item.Length -gt 1MB) {
            throw 'A credential profile component is outside its size bound.'
        }
    }
    $administratorReadback = Import-Clixml -LiteralPath $administratorPath -ErrorAction Stop
    $testUserReadback = Import-Clixml -LiteralPath $testUserPath -ErrorAction Stop
    if ($administratorReadback -isnot [pscredential] -or
        $testUserReadback -isnot [pscredential] -or
        $administratorReadback.UserName -ne $administratorCredential.UserName -or
        $testUserReadback.UserName -ne $testUserCredential.UserName) {
        throw 'DPAPI credential readback failed before profile publication.'
    }
    $metadataReadback = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -ErrorAction Stop
    if ([int](Get-HcrPropertyValue $metadataReadback 'schemaVersion') -ne 1 -or
        [string](Get-HcrPropertyValue $metadataReadback 'profileName') -ne $ProfileName -or
        [string](Get-HcrPropertyValue $metadataReadback 'vmName') -ne $VmName -or
        [string](Get-HcrPropertyValue $metadataReadback 'administratorSid') -ne $administratorSid -or
        [string](Get-HcrPropertyValue $metadataReadback 'testUserSid') -ne $testUserSid) {
        throw 'Credential metadata readback failed before profile publication.'
    }
    [void](Publish-HcrCredentialDirectory `
        $temporaryDirectory `
        $profileDirectory `
        $credentialRoot)

    $publishedDirectory = Assert-HcrLocalDirectory $profileDirectory 'CREDENTIAL_PROFILE_INVALID'
    Assert-HcrPrivateCredentialAcl $publishedDirectory.FullName
    $publishedChildren = @(Get-ChildItem -LiteralPath $publishedDirectory.FullName -Force)
    $expectedNames = @(
        'orchestration-admin.clixml',
        'standard-test-user.clixml',
        'profile.json'
    )
    if ($publishedChildren.Count -ne 3 -or
        @($publishedChildren | Where-Object {
            $_.PSIsContainer -or
            ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            $expectedNames -notcontains $_.Name
        }).Count -ne 0) {
        throw 'The atomically published credential profile is not the exact three-file bundle.'
    }
    $publishedAdministratorPath = Join-Path $publishedDirectory.FullName 'orchestration-admin.clixml'
    $publishedTestUserPath = Join-Path $publishedDirectory.FullName 'standard-test-user.clixml'
    $publishedMetadataPath = Join-Path $publishedDirectory.FullName 'profile.json'
    foreach ($path in @($publishedAdministratorPath, $publishedTestUserPath, $publishedMetadataPath)) {
        $item = Assert-HcrRegularLocalFile $path 'CREDENTIAL_PROFILE_INVALID'
        if ($item.Length -lt 1 -or $item.Length -gt 1MB) {
            throw 'A published credential profile component is outside its size bound.'
        }
    }
    $publishedAdministrator = Import-Clixml -LiteralPath $publishedAdministratorPath -ErrorAction Stop
    $publishedTestUser = Import-Clixml -LiteralPath $publishedTestUserPath -ErrorAction Stop
    $publishedMetadata = Get-Content -LiteralPath $publishedMetadataPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -ErrorAction Stop
    if ($publishedAdministrator -isnot [pscredential] -or
        $publishedTestUser -isnot [pscredential] -or
        $publishedAdministrator.UserName -ne $administratorCredential.UserName -or
        $publishedTestUser.UserName -ne $testUserCredential.UserName -or
        [int](Get-HcrPropertyValue $publishedMetadata 'schemaVersion') -ne 1 -or
        [string](Get-HcrPropertyValue $publishedMetadata 'profileName') -ne $ProfileName -or
        [string](Get-HcrPropertyValue $publishedMetadata 'vmName') -ne $VmName -or
        [string](Get-HcrPropertyValue $publishedMetadata 'administratorSid') -ne $administratorSid -or
        [string](Get-HcrPropertyValue $publishedMetadata 'testUserSid') -ne $testUserSid) {
        throw 'The atomically published credential profile failed final bundle readback.'
    }
    $published = $true
}
finally {
    if (-not $published -and (Test-Path -LiteralPath $temporaryDirectory -PathType Container)) {
        try {
            [void](Assert-HcrLocalDirectory $temporaryDirectory 'CREDENTIAL_PROFILE_INVALID')
            $children = @(Get-ChildItem -LiteralPath $temporaryDirectory -Force)
            $allowedNames = @('orchestration-admin.clixml', 'standard-test-user.clixml', 'profile.json')
            if (@($children | Where-Object {
                $_.PSIsContainer -or
                ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                $allowedNames -notcontains $_.Name
            }).Count -eq 0) {
                foreach ($child in $children) {
                    Remove-Item -LiteralPath $child.FullName -Force -ErrorAction SilentlyContinue
                }
                if (@(Get-ChildItem -LiteralPath $temporaryDirectory -Force).Count -eq 0) {
                    Remove-Item -LiteralPath $temporaryDirectory -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch { }
    }
}

[pscustomobject][ordered]@{
    ok = $true
    profileName = $ProfileName
    vmName = $VmName
    rolesValidated = $true
    dpapiScope = 'current-user-current-machine'
}

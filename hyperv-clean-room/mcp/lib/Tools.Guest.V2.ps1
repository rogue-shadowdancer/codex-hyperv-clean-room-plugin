function Get-HcrV2SourceCommit {
    $manifestPath = Join-Path $script:HcrPluginRoot '.codex-plugin\install-manifest.json'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        return [string](Get-HcrV2RuntimeIdentity).sourceCommit
    }
    if ((Get-HcrAdapterMode) -eq 'mock' -and $env:HCR_TEST_MODE -eq '1' -and
        $env:HCR_TEST_SOURCE_COMMIT -match '^[a-f0-9]{40}$') {
        return $env:HCR_TEST_SOURCE_COMMIT
    }
    Throw-HcrError 'RUNTIME_PROVENANCE_INVALID' 'The exact installed source commit is unavailable.'
}

function Get-HcrV2VerifiedInstalledInventory {
    $root = (Assert-HcrLocalDirectory $script:HcrPluginRoot 'RUNTIME_PROVENANCE_INVALID').FullName
    $manifestPath = Join-Path $root '.codex-plugin\install-manifest.json'
    $ownershipPath = Join-Path $root '.codex-plugin\install-ownership.json'
    [void](Assert-HcrRegularLocalFile $manifestPath 'RUNTIME_PROVENANCE_INVALID')
    [void](Assert-HcrRegularLocalFile $ownershipPath 'RUNTIME_PROVENANCE_INVALID')
    $manifest = Read-HcrJsonFile $manifestPath 'RUNTIME_PROVENANCE_INVALID'
    $ownership = Read-HcrJsonFile $ownershipPath 'RUNTIME_PROVENANCE_INVALID'
    $manifestFields = @(
        'schemaVersion', 'pluginName', 'installationId', 'sourceRoot',
        'targetRoot', 'sourceVersion', 'sourceCommit', 'cachebuster',
        'installedAtUtc', 'files'
    )
    $filesValue = Get-HcrPropertyValue $manifest 'files'
    if (-not (Test-HcrObjectLike $manifest) -or
        @((Get-HcrPropertyNames $manifest) | Where-Object {
                $manifestFields -notcontains $_
            }).Count -ne 0 -or
        @((Get-HcrPropertyNames $manifest)).Count -ne $manifestFields.Count -or
        -not (Test-HcrInteger (Get-HcrPropertyValue $manifest 'schemaVersion')) -or
        [int](Get-HcrPropertyValue $manifest 'schemaVersion') -ne 1 -or
        [string](Get-HcrPropertyValue $manifest 'pluginName') -cne 'hyperv-clean-room' -or
        -not (Test-HcrUuid (Get-HcrPropertyValue $manifest 'installationId')) -or
        [string](Get-HcrPropertyValue $manifest 'sourceVersion') -notmatch
            '^0\.4\.0\+codex\.[0-9]{14}$' -or
        [string](Get-HcrPropertyValue $manifest 'sourceCommit') -notmatch
            '^[a-f0-9]{40}$' -or
        -not (Test-HcrDateTimeString (Get-HcrPropertyValue $manifest 'installedAtUtc')) -or
        (Get-HcrPropertyValue $manifest 'targetRoot') -isnot [string] -or
        -not (Test-HcrLocalAbsolutePath (Get-HcrPropertyValue $manifest 'targetRoot')) -or
        (Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $manifest 'targetRoot'))) -ine
            (Get-HcrNormalizedPath $root) -or
        $filesValue -isnot [Array]) {
        Throw-HcrError 'RUNTIME_PROVENANCE_INVALID' 'The installed runtime manifest is invalid.'
    }
    $ownershipFields = @(
        'installationId', 'owner', 'pluginName', 'schemaVersion', 'targetRoot'
    )
    if (-not (Test-HcrObjectLike $ownership) -or
        @((Get-HcrPropertyNames $ownership) | Where-Object {
                $ownershipFields -notcontains $_
            }).Count -ne 0 -or
        @((Get-HcrPropertyNames $ownership)).Count -ne $ownershipFields.Count -or
        [string](Get-HcrPropertyValue $ownership 'installationId') -cne
            [string](Get-HcrPropertyValue $manifest 'installationId') -or
        [string](Get-HcrPropertyValue $ownership 'owner') -cne
            'hyperv-clean-room-installer/v1' -or
        [string](Get-HcrPropertyValue $ownership 'pluginName') -cne 'hyperv-clean-room' -or
        -not (Test-HcrInteger (Get-HcrPropertyValue $ownership 'schemaVersion')) -or
        [int](Get-HcrPropertyValue $ownership 'schemaVersion') -ne 1 -or
        (Get-HcrPropertyValue $ownership 'targetRoot') -isnot [string] -or
        -not (Test-HcrLocalAbsolutePath (Get-HcrPropertyValue $ownership 'targetRoot')) -or
        (Get-HcrNormalizedPath ([string](Get-HcrPropertyValue $ownership 'targetRoot'))) -ine
            (Get-HcrNormalizedPath $root)) {
        Throw-HcrError 'RUNTIME_PROVENANCE_INVALID' 'The installed runtime ownership binding is invalid.'
    }

    $declaredPaths = New-Object 'Collections.Generic.HashSet[string]' (
        [StringComparer]::OrdinalIgnoreCase
    )
    $rows = New-Object System.Collections.Generic.List[string]
    [int64]$totalBytes = 0
    foreach ($row in @($filesValue)) {
        $pathValue = Get-HcrPropertyValue $row 'path'
        $sizeValue = Get-HcrPropertyValue $row 'size'
        $shaValue = Get-HcrPropertyValue $row 'sha256'
        if (-not (Test-HcrObjectLike $row) -or
            @((Get-HcrPropertyNames $row)).Count -ne 3 -or
            @((Get-HcrPropertyNames $row) | Where-Object {
                    @('path', 'size', 'sha256') -notcontains $_
            }).Count -ne 0 -or
            $pathValue -isnot [string] -or
            -not (Test-HcrV2WindowsSafeRelativePath $pathValue) -or
            -not (Test-HcrInteger $sizeValue) -or [int64]$sizeValue -lt 0 -or
            [int64]$sizeValue -gt 1MB -or
            $shaValue -isnot [string] -or [string]$shaValue -notmatch '^[a-f0-9]{64}$') {
            Throw-HcrError 'RUNTIME_PROVENANCE_INVALID' 'The installed runtime inventory contains an invalid row.'
        }
        $relative = ([string]$pathValue).Replace('\', '/')
        if (-not $declaredPaths.Add($relative) -or
            @(
                '.codex-plugin/install-manifest.json',
                '.codex-plugin/install-ownership.json'
            ) -contains $relative) {
            Throw-HcrError 'RUNTIME_PROVENANCE_INVALID' 'The installed runtime inventory contains a duplicate or reserved path.'
        }
        $installedPath = Join-Path $root $relative.Replace('/', '\')
        if (-not (Test-HcrPathWithin $installedPath $root)) {
            Throw-HcrError 'RUNTIME_PROVENANCE_INVALID' 'The installed runtime inventory escaped the plugin root.'
        }
        $item = Assert-HcrRegularLocalFile $installedPath 'RUNTIME_PROVENANCE_INVALID'
        if ([int64]$item.Length -ne [int64]$sizeValue -or
            (Get-HcrSha256File $item.FullName) -cne [string]$shaValue) {
            Throw-HcrError 'RUNTIME_PROVENANCE_INVALID' 'An installed runtime file differs from its manifest identity.'
        }
        $totalBytes += [int64]$item.Length
        if ($totalBytes -gt 4MB) {
            Throw-HcrError 'RUNTIME_PROVENANCE_INVALID' 'The installed runtime payload exceeds its fixed bound.'
        }
        $rows.Add("$relative`t$([int64]$item.Length)`t$([string]$shaValue)")
    }
    if ($rows.Count -lt 1 -or $rows.Count -gt 256) {
        Throw-HcrError 'RUNTIME_PROVENANCE_INVALID' 'The installed runtime inventory count is invalid.'
    }

    $actualPaths = New-Object 'Collections.Generic.HashSet[string]' (
        [StringComparer]::OrdinalIgnoreCase
    )
    $pending = New-Object 'Collections.Generic.Queue[string]'
    $pending.Enqueue($root)
    $rootPrefix = $root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    while ($pending.Count -gt 0) {
        $directory = $pending.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                Throw-HcrError 'RUNTIME_PROVENANCE_INVALID' 'The installed runtime contains a reparse point.'
            }
            if ($item.PSIsContainer) {
                $pending.Enqueue($item.FullName)
                continue
            }
            if (-not $item.FullName.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                Throw-HcrError 'RUNTIME_PROVENANCE_INVALID' 'The installed runtime file escaped the plugin root.'
            }
            $relative = $item.FullName.Substring($rootPrefix.Length).Replace('\', '/')
            if (-not $actualPaths.Add($relative) -or $actualPaths.Count -gt 258) {
                Throw-HcrError 'RUNTIME_PROVENANCE_INVALID' 'The installed runtime file set is invalid.'
            }
        }
    }
    $expectedPaths = New-Object 'Collections.Generic.HashSet[string]' (
        [StringComparer]::OrdinalIgnoreCase
    )
    foreach ($relative in $declaredPaths) { [void]$expectedPaths.Add($relative) }
    [void]$expectedPaths.Add('.codex-plugin/install-manifest.json')
    [void]$expectedPaths.Add('.codex-plugin/install-ownership.json')
    if (-not $actualPaths.SetEquals($expectedPaths)) {
        Throw-HcrError 'RUNTIME_PROVENANCE_INVALID' 'The installed runtime file set differs from its closed manifest.'
    }
    $pluginManifest = Read-HcrJsonFile (
        Join-Path $root '.codex-plugin\plugin.json'
    ) 'RUNTIME_PROVENANCE_INVALID'
    if ([string](Get-HcrPropertyValue $pluginManifest 'version') -cne
        [string](Get-HcrPropertyValue $manifest 'sourceVersion')) {
        Throw-HcrError 'RUNTIME_PROVENANCE_INVALID' 'The installed plugin version differs from its provenance manifest.'
    }
    [string[]]$sortedRows = @($rows.ToArray())
    [Array]::Sort($sortedRows, [StringComparer]::Ordinal)
    return [pscustomobject][ordered]@{
        manifest = $manifest
        inventorySha256 = Get-HcrSha256Text ($sortedRows -join "`n")
    }
}

function Get-HcrV2RuntimeIdentity {
    $manifestPath = Join-Path $script:HcrPluginRoot '.codex-plugin\install-manifest.json'
    $buildVersion = $null
    $sourceCommit = $null
    $inventorySha256 = $null
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $verified = Get-HcrV2VerifiedInstalledInventory
        $manifest = $verified.manifest
        $buildVersion = [string](Get-HcrPropertyValue $manifest 'sourceVersion')
        $sourceCommit = [string](Get-HcrPropertyValue $manifest 'sourceCommit')
        $inventorySha256 = [string]$verified.inventorySha256
    }
    elseif ((Get-HcrAdapterMode) -eq 'mock' -and $env:HCR_TEST_MODE -eq '1') {
        $buildVersion = if ($env:HCR_TEST_PLUGIN_BUILD_VERSION -match
            '^0\.4\.0\+codex\.[0-9]{14}$') {
            $env:HCR_TEST_PLUGIN_BUILD_VERSION
        }
        else { '0.4.0+codex.00000000000000' }
        $sourceCommit = $env:HCR_TEST_SOURCE_COMMIT
        $inventorySha256 = if ($env:HCR_TEST_INSTALLED_INVENTORY_SHA256 -match
            '^[a-f0-9]{64}$') {
            $env:HCR_TEST_INSTALLED_INVENTORY_SHA256
        }
        else {
            Get-HcrSha256Text "mock-installed-runtime|$sourceCommit|$buildVersion"
        }
    }
    if ($buildVersion -notmatch '^0\.4\.0\+codex\.[0-9]{14}$' -or
        $sourceCommit -notmatch '^[a-f0-9]{40}$' -or
        $inventorySha256 -notmatch '^[a-f0-9]{64}$') {
        Throw-HcrError 'RUNTIME_PROVENANCE_INVALID' 'The exact installed runtime identity is unavailable.'
    }
    return [pscustomobject][ordered]@{
        pluginBaseVersion = '0.4.0'
        pluginBuildVersion = $buildVersion
        sourceCommit = $sourceCommit
        installedInventorySha256 = $inventorySha256
        adapterMode = if ((Get-HcrAdapterMode) -eq 'mock') { 'mock' } else { 'production' }
    }
}

function Get-HcrV2PortableCandidateSourceCommit {
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactPath,
        [Parameter(Mandatory = $true)][string]$ExpectedManifestSha256
    )

    $stream = $null
    $archive = $null
    $entryStream = $null
    $memory = $null
    try {
        [void](Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop)
        [void](Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop)
        $stream = [IO.File]::Open(
            $ArtifactPath,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::Read
        )
        $archive = New-Object IO.Compression.ZipArchive(
            $stream,
            [IO.Compression.ZipArchiveMode]::Read,
            $false
        )
        if ($archive.Entries.Count -gt 4096) {
            Throw-HcrError 'PORTABLE_MANIFEST_INVALID' 'The portable archive exceeds the fixed entry bound.'
        }
        $matches = @($archive.Entries | Where-Object {
                $_.FullName -ceq 'portable-manifest.json'
            })
        if ($matches.Count -ne 1 -or [int64]$matches[0].Length -gt 4MB) {
            Throw-HcrError 'PORTABLE_MANIFEST_INVALID' 'The archive must contain one bounded root portable manifest.'
        }
        $entryStream = $matches[0].Open()
        $memory = New-Object IO.MemoryStream
        $buffer = New-Object byte[] 81920
        $total = [int64]0
        while (($read = $entryStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $total += [int64]$read
            if ($total -gt 4MB) {
                Throw-HcrError 'PORTABLE_MANIFEST_INVALID' 'The portable manifest exceeds the fixed byte bound.'
            }
            $memory.Write($buffer, 0, $read)
        }
        $bytes = $memory.ToArray()
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $actualManifestSha256 = ([BitConverter]::ToString(
                    $sha.ComputeHash($bytes)
                )).Replace('-', '').ToLowerInvariant()
        }
        finally {
            $sha.Dispose()
        }
        if ($actualManifestSha256 -ne $ExpectedManifestSha256) {
            Throw-HcrError 'PORTABLE_MANIFEST_HASH_MISMATCH' 'The portable manifest hash does not match the profile.'
        }
        $json = (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes)
        $manifest = $json | ConvertFrom-Json -ErrorAction Stop
        $candidateSourceCommit = [string](Get-HcrPropertyValue $manifest 'sourceCommit')
        if ($candidateSourceCommit -notmatch '^[a-f0-9]{40}$') {
            Throw-HcrError 'PORTABLE_MANIFEST_INVALID' 'The portable candidate source commit is invalid.'
        }
        return $candidateSourceCommit
    }
    catch {
        if ($_.Exception.Data.Contains('HcrCode')) { throw }
        Throw-HcrError 'PORTABLE_MANIFEST_INVALID' 'The portable candidate manifest could not be read safely.'
    }
    finally {
        if ($null -ne $memory) { $memory.Dispose() }
        if ($null -ne $entryStream) { $entryStream.Dispose() }
        if ($null -ne $archive) { $archive.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-HcrV2FixtureSetSha256 {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Fixtures)
    $identity = @($Fixtures | ForEach-Object {
        [ordered]@{
            id = [string](Get-HcrPropertyValue $_ 'id')
            sourceRelativePath = ([string](Get-HcrPropertyValue $_ 'sourceRelativePath')).Replace('\', '/')
            sizeBytes = [int64](Get-HcrPropertyValue $_ 'sizeBytes')
            sha256 = [string](Get-HcrPropertyValue $_ 'sha256')
            mediaType = [string](Get-HcrPropertyValue $_ 'mediaType')
        }
    })
    return Get-HcrSha256Text (ConvertTo-HcrJson $identity 30)
}

function Resolve-HcrV2FixtureFiles {
    param(
        [Parameter(Mandatory = $true)][object]$Profile,
        [Parameter(Mandatory = $true)][string]$ProfilePath
    )

    $profileRoot = Get-HcrNormalizedPath (Split-Path -Parent $ProfilePath)
    $resolved = New-Object System.Collections.Generic.List[object]
    foreach ($fixture in @((Get-HcrPropertyValue $Profile 'fixtures' @()))) {
        $relative = [string](Get-HcrPropertyValue $fixture 'sourceRelativePath')
        $path = Get-HcrNormalizedPath (Join-Path $profileRoot $relative)
        if (-not (Test-HcrPathWithin $path $profileRoot)) {
            Throw-HcrError 'FIXTURE_INVALID' 'A fixture path escapes the profile directory.'
        }
        $item = Assert-HcrRegularLocalFile $path 'FIXTURE_INVALID'
        $hash = Get-HcrSha256File $item.FullName
        if ([int64]$item.Length -ne [int64](Get-HcrPropertyValue $fixture 'sizeBytes') -or
            $hash -ne [string](Get-HcrPropertyValue $fixture 'sha256')) {
            Throw-HcrError 'FIXTURE_HASH_MISMATCH' 'A fixture size or SHA-256 does not match the profile.'
        }
        $resolved.Add([pscustomobject][ordered]@{
            declaration = $fixture
            item = $item
            sha256 = $hash
        })
    }
    return @($resolved | ForEach-Object { $_ })
}

function Get-HcrV2GuestProjection {
    param([Parameter(Mandatory = $true)][object]$Guest)

    $base = Get-HcrGuestEvidenceProjection $Guest
    $sid = [string](Get-HcrPropertyValue $Guest 'userSid')
    if ($sid -notmatch '^S-1-[0-9-]+$') {
        Throw-HcrError 'GUEST_IDENTITY_INVALID' 'The ordinary test-user SID is unavailable.'
    }
    return [pscustomobject][ordered]@{
        windowsBuild = [string]$base.windowsBuild
        architecture = [string]$base.architecture
        userSid = $sid
        userName = [string]$base.userName
        isAdministrator = [bool]$base.isAdministrator
        isElevated = [bool]$base.isElevated
        tokenIntegrity = [string]$base.tokenIntegrity
        profilePathContainsNonAscii = [bool]$base.profilePathContainsNonAscii
    }
}

function ConvertTo-HcrV2Observations {
    param([AllowNull()][object]$Evidence)

    $observations = New-Object System.Collections.Generic.List[object]
    if ($null -ne $Evidence -and (Test-HcrObjectLike $Evidence)) {
        foreach ($property in @($Evidence.PSObject.Properties | Sort-Object Name)) {
            if ($observations.Count -ge 64) { break }
            $value = $property.Value
            if ($null -eq $value -or $value -is [string] -or $value -is [ValueType]) {
                $observations.Add([pscustomobject][ordered]@{
                    name = ([string]$property.Name).ToLowerInvariant().Replace('_', '-')
                    value = $value
                })
            }
        }
    }
    return @($observations | ForEach-Object { $_ })
}

function Invoke-HcrV2StepSafely {
    param(
        [Parameter(Mandatory = $true)][object]$Step,
        [Parameter(Mandatory = $true)][object]$Context,
        [switch]$Cleanup
    )

    try {
        $launchedProcess = $null
        if ($Cleanup -and [string](Get-HcrPropertyValue $Step 'type') -eq 'stopApplication') {
            $application = [string](Get-HcrPropertyValue $Step 'application')
            $matches = @($Context.launchedProcesses | Where-Object {
                    [string](Get-HcrPropertyValue $_ 'application') -eq $application
                } | Select-Object -Last 1)
            if ($matches.Count -eq 0) {
                return [pscustomobject][ordered]@{
                    status = 'failed'
                    summary = 'No current-operation launched PID exists for this application.'
                    evidence = [pscustomobject]@{ processIdentityRevalidated = $false }
                }
            }
            $launchedProcess = $matches[0]
        }
        $result = Invoke-HcrAdapter $(if ($Cleanup) { 'RunCleanupStep' } else { 'RunTestStep' }) ([pscustomobject][ordered]@{
            schemaVersion = 2
            vmName = $Context.vmName
            profileName = $Context.profileName
            operationId = $Context.operationId
            step = $Step
            workflowKind = $Context.workflowKind
            applications = $Context.applications
            artifact = $Context.artifact
            portableArtifact = $Context.portableArtifact
            portableManifest = $Context.portableManifest
            externalPortable = [bool]$Context.externalPortable
            uiRequired = [bool]$Context.uiRequired
            sourceCommit = $Context.sourceCommit
            fixtures = $Context.fixtures
            webDriver = $Context.webDriver
            deployment = Copy-HcrObject $Context.deployment
            launchedProcesses = @($Context.launchedProcesses | ForEach-Object { $_ })
            launchedProcess = $launchedProcess
            expectedVmId = $Context.expectedVmId
            expectedVmName = $Context.expectedVmName
            expectedOwnershipId = $Context.expectedOwnershipId
            expectedVmPath = $Context.expectedVmPath
            expectedVhdxPath = $Context.expectedVhdxPath
            timeoutSeconds = [int](Get-HcrPropertyValue $Step 'timeoutSeconds')
        })
        return $result
    }
    catch {
        $failure = Get-HcrExceptionData $_.Exception
        return [pscustomobject][ordered]@{
            status = 'failed'
            summary = "The fixed schema-v2 guest step failed: $($failure.code)."
            evidence = [pscustomobject]@{ errorCode = $failure.code }
            failureKind = 'adapter'
        }
    }
}

function New-HcrV2AutomaticAssertion {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][bool]$Required,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Summary,
        [AllowNull()][object]$Evidence
    )
    return [pscustomobject][ordered]@{
        id = $Id
        required = $Required
        status = $Status
        summary = if ($Summary.Length -gt 2000) { $Summary.Substring(0, 2000) } else { $Summary }
        observations = @(ConvertTo-HcrV2Observations $Evidence)
    }
}

function New-HcrV2CleanupResult {
    param(
        [Parameter(Mandatory = $true)][string]$OperationId,
        [Parameter(Mandatory = $true)][string]$ProfileId,
        [Parameter(Mandatory = $true)][object]$Step,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Summary,
        [AllowNull()][object]$Evidence
    )
    return [pscustomobject][ordered]@{
        operationId = $OperationId
        profileId = $ProfileId
        cleanupStepId = [string](Get-HcrPropertyValue $Step 'id')
        cleanupStepType = [string](Get-HcrPropertyValue $Step 'type')
        status = $Status
        summary = $Summary
        observations = @(ConvertTo-HcrV2Observations $Evidence)
    }
}

function Invoke-HcrRunTestProfileV2 {
    param(
        [Parameter(Mandatory = $true)][object]$Arguments,
        [Parameter(Mandatory = $true)][string]$OperationId
    )

    $vmName = [string](Get-HcrPropertyValue $Arguments 'vmName')
    $profileName = [string](Get-HcrPropertyValue $Arguments 'credentialProfile')
    $owned = Get-HcrRequiredOwnedVm $vmName
    $profileValidation = Read-AndValidate-HcrProfile ([string](Get-HcrPropertyValue $Arguments 'profilePath'))
    if (-not $profileValidation.valid -or (Get-HcrPropertyValue $profileValidation.profile 'schemaVersion') -ne 2) {
        Throw-HcrError 'PROFILE_INVALID' 'The schema-v2 test profile failed validation before execution.' ([ordered]@{ errors = @($profileValidation.errors) })
    }
    $profile = $profileValidation.profile
    $artifactDeclaration = Get-HcrPropertyValue $profile 'artifact'
    $externalPortable = [string](Get-HcrPropertyValue $artifactDeclaration 'portableManifestSource') -eq
        'externalProfileRelative'
    if ([string](Get-HcrPropertyValue $profile 'workflowKind') -eq 'legacyPackageLifecycle') {
        if (Test-HcrProperty $artifactDeclaration 'sizeBytes') {
            $legacyArtifact = Assert-HcrRegularLocalFile `
                ([string](Get-HcrPropertyValue $Arguments 'artifactPath')) `
                'INVALID_ARTIFACT'
            if ([int64]$legacyArtifact.Length -ne [int64](Get-HcrPropertyValue $artifactDeclaration 'sizeBytes')) {
                Throw-HcrError 'ARTIFACT_PROFILE_MISMATCH' 'The installer artifact size does not match the schema-v2 profile.'
            }
        }
        $legacyProfile = Convert-HcrLegacyProfileV2ToV1 $profile
        $legacyValidation = Test-HcrProfileDocument $legacyProfile
        if (-not $legacyValidation.valid) {
            Throw-HcrError 'PROFILE_INVALID' 'The schema-v2 legacy profile cannot enter the preserved v1 lifecycle runner.' ([ordered]@{
                errors = @($legacyValidation.errors)
            })
        }
        return Invoke-HcrRunTestProfileV1 $Arguments $OperationId $legacyProfile
    }
    $artifactItem = Assert-HcrRegularLocalFile ([string](Get-HcrPropertyValue $Arguments 'artifactPath')) 'INVALID_ARTIFACT'
    $artifactHash = Get-HcrSha256File $artifactItem.FullName
    $artifactNameMatches = if ($externalPortable) {
        $artifactItem.Name -ceq
            [string](Get-HcrPropertyValue $artifactDeclaration 'fileNamePattern')
    }
    else {
        $artifactItem.Name -like
            [string](Get-HcrPropertyValue $artifactDeclaration 'fileNamePattern')
    }
    if (-not $artifactNameMatches -or
        [int64]$artifactItem.Length -ne [int64](Get-HcrPropertyValue $artifactDeclaration 'sizeBytes') -or
        $artifactHash -ne [string](Get-HcrPropertyValue $artifactDeclaration 'sha256')) {
        Throw-HcrError 'ARTIFACT_PROFILE_MISMATCH' 'The portable artifact identity does not exactly match the profile.'
    }
    $externalManifest = if ($externalPortable) {
        Resolve-HcrExternalPortableManifestV2 $profile $profileValidation.path
    }
    else { $null }
    if ($externalPortable -and
        ([string](Get-HcrPropertyValue $externalManifest.document 'fileName') -cne
            $artifactItem.Name -or
        [string](Get-HcrPropertyValue $externalManifest.document 'newZipSha256') -cne
            $artifactHash)) {
        Throw-HcrError 'ARTIFACT_PROFILE_MISMATCH' 'The external portable manifest ZIP identity does not match the profile artifact.'
    }
    $fixtures = @(Resolve-HcrV2FixtureFiles $profile $profileValidation.path)
    [void](Invoke-HcrAdapter 'ResolveCredentialProfile' ([pscustomobject]@{ vmName = $vmName; profileName = $profileName }))
    $identityArguments = [ordered]@{
        vmName = $vmName; profileName = $profileName; operationId = $OperationId
        expectedVmId = [string](Get-HcrPropertyValue $owned.vm 'id')
        expectedVmName = [string](Get-HcrPropertyValue $owned.vm 'name')
        expectedOwnershipId = [string](Get-HcrPropertyValue $owned.ownership 'ownershipId')
        expectedVmPath = [string](Get-HcrPropertyValue $owned.vm 'vmPath')
        expectedVhdxPath = [string](Get-HcrPropertyValue $owned.vm 'vhdxPath')
    }
    $guestRaw = Invoke-HcrAdapter 'InspectGuest' ([pscustomobject]($identityArguments + @{ timeoutSeconds = 60 }))
    $guest = Get-HcrV2GuestProjection $guestRaw
    $profileSha = [string]$profileValidation.sha256
    $fixtureSetSha = Get-HcrV2FixtureSetSha256 @($fixtures | ForEach-Object { $_.declaration })
    $webDriver = Get-HcrPropertyValue $profile 'webDriver'
    $webDriverSha = if ($null -eq $webDriver) {
        $null
    }
    else { Get-HcrSha256Text (ConvertTo-HcrJson $webDriver 100) }
    $runtimeIdentity = if ($externalPortable) { Get-HcrV2RuntimeIdentity } else { $null }
    $runtimeSourceCommit = if ($externalPortable) {
        [string]$runtimeIdentity.sourceCommit
    }
    else { Get-HcrV2SourceCommit }
    $candidateSourceCommit = if ($externalPortable) {
        [string](Get-HcrPropertyValue $externalManifest.document 'packagingCommit')
    }
    else {
        Get-HcrV2PortableCandidateSourceCommit `
            $artifactItem.FullName `
            ([string](Get-HcrPropertyValue $artifactDeclaration 'portableManifestSha256'))
    }
    $evidenceRoot = Get-HcrEvidenceStagingRoot $OperationId
    [void](Initialize-HcrStateManagedDirectory $evidenceRoot)
    $operation = [pscustomobject][ordered]@{
        schemaVersion = 2; operationId = $OperationId; operationType = 'runTestProfile'; createdAt = Get-HcrUtcTimestamp
        vmId = [string](Get-HcrPropertyValue $owned.vm 'id'); vmName = $vmName; profileId = [string](Get-HcrPropertyValue $profile 'id')
        baselineType = [string](Get-HcrPropertyValue $profile 'baselineType'); adapterMode = Get-HcrAdapterMode
        sourceCommit = $candidateSourceCommit; portableZipSha256 = $artifactHash; profileSha256 = $profileSha
        fixtureSetSha256 = $fixtureSetSha; webDriverManifestSha256 = $webDriverSha
        evidenceKind = if ($externalPortable) { 'externalPortable' } else { $null }
        portableManifestRelativePath = if ($externalPortable) {
            [string](Get-HcrPropertyValue $artifactDeclaration 'portableManifestRelativePath')
        } else { $null }
        portableManifestSha256 = [string](Get-HcrPropertyValue $artifactDeclaration 'portableManifestSha256')
        portableManifestSizeBytes = if ($externalPortable) { [int64]$externalManifest.sizeBytes } else { $null }
        portableZipSourceSizeBytes = if ($externalPortable) { [int64]$artifactItem.Length } else { $null }
        portableZipGuestSizeBytes = $null
        portableZipSourceSha256 = if ($externalPortable) { $artifactHash } else { $null }
        portableZipGuestSha256 = $null
        portableManifestSourceSizeBytes = if ($externalPortable) { [int64]$externalManifest.sizeBytes } else { $null }
        portableManifestGuestSizeBytes = $null
        portableManifestSourceSha256 = if ($externalPortable) { [string]$externalManifest.sha256 } else { $null }
        portableManifestGuestSha256 = $null
        portableInventorySha256 = if ($externalPortable) {
            [string](Get-HcrPropertyValue $externalManifest.inventory 'sha256')
        } else { $null }
        cleanupTriggered = $false; cleanupSteps = @((Get-HcrPropertyValue $profile 'cleanupSteps' @()))
        automaticAssertions = @(); manualAssertions = @((Get-HcrPropertyValue $profile 'manualAssertions' @()))
        evidenceRoot = $evidenceRoot; evidenceFile = $null; evidenceSha256 = $null
        manualAttestations = @(); exportedEvidencePath = $null; exportedAt = $null
    }
    Save-HcrOperationRecord $operation

    $artifactEvidence = New-Object System.Collections.Generic.List[object]
    $fixtureIdentities = New-Object System.Collections.Generic.List[object]
    $automatic = New-Object System.Collections.Generic.List[object]
    $uiTrace = New-Object System.Collections.Generic.List[object]
    $launched = New-Object System.Collections.Generic.List[object]
    $context = [pscustomobject][ordered]@{
        operationId=$OperationId; vmName=$vmName; profileName=$profileName; workflowKind=[string](Get-HcrPropertyValue $profile 'workflowKind')
        applications=@((Get-HcrPropertyValue $profile 'applications')); artifact=$null; portableArtifact=$artifactDeclaration
        portableManifest=$null; externalPortable=$externalPortable; uiRequired=$(if($externalPortable){[bool]$externalManifest.uiRequired}else{$true})
        sourceCommit=$candidateSourceCommit; fixtures=@($fixtures | ForEach-Object { Copy-HcrObject $_.declaration }); webDriver=$webDriver
        deployment=$null
        launchedProcesses=$launched; expectedVmId=$identityArguments.expectedVmId; expectedVmName=$identityArguments.expectedVmName
        expectedOwnershipId=$identityArguments.expectedOwnershipId; expectedVmPath=$identityArguments.expectedVmPath; expectedVhdxPath=$identityArguments.expectedVhdxPath
    }
    $steps = @((Get-HcrPropertyValue $profile 'steps'))
    $artifactGuestHash = $null
    $preEvidenceError = $null
    $preEvidenceFailureCode = $null
    $stageStatus = 'passed'
    $stageSummary = 'Portable ZIP and fixture staging completed with exact hash verification.'
    $stageMachineEvidence = [pscustomobject]@{ sourceSha256=$artifactHash; guestSha256=$null }
    try {
        $staged = Invoke-HcrAdapter 'StageArtifact' ([pscustomobject]($identityArguments + @{
            sourcePath=$artifactItem.FullName; sourceSha256=$artifactHash; size=[int64]$artifactItem.Length
            guestDestination=$artifactItem.Name; timeoutSeconds=[int](Get-HcrPropertyValue $steps[0] 'timeoutSeconds')
        }))
        $artifactGuestHash = [string](Get-HcrPropertyValue $staged 'guestSha256')
        if ($externalPortable) {
            $operation.portableZipGuestSizeBytes = [int64](Get-HcrPropertyValue $staged 'bytesCopied')
            $operation.portableZipGuestSha256 = $artifactGuestHash
        }
        $context.artifact = [pscustomobject]@{ guestDestination=[string](Get-HcrPropertyValue $staged 'guestDestination'); sourceSha256=$artifactHash; guestSha256=$artifactGuestHash }
        $stageMachineEvidence = [pscustomobject]@{ sourceSha256=$artifactHash; guestSha256=$artifactGuestHash }
        if ($artifactGuestHash -ne $artifactHash) {
            $stageStatus = 'failed'
            $stageSummary = 'Portable ZIP staging did not preserve the exact source hash.'
            $preEvidenceFailureCode = 'ARTIFACT_PROFILE_MISMATCH'
        }
    }
    catch {
        $preEvidenceError = $_
        $stageFailure = Get-HcrExceptionData $_.Exception
        $preEvidenceFailureCode = [string]$stageFailure.code
        $stageStatus = 'failed'
        $stageSummary = "Portable ZIP staging failed through the fixed adapter: $($stageFailure.code)."
        $stageMachineEvidence = [pscustomobject]@{ sourceSha256=$artifactHash; guestSha256=$null; errorCode=$stageFailure.code }
        $context.artifact = [pscustomobject]@{ guestDestination=$null; sourceSha256=$artifactHash; guestSha256=$null }
    }
    $artifactEvidence.Add([pscustomobject][ordered]@{ role='portableZip'; id='portable-zip'; fileName=$artifactItem.Name; sizeBytes=[int64]$artifactItem.Length; sourceSha256=$artifactHash; guestSha256=$artifactGuestHash; status=$stageStatus })
    $portableManifestGuestHash = $null
    $portableManifestGuestSize = $null
    if ($externalPortable) {
        $manifestStatus = if ($stageStatus -eq 'passed') { 'passed' } else { 'notPerformed' }
        if ($stageStatus -eq 'passed') {
            try {
                $manifestStage = Invoke-HcrAdapter 'StageArtifact' ([pscustomobject]($identityArguments + @{
                    sourcePath=$externalManifest.item.FullName
                    sourceSha256=[string]$externalManifest.sha256
                    size=[int64]$externalManifest.sizeBytes
                    guestDestination='sidecar\portable-manifest.json'
                    timeoutSeconds=120
                }))
                $portableManifestGuestHash = [string](Get-HcrPropertyValue $manifestStage 'guestSha256')
                $portableManifestGuestSize = [int64](Get-HcrPropertyValue $manifestStage 'bytesCopied')
                $operation.portableManifestGuestSizeBytes = $portableManifestGuestSize
                $operation.portableManifestGuestSha256 = $portableManifestGuestHash
                $context.portableManifest = [pscustomobject][ordered]@{
                    guestDestination = [string](Get-HcrPropertyValue $manifestStage 'guestDestination')
                    sourceSizeBytes = [int64]$externalManifest.sizeBytes
                    guestSizeBytes = $portableManifestGuestSize
                    sourceSha256 = [string]$externalManifest.sha256
                    guestSha256 = $portableManifestGuestHash
                    document = Copy-HcrObject $externalManifest.document
                    inventory = Copy-HcrObject $externalManifest.inventory
                }
                if ($portableManifestGuestHash -cne [string]$externalManifest.sha256 -or
                    $portableManifestGuestSize -ne [int64]$externalManifest.sizeBytes) {
                    $manifestStatus = 'failed'
                    $stageStatus = 'failed'
                    $preEvidenceFailureCode = 'PORTABLE_MANIFEST_HASH_MISMATCH'
                    $stageSummary = 'External portable manifest staging did not preserve independent size and hash identity.'
                }
            }
            catch {
                $preEvidenceError = $_
                $manifestStatus = 'failed'
                $stageStatus = 'failed'
                $manifestFailure = Get-HcrExceptionData $_.Exception
                $preEvidenceFailureCode = [string]$manifestFailure.code
                $stageSummary = "External portable manifest staging failed through the fixed adapter: $($manifestFailure.code)."
            }
        }
        $artifactEvidence.Add([pscustomobject][ordered]@{
            role='portableManifest'; id='portable-manifest'
            fileName=[string](Get-HcrPropertyValue $artifactDeclaration 'portableManifestRelativePath')
            sizeBytes=[int64]$externalManifest.sizeBytes
            sourceSha256=[string]$externalManifest.sha256
            guestSha256=$portableManifestGuestHash; status=$manifestStatus
        })
    }
    foreach ($fixture in $fixtures) {
        $declaration = $fixture.declaration
        $fixtureId = [string](Get-HcrPropertyValue $declaration 'id')
        $fixtureGuestHash = $null
        $fixtureGuestSize = $null
        $fixtureStatus = if ($stageStatus -eq 'passed') { 'passed' } else { 'notPerformed' }
        if ($stageStatus -eq 'passed') {
            try {
                $fixtureStage = Invoke-HcrAdapter 'StageArtifact' ([pscustomobject]($identityArguments + @{
                    sourcePath=$fixture.item.FullName; sourceSha256=$fixture.sha256; size=[int64]$fixture.item.Length
                    guestDestination=('fixtures\' + $fixtureId + '-' + $fixture.item.Name); timeoutSeconds=120
                }))
                $fixtureGuestHash = [string](Get-HcrPropertyValue $fixtureStage 'guestSha256')
                $fixtureGuestSize = [int64](Get-HcrPropertyValue $fixtureStage 'bytesCopied')
                $fixtureContext = @($context.fixtures | Where-Object {
                    [string](Get-HcrPropertyValue $_ 'id') -eq $fixtureId
                })
                if ($fixtureContext.Count -ne 1) { Throw-HcrError 'FIXTURE_INVALID' 'The staged fixture identity is not unique.' }
                $fixtureContext[0] | Add-Member -NotePropertyName guestDestination -NotePropertyValue ([string](Get-HcrPropertyValue $fixtureStage 'guestDestination')) -Force
                $fixtureContext[0] | Add-Member -NotePropertyName guestSha256 -NotePropertyValue $fixtureGuestHash -Force
                if ($fixtureGuestHash -ne $fixture.sha256) {
                    $fixtureStatus = 'failed'
                    $stageStatus = 'failed'
                    $preEvidenceFailureCode = 'FIXTURE_HASH_MISMATCH'
                    $stageSummary = "Fixture '$fixtureId' staging did not preserve the exact source hash."
                    $stageMachineEvidence = [pscustomobject]@{ sourceSha256=$artifactHash; guestSha256=$artifactGuestHash; failedFixtureId=$fixtureId; errorCode='FIXTURE_HASH_MISMATCH' }
                }
            }
            catch {
                $preEvidenceError = $_
                $fixtureFailure = Get-HcrExceptionData $_.Exception
                $fixtureStatus = 'failed'
                $stageStatus = 'failed'
                $preEvidenceFailureCode = [string]$fixtureFailure.code
                $stageSummary = "Fixture '$fixtureId' staging failed through the fixed adapter: $($fixtureFailure.code)."
                $stageMachineEvidence = [pscustomobject]@{ sourceSha256=$artifactHash; guestSha256=$artifactGuestHash; failedFixtureId=$fixtureId; errorCode=$fixtureFailure.code }
            }
        }
        $artifactEvidence.Add([pscustomobject][ordered]@{ role='fixture'; id=$fixtureId; fileName=$fixture.item.Name; sizeBytes=[int64]$fixture.item.Length; sourceSha256=$fixture.sha256; guestSha256=$fixtureGuestHash; status=$fixtureStatus })
        if ($externalPortable) {
            $fixtureIdentities.Add([pscustomobject][ordered]@{
                id=$fixtureId
                sourceRelativePath=[string](Get-HcrPropertyValue $declaration 'sourceRelativePath')
                profileSizeBytes=[int64](Get-HcrPropertyValue $declaration 'sizeBytes')
                sourceSizeBytes=[int64]$fixture.item.Length
                guestSizeBytes=$fixtureGuestSize
                profileSha256=[string](Get-HcrPropertyValue $declaration 'sha256')
                sourceSha256=[string]$fixture.sha256
                guestSha256=$fixtureGuestHash
                status=$fixtureStatus
            })
        }
    }
    $automatic.Add((New-HcrV2AutomaticAssertion ([string](Get-HcrPropertyValue $steps[0] 'id')) $true $stageStatus $stageSummary $stageMachineEvidence))
    if ($externalPortable -and $stageStatus -ne 'passed') {
        if ([string]::IsNullOrWhiteSpace($preEvidenceFailureCode)) {
            $preEvidenceFailureCode = 'GUEST_IDENTITY_INVALID'
        }
        $operation.automaticAssertions = @($automatic | ForEach-Object { $_ })
        $operation | Add-Member -NotePropertyName preEvidenceFailure `
            -NotePropertyValue ([pscustomobject][ordered]@{
                code = $preEvidenceFailureCode
                message = $stageSummary
                portableZipGuestSha256 = $artifactGuestHash
                portableManifestGuestSizeBytes = $portableManifestGuestSize
                portableManifestGuestSha256 = $portableManifestGuestHash
                fixtureIdentities = @($fixtureIdentities | ForEach-Object { $_ })
            }) -Force
        Save-HcrOperationRecord $operation
        if ($null -ne $preEvidenceError) {
            throw $preEvidenceError
        }
        Throw-HcrError $preEvidenceFailureCode $stageSummary
    }
    $tokenOk = -not $guest.isAdministrator -and -not $guest.isElevated -and $guest.tokenIntegrity -eq 'medium'
    $automatic.Add((New-HcrV2AutomaticAssertion 'runtime-ordinary-user-token' $true $(if($tokenOk){'passed'}else{'failed'}) 'Ordinary test-user token invariants were evaluated.' ([pscustomobject]@{ userSid=$guest.userSid; tokenIntegrity=$guest.tokenIntegrity })))
    $cleanupTriggered = $stageStatus -ne 'passed' -or -not $tokenOk -or @($artifactEvidence | Where-Object { $_.status -ne 'passed' }).Count -gt 0
    $deploymentId = [Guid]::Empty.ToString(); $deploymentFingerprint = ('0' * 64)
    $previousInventory = $null; $deployedInventory = ('0' * 64); $dataPreserved = $false
    $driverArchiveGuestHash = $null; $driverExecutableGuestHash = $null
    $uiRequired = [bool]$context.uiRequired
    $fixedWebView2Version = if ($uiRequired) {
        [string](Get-HcrPropertyValue $webDriver 'browserVersion')
    } else { $null }
    $driverVerified = -not $uiRequired; $loopbackOnly = -not $uiRequired; $deployStatus = 'notPerformed'
    $deploymentSlotId = if ($externalPortable) { 'not-performed' } else { $null }
    $deployedEntrypoint = if ($externalPortable) {
        [string](Get-HcrPropertyValue $externalManifest.document 'entrypoint')
    } else { $null }
    $deployedPayloadSha256 = if ($externalPortable) {
        [string](Get-HcrPropertyValue $externalManifest.inventory 'sha256')
    } else { $artifactHash }
    $deployedPayloadSizeBytes = if ($externalPortable) {
        [int64](Get-HcrPropertyValue $externalManifest.inventory 'payloadSizeBytes')
    } else { [int64]$artifactItem.Length }
    $uiSessionStarted = $false; $uiSessionStopped = $false
    $uiSessionStopSummary = $null; $uiSessionStopEvidence = $null
    for ($index=1; $index -lt $steps.Count; $index++) {
        $step=$steps[$index]; $required=[bool](Get-HcrPropertyValue $step 'required' $true); $type=[string](Get-HcrPropertyValue $step 'type')
        if ($cleanupTriggered) { $result=[pscustomobject]@{status='notPerformed';summary='A prior required failure stopped ordinary steps.';evidence=$null} }
        else { $result=Invoke-HcrV2StepSafely $step $context }
        $status=[string](Get-HcrPropertyValue $result 'status' 'failed'); $summary=[string](Get-HcrPropertyValue $result 'summary' 'The step returned no summary.'); $machineEvidence=Get-HcrPropertyValue $result 'evidence'
        $workerStepPassed = $status -eq 'passed'
        if ($workerStepPassed -and $type -eq 'startUiSession') { $uiSessionStarted = $true; $uiSessionStopped = $false }
        if ($workerStepPassed -and $type -eq 'stopUiSession') {
            $uiSessionStopped = $true
            $uiSessionStopSummary = $summary
            $uiSessionStopEvidence = $machineEvidence
        }
        if ($status -eq 'passed' -and $type -eq 'deployPortable') {
            $workerManifestHash = [string](Get-HcrPropertyValue $machineEvidence 'portableManifestSha256')
            if (-not $externalPortable) { $portableManifestGuestHash = $workerManifestHash }
            $fixedWebView2Version = if ($uiRequired) {
                [string](Get-HcrPropertyValue $machineEvidence 'fixedWebView2Version')
            } else { $null }
            $expectedBrowserVersion = if ($uiRequired) {
                [string](Get-HcrPropertyValue $webDriver 'browserVersion')
            } else { '' }
            if ($workerManifestHash -cne [string](Get-HcrPropertyValue $artifactDeclaration 'portableManifestSha256') -or
                ($uiRequired -and $fixedWebView2Version -cne $expectedBrowserVersion) -or
                (-not $uiRequired -and -not [string]::IsNullOrEmpty($fixedWebView2Version))) {
                $status = 'failed'; $summary = 'The deployed portable manifest or conditional UI identity did not match the immutable profile.'
            }
            if ($externalPortable -and (
                    [int64](Get-HcrPropertyValue $machineEvidence 'portableManifestGuestSizeBytes' -1) -ne
                        [int64]$externalManifest.sizeBytes -or
                    [string](Get-HcrPropertyValue $machineEvidence 'portableInventorySha256') -cne
                        [string](Get-HcrPropertyValue $externalManifest.inventory 'sha256') -or
                    [int](Get-HcrPropertyValue $machineEvidence 'portableInventoryFileCount' -1) -ne
                        [int](Get-HcrPropertyValue $externalManifest.inventory 'fileCount') -or
                    [int64](Get-HcrPropertyValue $machineEvidence 'portableInventorySizeBytes' -1) -ne
                        [int64](Get-HcrPropertyValue $externalManifest.inventory 'payloadSizeBytes'))) {
                $status = 'failed'
                $summary = 'The deployed external portable inventory did not rebind to the validated sidecar.'
            }
            $candidateDeploymentId = Get-HcrPropertyValue $machineEvidence 'deploymentId'
            $candidateDeploymentFingerprint = Get-HcrPropertyValue $machineEvidence 'deploymentFingerprint'
            $candidateDeploymentSlotId = Get-HcrPropertyValue $machineEvidence 'deploymentSlotId'
            $candidateEntrypoint = Get-HcrPropertyValue $machineEvidence 'entrypoint'
            $candidateEntrypointSize = Get-HcrPropertyValue $machineEvidence 'entrypointSizeBytes'
            $candidateEntrypointSha = Get-HcrPropertyValue $machineEvidence 'entrypointSha256'
            if (-not (Test-HcrUuid $candidateDeploymentId) -or
                $candidateDeploymentFingerprint -isnot [string] -or
                [string]$candidateDeploymentFingerprint -notmatch '^[0-9a-f]{64}$' -or
                $candidateDeploymentSlotId -isnot [string] -or
                [string]$candidateDeploymentSlotId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' -or
                $candidateEntrypoint -isnot [string] -or
                -not (Test-HcrV2WindowsSafeRelativePath $candidateEntrypoint) -or
                -not (Test-HcrInteger $candidateEntrypointSize) -or
                [int64]$candidateEntrypointSize -lt 1 -or
                $candidateEntrypointSha -isnot [string] -or
                [string]$candidateEntrypointSha -notmatch '^[0-9a-f]{64}$') {
                $status = 'failed'
                $summary = 'The deployed portable identity was incomplete or invalid.'
            }
        }
        if ($status -eq 'passed' -and $type -eq 'acquireWebDriver') {
            $driverArchiveGuestHash = [string](Get-HcrPropertyValue $machineEvidence 'archiveSha256')
            $driverExecutableGuestHash = [string](Get-HcrPropertyValue $machineEvidence 'executableSha256')
            if ($driverArchiveGuestHash -ne [string](Get-HcrPropertyValue (Get-HcrPropertyValue $webDriver 'acquisition') 'archiveSha256') -or
                $driverExecutableGuestHash -ne [string](Get-HcrPropertyValue (Get-HcrPropertyValue $webDriver 'executable') 'sha256')) {
                $status = 'failed'; $summary = 'The acquired fixed-driver hashes did not match the immutable profile.'
            }
        }
        if ($status -eq 'passed' -and $type -eq 'startUiSession') {
            $loopbackOnly = [bool](Get-HcrPropertyValue $machineEvidence 'loopbackOnly' $false)
            if (-not $loopbackOnly) { $status = 'failed'; $summary = 'The owned UI session did not prove loopback-only binding.' }
        }
        if ($type -eq 'deployPortable') { $deployStatus = $status }
        $automatic.Add((New-HcrV2AutomaticAssertion ([string](Get-HcrPropertyValue $step 'id')) $required $status $summary $machineEvidence))
        if ($status -eq 'passed' -and @('launchApplication', 'startUiSession') -contains $type -and (Test-HcrProperty $result 'process')) { $launched.Add((Copy-HcrObject (Get-HcrPropertyValue $result 'process'))) }
        if ($status -eq 'passed' -and $type -eq 'deployPortable') {
            $deployStatus = 'passed'
            $deploymentId = [string](Get-HcrPropertyValue $machineEvidence 'deploymentId')
            $deploymentFingerprint = [string](Get-HcrPropertyValue $machineEvidence 'deploymentFingerprint')
            $previousInventory = Get-HcrPropertyValue $machineEvidence 'previousDataInventorySha256'
            $deployedInventory = [string](Get-HcrPropertyValue $machineEvidence 'deployedDataInventorySha256')
            $dataPreserved = [bool](Get-HcrPropertyValue $machineEvidence 'dataPreserved' $false)
            $deploymentSlotId = Get-HcrPropertyValue $machineEvidence 'deploymentSlotId'
            $deployedEntrypoint = Get-HcrPropertyValue $machineEvidence 'entrypoint'
            $context.deployment = [pscustomobject][ordered]@{
                applicationId = [string](Get-HcrPropertyValue $step 'application')
                deploymentId = $deploymentId
                deploymentFingerprint = $deploymentFingerprint
                slotId = [string]$deploymentSlotId
                entrypointRelativePath = [string](Get-HcrPropertyValue $machineEvidence 'entrypoint')
                entrypointSizeBytes = [int64](Get-HcrPropertyValue $machineEvidence 'entrypointSizeBytes')
                entrypointSha256 = [string](Get-HcrPropertyValue $machineEvidence 'entrypointSha256')
            }
            if ($externalPortable) {
                $deployedPayloadSha256 = [string](Get-HcrPropertyValue $machineEvidence 'portableInventorySha256')
                $deployedPayloadSizeBytes = [int64](Get-HcrPropertyValue $machineEvidence 'portableInventorySizeBytes')
            }
        }
        if ($status -eq 'passed' -and $type -eq 'acquireWebDriver') { $driverVerified = $true }
        if ($script:HcrV2UiStepTypes -contains $type) { $uiTrace.Add([pscustomobject][ordered]@{ stepId=[string](Get-HcrPropertyValue $step 'id'); stepType=$type; testId=$(if(Test-HcrProperty $step 'testId'){[string](Get-HcrPropertyValue $step 'testId')}else{$null}); status=$status; summary=$summary; observations=@(ConvertTo-HcrV2Observations $machineEvidence) }) }
        if ($status -eq 'failed' -and ($required -or $script:HcrV2ActionStepTypes -contains $type)) { $cleanupTriggered=$true }
    }
    if ($uiSessionStarted -and -not $uiSessionStopped) {
        $cleanupTriggered = $true
        $containmentOrdinal = 1
        do {
            $containmentId = "automatic-ui-session-containment-$containmentOrdinal"
            $containmentOrdinal++
        } while (@($automatic | Where-Object {
                    [string](Get-HcrPropertyValue $_ 'id') -eq $containmentId
                }).Count -gt 0)
        $containmentStep = [pscustomobject][ordered]@{
            id = $containmentId
            type = 'stopUiSession'
            timeoutSeconds = 30
            required = $true
        }
        $containmentResult = Invoke-HcrV2StepSafely $containmentStep $context -Cleanup
        $containmentStatus = [string](Get-HcrPropertyValue $containmentResult 'status' 'failed')
        $containmentSummary = [string](Get-HcrPropertyValue $containmentResult 'summary' 'UI-session containment returned no summary.')
        $containmentEvidence = Get-HcrPropertyValue $containmentResult 'evidence'
        $automatic.Add((New-HcrV2AutomaticAssertion $containmentStep.id $true $containmentStatus $containmentSummary $containmentEvidence))
        $uiTrace.Add([pscustomobject][ordered]@{
            stepId = $containmentStep.id
            stepType = $containmentStep.type
            testId = $null
            status = $containmentStatus
            summary = $containmentSummary
            observations = @(ConvertTo-HcrV2Observations $containmentEvidence)
        })
        if ($containmentStatus -eq 'passed') {
            $uiSessionStopped = $true
            $uiSessionStopSummary = $containmentSummary
            $uiSessionStopEvidence = $containmentEvidence
        }
    }
    $manifestHash=[string](Get-HcrPropertyValue $artifactDeclaration 'portableManifestSha256')
    $driverStatus = if ($driverVerified) { 'passed' } else { 'notPerformed' }
    if (-not $externalPortable) {
        $artifactEvidence.Add([pscustomobject][ordered]@{ role='portableManifest'; id='portable-manifest'; fileName='portable-manifest.json'; sizeBytes=0; sourceSha256=$manifestHash; guestSha256=$(if($deployStatus -eq 'passed'){$portableManifestGuestHash}else{$null}); status=$deployStatus })
    }
    if ($uiRequired) {
        $driverArchive=Get-HcrPropertyValue $webDriver 'acquisition'; $driverExecutable=Get-HcrPropertyValue $webDriver 'executable'
        $artifactEvidence.Add([pscustomobject][ordered]@{ role='webDriverArchive'; id='webdriver-archive'; fileName=[string](Get-HcrPropertyValue $driverArchive 'archiveFileName'); sizeBytes=[int64](Get-HcrPropertyValue $driverArchive 'archiveSizeBytes'); sourceSha256=[string](Get-HcrPropertyValue $driverArchive 'archiveSha256'); guestSha256=$(if($driverVerified){$driverArchiveGuestHash}else{$null}); status=$driverStatus })
        $artifactEvidence.Add([pscustomobject][ordered]@{ role='webDriverExecutable'; id='webdriver-executable'; fileName='msedgedriver.exe'; sizeBytes=[int64](Get-HcrPropertyValue $driverExecutable 'sizeBytes'); sourceSha256=[string](Get-HcrPropertyValue $driverExecutable 'sha256'); guestSha256=$(if($driverVerified){$driverExecutableGuestHash}else{$null}); status=$driverStatus })
    }
    $artifactEvidence.Add([pscustomobject][ordered]@{
        role='deployedPayload'; id='deployed-payload'
        fileName=$(if($externalPortable){'payload.inventory.json'}else{$artifactItem.Name})
        sizeBytes=$deployedPayloadSizeBytes; sourceSha256=$deployedPayloadSha256
        guestSha256=$(if($deployStatus -eq 'passed'){$deployedPayloadSha256}else{$null})
        status=$deployStatus
    })
    $operation.cleanupTriggered=$cleanupTriggered
    $operation.automaticAssertions=@($automatic | ForEach-Object { $_ })
    Save-HcrOperationRecord $operation
    $cleanupResults=New-Object System.Collections.Generic.List[object]
    foreach($step in @((Get-HcrPropertyValue $profile 'cleanupSteps' @()))){
        if($cleanupTriggered){
            if ([string](Get-HcrPropertyValue $step 'type') -eq 'stopUiSession' -and $uiSessionStopped) {
                $cleanupResults.Add((New-HcrV2CleanupResult $OperationId $operation.profileId $step 'passed' ('The owned UI session was already contained: ' + $uiSessionStopSummary) $uiSessionStopEvidence))
            }
            else {
                $result=Invoke-HcrV2StepSafely $step $context -Cleanup
                $cleanupResults.Add((New-HcrV2CleanupResult $OperationId $operation.profileId $step ([string](Get-HcrPropertyValue $result 'status' 'failed')) ([string](Get-HcrPropertyValue $result 'summary' 'Cleanup returned no summary.')) (Get-HcrPropertyValue $result 'evidence')))
            }
        }
        else{$cleanupResults.Add((New-HcrV2CleanupResult $OperationId $operation.profileId $step 'notPerformed' 'Cleanup was not triggered.' $null))}
    }
    $manual=@(@((Get-HcrPropertyValue $profile 'manualAssertions'))|ForEach-Object{[pscustomobject][ordered]@{id=[string](Get-HcrPropertyValue $_ 'id');required=[bool](Get-HcrPropertyValue $_ 'required');description=[string](Get-HcrPropertyValue $_ 'description');status='notPerformed';attestation=$null}})
    $machineStatus=if($cleanupTriggered -or -not $dataPreserved -or
        ($uiRequired -and -not $driverVerified) -or
        @($automatic|Where-Object{$_.required -and $_.status -ne 'passed'}).Count -gt 0){'failed'}else{'passed'}
    $overallStatus=if($machineStatus -eq 'failed'){'failed'}elseif(@($manual|Where-Object{$_.required -and $_.status -ne 'passed'}).Count -gt 0){'incomplete'}else{'passed'}
    $candidate = if ($externalPortable) {
        $manifestDocument = $externalManifest.document
        [pscustomobject][ordered]@{
            sourceCommit=$candidateSourceCommit
            runtimeSourceCommit=[string](Get-HcrPropertyValue $manifestDocument 'runtimeSourceCommit')
            runtimeSourceTree=[string](Get-HcrPropertyValue $manifestDocument 'runtimeSourceTree')
            packagingCommit=[string](Get-HcrPropertyValue $manifestDocument 'packagingCommit')
            packagingTree=[string](Get-HcrPropertyValue $manifestDocument 'packagingTree')
            portableZipFileName=$artifactItem.Name
            portableZipSizeBytes=[int64]$artifactItem.Length
            portableZipSha256=$artifactHash
            portableZipSourceSha256=$artifactHash
            portableZipGuestSha256=$artifactGuestHash
            profileSha256=$profileSha
            requiredDistributionBoundary=[string](Get-HcrPropertyValue $artifactDeclaration 'requiredDistributionBoundary')
            portableManifestDistributionBoundary=[string](Get-HcrPropertyValue $manifestDocument 'distributionBoundary')
            portableManifestSource='externalProfileRelative'
            portableManifestRelativePath=[string](Get-HcrPropertyValue $artifactDeclaration 'portableManifestRelativePath')
            portableManifestSizeBytes=[int64](Get-HcrPropertyValue $artifactDeclaration 'portableManifestSizeBytes')
            portableManifestSourceSizeBytes=[int64]$externalManifest.sizeBytes
            portableManifestGuestSizeBytes=$portableManifestGuestSize
            portableManifestSha256=$manifestHash
            portableManifestSourceSha256=[string]$externalManifest.sha256
            portableManifestGuestSha256=$portableManifestGuestHash
            portableInventoryFileCount=[int](Get-HcrPropertyValue $externalManifest.inventory 'fileCount')
            portableInventorySizeBytes=[int64](Get-HcrPropertyValue $externalManifest.inventory 'payloadSizeBytes')
            portableInventorySha256=[string](Get-HcrPropertyValue $externalManifest.inventory 'sha256')
            documentationSourceCommit=[string](Get-HcrPropertyValue $manifestDocument 'documentationSourceCommit')
            documentationSourceTree=[string](Get-HcrPropertyValue $manifestDocument 'documentationSourceTree')
            documentationFileCount=[int](Get-HcrPropertyValue $manifestDocument 'documentationFileCount')
            documentationPayloadSize=[int64](Get-HcrPropertyValue $manifestDocument 'documentationPayloadSize')
            documentationInventoryDigest=[string](Get-HcrPropertyValue $manifestDocument 'documentationInventoryDigest')
            oldRuntimeInventoryDigest=[string](Get-HcrPropertyValue $manifestDocument 'oldRuntimeInventoryDigest')
            newRuntimeInventoryDigest=[string](Get-HcrPropertyValue $manifestDocument 'newRuntimeInventoryDigest')
            fixtureSetSha256=$fixtureSetSha
            webDriverManifestSha256=$webDriverSha
        }
    }
    else {
        [pscustomobject][ordered]@{sourceCommit=$candidateSourceCommit;portableZipSha256=$artifactHash;profileSha256=$profileSha;fixtureSetSha256=$fixtureSetSha;webDriverManifestSha256=$webDriverSha}
    }
    $evidenceWarnings = [object[]]@()
    if ((Get-HcrAdapterMode) -eq 'mock') { $evidenceWarnings = [object[]]@([string]$script:HcrMockWarning) }
    $guestEvidence = Copy-HcrObject $guest
    if ($externalPortable) {
        $orchestration = Get-HcrPropertyValue $guestRaw 'orchestration'
        if ($null -eq $orchestration -and (Get-HcrAdapterMode) -eq 'mock') {
            $orchestration = [pscustomobject][ordered]@{
                userSid='S-1-5-21-1000-1000-1000-500'; isAdministrator=$true
                isElevated=$true; tokenIntegrity='high'
            }
        }
        $orchestrationSid = [string](Get-HcrPropertyValue $orchestration 'userSid')
        if ($null -eq $orchestration -or
            $orchestrationSid -notmatch '^S-1-[0-9-]+$' -or
            $orchestrationSid -eq [string](Get-HcrPropertyValue $guest 'userSid') -or
            -not [bool](Get-HcrPropertyValue $orchestration 'isAdministrator' $false) -or
            -not [bool](Get-HcrPropertyValue $orchestration 'isElevated' $false) -or
            @('high','system') -notcontains
                [string](Get-HcrPropertyValue $orchestration 'tokenIntegrity')) {
            Throw-HcrError 'GUEST_IDENTITY_INVALID' 'External evidence requires a distinct elevated orchestration identity.'
        }
        $guestEvidence | Add-Member -NotePropertyName orchestration `
            -NotePropertyValue (Copy-HcrObject $orchestration) -Force
    }
    $profileEvidence = [pscustomobject][ordered]@{
        id=$operation.profileId; schemaVersion=2; sha256=$profileSha
    }
    if ($externalPortable) {
        $profileEvidence | Add-Member -NotePropertyName fixtureIds -NotePropertyValue @(
            @((Get-HcrPropertyValue $profile 'fixtures' @())) | ForEach-Object {
                [string](Get-HcrPropertyValue $_ 'id')
            }
        ) -Force
    }
    $automationEvidence = [pscustomobject][ordered]@{
        deploymentId=$deploymentId;deploymentFingerprint=$deploymentFingerprint
        dataPreserved=$dataPreserved;previousDataInventorySha256=$previousInventory
        deployedDataInventorySha256=$deployedInventory;webDriverManifestSha256=$webDriverSha
        fixedWebView2Version=$fixedWebView2Version
        webDriverVersion=$(if($uiRequired){[string](Get-HcrPropertyValue $webDriver 'driverVersion')}else{$null})
        loopbackOnly=$loopbackOnly;uiTrace=@($uiTrace | ForEach-Object { $_ })
    }
    if ($externalPortable) {
        $automationEvidence | Add-Member -NotePropertyName deploymentSlotId -NotePropertyValue $deploymentSlotId -Force
        $automationEvidence | Add-Member -NotePropertyName entrypoint -NotePropertyValue $deployedEntrypoint -Force
        $automationEvidence | Add-Member -NotePropertyName uiRequired -NotePropertyValue $uiRequired -Force
    }
    $evidence=[pscustomobject][ordered]@{
        schemaVersion=2;operationId=$OperationId;createdAt=Get-HcrUtcTimestamp
        profile=$profileEvidence;candidate=$candidate
        runtime=$(if($externalPortable){$runtimeIdentity}else{[pscustomobject][ordered]@{pluginVersion='0.2.0';sourceCommit=$runtimeSourceCommit;adapterMode=$(if((Get-HcrAdapterMode)-eq'mock'){'mock'}else{'production'})}})
        baselineType=$operation.baselineType
        vm=[pscustomobject][ordered]@{id=$operation.vmId;name=$vmName;checkpointId=$null;checkpointName=$null;ownershipId=[string](Get-HcrPropertyValue $owned.ownership 'ownershipId');ownershipVerified=$true;fingerprint=Get-HcrVmFingerprint $owned.vm}
        guest=$guestEvidence;artifacts=@($artifactEvidence | ForEach-Object { $_ });automation=$automationEvidence
        powerOperations=@();networkOperations=@();networkRecovery=[pscustomobject][ordered]@{required=$false;changePlanId=$null;recoveryPlanId=$null;recoveryOperationId=$null;status='notPerformed';initialFingerprint=$null;finalFingerprint=$null}
        automaticAssertions=@($automatic | ForEach-Object { $_ });manualAssertions=$manual;cleanupTriggered=$cleanupTriggered;cleanupResults=@($cleanupResults | ForEach-Object { $_ });machineStatus=$machineStatus;overallStatus=$overallStatus
        warnings=$evidenceWarnings
    }
    if ($externalPortable) {
        $evidence | Add-Member -NotePropertyName evidenceKind -NotePropertyValue 'externalPortable' -Force
        $evidence | Add-Member -NotePropertyName fixtureIdentities -NotePropertyValue @(
            $fixtureIdentities | ForEach-Object { $_ }
        ) -Force
    }
    [void](Write-HcrOperationEvidence $operation $evidence);$operation.evidenceSha256=Get-HcrEvidenceDocumentDigest $evidence;Save-HcrOperationRecord $operation
    return [pscustomobject][ordered]@{changed=$true;data=[pscustomobject][ordered]@{testOperationId=$OperationId;profileId=$operation.profileId;machineStatus=$machineStatus;overallStatus=$overallStatus;cleanupTriggered=$cleanupTriggered;automaticAssertions=@($automatic | ForEach-Object { $_ });manualAssertions=$manual;cleanupResults=@($cleanupResults | ForEach-Object { $_ })};warnings=@('Evidence remains in a server-controlled staging root until collect_evidence exports it.')}
}

function Invoke-HcrRunTestProfile {
    param(
        [Parameter(Mandatory = $true)][object]$Arguments,
        [Parameter(Mandatory = $true)][string]$OperationId
    )
    $loaded=Read-HcrJsonDocument ([string](Get-HcrPropertyValue $Arguments 'profilePath')) 'PROFILE_INVALID' 4MB
    $version=Get-HcrExactSchemaVersion $loaded.document 'Profile'
    if($version -eq 1){return Invoke-HcrRunTestProfileV1 $Arguments $OperationId}
    return Invoke-HcrRunTestProfileV2 $Arguments $OperationId
}

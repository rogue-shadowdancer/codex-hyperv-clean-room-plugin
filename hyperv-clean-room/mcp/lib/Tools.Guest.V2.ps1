function Get-HcrV2SourceCommit {
    $manifestPath = Join-Path $script:HcrPluginRoot '.codex-plugin\install-manifest.json'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $manifest = Read-HcrJsonFile $manifestPath 'RUNTIME_PROVENANCE_INVALID'
        $commit = [string](Get-HcrPropertyValue $manifest 'sourceCommit')
        if ($commit -match '^[a-f0-9]{40}$') { return $commit }
    }
    if ((Get-HcrAdapterMode) -eq 'mock' -and $env:HCR_TEST_MODE -eq '1' -and
        $env:HCR_TEST_SOURCE_COMMIT -match '^[a-f0-9]{40}$') {
        return $env:HCR_TEST_SOURCE_COMMIT
    }
    Throw-HcrError 'RUNTIME_PROVENANCE_INVALID' 'The exact installed source commit is unavailable.'
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
            sourceCommit = $Context.sourceCommit
            fixtures = $Context.fixtures
            webDriver = $Context.webDriver
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
    if ($artifactItem.Name -notlike [string](Get-HcrPropertyValue $artifactDeclaration 'fileNamePattern') -or
        [int64]$artifactItem.Length -ne [int64](Get-HcrPropertyValue $artifactDeclaration 'sizeBytes') -or
        $artifactHash -ne [string](Get-HcrPropertyValue $artifactDeclaration 'sha256')) {
        Throw-HcrError 'ARTIFACT_PROFILE_MISMATCH' 'The portable artifact identity does not exactly match the profile.'
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
    $profileSha = Get-HcrSha256File $profileValidation.path
    $fixtureSetSha = Get-HcrV2FixtureSetSha256 @($fixtures | ForEach-Object { $_.declaration })
    $webDriver = Get-HcrPropertyValue $profile 'webDriver'
    $webDriverSha = Get-HcrSha256Text (ConvertTo-HcrJson $webDriver 100)
    $sourceCommit = Get-HcrV2SourceCommit
    $evidenceRoot = Get-HcrEvidenceStagingRoot $OperationId
    [void](New-Item -ItemType Directory -Path $evidenceRoot -Force)
    $operation = [pscustomobject][ordered]@{
        schemaVersion = 2; operationId = $OperationId; operationType = 'runTestProfile'; createdAt = Get-HcrUtcTimestamp
        vmId = [string](Get-HcrPropertyValue $owned.vm 'id'); vmName = $vmName; profileId = [string](Get-HcrPropertyValue $profile 'id')
        baselineType = [string](Get-HcrPropertyValue $profile 'baselineType'); adapterMode = Get-HcrAdapterMode
        sourceCommit = $sourceCommit; portableZipSha256 = $artifactHash; profileSha256 = $profileSha
        fixtureSetSha256 = $fixtureSetSha; webDriverManifestSha256 = $webDriverSha
        cleanupTriggered = $false; cleanupSteps = @((Get-HcrPropertyValue $profile 'cleanupSteps' @()))
        automaticAssertions = @(); manualAssertions = @((Get-HcrPropertyValue $profile 'manualAssertions' @()))
        evidenceRoot = $evidenceRoot; evidenceFile = $null; evidenceSha256 = $null
        manualAttestations = @(); exportedEvidencePath = $null; exportedAt = $null
    }
    Save-HcrOperationRecord $operation

    $artifactEvidence = New-Object System.Collections.Generic.List[object]
    $automatic = New-Object System.Collections.Generic.List[object]
    $uiTrace = New-Object System.Collections.Generic.List[object]
    $launched = New-Object System.Collections.Generic.List[object]
    $context = [pscustomobject][ordered]@{
        operationId=$OperationId; vmName=$vmName; profileName=$profileName; workflowKind=[string](Get-HcrPropertyValue $profile 'workflowKind')
        applications=@((Get-HcrPropertyValue $profile 'applications')); artifact=$null; portableArtifact=$artifactDeclaration; sourceCommit=$sourceCommit; fixtures=@($fixtures | ForEach-Object { Copy-HcrObject $_.declaration }); webDriver=$webDriver
        launchedProcesses=$launched; expectedVmId=$identityArguments.expectedVmId; expectedVmName=$identityArguments.expectedVmName
        expectedOwnershipId=$identityArguments.expectedOwnershipId; expectedVmPath=$identityArguments.expectedVmPath; expectedVhdxPath=$identityArguments.expectedVhdxPath
    }
    $steps = @((Get-HcrPropertyValue $profile 'steps'))
    $staged = Invoke-HcrAdapter 'StageArtifact' ([pscustomobject]($identityArguments + @{
        sourcePath=$artifactItem.FullName; sourceSha256=$artifactHash; size=[int64]$artifactItem.Length
        guestDestination=$artifactItem.Name; timeoutSeconds=[int](Get-HcrPropertyValue $steps[0] 'timeoutSeconds')
    }))
    $artifactGuestHash = [string](Get-HcrPropertyValue $staged 'guestSha256')
    $stageStatus = if ($artifactGuestHash -eq $artifactHash) { 'passed' } else { 'failed' }
    $context.artifact = [pscustomobject]@{ guestDestination=[string](Get-HcrPropertyValue $staged 'guestDestination'); sourceSha256=$artifactHash; guestSha256=$artifactGuestHash }
    $automatic.Add((New-HcrV2AutomaticAssertion ([string](Get-HcrPropertyValue $steps[0] 'id')) $true $stageStatus 'Portable ZIP staging completed with exact hash verification.' ([pscustomobject]@{ sourceSha256=$artifactHash; guestSha256=$artifactGuestHash })))
    $artifactEvidence.Add([pscustomobject][ordered]@{ role='portableZip'; id='portable-zip'; fileName=$artifactItem.Name; sizeBytes=[int64]$artifactItem.Length; sourceSha256=$artifactHash; guestSha256=$artifactGuestHash; status=$stageStatus })
    foreach ($fixture in $fixtures) {
        $declaration = $fixture.declaration
        $fixtureStage = Invoke-HcrAdapter 'StageArtifact' ([pscustomobject]($identityArguments + @{
            sourcePath=$fixture.item.FullName; sourceSha256=$fixture.sha256; size=[int64]$fixture.item.Length
            guestDestination=('fixtures\' + [string](Get-HcrPropertyValue $declaration 'id') + '-' + $fixture.item.Name); timeoutSeconds=120
        }))
        $fixtureGuestHash = [string](Get-HcrPropertyValue $fixtureStage 'guestSha256')
        $fixtureContext = @($context.fixtures | Where-Object {
            [string](Get-HcrPropertyValue $_ 'id') -eq [string](Get-HcrPropertyValue $declaration 'id')
        })
        if ($fixtureContext.Count -ne 1) { Throw-HcrError 'FIXTURE_INVALID' 'The staged fixture identity is not unique.' }
        $fixtureContext[0] | Add-Member -NotePropertyName guestDestination -NotePropertyValue ([string](Get-HcrPropertyValue $fixtureStage 'guestDestination')) -Force
        $fixtureContext[0] | Add-Member -NotePropertyName guestSha256 -NotePropertyValue $fixtureGuestHash -Force
        $artifactEvidence.Add([pscustomobject][ordered]@{ role='fixture'; id=[string](Get-HcrPropertyValue $declaration 'id'); fileName=$fixture.item.Name; sizeBytes=[int64]$fixture.item.Length; sourceSha256=$fixture.sha256; guestSha256=$fixtureGuestHash; status=$(if($fixtureGuestHash -eq $fixture.sha256){'passed'}else{'failed'}) })
    }
    $tokenOk = -not $guest.isAdministrator -and -not $guest.isElevated -and $guest.tokenIntegrity -eq 'medium'
    $automatic.Add((New-HcrV2AutomaticAssertion 'runtime-ordinary-user-token' $true $(if($tokenOk){'passed'}else{'failed'}) 'Ordinary test-user token invariants were evaluated.' ([pscustomobject]@{ userSid=$guest.userSid; tokenIntegrity=$guest.tokenIntegrity })))
    $cleanupTriggered = $stageStatus -ne 'passed' -or -not $tokenOk -or @($artifactEvidence | Where-Object { $_.status -ne 'passed' }).Count -gt 0
    $deploymentId = [Guid]::Empty.ToString(); $deploymentFingerprint = ('0' * 64)
    $previousInventory = $null; $deployedInventory = ('0' * 64); $dataPreserved = $false
    $portableManifestGuestHash = $null; $driverArchiveGuestHash = $null; $driverExecutableGuestHash = $null
    $fixedWebView2Version = [string](Get-HcrPropertyValue $webDriver 'browserVersion')
    $driverVerified = $false; $loopbackOnly = $false; $deployStatus = 'notPerformed'
    for ($index=1; $index -lt $steps.Count; $index++) {
        $step=$steps[$index]; $required=[bool](Get-HcrPropertyValue $step 'required' $true); $type=[string](Get-HcrPropertyValue $step 'type')
        if ($cleanupTriggered) { $result=[pscustomobject]@{status='notPerformed';summary='A prior required failure stopped ordinary steps.';evidence=$null} }
        else { $result=Invoke-HcrV2StepSafely $step $context }
        $status=[string](Get-HcrPropertyValue $result 'status' 'failed'); $summary=[string](Get-HcrPropertyValue $result 'summary' 'The step returned no summary.'); $machineEvidence=Get-HcrPropertyValue $result 'evidence'
        if ($status -eq 'passed' -and $type -eq 'deployPortable') {
            $portableManifestGuestHash = [string](Get-HcrPropertyValue $machineEvidence 'portableManifestSha256')
            $fixedWebView2Version = [string](Get-HcrPropertyValue $machineEvidence 'fixedWebView2Version')
            if ($portableManifestGuestHash -ne [string](Get-HcrPropertyValue $artifactDeclaration 'portableManifestSha256') -or
                $fixedWebView2Version -ne [string](Get-HcrPropertyValue $webDriver 'browserVersion')) {
                $status = 'failed'; $summary = 'The deployed portable manifest hash or fixed WebView2 version did not match the immutable profile.'
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
        }
        if ($status -eq 'passed' -and $type -eq 'acquireWebDriver') { $driverVerified = $true }
        if ($script:HcrV2UiStepTypes -contains $type) { $uiTrace.Add([pscustomobject][ordered]@{ stepId=[string](Get-HcrPropertyValue $step 'id'); stepType=$type; testId=$(if(Test-HcrProperty $step 'testId'){[string](Get-HcrPropertyValue $step 'testId')}else{$null}); status=$status; summary=$summary; observations=@(ConvertTo-HcrV2Observations $machineEvidence) }) }
        if ($status -eq 'failed' -and ($required -or $script:HcrV2ActionStepTypes -contains $type)) { $cleanupTriggered=$true }
    }
    $manifestHash=[string](Get-HcrPropertyValue $artifactDeclaration 'portableManifestSha256')
    $driverStatus = if ($driverVerified) { 'passed' } else { 'notPerformed' }
    $artifactEvidence.Add([pscustomobject][ordered]@{ role='portableManifest'; id='portable-manifest'; fileName='portable-manifest.json'; sizeBytes=0; sourceSha256=$manifestHash; guestSha256=$(if($deployStatus -eq 'passed'){$portableManifestGuestHash}else{$null}); status=$deployStatus })
    $driverArchive=Get-HcrPropertyValue $webDriver 'acquisition'; $driverExecutable=Get-HcrPropertyValue $webDriver 'executable'
    $artifactEvidence.Add([pscustomobject][ordered]@{ role='webDriverArchive'; id='webdriver-archive'; fileName=[string](Get-HcrPropertyValue $driverArchive 'archiveFileName'); sizeBytes=[int64](Get-HcrPropertyValue $driverArchive 'archiveSizeBytes'); sourceSha256=[string](Get-HcrPropertyValue $driverArchive 'archiveSha256'); guestSha256=$(if($driverVerified){$driverArchiveGuestHash}else{$null}); status=$driverStatus })
    $artifactEvidence.Add([pscustomobject][ordered]@{ role='webDriverExecutable'; id='webdriver-executable'; fileName='msedgedriver.exe'; sizeBytes=[int64](Get-HcrPropertyValue $driverExecutable 'sizeBytes'); sourceSha256=[string](Get-HcrPropertyValue $driverExecutable 'sha256'); guestSha256=$(if($driverVerified){$driverExecutableGuestHash}else{$null}); status=$driverStatus })
    $artifactEvidence.Add([pscustomobject][ordered]@{ role='deployedPayload'; id='deployed-payload'; fileName=$artifactItem.Name; sizeBytes=[int64]$artifactItem.Length; sourceSha256=$artifactHash; guestSha256=$(if($deployStatus -eq 'passed'){$artifactHash}else{$null}); status=$deployStatus })
    $operation.cleanupTriggered=$cleanupTriggered
    $operation.automaticAssertions=@($automatic | ForEach-Object { $_ })
    Save-HcrOperationRecord $operation
    $cleanupResults=New-Object System.Collections.Generic.List[object]
    foreach($step in @((Get-HcrPropertyValue $profile 'cleanupSteps' @()))){
        if($cleanupTriggered){$result=Invoke-HcrV2StepSafely $step $context -Cleanup; $cleanupResults.Add((New-HcrV2CleanupResult $OperationId $operation.profileId $step ([string](Get-HcrPropertyValue $result 'status' 'failed')) ([string](Get-HcrPropertyValue $result 'summary' 'Cleanup returned no summary.')) (Get-HcrPropertyValue $result 'evidence')))}
        else{$cleanupResults.Add((New-HcrV2CleanupResult $OperationId $operation.profileId $step 'notPerformed' 'Cleanup was not triggered.' $null))}
    }
    $manual=@(@((Get-HcrPropertyValue $profile 'manualAssertions'))|ForEach-Object{[pscustomobject][ordered]@{id=[string](Get-HcrPropertyValue $_ 'id');required=[bool](Get-HcrPropertyValue $_ 'required');description=[string](Get-HcrPropertyValue $_ 'description');status='notPerformed';attestation=$null}})
    $machineStatus=if($cleanupTriggered -or -not $dataPreserved -or -not $driverVerified -or @($automatic|Where-Object{$_.required -and $_.status -ne 'passed'}).Count -gt 0){'failed'}else{'passed'}
    $overallStatus=if($machineStatus -eq 'failed'){'failed'}elseif(@($manual|Where-Object{$_.required -and $_.status -ne 'passed'}).Count -gt 0){'incomplete'}else{'passed'}
    $candidate=[pscustomobject][ordered]@{sourceCommit=$sourceCommit;portableZipSha256=$artifactHash;profileSha256=$profileSha;fixtureSetSha256=$fixtureSetSha;webDriverManifestSha256=$webDriverSha}
    $evidenceWarnings = [object[]]@()
    if ((Get-HcrAdapterMode) -eq 'mock') { $evidenceWarnings = [object[]]@([string]$script:HcrMockWarning) }
    $evidence=[pscustomobject][ordered]@{
        schemaVersion=2;operationId=$OperationId;createdAt=Get-HcrUtcTimestamp
        profile=[pscustomobject][ordered]@{id=$operation.profileId;schemaVersion=2;sha256=$profileSha};candidate=$candidate
        runtime=[pscustomobject][ordered]@{pluginVersion='0.2.0';sourceCommit=$sourceCommit;adapterMode=$(if((Get-HcrAdapterMode)-eq'mock'){'mock'}else{'production'})}
        baselineType=$operation.baselineType
        vm=[pscustomobject][ordered]@{id=$operation.vmId;name=$vmName;checkpointId=$null;checkpointName=$null;ownershipId=[string](Get-HcrPropertyValue $owned.ownership 'ownershipId');ownershipVerified=$true;fingerprint=Get-HcrVmFingerprint $owned.vm}
        guest=$guest;artifacts=@($artifactEvidence | ForEach-Object { $_ });automation=[pscustomobject][ordered]@{deploymentId=$deploymentId;deploymentFingerprint=$deploymentFingerprint;dataPreserved=$dataPreserved;previousDataInventorySha256=$previousInventory;deployedDataInventorySha256=$deployedInventory;webDriverManifestSha256=$webDriverSha;fixedWebView2Version=$fixedWebView2Version;webDriverVersion=[string](Get-HcrPropertyValue $webDriver 'driverVersion');loopbackOnly=$loopbackOnly;uiTrace=@($uiTrace | ForEach-Object { $_ })}
        powerOperations=@();networkOperations=@();networkRecovery=[pscustomobject][ordered]@{required=$false;changePlanId=$null;recoveryPlanId=$null;recoveryOperationId=$null;status='notPerformed';initialFingerprint=$null;finalFingerprint=$null}
        automaticAssertions=@($automatic | ForEach-Object { $_ });manualAssertions=$manual;cleanupTriggered=$cleanupTriggered;cleanupResults=@($cleanupResults | ForEach-Object { $_ });machineStatus=$machineStatus;overallStatus=$overallStatus
        warnings=$evidenceWarnings
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

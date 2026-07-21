function Invoke-HcrInspectGuest {
    param(
        [Parameter(Mandatory = $true)][object]$Arguments,
        [Parameter(Mandatory = $true)][string]$OperationId
    )

    $vmName = [string](Get-HcrPropertyValue $Arguments 'vmName')
    $owned = Get-HcrRequiredOwnedVm $vmName
    [void](Invoke-HcrAdapter 'ResolveCredentialProfile' ([pscustomobject][ordered]@{
        vmName = $vmName
        profileName = [string](Get-HcrPropertyValue $Arguments 'credentialProfile')
    }))
    $guest = Invoke-HcrAdapter 'InspectGuest' ([pscustomobject][ordered]@{
        vmName = $vmName
        profileName = [string](Get-HcrPropertyValue $Arguments 'credentialProfile')
        operationId = $OperationId
        expectedVmId = [string](Get-HcrPropertyValue $owned.vm 'id')
        expectedVmName = [string](Get-HcrPropertyValue $owned.vm 'name')
        expectedOwnershipId = [string](Get-HcrPropertyValue $owned.ownership 'ownershipId')
        expectedVmPath = [string](Get-HcrPropertyValue $owned.vm 'vmPath')
        expectedVhdxPath = [string](Get-HcrPropertyValue $owned.vm 'vhdxPath')
        timeoutSeconds = 60
    })
    return [pscustomobject][ordered]@{
        changed = $true
        data = [pscustomobject][ordered]@{
            vmId = [string](Get-HcrPropertyValue $owned.vm 'id')
            vmName = $vmName
            ownershipVerified = $true
            guest = $guest
        }
        warnings = @()
    }
}

function Invoke-HcrStageArtifact {
    param(
        [Parameter(Mandatory = $true)][object]$Arguments,
        [Parameter(Mandatory = $true)][string]$OperationId
    )

    $vmName = [string](Get-HcrPropertyValue $Arguments 'vmName')
    $owned = Get-HcrRequiredOwnedVm $vmName
    [void](Invoke-HcrAdapter 'ResolveCredentialProfile' ([pscustomobject][ordered]@{
        vmName = $vmName
        profileName = [string](Get-HcrPropertyValue $Arguments 'credentialProfile')
    }))
    $destination = [string](Get-HcrPropertyValue $Arguments 'guestDestination')
    if (-not (Test-HcrSafeRelativePath $destination)) {
        Throw-HcrError 'INVALID_GUEST_PATH' 'guestDestination must be relative to the test staging root.'
    }
    $source = Assert-HcrRegularLocalFile ([string](Get-HcrPropertyValue $Arguments 'sourcePath')) 'INVALID_ARTIFACT'
    $sourceHash = Get-HcrSha256File $source.FullName
    $staged = Invoke-HcrAdapter 'StageArtifact' ([pscustomobject][ordered]@{
        vmName = $vmName
        profileName = [string](Get-HcrPropertyValue $Arguments 'credentialProfile')
        operationId = $OperationId
        sourcePath = $source.FullName
        sourceSha256 = $sourceHash
        size = [int64]$source.Length
        guestDestination = $destination
        expectedVmId = [string](Get-HcrPropertyValue $owned.vm 'id')
        expectedVmName = [string](Get-HcrPropertyValue $owned.vm 'name')
        expectedOwnershipId = [string](Get-HcrPropertyValue $owned.ownership 'ownershipId')
        expectedVmPath = [string](Get-HcrPropertyValue $owned.vm 'vmPath')
        expectedVhdxPath = [string](Get-HcrPropertyValue $owned.vm 'vhdxPath')
        timeoutSeconds = 300
    })
    $guestHash = [string](Get-HcrPropertyValue $staged 'guestSha256')
    if ($guestHash -ne $sourceHash) {
        Throw-HcrError 'ARTIFACT_HASH_MISMATCH' 'The staged artifact hash does not match the source hash.' ([ordered]@{
            sourceSha256 = $sourceHash
            guestSha256 = $guestHash
        })
    }
    return [pscustomobject][ordered]@{
        changed = $true
        data = [pscustomobject][ordered]@{
            fileName = $source.Name
            size = [int64]$source.Length
            sourceSha256 = $sourceHash
            guestSha256 = $guestHash
            guestDestination = [string](Get-HcrPropertyValue $staged 'guestDestination')
        }
        warnings = @('This staging result is scoped to this operation and is not reused by run_test_profile.')
    }
}

function New-HcrAutomaticAssertion {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][bool]$Required,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Summary,
        [AllowNull()][object]$Evidence = $null
    )

    if (@('passed', 'failed', 'notPerformed', 'unsupported') -notcontains $Status) {
        $Status = 'failed'
        $Summary = 'The adapter returned an unsupported result status.'
        $Evidence = $null
    }
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 2000) }
    return [pscustomobject][ordered]@{
        id = $Id
        required = $Required
        status = $Status
        summary = $Summary
        evidence = $Evidence
    }
}

function Get-HcrGuestEvidenceProjection {
    param([Parameter(Mandatory = $true)][object]$Guest)

    $enabledAdministrator = [bool](Get-HcrPropertyValue $Guest 'isAdministrator' $true)
    $hasAdministratorsSid = if (Test-HcrProperty $Guest 'hasAdministratorsSid') {
        [bool](Get-HcrPropertyValue $Guest 'hasAdministratorsSid' $true)
    }
    else { $enabledAdministrator }
    $architecture = switch ([string](Get-HcrPropertyValue $Guest 'architecture')) {
        'AMD64' { 'x64' }
        'x64' { 'x64' }
        default {
            Throw-HcrError 'GUEST_ARCHITECTURE_UNSUPPORTED' 'The clean-room profile requires an x64 Windows guest.'
        }
    }
    return [pscustomobject][ordered]@{
        windowsBuild = [string](Get-HcrPropertyValue $Guest 'windowsBuild')
        architecture = $architecture
        userName = [string](Get-HcrPropertyValue $Guest 'userName')
        isAdministrator = [bool](
            $enabledAdministrator -or $hasAdministratorsSid
        )
        isElevated = [bool](Get-HcrPropertyValue $Guest 'isElevated' $true)
        tokenIntegrity = [string](Get-HcrPropertyValue $Guest 'tokenIntegrity' 'high')
        profilePathContainsNonAscii = [bool](Get-HcrPropertyValue $Guest 'profilePathContainsNonAscii' $false)
    }
}

function Invoke-HcrProfileStepSafely {
    param(
        [Parameter(Mandatory = $true)][object]$Step,
        [Parameter(Mandatory = $true)][object]$Context
    )

    $started = [Diagnostics.Stopwatch]::StartNew()
    try {
        $result = Invoke-HcrAdapter 'RunTestStep' ([pscustomobject][ordered]@{
            vmName = $Context.vmName
            profileName = $Context.profileName
            operationId = $Context.operationId
            step = $Step
            applications = $Context.applications
            artifact = $Context.artifact
        launchedProcesses = @($Context.launchedProcesses | ForEach-Object { $_ })
        expectedVmId = $Context.expectedVmId
        expectedVmName = $Context.expectedVmName
        expectedOwnershipId = $Context.expectedOwnershipId
        expectedVmPath = $Context.expectedVmPath
        expectedVhdxPath = $Context.expectedVhdxPath
        timeoutSeconds = [int](Get-HcrPropertyValue $Step 'timeoutSeconds')
        })
        $started.Stop()
        if ([bool](Get-HcrPropertyValue $result 'timedOut' $false) -or
            $started.Elapsed.TotalSeconds -gt [double](Get-HcrPropertyValue $Step 'timeoutSeconds')) {
            return [pscustomobject][ordered]@{
                status = 'failed'
                summary = 'The step exceeded its declared timeout.'
                evidence = [pscustomobject]@{ timedOut = $true }
                failureKind = 'timeout'
            }
        }
        return $result
    }
    catch {
        $started.Stop()
        $failure = Get-HcrExceptionData $_.Exception
        return [pscustomobject][ordered]@{
            status = 'failed'
            summary = "Guest adapter failure: $($failure.code)."
            evidence = [pscustomobject]@{ errorCode = $failure.code }
            failureKind = 'adapter'
        }
    }
}

function New-HcrUnperformedCleanupResults {
    param(
        [Parameter(Mandatory = $true)][string]$OperationId,
        [Parameter(Mandatory = $true)][string]$ProfileId,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$CleanupSteps
    )

    return @($CleanupSteps | ForEach-Object {
        [pscustomobject][ordered]@{
            operationId = $OperationId
            profileId = $ProfileId
            cleanupStepId = [string](Get-HcrPropertyValue $_ 'id')
            cleanupStepType = [string](Get-HcrPropertyValue $_ 'type')
            status = 'notPerformed'
            summary = 'Cleanup was not triggered.'
            evidence = $null
        }
    })
}

function Get-HcrBoundedCleanupTimeout {
    param(
        [Parameter(Mandatory = $true)][int]$DeclaredSeconds,
        [Parameter(Mandatory = $true)][int]$RemainingSeconds
    )

    if ($DeclaredSeconds -lt 1 -or $RemainingSeconds -lt 1) { return 0 }
    return [int][Math]::Min($DeclaredSeconds, $RemainingSeconds)
}

function Invoke-HcrCleanupSteps {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$CleanupSteps,
        [Parameter(Mandatory = $true)][object]$Context
    )

    $results = New-Object System.Collections.Generic.List[object]
    $budget = [Diagnostics.Stopwatch]::StartNew()
    $cleanupDeadlineUtc = [DateTimeOffset]::UtcNow.AddSeconds(300)
    foreach ($step in $CleanupSteps) {
        $stepId = [string](Get-HcrPropertyValue $step 'id')
        $stepType = [string](Get-HcrPropertyValue $step 'type')
        $remainingSeconds = [int][Math]::Floor(
            ($cleanupDeadlineUtc - [DateTimeOffset]::UtcNow).TotalSeconds
        )
        if ($remainingSeconds -lt 1) {
            $results.Add([pscustomobject][ordered]@{
                operationId = $Context.operationId
                profileId = $Context.profileId
                cleanupStepId = $stepId
                cleanupStepType = $stepType
                status = 'notPerformed'
                summary = 'The total cleanup budget was exhausted.'
                evidence = $null
            })
            continue
        }
        $effectiveStep = Copy-HcrObject $step
        $effectiveTimeout = Get-HcrBoundedCleanupTimeout `
            -DeclaredSeconds ([int](Get-HcrPropertyValue $step 'timeoutSeconds')) `
            -RemainingSeconds $remainingSeconds
        $effectiveStep.timeoutSeconds = $effectiveTimeout
        $launchedProcess = $null
        if ($stepType -eq 'stopApplication') {
            $application = [string](Get-HcrPropertyValue $step 'application')
            $processes = @($Context.launchedProcesses | Where-Object {
                [string](Get-HcrPropertyValue $_ 'application') -eq $application
            } | Select-Object -Last 1)
            if ($processes.Count -eq 0) {
                $results.Add([pscustomobject][ordered]@{
                    operationId = $Context.operationId
                    profileId = $Context.profileId
                    cleanupStepId = $stepId
                    cleanupStepType = $stepType
                    status = 'failed'
                    summary = 'No current-operation launched PID exists for this application.'
                    evidence = [pscustomobject]@{ processIdentityRevalidated = $false }
                })
                continue
            }
            $launchedProcess = $processes[0]
        }
        try {
            $timer = [Diagnostics.Stopwatch]::StartNew()
            $result = Invoke-HcrAdapter 'RunCleanupStep' ([pscustomobject][ordered]@{
                vmName = $Context.vmName
                profileName = $Context.profileName
                operationId = $Context.operationId
                step = $effectiveStep
                applications = $Context.applications
                launchedProcess = $launchedProcess
                expectedVmId = $Context.expectedVmId
                expectedVmName = $Context.expectedVmName
                expectedOwnershipId = $Context.expectedOwnershipId
                expectedVmPath = $Context.expectedVmPath
                expectedVhdxPath = $Context.expectedVhdxPath
                timeoutSeconds = $effectiveTimeout
                deadlineUtc = $cleanupDeadlineUtc.ToString('o')
            })
            $timer.Stop()
            $status = [string](Get-HcrPropertyValue $result 'status' 'failed')
            $summary = [string](Get-HcrPropertyValue $result 'summary' 'Cleanup adapter returned no summary.')
            $machineEvidence = Get-HcrPropertyValue $result 'evidence'
            if ([bool](Get-HcrPropertyValue $result 'timedOut' $false) -or
                $timer.Elapsed.TotalSeconds -gt [double]$effectiveTimeout -or
                [DateTimeOffset]::UtcNow -gt $cleanupDeadlineUtc) {
                $status = 'failed'
                $summary = 'The cleanup step exceeded its declared timeout.'
                $machineEvidence = [pscustomobject]@{ timedOut = $true }
            }
            if (@('passed', 'failed', 'unsupported') -notcontains $status) {
                $status = 'failed'
                $summary = 'The cleanup adapter returned an invalid status.'
                $machineEvidence = $null
            }
        }
        catch {
            $failure = Get-HcrExceptionData $_.Exception
            $status = 'failed'
            $summary = "Cleanup adapter failure: $($failure.code)."
            $machineEvidence = [pscustomobject]@{ errorCode = $failure.code }
        }
        if ($summary.Length -gt 2000) { $summary = $summary.Substring(0, 2000) }
        $results.Add([pscustomobject][ordered]@{
            operationId = $Context.operationId
            profileId = $Context.profileId
            cleanupStepId = $stepId
            cleanupStepType = $stepType
            status = $status
            summary = $summary
            evidence = $machineEvidence
        })
    }
    $budget.Stop()
    return @($results | ForEach-Object { $_ })
}

function Write-HcrOperationEvidence {
    param(
        [Parameter(Mandatory = $true)][object]$Operation,
        [Parameter(Mandatory = $true)][object]$Evidence
    )

    $root = [string](Get-HcrPropertyValue $Operation 'evidenceRoot')
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $root -Force)
    }
    $path = Join-Path $root 'evidence.json'
    Write-HcrJsonFile $path $Evidence
    $Operation.evidenceFile = $path
    return $path
}

function Invoke-HcrRunTestProfileV1 {
    param(
        [Parameter(Mandatory = $true)][object]$Arguments,
        [Parameter(Mandatory = $true)][string]$OperationId,
        [AllowNull()][object]$ValidatedProfile = $null
    )

    $vmName = [string](Get-HcrPropertyValue $Arguments 'vmName')
    $profileName = [string](Get-HcrPropertyValue $Arguments 'credentialProfile')
    $owned = Get-HcrRequiredOwnedVm $vmName
    if ($null -eq $ValidatedProfile) {
        $profileValidation = Read-AndValidate-HcrProfile ([string](Get-HcrPropertyValue $Arguments 'profilePath'))
        if (-not $profileValidation.valid) {
            Throw-HcrError 'PROFILE_INVALID' 'The test profile failed validation before execution.' ([ordered]@{ errors = @($profileValidation.errors) })
        }
        $profile = $profileValidation.profile
    }
    else {
        # Only the exact-version schema-v2 legacy dispatcher supplies this
        # deterministic inverse projection after native v2 validation.
        $profile = $ValidatedProfile
    }
    $artifactItem = Assert-HcrRegularLocalFile ([string](Get-HcrPropertyValue $Arguments 'artifactPath')) 'INVALID_ARTIFACT'
    $artifactDeclaration = Get-HcrPropertyValue $profile 'artifact'
    $fileNamePattern = [string](Get-HcrPropertyValue $artifactDeclaration 'fileNamePattern')
    if ($artifactItem.Name -notlike $fileNamePattern) {
        Throw-HcrError 'ARTIFACT_PROFILE_MISMATCH' 'The artifact filename does not match the profile glob.'
    }
    $sourceHash = Get-HcrSha256File $artifactItem.FullName
    if ((Test-HcrProperty $artifactDeclaration 'sha256') -and
        [string](Get-HcrPropertyValue $artifactDeclaration 'sha256') -ne $sourceHash) {
        Throw-HcrError 'ARTIFACT_PROFILE_MISMATCH' 'The artifact SHA-256 does not match the profile.'
    }
    [void](Invoke-HcrAdapter 'ResolveCredentialProfile' ([pscustomobject][ordered]@{
        vmName = $vmName
        profileName = $profileName
    }))
    $guestRaw = Invoke-HcrAdapter 'InspectGuest' ([pscustomobject][ordered]@{
        vmName = $vmName
        profileName = $profileName
        operationId = $OperationId
        expectedVmId = [string](Get-HcrPropertyValue $owned.vm 'id')
        expectedVmName = [string](Get-HcrPropertyValue $owned.vm 'name')
        expectedOwnershipId = [string](Get-HcrPropertyValue $owned.ownership 'ownershipId')
        expectedVmPath = [string](Get-HcrPropertyValue $owned.vm 'vmPath')
        expectedVhdxPath = [string](Get-HcrPropertyValue $owned.vm 'vhdxPath')
        timeoutSeconds = 60
    })
    $guest = Get-HcrGuestEvidenceProjection $guestRaw

    # Validation is complete; creating immutable operation state enters execution.
    $evidenceRoot = Get-HcrEvidenceStagingRoot $OperationId
    [void](New-Item -ItemType Directory -Path $evidenceRoot -Force)
    $steps = @((Get-HcrPropertyValue $profile 'steps'))
    $cleanupSteps = @((Get-HcrPropertyValue $profile 'cleanupSteps' @()))
    $automaticIdentities = @()
    $automaticIdentities += [pscustomobject][ordered]@{
        id = [string](Get-HcrPropertyValue $steps[0] 'id')
        required = $true
        type = 'stageArtifact'
    }
    $automaticIdentities += [pscustomobject][ordered]@{
        id = 'runtime-ordinary-user-token'
        required = $true
        type = 'runtimeInvariant'
    }
    for ($identityIndex = 1; $identityIndex -lt $steps.Count; $identityIndex++) {
        $identityStep = $steps[$identityIndex]
        $automaticIdentities += [pscustomobject][ordered]@{
            id = [string](Get-HcrPropertyValue $identityStep 'id')
            required = [bool](Get-HcrPropertyValue $identityStep 'required' $true)
            type = [string](Get-HcrPropertyValue $identityStep 'type')
        }
    }
    $manualIdentities = @(@((Get-HcrPropertyValue $profile 'manualAssertions')) | ForEach-Object {
        [pscustomobject][ordered]@{
            id = [string](Get-HcrPropertyValue $_ 'id')
            required = [bool](Get-HcrPropertyValue $_ 'required')
            description = [string](Get-HcrPropertyValue $_ 'description')
        }
    })
    $operation = [pscustomobject][ordered]@{
        schemaVersion = 1
        operationId = $OperationId
        operationType = 'runTestProfile'
        createdAt = Get-HcrUtcTimestamp
        vmId = [string](Get-HcrPropertyValue $owned.vm 'id')
        vmName = $vmName
        profileId = [string](Get-HcrPropertyValue $profile 'id')
        baselineType = [string](Get-HcrPropertyValue $profile 'baselineType')
        adapterMode = Get-HcrAdapterMode
        cleanupTriggered = $false
        cleanupSteps = @($cleanupSteps | ForEach-Object {
            [pscustomobject][ordered]@{
                id = [string](Get-HcrPropertyValue $_ 'id')
                type = [string](Get-HcrPropertyValue $_ 'type')
            }
        })
        automaticAssertions = $automaticIdentities
        manualAssertions = $manualIdentities
        artifact = [pscustomobject][ordered]@{
            fileName = $artifactItem.Name
            size = [int64]$artifactItem.Length
            sourceSha256 = $sourceHash
            guestSha256 = $null
        }
        guest = $guest
        ownershipVerified = $true
        evidenceRoot = $evidenceRoot
        evidenceFile = $null
        evidenceSha256 = $null
        launchedProcesses = @()
        manualAttestations = @()
        exportedEvidencePath = $null
        exportedAt = $null
    }
    Save-HcrOperationRecord $operation

    $automatic = New-Object System.Collections.Generic.List[object]
    $launched = New-Object System.Collections.Generic.List[object]
    $guestDestination = $artifactItem.Name
    $staged = $null
    try {
        $staged = Invoke-HcrAdapter 'StageArtifact' ([pscustomobject][ordered]@{
            vmName = $vmName
            profileName = $profileName
            operationId = $OperationId
            sourcePath = $artifactItem.FullName
            sourceSha256 = $sourceHash
            size = [int64]$artifactItem.Length
            guestDestination = $guestDestination
            expectedVmId = [string](Get-HcrPropertyValue $owned.vm 'id')
            expectedVmName = [string](Get-HcrPropertyValue $owned.vm 'name')
            expectedOwnershipId = [string](Get-HcrPropertyValue $owned.ownership 'ownershipId')
            expectedVmPath = [string](Get-HcrPropertyValue $owned.vm 'vmPath')
            expectedVhdxPath = [string](Get-HcrPropertyValue $owned.vm 'vhdxPath')
            timeoutSeconds = [int](Get-HcrPropertyValue $steps[0] 'timeoutSeconds')
        })
        $guestDestination = [string](Get-HcrPropertyValue $staged 'guestDestination')
        $guestHash = [string](Get-HcrPropertyValue $staged 'guestSha256')
        $stageStatus = if ($guestHash -eq $sourceHash) { 'passed' } else { 'failed' }
        $stageSummary = if ($stageStatus -eq 'passed') { 'Artifact staged and both SHA-256 values match.' } else { 'Artifact staging hash mismatch.' }
        $automatic.Add((New-HcrAutomaticAssertion `
            ([string](Get-HcrPropertyValue $steps[0] 'id')) `
            $true `
            $stageStatus `
            $stageSummary `
            ([pscustomobject]@{ sourceSha256 = $sourceHash; guestSha256 = $guestHash })))
    }
    catch {
        $failure = Get-HcrExceptionData $_.Exception
        $guestHash = $null
        $automatic.Add((New-HcrAutomaticAssertion `
            ([string](Get-HcrPropertyValue $steps[0] 'id')) `
            $true `
            'failed' `
            "Artifact staging failed: $($failure.code)." `
            ([pscustomobject]@{ errorCode = $failure.code })))
    }
    $cleanupTriggered = $automatic[0].status -eq 'failed'
    $tokenOk = -not $guest.isAdministrator -and -not $guest.isElevated -and
        $guest.tokenIntegrity -eq 'medium'
    $automatic.Add((New-HcrAutomaticAssertion `
        'runtime-ordinary-user-token' `
        $true `
        $(if ($tokenOk) { 'passed' } else { 'failed' }) `
        $(if ($tokenOk) { 'Standard test-user token invariants passed.' } else { 'The test identity is elevated, administrative, or not medium integrity.' }) `
        ([pscustomobject]@{
            isAdministrator = $guest.isAdministrator
            isElevated = $guest.isElevated
            tokenIntegrity = $guest.tokenIntegrity
        })))
    if (-not $tokenOk) { $cleanupTriggered = $true }

    $context = [pscustomobject][ordered]@{
        vmName = $vmName
        profileName = $profileName
        operationId = $OperationId
        profileId = [string](Get-HcrPropertyValue $profile 'id')
        applications = @((Get-HcrPropertyValue $profile 'applications'))
        artifact = [pscustomobject][ordered]@{
            sourcePath = $artifactItem.FullName
            guestDestination = $guestDestination
            sourceSha256 = $sourceHash
            guestSha256 = $guestHash
        }
        launchedProcesses = $launched
        expectedVmId = [string](Get-HcrPropertyValue $owned.vm 'id')
        expectedVmName = [string](Get-HcrPropertyValue $owned.vm 'name')
        expectedOwnershipId = [string](Get-HcrPropertyValue $owned.ownership 'ownershipId')
        expectedVmPath = [string](Get-HcrPropertyValue $owned.vm 'vmPath')
        expectedVhdxPath = [string](Get-HcrPropertyValue $owned.vm 'vhdxPath')
    }
    for ($index = 1; $index -lt $steps.Count; $index++) {
        $step = $steps[$index]
        $required = [bool](Get-HcrPropertyValue $step 'required' $true)
        if ($cleanupTriggered) {
            $automatic.Add((New-HcrAutomaticAssertion `
                ([string](Get-HcrPropertyValue $step 'id')) `
                $required `
                'notPerformed' `
                'A prior required execution failure stopped ordinary steps.' `
                $null))
            continue
        }
        $result = Invoke-HcrProfileStepSafely $step $context
        $status = [string](Get-HcrPropertyValue $result 'status' 'failed')
        $stepType = [string](Get-HcrPropertyValue $step 'type')
        if (($script:HcrActionStepTypes -contains $stepType) -and $status -ne 'passed') {
            $status = 'failed'
        }
        $automatic.Add((New-HcrAutomaticAssertion `
            ([string](Get-HcrPropertyValue $step 'id')) `
            $required `
            $status `
            ([string](Get-HcrPropertyValue $result 'summary' 'The step returned no summary.')) `
            (Get-HcrPropertyValue $result 'evidence')))
        if ($status -eq 'passed' -and $stepType -eq 'launchApplication' -and
            (Test-HcrProperty $result 'process')) {
            $launched.Add((Copy-HcrObject (Get-HcrPropertyValue $result 'process')))
        }
        $failureKind = [string](Get-HcrPropertyValue $result 'failureKind')
        if ($status -eq 'failed' -and (
            $required -or
            $script:HcrActionStepTypes -contains $stepType -or
            @('timeout', 'adapter') -contains $failureKind
        )) {
            $cleanupTriggered = $true
        }
    }
    $operation.cleanupTriggered = $cleanupTriggered
    $operation.artifact.guestSha256 = $guestHash
    $operation.launchedProcesses = @($launched | ForEach-Object { $_ })
    Save-HcrOperationRecord $operation

    $cleanupContext = [pscustomobject][ordered]@{
        operationId = $OperationId
        profileId = [string](Get-HcrPropertyValue $profile 'id')
        vmName = $vmName
        profileName = $profileName
        applications = @((Get-HcrPropertyValue $profile 'applications'))
        launchedProcesses = $launched
        expectedVmId = [string](Get-HcrPropertyValue $owned.vm 'id')
        expectedVmName = [string](Get-HcrPropertyValue $owned.vm 'name')
        expectedOwnershipId = [string](Get-HcrPropertyValue $owned.ownership 'ownershipId')
        expectedVmPath = [string](Get-HcrPropertyValue $owned.vm 'vmPath')
        expectedVhdxPath = [string](Get-HcrPropertyValue $owned.vm 'vhdxPath')
    }
    $cleanupResults = if ($cleanupTriggered) {
        Invoke-HcrCleanupSteps $cleanupSteps $cleanupContext
    }
    else {
        New-HcrUnperformedCleanupResults $OperationId $cleanupContext.profileId $cleanupSteps
    }
    $manual = @(@((Get-HcrPropertyValue $profile 'manualAssertions')) | ForEach-Object {
        [pscustomobject][ordered]@{
            id = [string](Get-HcrPropertyValue $_ 'id')
            required = [bool](Get-HcrPropertyValue $_ 'required')
            description = [string](Get-HcrPropertyValue $_ 'description')
            status = 'notPerformed'
            attestation = $null
        }
    })
    $overall = Get-HcrDerivedOverallStatus @($automatic | ForEach-Object { $_ }) $manual
    $evidenceWarnings = @()
    if ((Get-HcrAdapterMode) -eq 'mock') {
        $evidenceWarnings += $script:HcrMockWarning
    }
    $evidence = [pscustomobject][ordered]@{
        schemaVersion = 1
        operationId = $OperationId
        createdAt = Get-HcrUtcTimestamp
        profileId = [string](Get-HcrPropertyValue $profile 'id')
        baselineType = [string](Get-HcrPropertyValue $profile 'baselineType')
        vm = [pscustomobject][ordered]@{
            id = [string](Get-HcrPropertyValue $owned.vm 'id')
            name = $vmName
            checkpointName = $null
            ownershipVerified = $true
        }
        guest = $guest
        artifact = [pscustomobject][ordered]@{
            fileName = $artifactItem.Name
            size = [int64]$artifactItem.Length
            sourceSha256 = $sourceHash
            guestSha256 = $guestHash
        }
        automaticAssertions = @($automatic | ForEach-Object { $_ })
        manualAssertions = $manual
        cleanupTriggered = $cleanupTriggered
        cleanupResults = @($cleanupResults)
        overallStatus = $overall
        warnings = $evidenceWarnings
    }
    [void](Write-HcrOperationEvidence $operation $evidence)
    $operation.evidenceSha256 = Get-HcrEvidenceDocumentDigest $evidence
    Save-HcrOperationRecord $operation
    return [pscustomobject][ordered]@{
        changed = $true
        data = [pscustomobject][ordered]@{
            testOperationId = $OperationId
            profileId = [string](Get-HcrPropertyValue $profile 'id')
            overallStatus = $overall
            cleanupTriggered = $cleanupTriggered
            automaticAssertions = @($automatic | ForEach-Object { $_ })
            manualAssertions = $manual
            cleanupResults = @($cleanupResults)
        }
        warnings = @('Evidence remains in a server-controlled staging root until collect_evidence exports it.')
    }
}

function Get-HcrObserverIdentity {
    try {
        $name = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        if (-not [string]::IsNullOrWhiteSpace($name)) { return $name }
    }
    catch {
        # Fall back to the process environment without emitting a diagnostic.
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERNAME)) { return $env:USERNAME }
    return 'unknown-windows-identity'
}

function Resolve-HcrEvidenceReferences {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$References,
        [Parameter(Mandatory = $true)][string]$EvidenceRoot
    )

    $verified = New-Object System.Collections.Generic.List[object]
    foreach ($reference in $References) {
        $relative = [string](Get-HcrPropertyValue $reference 'path')
        $expectedHash = [string](Get-HcrPropertyValue $reference 'sha256')
        if (-not (Test-HcrSafeRelativePath $relative) -or
            $expectedHash -notmatch '^[a-f0-9]{64}$') {
            Throw-HcrError 'EVIDENCE_REFERENCE_INVALID' 'A manual evidence reference is invalid.'
        }
        $canonicalRelative = $relative.Replace('\', '/')
        if ($canonicalRelative.Equals('evidence.json', [StringComparison]::OrdinalIgnoreCase) -or
            $canonicalRelative.Equals('inventory.json', [StringComparison]::OrdinalIgnoreCase)) {
            Throw-HcrError 'EVIDENCE_REFERENCE_INVALID' 'Mutable evidence control documents cannot be manual evidence references.'
        }
        $candidate = Get-HcrNormalizedPath (Join-Path $EvidenceRoot $relative)
        if (-not (Test-HcrPathWithin $candidate $EvidenceRoot)) {
            Throw-HcrError 'EVIDENCE_REFERENCE_INVALID' 'A manual evidence reference escapes the staging root.'
        }
        $item = Assert-HcrRegularLocalFile $candidate 'EVIDENCE_REFERENCE_INVALID'
        $actualHash = Get-HcrSha256File $item.FullName
        if ($actualHash -ne $expectedHash) {
            Throw-HcrError 'EVIDENCE_REFERENCE_HASH_MISMATCH' 'A manual evidence reference hash does not match.'
        }
        $verified.Add([pscustomobject][ordered]@{
            path = $canonicalRelative
            sha256 = $actualHash
        })
    }
    return @($verified | ForEach-Object { $_ })
}

function Invoke-HcrRecordManualAttestation {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $operationId = [string](Get-HcrPropertyValue $Arguments 'operationId')
    $status = [string](Get-HcrPropertyValue $Arguments 'status')
    $method = [string](Get-HcrPropertyValue $Arguments 'method')
    if (($status -eq 'unsupported' -and $method -ne 'declaredUnsupported') -or
        ($status -ne 'unsupported' -and $method -eq 'declaredUnsupported')) {
        Throw-HcrError 'INVALID_ARGUMENT' 'Manual status and method are inconsistent.'
    }
    $references = @((Get-HcrPropertyValue $Arguments 'evidenceReferences' @()))
    $result = Update-HcrOperationRecord $operationId {
        param($operation)

        if ((Get-HcrPropertyValue $operation 'operationType') -ne 'runTestProfile') {
            Throw-HcrError 'OPERATION_TYPE_MISMATCH' 'Manual attestations require a test-profile operation.'
        }
        $evidencePath = [string](Get-HcrPropertyValue $operation 'evidenceFile')
        if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
            Throw-HcrError 'EVIDENCE_NOT_READY' 'The operation evidence is not ready.'
        }
        $evidence = Read-HcrJsonFile $evidencePath 'EVIDENCE_NOT_READY'
        $isV2 = [int](Get-HcrPropertyValue $operation 'schemaVersion' 1) -eq 2
        $existingValidation = if ($isV2) {
            Test-HcrEvidenceDocumentV2 $evidence $operation
        }
        else { Test-HcrEvidenceDocument $evidence $operation }
        if (-not $existingValidation.valid) {
            Throw-HcrError 'EVIDENCE_INVALID' 'The existing operation evidence was modified or is invalid.' ([ordered]@{
                errors = @($existingValidation.errors)
            })
        }
        $assertionId = [string](Get-HcrPropertyValue $Arguments 'assertionId')
        $matches = @(@((Get-HcrPropertyValue $evidence 'manualAssertions' @())) |
            Where-Object { [string](Get-HcrPropertyValue $_ 'id') -eq $assertionId })
        if ($matches.Count -ne 1) {
            Throw-HcrError 'MANUAL_ASSERTION_NOT_FOUND' 'The manual assertion does not exist or is ambiguous.'
        }
        $assertion = $matches[0]
        if ((Get-HcrPropertyValue $assertion 'status') -ne 'notPerformed') {
            Throw-HcrError 'MANUAL_ASSERTION_ALREADY_RECORDED' 'The manual assertion already has an attestation.'
        }
        $verifiedReferences = Resolve-HcrEvidenceReferences `
            $references `
            ([string](Get-HcrPropertyValue $operation 'evidenceRoot'))
        $attestation = [pscustomobject][ordered]@{
            operationId = $operationId
            profileId = [string](Get-HcrPropertyValue $operation 'profileId')
            assertionId = $assertionId
            observer = Get-HcrObserverIdentity
            observedAt = Get-HcrUtcTimestamp
            method = $method
            summary = [string](Get-HcrPropertyValue $Arguments 'summary')
            evidenceReferences = @($verifiedReferences)
        }
        if ($isV2) {
            $attestation | Add-Member -NotePropertyName candidate -NotePropertyValue `
                (Copy-HcrObject (Get-HcrPropertyValue $evidence 'candidate')) -Force
        }
        $assertion.status = $status
        $assertion.attestation = $attestation
        $evidence.overallStatus = if ($isV2) {
            if ((Get-HcrPropertyValue $evidence 'machineStatus') -eq 'failed' -or
                @(@((Get-HcrPropertyValue $evidence 'manualAssertions')) | Where-Object {
                    (Get-HcrPropertyValue $_ 'required') -eq $true -and
                    (Get-HcrPropertyValue $_ 'status') -eq 'failed'
                }).Count -gt 0) { 'failed' }
            elseif (@(@((Get-HcrPropertyValue $evidence 'manualAssertions')) | Where-Object {
                    (Get-HcrPropertyValue $_ 'required') -eq $true -and
                    (Get-HcrPropertyValue $_ 'status') -ne 'passed'
                }).Count -gt 0) { 'incomplete' }
            else { 'passed' }
        }
        else {
            Get-HcrDerivedOverallStatus `
                @((Get-HcrPropertyValue $evidence 'automaticAssertions')) `
                @((Get-HcrPropertyValue $evidence 'manualAssertions'))
        }
        $operation.manualAttestations = @(@((Get-HcrPropertyValue $operation 'manualAttestations' @())) + $attestation)
        $operation.evidenceSha256 = Get-HcrEvidenceDocumentDigest $evidence
        $validation = if ($isV2) {
            Test-HcrEvidenceDocumentV2 $evidence $operation
        }
        else { Test-HcrEvidenceDocument $evidence $operation }
        if (-not $validation.valid) {
            Throw-HcrError 'EVIDENCE_INVALID' 'The attestation would make operation evidence invalid.' ([ordered]@{
                errors = @($validation.errors)
            })
        }
        Write-HcrJsonFile $evidencePath $evidence
        $operation | Add-Member -NotePropertyName lastAttestation -NotePropertyValue $attestation -Force
        return $operation
    }
    $attestationResult = Get-HcrPropertyValue $result 'lastAttestation'
    return [pscustomobject][ordered]@{
        changed = $true
        data = [pscustomobject][ordered]@{
            testOperationId = $operationId
            assertionId = [string](Get-HcrPropertyValue $attestationResult 'assertionId')
            status = $status
            attestation = $attestationResult
        }
        warnings = @()
    }
}

function Test-HcrEvidenceOutputForbidden {
    param([Parameter(Mandatory = $true)][string]$OutputDirectory)

    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @(
        $env:windir,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $script:HcrPluginRoot,
        $script:HcrStateRoot,
        (Get-HcrCredentialRoot)
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) {
            $roots.Add((Get-HcrNormalizedPath ([string]$candidate)))
        }
    }
    foreach ($ownership in @(Get-HcrOwnershipRecords)) {
        $vmRoot = [string](Get-HcrPropertyValue $ownership 'vmRoot')
        if (-not [string]::IsNullOrWhiteSpace($vmRoot)) {
            $roots.Add((Get-HcrNormalizedPath $vmRoot))
        }
    }
    foreach ($root in $roots) {
        if (Test-HcrPathWithin $OutputDirectory $root) { return $true }
    }
    return $false
}

function Invoke-HcrCollectEvidence {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $operationId = [string](Get-HcrPropertyValue $Arguments 'operationId')
    $outputItem = Assert-HcrLocalDirectory ([string](Get-HcrPropertyValue $Arguments 'outputDirectory')) 'INVALID_EVIDENCE_OUTPUT'
    if (Test-HcrEvidenceOutputForbidden $outputItem.FullName) {
        Throw-HcrError 'EVIDENCE_OUTPUT_FORBIDDEN' 'The output directory is inside a protected or managed root.'
    }
    $outputDirectory = $outputItem.FullName
    $holder = [pscustomobject]@{ result = $null }
    [void](Update-HcrOperationRecord $operationId {
        param($operation)

        if ((Get-HcrPropertyValue $operation 'operationType') -ne 'runTestProfile') {
            Throw-HcrError 'OPERATION_TYPE_MISMATCH' 'Only test-profile operations have collectible evidence.'
        }
        $lockedOutput = Assert-HcrLocalDirectory $outputDirectory 'INVALID_EVIDENCE_OUTPUT'
        if (Test-HcrEvidenceOutputForbidden $lockedOutput.FullName) {
            Throw-HcrError 'EVIDENCE_OUTPUT_FORBIDDEN' 'The output directory changed into a protected or managed root.'
        }
        $sourceRoot = [string](Get-HcrPropertyValue $operation 'evidenceRoot')
        $evidencePath = [string](Get-HcrPropertyValue $operation 'evidenceFile')
        if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container) -or
            -not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
            Throw-HcrError 'EVIDENCE_NOT_READY' 'The operation evidence staging root is unavailable.'
        }
        [void](Assert-HcrLocalDirectory $sourceRoot 'EVIDENCE_STAGING_INVALID')
        $evidence = Read-HcrJsonFile $evidencePath 'EVIDENCE_NOT_READY'
        $validation = if ([int](Get-HcrPropertyValue $operation 'schemaVersion' 1) -eq 2) {
            Test-HcrEvidenceDocumentV2 $evidence $operation
        }
        else { Test-HcrEvidenceDocument $evidence $operation }
        if (-not $validation.valid) {
            Throw-HcrError 'EVIDENCE_INVALID' 'The staged evidence failed validation and was not exported.' ([ordered]@{
                errors = @($validation.errors)
            })
        }
        if ($env:HCR_TEST_MODE -eq '1') {
            $testHook = Get-Variable `
                -Name HcrEvidenceExportAfterValidationTestHook `
                -Scope Global `
                -ValueOnly `
                -ErrorAction SilentlyContinue
            if ($testHook -is [scriptblock]) {
                & $testHook $sourceRoot $evidencePath
            }
        }
        foreach ($item in @(Get-ChildItem -LiteralPath $sourceRoot -Force -Recurse)) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                Throw-HcrError 'EVIDENCE_STAGING_INVALID' 'The evidence staging root contains a reparse point.'
            }
        }

        # Rebind all attestation claims while the operation record is locked.
        $claimedHashes = @{}
        foreach ($assertion in @((Get-HcrPropertyValue $evidence 'manualAssertions' @()))) {
            $attestation = Get-HcrPropertyValue $assertion 'attestation'
            if ($null -eq $attestation) { continue }
            $verified = @(Resolve-HcrEvidenceReferences `
                @((Get-HcrPropertyValue $attestation 'evidenceReferences' @())) `
                $sourceRoot)
            foreach ($reference in $verified) {
                $relative = [string](Get-HcrPropertyValue $reference 'path')
                $hash = [string](Get-HcrPropertyValue $reference 'sha256')
                if ($claimedHashes.ContainsKey($relative) -and $claimedHashes[$relative] -ne $hash) {
                    Throw-HcrError 'EVIDENCE_REFERENCE_HASH_MISMATCH' 'Duplicate manual evidence claims disagree.'
                }
                $claimedHashes[$relative] = $hash
            }
        }

        $sourceFiles = New-Object System.Collections.Generic.List[object]
        foreach ($file in @(Get-ChildItem -LiteralPath $sourceRoot -Force -Recurse -File | Sort-Object FullName)) {
            $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart('\', '/').Replace('\', '/')
            if (-not (Test-HcrSafeRelativePath $relative)) {
                Throw-HcrError 'EVIDENCE_STAGING_INVALID' 'The evidence staging root contains an unsafe relative path.'
            }
            if ($relative.Equals('inventory.json', [StringComparison]::OrdinalIgnoreCase)) {
                Throw-HcrError 'EVIDENCE_STAGING_INVALID' 'The generated inventory name is reserved in the evidence staging root.'
            }
            $regular = Assert-HcrRegularLocalFile $file.FullName 'EVIDENCE_STAGING_INVALID'
            $sourceHash = Get-HcrSha256File $regular.FullName
            if ($claimedHashes.ContainsKey($relative) -and $claimedHashes[$relative] -ne $sourceHash) {
                Throw-HcrError 'EVIDENCE_REFERENCE_HASH_MISMATCH' 'A manual evidence reference changed before export.'
            }
            $sourceFiles.Add([pscustomobject][ordered]@{
                path = $regular.FullName
                relative = $relative
                size = [int64]$regular.Length
                sha256 = $sourceHash
            })
        }
        foreach ($claimedPath in @($claimedHashes.Keys)) {
            if (@($sourceFiles | Where-Object { $_.relative -eq $claimedPath }).Count -ne 1) {
                Throw-HcrError 'EVIDENCE_REFERENCE_INVALID' 'A claimed manual evidence file is not uniquely exportable.'
            }
        }

        $targetRoot = Get-HcrNormalizedPath (Join-Path $lockedOutput.FullName "hyperv-clean-room-$operationId")
        if (Test-Path -LiteralPath $targetRoot) {
            Throw-HcrError 'EVIDENCE_OUTPUT_EXISTS' 'The operation evidence output directory already exists.'
        }
        [void](New-Item -ItemType Directory -Path $targetRoot)
        [void](Assert-HcrLocalDirectory $targetRoot 'INVALID_EVIDENCE_OUTPUT')
        $inventoryFiles = New-Object System.Collections.Generic.List[object]
        foreach ($source in $sourceFiles) {
            $destination = Get-HcrNormalizedPath (Join-Path $targetRoot $source.relative)
            if (-not (Test-HcrPathWithin $destination $targetRoot)) {
                Throw-HcrError 'EVIDENCE_STAGING_INVALID' 'An evidence file escapes the export root.'
            }
            $destinationParent = Split-Path -Parent $destination
            [void](Initialize-HcrLocalDirectoryPath $destinationParent 'INVALID_EVIDENCE_OUTPUT')
            $beforeHash = Get-HcrSha256File `
                (Assert-HcrRegularLocalFile $source.path 'EVIDENCE_STAGING_INVALID').FullName
            if ($beforeHash -ne $source.sha256) {
                Throw-HcrError 'EVIDENCE_REFERENCE_HASH_MISMATCH' 'An evidence source changed before copy.'
            }
            Copy-Item -LiteralPath $source.path -Destination $destination -ErrorAction Stop
            $afterHash = Get-HcrSha256File `
                (Assert-HcrRegularLocalFile $source.path 'EVIDENCE_STAGING_INVALID').FullName
            $copied = Assert-HcrRegularLocalFile $destination 'EVIDENCE_STAGING_INVALID'
            $copiedHash = Get-HcrSha256File $copied.FullName
            if ($beforeHash -ne $afterHash -or
                $beforeHash -ne $copiedHash -or
                ($claimedHashes.ContainsKey($source.relative) -and
                    $claimedHashes[$source.relative] -ne $copiedHash)) {
                Throw-HcrError 'EVIDENCE_REFERENCE_HASH_MISMATCH' 'Source, copied, and claimed evidence hashes do not agree.'
            }
            $inventoryFiles.Add([pscustomobject][ordered]@{
                path = $source.relative
                size = [int64]$copied.Length
                sha256 = $copiedHash
            })
        }
        $copiedEvidencePath = Join-Path $targetRoot 'evidence.json'
        $copiedEvidence = Read-HcrJsonFile $copiedEvidencePath 'EVIDENCE_STAGING_INVALID'
        $copiedValidation = Test-HcrEvidenceDocument $copiedEvidence $operation
        if (-not $copiedValidation.valid) {
            Throw-HcrError 'EVIDENCE_INVALID' 'The exact copied evidence bytes do not match immutable operation state.' ([ordered]@{
                errors = @($copiedValidation.errors)
            })
        }
        foreach ($entry in $inventoryFiles) {
            $inventoryTarget = Assert-HcrRegularLocalFile `
                (Join-Path $targetRoot ([string]$entry.path)) `
                'EVIDENCE_STAGING_INVALID'
            if ((Get-HcrSha256File $inventoryTarget.FullName) -ne [string]$entry.sha256) {
                Throw-HcrError 'EVIDENCE_REFERENCE_HASH_MISMATCH' 'The evidence inventory does not match the copied bytes.'
            }
        }
        $inventory = [pscustomobject][ordered]@{
            schemaVersion = 1
            operationId = $operationId
            createdAt = Get-HcrUtcTimestamp
            files = @($inventoryFiles | ForEach-Object { $_ })
        }
        $inventoryPath = Join-Path $targetRoot 'inventory.json'
        Write-HcrJsonFile $inventoryPath $inventory
        if ($env:HCR_TEST_MODE -eq '1') {
            $inventoryHook = Get-Variable `
                -Name HcrEvidenceExportAfterInventoryWriteTestHook `
                -Scope Global `
                -ValueOnly `
                -ErrorAction SilentlyContinue
            if ($inventoryHook -is [scriptblock]) {
                & $inventoryHook $inventoryPath $targetRoot
            }
        }

        # The serialized inventory is the exported verifier contract. Reopen
        # those exact bytes, bind every entry back to the generated in-memory
        # inventory, then verify the final copied files from the parsed claims.
        $publishedInventoryFile = Assert-HcrRegularLocalFile `
            $inventoryPath `
            'EVIDENCE_STAGING_INVALID'
        $publishedInventory = Read-HcrJsonFile `
            $publishedInventoryFile.FullName `
            'EVIDENCE_STAGING_INVALID'
        $inventoryPropertyNames = @(Get-HcrPropertyNames $publishedInventory)
        if ($inventoryPropertyNames.Count -ne 4 -or
            @('schemaVersion', 'operationId', 'createdAt', 'files' | Where-Object {
                $inventoryPropertyNames -notcontains $_
            }).Count -ne 0 -or
            [int](Get-HcrPropertyValue $publishedInventory 'schemaVersion' 0) -ne 1 -or
            [string](Get-HcrPropertyValue $publishedInventory 'operationId') -ne $operationId -or
            [string]::IsNullOrWhiteSpace([string](Get-HcrPropertyValue $publishedInventory 'createdAt'))) {
            Throw-HcrError 'EVIDENCE_INVENTORY_INVALID' 'The published evidence inventory header is invalid.'
        }
        $publishedEntries = @((Get-HcrPropertyValue $publishedInventory 'files' @()))
        if ($publishedEntries.Count -ne $inventoryFiles.Count) {
            Throw-HcrError 'EVIDENCE_INVENTORY_INVALID' 'The published evidence inventory membership changed.'
        }
        for ($index = 0; $index -lt $inventoryFiles.Count; $index++) {
            $expectedEntry = $inventoryFiles[$index]
            $publishedEntry = $publishedEntries[$index]
            $entryPropertyNames = @(Get-HcrPropertyNames $publishedEntry)
            if ($entryPropertyNames.Count -ne 3 -or
                @('path', 'size', 'sha256' | Where-Object {
                    $entryPropertyNames -notcontains $_
                }).Count -ne 0 -or
                [string](Get-HcrPropertyValue $publishedEntry 'path') -ne
                    [string](Get-HcrPropertyValue $expectedEntry 'path') -or
                [int64](Get-HcrPropertyValue $publishedEntry 'size' -1) -ne
                    [int64](Get-HcrPropertyValue $expectedEntry 'size') -or
                [string](Get-HcrPropertyValue $publishedEntry 'sha256') -ne
                    [string](Get-HcrPropertyValue $expectedEntry 'sha256')) {
                Throw-HcrError 'EVIDENCE_INVENTORY_INVALID' 'A published evidence inventory entry changed.'
            }
            $publishedTarget = Assert-HcrRegularLocalFile `
                (Join-Path $targetRoot ([string](Get-HcrPropertyValue $publishedEntry 'path'))) `
                'EVIDENCE_STAGING_INVALID'
            if ([int64]$publishedTarget.Length -ne
                    [int64](Get-HcrPropertyValue $publishedEntry 'size') -or
                (Get-HcrSha256File $publishedTarget.FullName) -ne
                    [string](Get-HcrPropertyValue $publishedEntry 'sha256')) {
                Throw-HcrError 'EVIDENCE_REFERENCE_HASH_MISMATCH' 'The final copied evidence bytes do not match the published inventory.'
            }
        }
        foreach ($publishedItem in @(Get-ChildItem -LiteralPath $targetRoot -Force -Recurse)) {
            if (($publishedItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                Throw-HcrError 'EVIDENCE_STAGING_INVALID' 'The final evidence bundle contains a reparse point.'
            }
        }
        $expectedPublishedPaths = @($publishedEntries | ForEach-Object {
            [string](Get-HcrPropertyValue $_ 'path')
        }) + @('inventory.json')
        $actualPublishedPaths = @(Get-ChildItem -LiteralPath $targetRoot -Force -Recurse -File |
            ForEach-Object {
                $_.FullName.Substring($targetRoot.Length).TrimStart('\', '/').Replace('\', '/')
            })
        if ($actualPublishedPaths.Count -ne $expectedPublishedPaths.Count -or
            @($actualPublishedPaths | Where-Object {
                $expectedPublishedPaths -notcontains $_
            }).Count -ne 0) {
            Throw-HcrError 'EVIDENCE_INVENTORY_INVALID' 'The final evidence bundle does not match the published inventory.'
        }
        $inventoryPath = $publishedInventoryFile.FullName
        $exportedEvidencePath = Join-Path $targetRoot 'evidence.json'
        $operation | Add-Member -NotePropertyName exportedEvidencePath -NotePropertyValue $exportedEvidencePath -Force
        $operation | Add-Member -NotePropertyName exportedAt -NotePropertyValue (Get-HcrUtcTimestamp) -Force
        $holder.result = [pscustomobject][ordered]@{
            changed = $true
            data = [pscustomobject][ordered]@{
                testOperationId = $operationId
                outputDirectory = $targetRoot
                inventoryPath = $inventoryPath
                fileCount = $inventoryFiles.Count
            }
            warnings = @()
            evidencePath = $exportedEvidencePath
        }
        return $operation
    })
    return $holder.result
}

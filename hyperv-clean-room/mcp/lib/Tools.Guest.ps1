function Invoke-HcrInspectGuest {
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $vmName = [string](Get-HcrPropertyValue $Arguments 'vmName')
    $owned = Get-HcrRequiredOwnedVm $vmName
    [void](Invoke-HcrAdapter 'ResolveCredentialProfile' ([pscustomobject][ordered]@{
        vmName = $vmName
        profileName = [string](Get-HcrPropertyValue $Arguments 'credentialProfile')
    }))
    $guest = Invoke-HcrAdapter 'InspectGuest' ([pscustomobject][ordered]@{
        vmName = $vmName
        profileName = [string](Get-HcrPropertyValue $Arguments 'credentialProfile')
    })
    return [pscustomobject][ordered]@{
        changed = $false
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
    param([Parameter(Mandatory = $true)][object]$Arguments)

    $vmName = [string](Get-HcrPropertyValue $Arguments 'vmName')
    [void](Get-HcrRequiredOwnedVm $vmName)
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
        sourcePath = $source.FullName
        sourceSha256 = $sourceHash
        size = [int64]$source.Length
        guestDestination = $destination
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
            guestDestination = $destination
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

    return [pscustomobject][ordered]@{
        windowsBuild = [string](Get-HcrPropertyValue $Guest 'windowsBuild')
        architecture = [string](Get-HcrPropertyValue $Guest 'architecture')
        userName = [string](Get-HcrPropertyValue $Guest 'userName')
        isAdministrator = [bool](Get-HcrPropertyValue $Guest 'isAdministrator' $true)
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

function Invoke-HcrCleanupSteps {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$CleanupSteps,
        [Parameter(Mandatory = $true)][object]$Context
    )

    $results = New-Object System.Collections.Generic.List[object]
    $budget = [Diagnostics.Stopwatch]::StartNew()
    foreach ($step in $CleanupSteps) {
        $stepId = [string](Get-HcrPropertyValue $step 'id')
        $stepType = [string](Get-HcrPropertyValue $step 'type')
        if ($budget.Elapsed.TotalSeconds -ge 300) {
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
                step = $step
                applications = $Context.applications
                launchedProcess = $launchedProcess
            })
            $timer.Stop()
            $status = [string](Get-HcrPropertyValue $result 'status' 'failed')
            $summary = [string](Get-HcrPropertyValue $result 'summary' 'Cleanup adapter returned no summary.')
            $machineEvidence = Get-HcrPropertyValue $result 'evidence'
            if ([bool](Get-HcrPropertyValue $result 'timedOut' $false) -or
                $timer.Elapsed.TotalSeconds -gt [double](Get-HcrPropertyValue $step 'timeoutSeconds')) {
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

function Invoke-HcrRunTestProfile {
    param(
        [Parameter(Mandatory = $true)][object]$Arguments,
        [Parameter(Mandatory = $true)][string]$OperationId
    )

    $vmName = [string](Get-HcrPropertyValue $Arguments 'vmName')
    $profileName = [string](Get-HcrPropertyValue $Arguments 'credentialProfile')
    $owned = Get-HcrRequiredOwnedVm $vmName
    $profileValidation = Read-AndValidate-HcrProfile ([string](Get-HcrPropertyValue $Arguments 'profilePath'))
    if (-not $profileValidation.valid) {
        Throw-HcrError 'PROFILE_INVALID' 'The test profile failed validation before execution.' ([ordered]@{ errors = @($profileValidation.errors) })
    }
    $artifactItem = Assert-HcrRegularLocalFile ([string](Get-HcrPropertyValue $Arguments 'artifactPath')) 'INVALID_ARTIFACT'
    $profile = $profileValidation.profile
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
        launchedProcesses = @()
        manualAttestations = @()
        exportedEvidencePath = $null
        exportedAt = $null
    }
    Save-HcrOperationRecord $operation

    $automatic = New-Object System.Collections.Generic.List[object]
    $launched = New-Object System.Collections.Generic.List[object]
    $guestDestination = "operations\$OperationId\$($artifactItem.Name)"
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
        })
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
        $guestHash = ('0' * 64)
        $automatic.Add((New-HcrAutomaticAssertion `
            ([string](Get-HcrPropertyValue $steps[0] 'id')) `
            $true `
            'failed' `
            "Artifact staging failed: $($failure.code)." `
            ([pscustomobject]@{ errorCode = $failure.code })))
    }
    $cleanupTriggered = $automatic[0].status -eq 'failed'
    if (-not $cleanupTriggered) {
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
    }

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
        if ($status -eq 'failed' -and ($required -or $script:HcrActionStepTypes -contains $stepType)) {
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
            path = $relative.Replace('\', '/')
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
        $assertion.status = $status
        $assertion.attestation = $attestation
        $evidence.overallStatus = Get-HcrDerivedOverallStatus `
            @((Get-HcrPropertyValue $evidence 'automaticAssertions')) `
            @((Get-HcrPropertyValue $evidence 'manualAssertions'))
        $operation.manualAttestations = @(@((Get-HcrPropertyValue $operation 'manualAttestations' @())) + $attestation)
        $validation = Test-HcrEvidenceDocument $evidence $operation
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
    $operation = Get-HcrOperationRecord $operationId
    if ((Get-HcrPropertyValue $operation 'operationType') -ne 'runTestProfile') {
        Throw-HcrError 'OPERATION_TYPE_MISMATCH' 'Only test-profile operations have collectible evidence.'
    }
    $outputItem = Assert-HcrLocalDirectory ([string](Get-HcrPropertyValue $Arguments 'outputDirectory')) 'INVALID_EVIDENCE_OUTPUT'
    if (Test-HcrEvidenceOutputForbidden $outputItem.FullName) {
        Throw-HcrError 'EVIDENCE_OUTPUT_FORBIDDEN' 'The output directory is inside a protected or managed root.'
    }
    $sourceRoot = [string](Get-HcrPropertyValue $operation 'evidenceRoot')
    $evidencePath = [string](Get-HcrPropertyValue $operation 'evidenceFile')
    if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container) -or
        -not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
        Throw-HcrError 'EVIDENCE_NOT_READY' 'The operation evidence staging root is unavailable.'
    }
    $evidence = Read-HcrJsonFile $evidencePath 'EVIDENCE_NOT_READY'
    $validation = Test-HcrEvidenceDocument $evidence $operation
    if (-not $validation.valid) {
        Throw-HcrError 'EVIDENCE_INVALID' 'The staged evidence failed validation and was not exported.' ([ordered]@{
            errors = @($validation.errors)
        })
    }
    foreach ($item in @(Get-ChildItem -LiteralPath $sourceRoot -Force -Recurse)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Throw-HcrError 'EVIDENCE_STAGING_INVALID' 'The evidence staging root contains a reparse point.'
        }
    }
    $targetRoot = Get-HcrNormalizedPath (Join-Path $outputItem.FullName "hyperv-clean-room-$operationId")
    if (Test-Path -LiteralPath $targetRoot) {
        Throw-HcrError 'EVIDENCE_OUTPUT_EXISTS' 'The operation evidence output directory already exists.'
    }
    [void](New-Item -ItemType Directory -Path $targetRoot)
    $inventoryFiles = New-Object System.Collections.Generic.List[object]
    foreach ($file in @(Get-ChildItem -LiteralPath $sourceRoot -Force -Recurse -File | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart('\', '/')
        if (-not (Test-HcrSafeRelativePath $relative)) {
            Throw-HcrError 'EVIDENCE_STAGING_INVALID' 'The evidence staging root contains an unsafe relative path.'
        }
        $destination = Get-HcrNormalizedPath (Join-Path $targetRoot $relative)
        if (-not (Test-HcrPathWithin $destination $targetRoot)) {
            Throw-HcrError 'EVIDENCE_STAGING_INVALID' 'An evidence file escapes the export root.'
        }
        $destinationParent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
            [void](New-Item -ItemType Directory -Path $destinationParent -Force)
        }
        Copy-Item -LiteralPath $file.FullName -Destination $destination -ErrorAction Stop
        $inventoryFiles.Add([pscustomobject][ordered]@{
            path = $relative.Replace('\', '/')
            size = [int64]$file.Length
            sha256 = Get-HcrSha256File $destination
        })
    }
    $inventory = [pscustomobject][ordered]@{
        schemaVersion = 1
        operationId = $operationId
        createdAt = Get-HcrUtcTimestamp
        files = @($inventoryFiles | ForEach-Object { $_ })
    }
    Write-HcrJsonFile (Join-Path $targetRoot 'inventory.json') $inventory
    $exportedEvidencePath = Join-Path $targetRoot 'evidence.json'
    $operation | Add-Member -NotePropertyName exportedEvidencePath -NotePropertyValue $exportedEvidencePath -Force
    $operation | Add-Member -NotePropertyName exportedAt -NotePropertyValue (Get-HcrUtcTimestamp) -Force
    Save-HcrOperationRecord $operation
    return [pscustomobject][ordered]@{
        changed = $true
        data = [pscustomobject][ordered]@{
            testOperationId = $operationId
            outputDirectory = $targetRoot
            inventoryPath = Join-Path $targetRoot 'inventory.json'
            fileCount = $inventoryFiles.Count
        }
        warnings = @()
        evidencePath = $exportedEvidencePath
    }
}

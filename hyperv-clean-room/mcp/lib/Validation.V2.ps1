function Get-HcrExactSchemaVersion {
    param(
        [Parameter(Mandatory = $true)][object]$Document,
        [Parameter(Mandatory = $true)][string]$DocumentKind
    )

    if (-not (Test-HcrProperty $Document 'schemaVersion') -or
        -not (Test-HcrInteger (Get-HcrPropertyValue $Document 'schemaVersion'))) {
        Throw-HcrError 'UNSUPPORTED_SCHEMA_VERSION' "$DocumentKind requires an exact integer schemaVersion."
    }
    $version = [int](Get-HcrPropertyValue $Document 'schemaVersion')
    if (@(1, 2) -notcontains $version) {
        Throw-HcrError 'UNSUPPORTED_SCHEMA_VERSION' "$DocumentKind schemaVersion is not supported."
    }
    return $version
}

function Test-HcrV2Sha256 {
    param([AllowNull()][object]$Value)
    return $Value -is [string] -and $Value -cmatch '^[a-f0-9]{64}$'
}

function Test-HcrV2ClosedObject {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string[]]$Allowed,
        [Parameter(Mandatory = $true)][string[]]$Required,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Errors
    )

    if (-not (Test-HcrObjectLike $Value)) {
        Add-HcrValidationError $Errors "$Path must be an object."
        return $false
    }
    [void](Test-HcrAllowedProperties $Value $Allowed $Path $Errors)
    [void](Test-HcrRequiredProperties $Value $Required $Path $Errors)
    return $true
}

function Test-HcrV2ProfileStep {
    param(
        [AllowNull()][object]$Step,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][bool]$Cleanup,
        [Parameter(Mandatory = $true)][string[]]$ApplicationIds,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$FixtureIds,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Errors
    )

    if (-not (Test-HcrObjectLike $Step)) {
        Add-HcrValidationError $Errors "$Path must be an object."
        return
    }
    $baseFields = @('id', 'type', 'timeoutSeconds', 'required')
    $type = [string](Get-HcrPropertyValue $Step 'type')
    if ($Cleanup) {
        $shape = switch ($type) {
            'stopApplication' { [pscustomobject]@{ Allowed=@('application'); Required=@('application') }; break }
            { @('assertFile', 'assertShortcut') -contains $_ } { [pscustomobject]@{ Allowed=@('path', 'expected'); Required=@('path') }; break }
            'assertRegistry' { [pscustomobject]@{ Allowed=@('registryPath', 'registryName', 'expected'); Required=@('registryPath') }; break }
            'assertProcess' { [pscustomobject]@{ Allowed=@('application', 'processName', 'expected'); Required=@() }; break }
            'assertModule' { [pscustomobject]@{ Allowed=@('application', 'moduleRelativePath', 'expected'); Required=@('application', 'moduleRelativePath') }; break }
            'assertPort' { [pscustomobject]@{ Allowed=@('port', 'expected'); Required=@('port') }; break }
            'assertSentinel' { [pscustomobject]@{ Allowed=@('sentinelId', 'expected'); Required=@('sentinelId') }; break }
            'captureUiScreenshot' { [pscustomobject]@{ Allowed=@('evidenceName'); Required=@('evidenceName') }; break }
            default { [pscustomobject]@{ Allowed=@(); Required=@() } }
        }
        $fields = @($baseFields + @($shape.Allowed))
        $requiredFields = @('id', 'type', 'timeoutSeconds') + @($shape.Required)
    }
    else {
        $shape = switch ($type) {
            { @('installPackage', 'deployPortable', 'launchApplication', 'stopApplication', 'uninstallPackage') -contains $_ } { [pscustomobject]@{ Allowed=@('application'); Required=@('application') }; break }
            { @('assertFile', 'assertShortcut') -contains $_ } { [pscustomobject]@{ Allowed=@('path', 'expected'); Required=@('path') }; break }
            'assertRegistry' { [pscustomobject]@{ Allowed=@('registryPath', 'registryName', 'expected'); Required=@('registryPath') }; break }
            'assertProcess' { [pscustomobject]@{ Allowed=@('application', 'processName', 'expected'); Required=@() }; break }
            'assertModule' { [pscustomobject]@{ Allowed=@('application', 'moduleRelativePath', 'expected'); Required=@('application', 'moduleRelativePath') }; break }
            'assertPort' { [pscustomobject]@{ Allowed=@('port', 'expected'); Required=@('port') }; break }
            { @('writeSentinel', 'assertSentinel') -contains $_ } { [pscustomobject]@{ Allowed=@('sentinelId', 'expected'); Required=@('sentinelId') }; break }
            'startUiSession' { [pscustomobject]@{ Allowed=@('application'); Required=@('application') }; break }
            'uiClick' { [pscustomobject]@{ Allowed=@('testId'); Required=@('testId') }; break }
            'uiSetText' { [pscustomobject]@{ Allowed=@('testId', 'text'); Required=@('testId', 'text') }; break }
            'uiPressKey' { [pscustomobject]@{ Allowed=@('testId', 'key'); Required=@('testId', 'key') }; break }
            'uiSelectOption' { [pscustomobject]@{ Allowed=@('testId', 'value'); Required=@('testId', 'value') }; break }
            'uiUploadFixture' { [pscustomobject]@{ Allowed=@('testId', 'fixtureId'); Required=@('testId', 'fixtureId') }; break }
            'assertUiElement' { [pscustomobject]@{ Allowed=@('testId', 'state', 'expected'); Required=@('testId', 'state') }; break }
            'captureUiScreenshot' { [pscustomobject]@{ Allowed=@('evidenceName'); Required=@('evidenceName') }; break }
            default { [pscustomobject]@{ Allowed=@(); Required=@() } }
        }
        $fields = @($baseFields + @($shape.Allowed))
        $requiredFields = @('id', 'type', 'timeoutSeconds') + @($shape.Required)
    }
    if (-not (Test-HcrV2ClosedObject $Step $fields $requiredFields $Path $Errors)) { return }
    $id = Get-HcrPropertyValue $Step 'id'
    $timeout = Get-HcrPropertyValue $Step 'timeoutSeconds'
    $allowed = if ($Cleanup) { $script:HcrV2CleanupStepTypes } else {
        @($script:HcrV2ActionStepTypes + $script:HcrV2AssertionStepTypes)
    }
    if (-not (Test-HcrIdentifier $id)) { Add-HcrValidationError $Errors "$Path.id is invalid." }
    if ($allowed -notcontains $type) { Add-HcrValidationError $Errors "$Path.type is unsupported." }
    $maximum = if ($Cleanup) { 120 } else { 900 }
    if (-not (Test-HcrInteger $timeout) -or [int]$timeout -lt 1 -or [int]$timeout -gt $maximum) {
        Add-HcrValidationError $Errors "$Path.timeoutSeconds is outside the fixed bound."
    }
    if (Test-HcrProperty $Step 'application') {
        $application = [string](Get-HcrPropertyValue $Step 'application')
        if ($ApplicationIds -notcontains $application) {
            Add-HcrValidationError $Errors "$Path.application is not declared."
        }
    }
    if ($type -eq 'uiUploadFixture' -and
        $FixtureIds -notcontains [string](Get-HcrPropertyValue $Step 'fixtureId')) {
        Add-HcrValidationError $Errors "$Path.fixtureId is not declared."
    }
    if (@('uiClick', 'uiSetText', 'uiPressKey', 'uiSelectOption', 'uiUploadFixture', 'assertUiElement') -contains $type) {
        if (-not (Test-HcrIdentifier (Get-HcrPropertyValue $Step 'testId'))) {
            Add-HcrValidationError $Errors "$Path.testId must be a closed data-testid identifier."
        }
    }
    if ($type -eq 'uiPressKey' -and
        @('Enter', 'Escape', 'Tab', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight') -notcontains
            [string](Get-HcrPropertyValue $Step 'key')) {
        Add-HcrValidationError $Errors "$Path.key is not in the closed key set."
    }
    if ($type -eq 'assertProcess') {
        $processBindings = @(@('application', 'processName') | Where-Object { Test-HcrProperty $Step $_ })
        if ($processBindings.Count -ne 1) { Add-HcrValidationError $Errors "$Path must bind exactly one application or processName." }
    }
    if ($type -eq 'uiSetText' -and ([string](Get-HcrPropertyValue $Step 'text')).Length -gt 4096) {
        Add-HcrValidationError $Errors "$Path.text exceeds the fixed UI text bound."
    }
    if ($type -eq 'uiSelectOption') {
        $value = [string](Get-HcrPropertyValue $Step 'value')
        if ($value.Length -lt 1 -or $value.Length -gt 512) { Add-HcrValidationError $Errors "$Path.value is outside the fixed option bound." }
    }
    if ($type -eq 'assertUiElement') {
        $state = [string](Get-HcrPropertyValue $Step 'state')
        $textStates = @('textEquals', 'textContains', 'valueEquals')
        if (@('visible', 'hidden', 'enabled', 'disabled', 'checked', 'unchecked') + $textStates -notcontains $state) {
            Add-HcrValidationError $Errors "$Path.state is outside the closed UI assertion set."
        }
        if (($textStates -contains $state) -ne (Test-HcrProperty $Step 'expected')) {
            Add-HcrValidationError $Errors "$Path.expected does not match the UI assertion state."
        }
    }
    foreach ($relativeField in @('path', 'registryPath', 'moduleRelativePath')) {
        if (Test-HcrProperty $Step $relativeField) {
            $relative = [string](Get-HcrPropertyValue $Step $relativeField)
            if (-not (Test-HcrSafeRelativePath $relative)) {
                Add-HcrValidationError $Errors "$Path.$relativeField is not a safe relative path."
            }
        }
    }
    $mustBeRequired = (-not $Cleanup -and $script:HcrV2ActionStepTypes -contains $type) -or
        ($Cleanup -and @('stopApplication', 'stopUiSession', 'captureUiScreenshot', 'wait') -contains $type)
    if ($mustBeRequired -and (Get-HcrPropertyValue $Step 'required' $true) -ne $true) {
        Add-HcrValidationError $Errors "$Path.required must be true for an action."
    }
    if ((Test-HcrProperty $Step 'required') -and
        -not (Test-HcrBoolean (Get-HcrPropertyValue $Step 'required'))) {
        Add-HcrValidationError $Errors "$Path.required must be Boolean."
    }
}

function Test-HcrProfileDocumentV2 {
    param([Parameter(Mandatory = $true)][object]$Profile)

    $errors = New-Object System.Collections.Generic.List[string]
    $top = @(
        'schemaVersion', 'id', 'description', 'workflowKind', 'platform',
        'baselineType', 'artifact', 'fixtures', 'webDriver', 'applications',
        'steps', 'cleanupSteps', 'manualAssertions'
    )
    $required = @(
        'schemaVersion', 'id', 'workflowKind', 'platform', 'baselineType',
        'artifact', 'fixtures', 'applications', 'steps', 'cleanupSteps',
        'manualAssertions'
    )
    if (-not (Test-HcrV2ClosedObject $Profile $top $required '$' $errors)) {
        return [pscustomobject]@{ valid = $false; errors = @($errors) }
    }
    if ((Get-HcrPropertyValue $Profile 'schemaVersion') -ne 2) { Add-HcrValidationError $errors '$.schemaVersion must equal 2.' }
    if (-not (Test-HcrIdentifier (Get-HcrPropertyValue $Profile 'id'))) { Add-HcrValidationError $errors '$.id is invalid.' }
    $workflow = [string](Get-HcrPropertyValue $Profile 'workflowKind')
    if (@('legacyPackageLifecycle', 'portableAutomation') -notcontains $workflow) { Add-HcrValidationError $errors '$.workflowKind is invalid.' }
    if ((Get-HcrPropertyValue $Profile 'platform') -ne 'windows-x64') { Add-HcrValidationError $errors '$.platform must equal windows-x64.' }
    if (@('stock-clean', 'webview2-absent-derived') -notcontains (Get-HcrPropertyValue $Profile 'baselineType')) { Add-HcrValidationError $errors '$.baselineType is invalid.' }

    $artifact = Get-HcrPropertyValue $Profile 'artifact'
    $packageKind = [string](Get-HcrPropertyValue $artifact 'packageKind')
    if ($workflow -eq 'portableAutomation') {
        $portableFields = @('packageKind', 'fileNamePattern', 'architecture', 'sha256', 'sizeBytes', 'portableManifestEntryPath', 'portableManifestSha256')
        [void](Test-HcrV2ClosedObject $artifact $portableFields $portableFields '$.artifact' $errors)
        if ($packageKind -ne 'portableZip' -or (Get-HcrPropertyValue $artifact 'architecture') -ne 'x64' -or
            (Get-HcrPropertyValue $artifact 'portableManifestEntryPath') -ne 'portable-manifest.json' -or
            -not (Test-HcrV2Sha256 (Get-HcrPropertyValue $artifact 'sha256')) -or
            -not (Test-HcrV2Sha256 (Get-HcrPropertyValue $artifact 'portableManifestSha256'))) {
            Add-HcrValidationError $errors '$.artifact is not a fixed portable ZIP contract.'
        }
        $size = Get-HcrPropertyValue $artifact 'sizeBytes'
        if (-not (Test-HcrInteger $size) -or [int64]$size -lt 1 -or [int64]$size -gt 8GB) { Add-HcrValidationError $errors '$.artifact.sizeBytes is invalid.' }
        $name = [string](Get-HcrPropertyValue $artifact 'fileNamePattern')
        if ($name -notmatch '^[^\\/:*?"<>|%]+\.zip$') { Add-HcrValidationError $errors '$.artifact.fileNamePattern is invalid.' }
    }
    else {
        $installerFields = @('packageKind', 'fileNamePattern', 'architecture', 'sha256', 'sizeBytes')
        $installerRequiredFields = @('packageKind', 'fileNamePattern', 'architecture')
        [void](Test-HcrV2ClosedObject $artifact $installerFields $installerRequiredFields '$.artifact' $errors)
        if (@('nsis', 'msi') -notcontains $packageKind -or (Get-HcrPropertyValue $artifact 'architecture') -ne 'x64') {
            Add-HcrValidationError $errors '$.artifact is not a supported legacy package contract.'
        }
        if ((Test-HcrProperty $artifact 'sha256') -and
            -not (Test-HcrV2Sha256 (Get-HcrPropertyValue $artifact 'sha256'))) {
            Add-HcrValidationError $errors '$.artifact.sha256 is invalid.'
        }
        if (Test-HcrProperty $artifact 'sizeBytes') {
            $size = Get-HcrPropertyValue $artifact 'sizeBytes'
            if (-not (Test-HcrInteger $size) -or [int64]$size -lt 1) {
                Add-HcrValidationError $errors '$.artifact.sizeBytes is invalid.'
            }
        }
    }

    $fixtureIds = New-Object System.Collections.Generic.List[string]
    $fixtures = @((Get-HcrPropertyValue $Profile 'fixtures' @()))
    if ($fixtures.Count -gt 32) { Add-HcrValidationError $errors '$.fixtures exceeds the fixed count limit.' }
    for ($index = 0; $index -lt $fixtures.Count; $index++) {
        $fixture = $fixtures[$index]
        $path = "$.fixtures[$index]"
        $fields = @('id', 'sourceRelativePath', 'sizeBytes', 'sha256', 'mediaType')
        [void](Test-HcrV2ClosedObject $fixture $fields $fields $path $errors)
        $id = [string](Get-HcrPropertyValue $fixture 'id')
        if (-not (Test-HcrIdentifier $id) -or $fixtureIds.Contains($id)) { Add-HcrValidationError $errors "$path.id is invalid or duplicated." } else { $fixtureIds.Add($id) }
        if (-not (Test-HcrSafeRelativePath ([string](Get-HcrPropertyValue $fixture 'sourceRelativePath')))) { Add-HcrValidationError $errors "$path.sourceRelativePath is unsafe." }
        if (-not (Test-HcrV2Sha256 (Get-HcrPropertyValue $fixture 'sha256'))) { Add-HcrValidationError $errors "$path.sha256 is invalid." }
        $fixtureSize = Get-HcrPropertyValue $fixture 'sizeBytes'
        if (-not (Test-HcrInteger $fixtureSize) -or [int64]$fixtureSize -lt 1 -or [int64]$fixtureSize -gt 1GB) { Add-HcrValidationError $errors "$path.sizeBytes is invalid." }
        if (@('image/png', 'image/jpeg', 'application/json', 'text/plain', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') -notcontains [string](Get-HcrPropertyValue $fixture 'mediaType')) { Add-HcrValidationError $errors "$path.mediaType is unsupported." }
    }

    $applicationIds = New-Object System.Collections.Generic.List[string]
    $applications = @((Get-HcrPropertyValue $Profile 'applications' @()))
    if ($applications.Count -lt 1 -or $applications.Count -gt 16) { Add-HcrValidationError $errors '$.applications has an invalid count.' }
    for ($index = 0; $index -lt $applications.Count; $index++) {
        $application = $applications[$index]
        $path = "$.applications[$index]"
        $id = [string](Get-HcrPropertyValue $application 'id')
        if (-not (Test-HcrApplicationIdentifier $id) -or $applicationIds.Contains($id)) { Add-HcrValidationError $errors "$path.id is invalid or duplicated." } else { $applicationIds.Add($id) }
        if ($workflow -eq 'portableAutomation') {
            $fields = @('id', 'packageKind', 'executableRelativePath', 'dataDirectoryRelativePath', 'processName')
            [void](Test-HcrV2ClosedObject $application $fields $fields $path $errors)
            if ((Get-HcrPropertyValue $application 'packageKind') -ne 'portableZip' -or
                (Get-HcrPropertyValue $application 'dataDirectoryRelativePath') -ne 'data') { Add-HcrValidationError $errors "$path is not a portable application." }
        }
        else {
            $fields = @('id', 'packageKind', 'installMode', 'executableRelativePath', 'uninstallerDiscovery', 'processName')
            $requiredFields = @('id', 'packageKind', 'installMode', 'executableRelativePath', 'uninstallerDiscovery')
            [void](Test-HcrV2ClosedObject $application $fields $requiredFields $path $errors)
            if ((Get-HcrPropertyValue $application 'packageKind') -ne $packageKind -or
                (Get-HcrPropertyValue $application 'installMode') -ne 'currentUser' -or
                @('hkcuUninstall', 'msiProduct') -notcontains (Get-HcrPropertyValue $application 'uninstallerDiscovery')) { Add-HcrValidationError $errors "$path is not a supported legacy application." }
        }
        if (-not (Test-HcrSafeRelativePath ([string](Get-HcrPropertyValue $application 'executableRelativePath')))) { Add-HcrValidationError $errors "$path.executableRelativePath is unsafe." }
        if ((Test-HcrProperty $application 'processName') -and
            [string](Get-HcrPropertyValue $application 'processName') -notmatch '^[a-zA-Z0-9._-]+$') {
            Add-HcrValidationError $errors "$path.processName is invalid."
        }
    }

    $steps = @((Get-HcrPropertyValue $Profile 'steps' @()))
    if ($steps.Count -lt 1 -or $steps.Count -gt 128) { Add-HcrValidationError $errors '$.steps has an invalid count.' }
    $stepIds = New-Object System.Collections.Generic.HashSet[string]
    for ($index = 0; $index -lt $steps.Count; $index++) {
        Test-HcrV2ProfileStep $steps[$index] "$.steps[$index]" $false @($applicationIds) @($fixtureIds) $errors
        if (-not $stepIds.Add([string](Get-HcrPropertyValue $steps[$index] 'id'))) { Add-HcrValidationError $errors "$.steps[$index].id is duplicated." }
    }
    $stepTypes = @($steps | ForEach-Object { [string](Get-HcrPropertyValue $_ 'type') })
    if ($stepTypes.Count -lt 1 -or $stepTypes[0] -ne 'stageArtifact' -or @($stepTypes | Where-Object { $_ -eq 'stageArtifact' }).Count -ne 1) { Add-HcrValidationError $errors '$.steps must begin with exactly one stageArtifact.' }
    if ($workflow -eq 'portableAutomation') {
        if ($fixtures.Count -lt 1) { Add-HcrValidationError $errors '$.fixtures requires at least one hash-bound fixture for portable evidence.' }
        foreach ($requiredType in @('deployPortable', 'launchApplication', 'acquireWebDriver', 'startUiSession', 'stopUiSession')) {
            if (@($stepTypes | Where-Object { $_ -eq $requiredType }).Count -ne 1) { Add-HcrValidationError $errors "$.steps requires exactly one $requiredType." }
        }
        $positions = @{}; for ($index = 0; $index -lt $stepTypes.Count; $index++) { if (-not $positions.ContainsKey($stepTypes[$index])) { $positions[$stepTypes[$index]] = $index } }
        if ($positions['deployPortable'] -le $positions['stageArtifact'] -or
            $positions['launchApplication'] -le $positions['deployPortable'] -or
            $positions['acquireWebDriver'] -le $positions['deployPortable'] -or
            $positions['startUiSession'] -le $positions['launchApplication'] -or
            $positions['startUiSession'] -le $positions['acquireWebDriver'] -or
            $positions['stopUiSession'] -le $positions['startUiSession']) {
            Add-HcrValidationError $errors '$.steps violates the closed portable/UI lifecycle order.'
        }
        if ($positions.ContainsKey('launchApplication') -and $positions.ContainsKey('startUiSession') -and
            [string](Get-HcrPropertyValue $steps[$positions['launchApplication']] 'application') -ne
                [string](Get-HcrPropertyValue $steps[$positions['startUiSession']] 'application')) {
            Add-HcrValidationError $errors '$.steps must launch the application bound to the UI session.'
        }
        $uiInteractionTypes = @('uiClick', 'uiSetText', 'uiPressKey', 'uiSelectOption', 'uiUploadFixture', 'assertUiElement', 'captureUiScreenshot')
        for ($index = 0; $index -lt $stepTypes.Count; $index++) {
            if ($uiInteractionTypes -contains $stepTypes[$index] -and
                ($index -le $positions['startUiSession'] -or $index -ge $positions['stopUiSession'])) {
                Add-HcrValidationError $errors "$.steps[$index] is outside the owned UI session."
            }
        }
        if (@($stepTypes | Where-Object { @('installPackage', 'uninstallPackage') -contains $_ }).Count -gt 0) { Add-HcrValidationError $errors '$.steps contains a package mutation forbidden for portable automation.' }
        for ($index = 0; $index -lt $stepTypes.Count; $index++) {
            if ((@('launchApplication') + $script:HcrV2UiStepTypes) -contains $stepTypes[$index] -and
                $index -lt $positions['deployPortable']) {
                Add-HcrValidationError $errors "$.steps[$index] precedes atomic portable deployment."
            }
        }
        if (-not (Test-HcrProperty $Profile 'webDriver')) { Add-HcrValidationError $errors '$.webDriver is required for portable automation.' }
        else { Test-HcrWebDriverManifestV2 (Get-HcrPropertyValue $Profile 'webDriver') '$.webDriver' $errors }
    }
    else {
        if (Test-HcrProperty $Profile 'webDriver') { Add-HcrValidationError $errors '$.webDriver is forbidden for legacy package lifecycle profiles.' }
        if (@($stepTypes | Where-Object { $_ -eq 'deployPortable' -or $script:HcrV2UiStepTypes -contains $_ }).Count -gt 0) { Add-HcrValidationError $errors '$.steps contains portable/UI work forbidden for legacy package lifecycle profiles.' }
    }

    $cleanup = @((Get-HcrPropertyValue $Profile 'cleanupSteps' @()))
    if ($cleanup.Count -gt 16) { Add-HcrValidationError $errors '$.cleanupSteps exceeds the fixed cleanup budget.' }
    $cleanupBudgetSeconds = 0
    for ($index = 0; $index -lt $cleanup.Count; $index++) {
        Test-HcrV2ProfileStep $cleanup[$index] "$.cleanupSteps[$index]" $true @($applicationIds) @($fixtureIds) $errors
        $cleanupBudgetSeconds += [int](Get-HcrPropertyValue $cleanup[$index] 'timeoutSeconds' 0)
    }
    if ($cleanupBudgetSeconds -gt 300) { Add-HcrValidationError $errors '$.cleanupSteps exceeds the 300-second total budget.' }
    if (@($cleanup | Where-Object { @('stopUiSession', 'captureUiScreenshot') -contains [string](Get-HcrPropertyValue $_ 'type') }).Count -gt 0 -and -not (Test-HcrProperty $Profile 'webDriver')) { Add-HcrValidationError $errors '$.cleanupSteps requires the fixed WebDriver contract.' }
    $manual = @((Get-HcrPropertyValue $Profile 'manualAssertions' @()))
    if ($manual.Count -gt 64) { Add-HcrValidationError $errors '$.manualAssertions exceeds the fixed count limit.' }
    for ($index = 0; $index -lt $manual.Count; $index++) {
        $assertion = $manual[$index]
        [void](Test-HcrV2ClosedObject $assertion @('id', 'description', 'required') @('id', 'description', 'required') "$.manualAssertions[$index]" $errors)
        if (-not (Test-HcrIdentifier (Get-HcrPropertyValue $assertion 'id')) -or
            -not (Test-HcrBoolean (Get-HcrPropertyValue $assertion 'required'))) { Add-HcrValidationError $errors "$.manualAssertions[$index] is invalid." }
    }
    $executionIds = New-Object System.Collections.Generic.HashSet[string]
    foreach ($item in @($steps + $cleanup + $manual)) {
        $itemId = [string](Get-HcrPropertyValue $item 'id')
        if (-not $executionIds.Add($itemId)) { Add-HcrValidationError $errors "Execution ID '$itemId' is not globally unique." }
    }
    return [pscustomobject][ordered]@{ valid = $errors.Count -eq 0; errors = @($errors | ForEach-Object { [string]$_ }) }
}

function Test-HcrWebDriverManifestV2 {
    param(
        [Parameter(Mandatory = $true)][object]$Manifest,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Errors
    )

    $fields = @('schemaVersion', 'id', 'provider', 'browserKind', 'browserVersion', 'driverVersion', 'architecture', 'acquisition', 'executable', 'sessionPolicy', 'files')
    [void](Test-HcrV2ClosedObject $Manifest $fields $fields $Path $Errors)
    if ((Get-HcrPropertyValue $Manifest 'schemaVersion') -ne 2 -or
        -not (Test-HcrIdentifier (Get-HcrPropertyValue $Manifest 'id')) -or
        (Get-HcrPropertyValue $Manifest 'provider') -ne 'microsoftEdgeDriver' -or
        (Get-HcrPropertyValue $Manifest 'browserKind') -ne 'fixedVersionWebView2' -or
        (Get-HcrPropertyValue $Manifest 'architecture') -ne 'x64' -or
        [string](Get-HcrPropertyValue $Manifest 'browserVersion') -notmatch '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' -or
        [string](Get-HcrPropertyValue $Manifest 'browserVersion') -ne [string](Get-HcrPropertyValue $Manifest 'driverVersion')) { Add-HcrValidationError $Errors "$Path has an incompatible fixed driver identity." }
    $acquisition = Get-HcrPropertyValue $Manifest 'acquisition'
    $acquisitionFields = @('source', 'archiveFileName', 'archiveSizeBytes', 'archiveSha256', 'redirectPolicy')
    [void](Test-HcrV2ClosedObject $acquisition $acquisitionFields $acquisitionFields "$Path.acquisition" $Errors)
    $archiveSize = Get-HcrPropertyValue $acquisition 'archiveSizeBytes'
    if ((Get-HcrPropertyValue $acquisition 'source') -ne 'microsoftFixedEndpoint' -or (Get-HcrPropertyValue $acquisition 'archiveFileName') -ne 'edgedriver_win64.zip' -or (Get-HcrPropertyValue $acquisition 'redirectPolicy') -ne 'microsoftHttpsAllowlist' -or -not (Test-HcrInteger $archiveSize) -or [int64]$archiveSize -lt 1 -or [int64]$archiveSize -gt 512MB -or -not (Test-HcrV2Sha256 (Get-HcrPropertyValue $acquisition 'archiveSha256'))) { Add-HcrValidationError $Errors "$Path.acquisition is not fixed and hash-bound." }
    $executable = Get-HcrPropertyValue $Manifest 'executable'
    $executableFields = @('relativePath', 'sizeBytes', 'sha256', 'peArchitecture', 'authenticodePublisher')
    [void](Test-HcrV2ClosedObject $executable $executableFields $executableFields "$Path.executable" $Errors)
    $executableSize = Get-HcrPropertyValue $executable 'sizeBytes'
    if ((Get-HcrPropertyValue $executable 'relativePath') -ne 'msedgedriver.exe' -or -not (Test-HcrInteger $executableSize) -or [int64]$executableSize -lt 1 -or [int64]$executableSize -gt 512MB -or (Get-HcrPropertyValue $executable 'peArchitecture') -ne 'x64' -or (Get-HcrPropertyValue $executable 'authenticodePublisher') -ne 'Microsoft Corporation' -or -not (Test-HcrV2Sha256 (Get-HcrPropertyValue $executable 'sha256'))) { Add-HcrValidationError $Errors "$Path.executable is not the fixed verified driver." }
    $policy = Get-HcrPropertyValue $Manifest 'sessionPolicy'
    $policyFields = @('listenAddress', 'portPolicy', 'browserArguments', 'allowNavigation', 'allowExecuteScript', 'allowArbitrarySelector')
    [void](Test-HcrV2ClosedObject $policy $policyFields $policyFields "$Path.sessionPolicy" $Errors)
    if ((Get-HcrPropertyValue $policy 'listenAddress') -ne '127.0.0.1' -or (Get-HcrPropertyValue $policy 'portPolicy') -ne 'serverAllocatedEphemeral' -or @((Get-HcrPropertyValue $policy 'browserArguments' @())).Count -ne 0 -or (Get-HcrPropertyValue $policy 'allowNavigation') -ne $false -or (Get-HcrPropertyValue $policy 'allowExecuteScript') -ne $false -or (Get-HcrPropertyValue $policy 'allowArbitrarySelector') -ne $false) { Add-HcrValidationError $Errors "$Path.sessionPolicy violates the closed loopback-only policy." }
    $files = @((Get-HcrPropertyValue $Manifest 'files' @()))
    if ($files.Count -lt 1 -or $files.Count -gt 64) { Add-HcrValidationError $Errors "$Path.files has an invalid count." }
    $paths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    for ($index = 0; $index -lt $files.Count; $index++) {
        $file = $files[$index]; $filePath = "$Path.files[$index]"
        [void](Test-HcrV2ClosedObject $file @('path', 'sizeBytes', 'sha256') @('path', 'sizeBytes', 'sha256') $filePath $Errors)
        $relative = [string](Get-HcrPropertyValue $file 'path'); $size = Get-HcrPropertyValue $file 'sizeBytes'
        if (-not (Test-HcrSafeRelativePath $relative) -or -not $paths.Add($relative) -or -not (Test-HcrInteger $size) -or [int64]$size -lt 1 -or [int64]$size -gt 512MB -or -not (Test-HcrV2Sha256 (Get-HcrPropertyValue $file 'sha256'))) { Add-HcrValidationError $Errors "$filePath is unsafe, duplicated, or not hash-bound." }
    }
    if (-not $paths.Contains('msedgedriver.exe')) { Add-HcrValidationError $Errors "$Path.files does not contain the fixed executable." }
}

function Read-AndValidate-HcrProfile {
    param([Parameter(Mandatory = $true)][string]$ProfilePath)

    $loaded = Read-HcrJsonDocument $ProfilePath 'PROFILE_INVALID' 4MB
    $version = Get-HcrExactSchemaVersion $loaded.document 'Profile'
    if ($version -eq 1) { return Read-AndValidate-HcrProfileV1 $loaded.path }
    $validation = Test-HcrProfileDocumentV2 $loaded.document
    $cleanupBudgetSeconds = 0
    foreach ($cleanupStep in @((Get-HcrPropertyValue $loaded.document 'cleanupSteps' @()))) {
        $cleanupBudgetSeconds += [int](Get-HcrPropertyValue $cleanupStep 'timeoutSeconds' 0)
    }
    return [pscustomobject][ordered]@{ path = $loaded.path; profile = $loaded.document; valid = $validation.valid; errors = @($validation.errors); cleanupBudgetSeconds = $cleanupBudgetSeconds }
}

function Test-HcrEvidenceDocumentV2 {
    param(
        [Parameter(Mandatory = $true)][object]$Evidence,
        [AllowNull()][object]$OperationRecord
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $fields = @('schemaVersion', 'operationId', 'createdAt', 'profile', 'candidate', 'runtime', 'baselineType', 'vm', 'guest', 'artifacts', 'automation', 'powerOperations', 'networkOperations', 'networkRecovery', 'automaticAssertions', 'manualAssertions', 'cleanupTriggered', 'cleanupResults', 'machineStatus', 'overallStatus', 'warnings')
    [void](Test-HcrV2ClosedObject $Evidence $fields $fields '$' $errors)
    $operationId = [string](Get-HcrPropertyValue $Evidence 'operationId')
    if ((Get-HcrPropertyValue $Evidence 'schemaVersion') -ne 2 -or -not (Test-HcrUuid $operationId)) { Add-HcrValidationError $errors '$.schemaVersion or operationId is invalid.' }
    if ($null -eq $OperationRecord -or [string](Get-HcrPropertyValue $OperationRecord 'operationId') -ne $operationId -or [int](Get-HcrPropertyValue $OperationRecord 'schemaVersion' 0) -ne 2) { Add-HcrValidationError $errors 'Immutable schema-v2 operation state is unavailable or mismatched.' }
    $profile = Get-HcrPropertyValue $Evidence 'profile'; $candidate = Get-HcrPropertyValue $Evidence 'candidate'; $runtime = Get-HcrPropertyValue $Evidence 'runtime'
    if ((Get-HcrPropertyValue $profile 'schemaVersion') -ne 2 -or -not (Test-HcrV2Sha256 (Get-HcrPropertyValue $profile 'sha256'))) { Add-HcrValidationError $errors '$.profile provenance is invalid.' }
    foreach ($field in @('sourceCommit', 'portableZipSha256', 'profileSha256', 'fixtureSetSha256', 'webDriverManifestSha256')) { $value=[string](Get-HcrPropertyValue $candidate $field); if (($field -eq 'sourceCommit' -and $value -notmatch '^[a-f0-9]{40}$') -or ($field -ne 'sourceCommit' -and -not (Test-HcrV2Sha256 $value))) { Add-HcrValidationError $errors "$.candidate.$field is invalid." } }
    if ((Get-HcrPropertyValue $runtime 'pluginVersion') -ne '0.2.0' -or [string](Get-HcrPropertyValue $runtime 'sourceCommit') -notmatch '^[a-f0-9]{40}$' -or @('mock', 'production') -notcontains (Get-HcrPropertyValue $runtime 'adapterMode')) { Add-HcrValidationError $errors '$.runtime provenance is invalid.' }
    $guest = Get-HcrPropertyValue $Evidence 'guest'; $automation = Get-HcrPropertyValue $Evidence 'automation'; $vm = Get-HcrPropertyValue $Evidence 'vm'
    $automatic = @((Get-HcrPropertyValue $Evidence 'automaticAssertions' @())); $manual = @((Get-HcrPropertyValue $Evidence 'manualAssertions' @())); $cleanup = @((Get-HcrPropertyValue $Evidence 'cleanupResults' @()))
    foreach ($collection in @($automatic, $manual, $cleanup)) { foreach ($entry in @($collection)) { if (@('passed', 'failed', 'notPerformed', 'unsupported') -notcontains (Get-HcrPropertyValue $entry 'status')) { Add-HcrValidationError $errors 'Evidence contains an unsupported result status.' } } }
    $requiredAutomaticFailed = @($automatic | Where-Object { (Get-HcrPropertyValue $_ 'required' $true) -eq $true -and (Get-HcrPropertyValue $_ 'status') -ne 'passed' }).Count -gt 0
    $invariants = (Get-HcrPropertyValue $vm 'ownershipVerified') -eq $true -and (Get-HcrPropertyValue $guest 'isAdministrator') -eq $false -and (Get-HcrPropertyValue $guest 'isElevated') -eq $false -and (Get-HcrPropertyValue $guest 'tokenIntegrity') -eq 'medium' -and (Get-HcrPropertyValue $automation 'dataPreserved') -eq $true -and (Get-HcrPropertyValue $automation 'loopbackOnly') -eq $true
    $machineFactsPassed = -not $requiredAutomaticFailed -and $invariants
    $artifacts = @((Get-HcrPropertyValue $Evidence 'artifacts' @()))
    $requiredRoles = @('portableZip', 'portableManifest', 'webDriverArchive', 'webDriverExecutable', 'deployedPayload')
    foreach ($role in $requiredRoles) {
        if (@($artifacts | Where-Object { (Get-HcrPropertyValue $_ 'role') -eq $role }).Count -ne 1) { Add-HcrValidationError $errors "Evidence requires exactly one $role artifact."; $machineFactsPassed = $false }
    }
    if (@($artifacts | Where-Object { (Get-HcrPropertyValue $_ 'role') -eq 'fixture' }).Count -lt 1) { Add-HcrValidationError $errors 'Evidence requires at least one fixture artifact.'; $machineFactsPassed = $false }
    foreach ($artifact in $artifacts) {
        $artifactStatus = [string](Get-HcrPropertyValue $artifact 'status')
        $artifactGuestHash = Get-HcrPropertyValue $artifact 'guestSha256'
        if ($artifactStatus -ne 'passed') { $machineFactsPassed = $false }
        if (($artifactStatus -eq 'passed' -or $null -ne $artifactGuestHash) -and
            [string](Get-HcrPropertyValue $artifact 'sourceSha256') -ne [string]$artifactGuestHash) {
            Add-HcrValidationError $errors "Artifact role '$([string](Get-HcrPropertyValue $artifact 'role'))' has hash drift."
            $machineFactsPassed = $false
        }
    }
    if ([string](Get-HcrPropertyValue $profile 'sha256') -ne [string](Get-HcrPropertyValue $candidate 'profileSha256')) { Add-HcrValidationError $errors 'The profile hash is not bound to the candidate.'; $machineFactsPassed = $false }
    if ([string](Get-HcrPropertyValue $automation 'webDriverManifestSha256') -ne [string](Get-HcrPropertyValue $candidate 'webDriverManifestSha256')) { Add-HcrValidationError $errors 'The WebDriver manifest hash is not bound to the candidate.'; $machineFactsPassed = $false }
    if ([string](Get-HcrPropertyValue $automation 'fixedWebView2Version') -ne [string](Get-HcrPropertyValue $automation 'webDriverVersion')) { Add-HcrValidationError $errors 'The fixed WebView2 and WebDriver versions do not match.'; $machineFactsPassed = $false }
    $portableArtifacts = @($artifacts | Where-Object { (Get-HcrPropertyValue $_ 'role') -eq 'portableZip' })
    if ($portableArtifacts.Count -eq 1 -and [string](Get-HcrPropertyValue $portableArtifacts[0] 'sourceSha256') -ne [string](Get-HcrPropertyValue $candidate 'portableZipSha256')) { Add-HcrValidationError $errors 'The portable ZIP hash is not bound to the candidate.'; $machineFactsPassed = $false }
    $previousInventory = Get-HcrPropertyValue $automation 'previousDataInventorySha256'
    if ($null -ne $previousInventory -and [string]$previousInventory -ne [string](Get-HcrPropertyValue $automation 'deployedDataInventorySha256')) { Add-HcrValidationError $errors 'The portable data inventory was not preserved byte-for-byte.'; $machineFactsPassed = $false }
    $automaticById = @{}; foreach ($entry in $automatic) { $automaticById[[string](Get-HcrPropertyValue $entry 'id')] = $entry }
    foreach ($trace in @((Get-HcrPropertyValue $automation 'uiTrace' @()))) {
        $traceStatus = [string](Get-HcrPropertyValue $trace 'status'); $traceId = [string](Get-HcrPropertyValue $trace 'stepId')
        if ($traceStatus -ne 'passed' -and (-not $automaticById.ContainsKey($traceId) -or (Get-HcrPropertyValue $automaticById[$traceId] 'required' $true) -ne $false)) { $machineFactsPassed = $false }
    }
    $powerOperations = @((Get-HcrPropertyValue $Evidence 'powerOperations' @())); $networkOperations = @((Get-HcrPropertyValue $Evidence 'networkOperations' @()))
    if (@(@($powerOperations + $networkOperations) | Where-Object { (Get-HcrPropertyValue $_ 'status') -ne 'passed' }).Count -gt 0) { $machineFactsPassed = $false }
    $recovery = Get-HcrPropertyValue $Evidence 'networkRecovery'
    $disconnectEffects = @($networkOperations | Where-Object { (Get-HcrPropertyValue $_ 'planRole') -eq 'change' -and (Get-HcrPropertyValue $_ 'target') -eq 'disconnected' -and @('confirmed', 'indeterminate') -contains (Get-HcrPropertyValue $_ 'effectState') })
    $recoveryRequired = $disconnectEffects.Count -gt 0
    if ((Get-HcrPropertyValue $recovery 'required') -ne $recoveryRequired) { Add-HcrValidationError $errors 'The network recovery requirement does not match disconnect effects.'; $machineFactsPassed = $false }
    if ($recoveryRequired -and (Get-HcrPropertyValue $recovery 'status') -ne 'passed') { $machineFactsPassed = $false }
    if ($recoveryRequired -and (Get-HcrPropertyValue $recovery 'status') -eq 'passed' -and ([string](Get-HcrPropertyValue $recovery 'initialFingerprint') -ne [string](Get-HcrPropertyValue $recovery 'finalFingerprint') -or -not (Test-HcrUuid ([string](Get-HcrPropertyValue $recovery 'recoveryOperationId'))))) { Add-HcrValidationError $errors 'Passed network recovery is not bound to the restored baseline.'; $machineFactsPassed = $false }
    foreach ($manualResult in $manual) {
        $attestation = Get-HcrPropertyValue $manualResult 'attestation'
        if ($null -eq $attestation) { continue }
        if ([string](Get-HcrPropertyValue $attestation 'operationId') -ne $operationId -or
            [string](Get-HcrPropertyValue $attestation 'profileId') -ne [string](Get-HcrPropertyValue $profile 'id') -or
            [string](Get-HcrPropertyValue $attestation 'assertionId') -ne [string](Get-HcrPropertyValue $manualResult 'id')) {
            Add-HcrValidationError $errors 'A manual attestation is not bound to its operation, profile, and assertion.'
        }
        $attestationCandidate = Get-HcrPropertyValue $attestation 'candidate'
        foreach ($field in @('sourceCommit', 'portableZipSha256', 'profileSha256', 'fixtureSetSha256', 'webDriverManifestSha256')) {
            if ([string](Get-HcrPropertyValue $attestationCandidate $field) -ne [string](Get-HcrPropertyValue $candidate $field)) { Add-HcrValidationError $errors "A manual attestation is not bound to candidate $field." }
        }
    }
    $derivedMachine = if ($machineFactsPassed) { 'passed' } else { 'failed' }
    $derivedOverall = if ($derivedMachine -eq 'failed') { 'failed' } elseif (@($manual | Where-Object { (Get-HcrPropertyValue $_ 'required') -eq $true -and (Get-HcrPropertyValue $_ 'status') -eq 'failed' }).Count -gt 0) { 'failed' } elseif (@($manual | Where-Object { (Get-HcrPropertyValue $_ 'required') -eq $true -and (Get-HcrPropertyValue $_ 'status') -ne 'passed' }).Count -gt 0) { 'incomplete' } else { 'passed' }
    if ((Get-HcrPropertyValue $Evidence 'machineStatus') -ne $derivedMachine) { Add-HcrValidationError $errors '$.machineStatus does not match deterministic derivation.' }
    if ((Get-HcrPropertyValue $Evidence 'overallStatus') -ne $derivedOverall) { Add-HcrValidationError $errors '$.overallStatus does not match deterministic derivation.' }
    if ($null -ne $OperationRecord) {
        $expectedEvidenceDigest = [string](Get-HcrPropertyValue $OperationRecord 'evidenceSha256')
        if ($expectedEvidenceDigest -notmatch '^[a-f0-9]{64}$' -or
            (Get-HcrEvidenceDocumentDigest $Evidence) -ne $expectedEvidenceDigest) {
            Add-HcrValidationError $errors 'Evidence content does not match immutable operation state.'
        }
        foreach ($binding in @('profileSha256', 'portableZipSha256', 'fixtureSetSha256', 'webDriverManifestSha256', 'sourceCommit')) {
            if ([string](Get-HcrPropertyValue $candidate $binding) -ne [string](Get-HcrPropertyValue $OperationRecord $binding)) { Add-HcrValidationError $errors "$.candidate.$binding does not match immutable operation state." }
        }
    }
    return [pscustomobject][ordered]@{ valid = $errors.Count -eq 0; errors = @($errors | ForEach-Object { [string]$_ }); derivedMachineStatus = $derivedMachine; derivedOverallStatus = $derivedOverall }
}

function Read-AndValidate-HcrEvidence {
    param([Parameter(Mandatory = $true)][string]$EvidencePath)

    $loaded = Read-HcrJsonDocument $EvidencePath 'EVIDENCE_INVALID' 8MB
    $version = Get-HcrExactSchemaVersion $loaded.document 'Evidence'
    if ($version -eq 1) { return Read-AndValidate-HcrEvidenceV1 $loaded.path }
    $operation = $null; $operationId = Get-HcrPropertyValue $loaded.document 'operationId'
    if (Test-HcrUuid $operationId) { try { $operation = Get-HcrOperationRecord ([string]$operationId) } catch { $operation = $null } }
    $validation = Test-HcrEvidenceDocumentV2 $loaded.document $operation
    return [pscustomobject][ordered]@{ path = $loaded.path; evidence = $loaded.document; operation = $operation; valid = $validation.valid; errors = @($validation.errors); derivedOverallStatus = $validation.derivedOverallStatus; derivedMachineStatus = $validation.derivedMachineStatus }
}

function Convert-HcrProfileV1ToV2 {
    param([Parameter(Mandatory = $true)][object]$Profile)

    if ((Get-HcrPropertyValue $Profile 'schemaVersion') -ne 1) { Throw-HcrError 'MIGRATION_SOURCE_INVALID' 'Only a schema-v1 test profile can be migrated.' }
    $validation = Test-HcrProfileDocument $Profile
    if (-not $validation.valid) { Throw-HcrError 'MIGRATION_SOURCE_INVALID' 'The schema-v1 profile is invalid.' ([ordered]@{ errors = @($validation.errors) }) }
    $kinds = @(@((Get-HcrPropertyValue $Profile 'applications' @())) | ForEach-Object { [string](Get-HcrPropertyValue $_ 'installerType') } | Sort-Object -Unique)
    if ($kinds.Count -ne 1 -or @('nsis', 'msi') -notcontains $kinds[0]) { Throw-HcrError 'MIGRATION_AMBIGUOUS_PACKAGE_KIND' 'The schema-v1 package kind cannot be inferred losslessly.' }
    $artifactV1 = Get-HcrPropertyValue $Profile 'artifact'
    $result = [ordered]@{
        schemaVersion = 2
        id = [string](Get-HcrPropertyValue $Profile 'id')
    }
    if (Test-HcrProperty $Profile 'description') { $result.description = [string](Get-HcrPropertyValue $Profile 'description') }
    $result.workflowKind = 'legacyPackageLifecycle'; $result.platform = 'windows-x64'; $result.baselineType = [string](Get-HcrPropertyValue $Profile 'baselineType')
    $result.artifact = [ordered]@{ packageKind = $kinds[0]; fileNamePattern = [string](Get-HcrPropertyValue $artifactV1 'fileNamePattern'); architecture = 'x64' }
    if (Test-HcrProperty $artifactV1 'sha256') {
        $result.artifact.sha256 = [string](Get-HcrPropertyValue $artifactV1 'sha256')
    }
    $result.fixtures = @()
    $result.applications = @(@((Get-HcrPropertyValue $Profile 'applications')) | ForEach-Object {
        $application = [ordered]@{
            id = [string](Get-HcrPropertyValue $_ 'id')
            packageKind = [string](Get-HcrPropertyValue $_ 'installerType')
            installMode = [string](Get-HcrPropertyValue $_ 'installMode')
            executableRelativePath = [string](Get-HcrPropertyValue $_ 'executableRelativePath')
            uninstallerDiscovery = [string](Get-HcrPropertyValue $_ 'uninstallerDiscovery')
        }
        if (Test-HcrProperty $_ 'processName') {
            $application.processName = [string](Get-HcrPropertyValue $_ 'processName')
        }
        return $application
    })
    $result.steps = @((Get-HcrPropertyValue $Profile 'steps') | ForEach-Object { Copy-HcrObject $_ })
    $result.cleanupSteps = @((Get-HcrPropertyValue $Profile 'cleanupSteps') | ForEach-Object { Copy-HcrObject $_ })
    $result.manualAssertions = @((Get-HcrPropertyValue $Profile 'manualAssertions') | ForEach-Object { Copy-HcrObject $_ })
    return [pscustomobject]$result
}

function Convert-HcrLegacyProfileV2ToV1 {
    param([Parameter(Mandatory = $true)][object]$Profile)

    if ([int](Get-HcrPropertyValue $Profile 'schemaVersion' 0) -ne 2 -or
        [string](Get-HcrPropertyValue $Profile 'workflowKind') -ne 'legacyPackageLifecycle') {
        Throw-HcrError 'PROFILE_INVALID' 'Only a validated schema-v2 legacyPackageLifecycle profile can use the preserved legacy runner.'
    }

    $artifactV2 = Get-HcrPropertyValue $Profile 'artifact'
    $result = [ordered]@{
        schemaVersion = 1
        id = [string](Get-HcrPropertyValue $Profile 'id')
    }
    if (Test-HcrProperty $Profile 'description') {
        $result.description = [string](Get-HcrPropertyValue $Profile 'description')
    }
    $result.platform = [string](Get-HcrPropertyValue $Profile 'platform')
    $result.baselineType = [string](Get-HcrPropertyValue $Profile 'baselineType')
    $result.artifact = [ordered]@{
        fileNamePattern = [string](Get-HcrPropertyValue $artifactV2 'fileNamePattern')
        architecture = [string](Get-HcrPropertyValue $artifactV2 'architecture')
    }
    if (Test-HcrProperty $artifactV2 'sha256') {
        $result.artifact.sha256 = [string](Get-HcrPropertyValue $artifactV2 'sha256')
    }
    $result.applications = @(@((Get-HcrPropertyValue $Profile 'applications')) | ForEach-Object {
        $application = [ordered]@{
            id = [string](Get-HcrPropertyValue $_ 'id')
            installerType = [string](Get-HcrPropertyValue $_ 'packageKind')
            installMode = [string](Get-HcrPropertyValue $_ 'installMode')
            executableRelativePath = [string](Get-HcrPropertyValue $_ 'executableRelativePath')
            uninstallerDiscovery = [string](Get-HcrPropertyValue $_ 'uninstallerDiscovery')
        }
        if (Test-HcrProperty $_ 'processName') {
            $application.processName = [string](Get-HcrPropertyValue $_ 'processName')
        }
        return $application
    })
    $result.steps = @((Get-HcrPropertyValue $Profile 'steps') | ForEach-Object { Copy-HcrObject $_ })
    $result.cleanupSteps = @((Get-HcrPropertyValue $Profile 'cleanupSteps') | ForEach-Object { Copy-HcrObject $_ })
    $result.manualAssertions = @((Get-HcrPropertyValue $Profile 'manualAssertions') | ForEach-Object { Copy-HcrObject $_ })
    return [pscustomobject]$result
}

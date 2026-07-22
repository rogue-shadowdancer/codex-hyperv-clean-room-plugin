function Test-HcrSimpleSchemaValue {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][object]$Schema,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors
    )

    $declaredTypes = @()
    if (Test-HcrProperty $Schema 'type') {
        $declaredTypes = @((Get-HcrPropertyValue $Schema 'type'))
    }
    if ($declaredTypes.Count -gt 0) {
        $matchesType = $false
        foreach ($type in $declaredTypes) {
            switch ([string]$type) {
                'null' { if ($null -eq $Value) { $matchesType = $true } }
                'object' { if (Test-HcrObjectLike $Value) { $matchesType = $true } }
                'array' {
                    if ($Value -is [System.Collections.IEnumerable] -and
                        $Value -isnot [string] -and
                        $Value -isnot [System.Collections.IDictionary]) {
                        $matchesType = $true
                    }
                }
                'string' { if ($Value -is [string]) { $matchesType = $true } }
                'integer' { if (Test-HcrInteger $Value) { $matchesType = $true } }
                'number' {
                    if ($Value -is [ValueType] -and $Value -isnot [bool]) {
                        $matchesType = $true
                    }
                }
                'boolean' { if (Test-HcrBoolean $Value) { $matchesType = $true } }
            }
        }
        if (-not $matchesType) {
            Add-HcrValidationError $Errors "$Path has the wrong JSON type."
            return
        }
    }

    if (Test-HcrProperty $Schema 'const') {
        $constant = Get-HcrPropertyValue $Schema 'const'
        if ($Value -ne $constant) {
            Add-HcrValidationError $Errors "$Path must equal '$constant'."
        }
    }
    if (Test-HcrProperty $Schema 'enum') {
        $allowed = @((Get-HcrPropertyValue $Schema 'enum'))
        if ($allowed -notcontains $Value) {
            Add-HcrValidationError $Errors "$Path contains an unsupported value."
        }
    }
    if ($Value -is [string]) {
        if (Test-HcrProperty $Schema 'minLength') {
            if ($Value.Length -lt [int](Get-HcrPropertyValue $Schema 'minLength')) {
                Add-HcrValidationError $Errors "$Path is shorter than allowed."
            }
        }
        if (Test-HcrProperty $Schema 'maxLength') {
            if ($Value.Length -gt [int](Get-HcrPropertyValue $Schema 'maxLength')) {
                Add-HcrValidationError $Errors "$Path is longer than allowed."
            }
        }
        if (Test-HcrProperty $Schema 'pattern') {
            if ($Value -notmatch [string](Get-HcrPropertyValue $Schema 'pattern')) {
                Add-HcrValidationError $Errors "$Path does not match the required format."
            }
        }
        if ((Get-HcrPropertyValue $Schema 'format') -eq 'uuid' -and
            -not (Test-HcrUuid $Value)) {
            Add-HcrValidationError $Errors "$Path must be a UUID."
        }
    }
    if (Test-HcrInteger $Value) {
        if (Test-HcrProperty $Schema 'minimum') {
            if ([decimal]$Value -lt [decimal](Get-HcrPropertyValue $Schema 'minimum')) {
                Add-HcrValidationError $Errors "$Path is below the allowed minimum."
            }
        }
        if (Test-HcrProperty $Schema 'maximum') {
            if ([decimal]$Value -gt [decimal](Get-HcrPropertyValue $Schema 'maximum')) {
                Add-HcrValidationError $Errors "$Path exceeds the allowed maximum."
            }
        }
    }
    if (Test-HcrObjectLike $Value) {
        $properties = Get-HcrPropertyValue $Schema 'properties'
        $required = @((Get-HcrPropertyValue $Schema 'required' @()))
        foreach ($name in $required) {
            if (-not (Test-HcrProperty $Value ([string]$name))) {
                Add-HcrValidationError $Errors "$Path is missing required field '$name'."
            }
        }
        if ($null -ne $properties) {
            foreach ($name in (Get-HcrPropertyNames $Value)) {
                if (-not (Test-HcrProperty $properties $name)) {
                    if ((Get-HcrPropertyValue $Schema 'additionalProperties' $true) -eq $false) {
                        Add-HcrValidationError $Errors "$Path contains unsupported field '$name'."
                    }
                    continue
                }
                Test-HcrSimpleSchemaValue `
                    (Get-HcrPropertyValue $Value $name) `
                    (Get-HcrPropertyValue $properties $name) `
                    "$Path.$name" `
                    $Errors
            }
        }
    }
    if ($Value -is [System.Collections.IEnumerable] -and
        $Value -isnot [string] -and
        $Value -isnot [System.Collections.IDictionary]) {
        $items = @($Value)
        if (Test-HcrProperty $Schema 'minItems') {
            if ($items.Count -lt [int](Get-HcrPropertyValue $Schema 'minItems')) {
                Add-HcrValidationError $Errors "$Path has too few entries."
            }
        }
        if (Test-HcrProperty $Schema 'maxItems') {
            if ($items.Count -gt [int](Get-HcrPropertyValue $Schema 'maxItems')) {
                Add-HcrValidationError $Errors "$Path has too many entries."
            }
        }
        $itemSchema = Get-HcrPropertyValue $Schema 'items'
        if ($null -ne $itemSchema) {
            for ($index = 0; $index -lt $items.Count; $index++) {
                Test-HcrSimpleSchemaValue $items[$index] $itemSchema "$Path[$index]" $Errors
            }
        }
    }
}

function Assert-HcrToolArguments {
    param(
        [Parameter(Mandatory = $true)][string]$ToolName,
        [AllowNull()][object]$Arguments
    )

    if ($null -eq $Arguments) {
        $Arguments = [pscustomobject]@{}
    }
    $definition = @(Get-HcrToolDefinitions | Where-Object { $_.name -eq $ToolName })
    if ($definition.Count -ne 1) {
        Throw-HcrError 'METHOD_NOT_FOUND' 'The requested MCP tool does not exist.'
    }
    $errors = New-Object System.Collections.Generic.List[string]
    Test-HcrSimpleSchemaValue $Arguments $definition[0].inputSchema '$' $errors
    if ($errors.Count -gt 0) {
        Throw-HcrError 'INVALID_ARGUMENT' 'The tool arguments are invalid.' ([ordered]@{
            errors = @($errors | ForEach-Object { [string]$_ })
        })
    }
    return $Arguments
}

function Read-HcrJsonDocument {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ErrorCode,
        [int64]$MaximumBytes = 4MB
    )

    $item = Assert-HcrRegularLocalFile $Path $ErrorCode
    if ($item.Length -gt $MaximumBytes) {
        Throw-HcrError $ErrorCode 'The JSON document exceeds the size limit.'
    }
    try {
        $document = Get-Content -LiteralPath $item.FullName -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Throw-HcrError $ErrorCode 'The file is not valid UTF-8 JSON.'
    }
    return [pscustomobject][ordered]@{
        path = $item.FullName
        document = $document
    }
}

function Test-HcrIdentifier {
    param([AllowNull()][object]$Value)
    return $Value -is [string] -and $Value -match '^[a-z0-9]+(?:-[a-z0-9]+)*$'
}

function Test-HcrApplicationIdentifier {
    param([AllowNull()][object]$Value)
    return $Value -is [string] -and $Value -match '^[a-zA-Z][a-zA-Z0-9-]*$'
}

function Test-HcrExpectedScalar {
    param([AllowNull()][object]$Value)
    return $null -eq $Value -or $Value -is [string] -or
        $Value -is [ValueType]
}

function Test-HcrProfileStep {
    param(
        [AllowNull()][object]$Step,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][bool]$Cleanup,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$DeclaredApplications,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors
    )

    $allFields = @(
        'id', 'type', 'application', 'timeoutSeconds', 'path', 'registryPath',
        'registryName', 'expected', 'processName', 'moduleRelativePath', 'port',
        'sentinelId', 'required'
    )
    if (-not (Test-HcrAllowedProperties $Step $allFields $Path $Errors)) {
        return
    }
    [void](Test-HcrRequiredProperties $Step @('id', 'type', 'timeoutSeconds') $Path $Errors)
    $id = Get-HcrPropertyValue $Step 'id'
    if (-not (Test-HcrIdentifier $id)) {
        Add-HcrValidationError $Errors "$Path.id is not a valid id."
    }
    $type = [string](Get-HcrPropertyValue $Step 'type')
    $allowedTypes = if ($Cleanup) {
        $script:HcrCleanupStepTypes
    }
    else {
        @($script:HcrActionStepTypes + $script:HcrAssertionStepTypes)
    }
    if ($allowedTypes -notcontains $type) {
        Add-HcrValidationError $Errors "$Path.type is not allowed."
    }
    $timeout = Get-HcrPropertyValue $Step 'timeoutSeconds'
    $timeoutMaximum = if ($Cleanup) { 120 } else { 900 }
    if (-not (Test-HcrInteger $timeout) -or [int64]$timeout -lt 1 -or
        [int64]$timeout -gt $timeoutMaximum) {
        Add-HcrValidationError $Errors "$Path.timeoutSeconds is outside 1..$timeoutMaximum."
    }
    if ((Test-HcrProperty $Step 'required') -and
        -not (Test-HcrBoolean (Get-HcrPropertyValue $Step 'required'))) {
        Add-HcrValidationError $Errors "$Path.required must be boolean."
    }

    $typeFields = @{
        stageArtifact = @()
        installPackage = @('application')
        launchApplication = @('application')
        stopApplication = @('application')
        uninstallPackage = @('application')
        assertFile = @('path', 'expected')
        assertRegistry = @('registryPath', 'registryName', 'expected')
        assertProcess = @('application', 'processName', 'expected')
        assertModule = @('application', 'moduleRelativePath', 'expected')
        assertShortcut = @('path', 'expected')
        assertPort = @('port', 'expected')
        writeSentinel = @('sentinelId')
        assertSentinel = @('sentinelId', 'expected')
        wait = @()
    }
    $allowedForType = @('id', 'type', 'timeoutSeconds', 'required')
    if ($typeFields.ContainsKey($type)) {
        $allowedForType += @($typeFields[$type])
        foreach ($field in (Get-HcrPropertyNames $Step)) {
            if ($allowedForType -notcontains $field) {
                Add-HcrValidationError $Errors "$Path.$field is invalid for step type '$type'."
            }
        }
    }

    if (@('installPackage', 'launchApplication', 'stopApplication', 'uninstallPackage') -contains $type -and
        -not (Test-HcrProperty $Step 'application')) {
        Add-HcrValidationError $Errors "$Path.application is required for '$type'."
    }
    if (@('assertFile', 'assertShortcut') -contains $type -and
        -not (Test-HcrProperty $Step 'path')) {
        Add-HcrValidationError $Errors "$Path.path is required for '$type'."
    }
    if ($type -eq 'assertRegistry' -and -not (Test-HcrProperty $Step 'registryPath')) {
        Add-HcrValidationError $Errors "$Path.registryPath is required."
    }
    if ($type -eq 'assertProcess') {
        $selectorCount = 0
        if (Test-HcrProperty $Step 'application') { $selectorCount++ }
        if (Test-HcrProperty $Step 'processName') { $selectorCount++ }
        if ($selectorCount -ne 1) {
            Add-HcrValidationError $Errors "$Path must select exactly one application or processName."
        }
    }
    if ($type -eq 'assertModule' -and
        (-not (Test-HcrProperty $Step 'application') -or
         -not (Test-HcrProperty $Step 'moduleRelativePath'))) {
        Add-HcrValidationError $Errors "$Path requires application and moduleRelativePath."
    }
    if ($type -eq 'assertPort' -and -not (Test-HcrProperty $Step 'port')) {
        Add-HcrValidationError $Errors "$Path.port is required."
    }
    if (@('writeSentinel', 'assertSentinel') -contains $type -and
        -not (Test-HcrProperty $Step 'sentinelId')) {
        Add-HcrValidationError $Errors "$Path.sentinelId is required."
    }

    if (Test-HcrProperty $Step 'application') {
        $application = Get-HcrPropertyValue $Step 'application'
        if (-not (Test-HcrApplicationIdentifier $application)) {
            Add-HcrValidationError $Errors "$Path.application is invalid."
        }
        elseif ($DeclaredApplications -notcontains [string]$application) {
            Add-HcrValidationError $Errors "$Path references an unknown application."
        }
    }
    foreach ($field in @('path', 'registryPath', 'moduleRelativePath')) {
        if ((Test-HcrProperty $Step $field) -and
            -not (Test-HcrSafeRelativePath (Get-HcrPropertyValue $Step $field))) {
            Add-HcrValidationError $Errors "$Path.$field is not a safe relative path."
        }
    }
    if ((Test-HcrProperty $Step 'processName') -and
        ((Get-HcrPropertyValue $Step 'processName') -isnot [string] -or
         [string](Get-HcrPropertyValue $Step 'processName') -notmatch '^[a-zA-Z0-9._-]+$')) {
        Add-HcrValidationError $Errors "$Path.processName is invalid."
    }
    if (Test-HcrProperty $Step 'port') {
        $port = Get-HcrPropertyValue $Step 'port'
        if (-not (Test-HcrInteger $port) -or [int64]$port -lt 1 -or [int64]$port -gt 65535) {
            Add-HcrValidationError $Errors "$Path.port is outside 1..65535."
        }
    }
    if ((Test-HcrProperty $Step 'sentinelId') -and
        -not (Test-HcrIdentifier (Get-HcrPropertyValue $Step 'sentinelId'))) {
        Add-HcrValidationError $Errors "$Path.sentinelId is invalid."
    }
    if (Test-HcrProperty $Step 'registryName') {
        $registryName = Get-HcrPropertyValue $Step 'registryName'
        if ($registryName -isnot [string] -or $registryName.Length -gt 255) {
            Add-HcrValidationError $Errors "$Path.registryName is invalid."
        }
    }
    if ((Test-HcrProperty $Step 'expected') -and
        -not (Test-HcrExpectedScalar (Get-HcrPropertyValue $Step 'expected'))) {
        Add-HcrValidationError $Errors "$Path.expected must be a JSON scalar."
    }
    $requiredValue = Get-HcrPropertyValue $Step 'required' $true
    if (($script:HcrActionStepTypes -contains $type) -and $requiredValue -eq $false) {
        Add-HcrValidationError $Errors "$Path cannot make action '$type' optional."
    }
}

function Test-HcrProfileDocument {
    param([AllowNull()][object]$Profile)

    $errors = New-Object System.Collections.Generic.List[string]
    $rootAllowed = @(
        'schemaVersion', 'id', 'description', 'platform', 'baselineType',
        'artifact', 'applications', 'steps', 'cleanupSteps', 'manualAssertions'
    )
    if (-not (Test-HcrAllowedProperties $Profile $rootAllowed '$' $errors)) {
        return [pscustomobject]@{ valid = $false; errors = @($errors | ForEach-Object { [string]$_ }) }
    }
    [void](Test-HcrRequiredProperties $Profile @(
        'schemaVersion', 'id', 'platform', 'baselineType', 'artifact',
        'applications', 'steps', 'cleanupSteps', 'manualAssertions'
    ) '$' $errors)
    if ((Get-HcrPropertyValue $Profile 'schemaVersion') -ne 1) {
        Add-HcrValidationError $errors '$.schemaVersion must equal 1.'
    }
    if (-not (Test-HcrIdentifier (Get-HcrPropertyValue $Profile 'id'))) {
        Add-HcrValidationError $errors '$.id is invalid.'
    }
    if ((Get-HcrPropertyValue $Profile 'platform') -ne 'windows-x64') {
        Add-HcrValidationError $errors '$.platform must equal windows-x64.'
    }
    if (@('stock-clean', 'webview2-absent-derived') -notcontains
        (Get-HcrPropertyValue $Profile 'baselineType')) {
        Add-HcrValidationError $errors '$.baselineType is invalid.'
    }
    if (Test-HcrProperty $Profile 'description') {
        $description = Get-HcrPropertyValue $Profile 'description'
        if ($description -isnot [string] -or $description.Length -gt 1000) {
            Add-HcrValidationError $errors '$.description is invalid.'
        }
    }

    $artifact = Get-HcrPropertyValue $Profile 'artifact'
    if (Test-HcrAllowedProperties $artifact @('fileNamePattern', 'architecture', 'sha256') '$.artifact' $errors) {
        [void](Test-HcrRequiredProperties $artifact @('fileNamePattern', 'architecture') '$.artifact' $errors)
        $pattern = Get-HcrPropertyValue $artifact 'fileNamePattern'
        if ($pattern -isnot [string] -or $pattern.Length -lt 1 -or
            $pattern.Length -gt 260 -or $pattern -match '[\\/]') {
            Add-HcrValidationError $errors '$.artifact.fileNamePattern is invalid.'
        }
        if ((Get-HcrPropertyValue $artifact 'architecture') -ne 'x64') {
            Add-HcrValidationError $errors '$.artifact.architecture must equal x64.'
        }
        if (Test-HcrProperty $artifact 'sha256') {
            $hash = Get-HcrPropertyValue $artifact 'sha256'
            if ($hash -isnot [string] -or $hash -notmatch '^[a-f0-9]{64}$') {
                Add-HcrValidationError $errors '$.artifact.sha256 is invalid.'
            }
        }
    }

    $applicationsValue = Get-HcrPropertyValue $Profile 'applications' @()
    $applications = @(if ($applicationsValue -is [System.Collections.IEnumerable] -and
        $applicationsValue -isnot [string] -and
        $applicationsValue -isnot [System.Collections.IDictionary]) {
        @($applicationsValue)
    }
    else {
        Add-HcrValidationError $errors '$.applications must be an array.'
        @()
    })
    if ($applications.Count -lt 1) {
        Add-HcrValidationError $errors '$.applications must contain at least one entry.'
    }
    $applicationIds = New-Object System.Collections.Generic.List[string]
    for ($index = 0; $index -lt $applications.Count; $index++) {
        $path = "$.applications[$index]"
        $application = $applications[$index]
        if (-not (Test-HcrAllowedProperties $application @(
            'id', 'installerType', 'installMode', 'executableRelativePath',
            'uninstallerDiscovery', 'processName'
        ) $path $errors)) { continue }
        [void](Test-HcrRequiredProperties $application @(
            'id', 'installerType', 'installMode', 'executableRelativePath',
            'uninstallerDiscovery'
        ) $path $errors)
        $applicationId = Get-HcrPropertyValue $application 'id'
        if (-not (Test-HcrApplicationIdentifier $applicationId)) {
            Add-HcrValidationError $errors "$path.id is invalid."
        }
        else {
            if ($applicationIds -contains [string]$applicationId) {
                Add-HcrValidationError $errors "$path.id is duplicated."
            }
            $applicationIds.Add([string]$applicationId)
        }
        if (@('nsis', 'msi') -notcontains (Get-HcrPropertyValue $application 'installerType')) {
            Add-HcrValidationError $errors "$path.installerType is invalid."
        }
        if ((Get-HcrPropertyValue $application 'installMode') -ne 'currentUser') {
            Add-HcrValidationError $errors "$path.installMode must equal currentUser."
        }
        if (-not (Test-HcrSafeRelativePath (Get-HcrPropertyValue $application 'executableRelativePath'))) {
            Add-HcrValidationError $errors "$path.executableRelativePath is unsafe."
        }
        if (@('hkcuUninstall', 'msiProduct') -notcontains
            (Get-HcrPropertyValue $application 'uninstallerDiscovery')) {
            Add-HcrValidationError $errors "$path.uninstallerDiscovery is invalid."
        }
        if ((Test-HcrProperty $application 'processName') -and
            ((Get-HcrPropertyValue $application 'processName') -isnot [string] -or
             [string](Get-HcrPropertyValue $application 'processName') -notmatch '^[a-zA-Z0-9._-]+$')) {
            Add-HcrValidationError $errors "$path.processName is invalid."
        }
    }

    $collections = [ordered]@{}
    foreach ($name in @('steps', 'cleanupSteps', 'manualAssertions')) {
        $value = Get-HcrPropertyValue $Profile $name @()
        if ($value -is [System.Collections.IEnumerable] -and
            $value -isnot [string] -and
            $value -isnot [System.Collections.IDictionary]) {
            $collections[$name] = @($value)
        }
        else {
            Add-HcrValidationError $errors "`$.$name must be an array."
            $collections[$name] = @()
        }
    }
    if ($collections.steps.Count -lt 1) {
        Add-HcrValidationError $errors '$.steps must contain at least one entry.'
    }
    if ($collections.cleanupSteps.Count -gt 16) {
        Add-HcrValidationError $errors '$.cleanupSteps exceeds 16 entries.'
    }
    $executionIds = New-Object System.Collections.Generic.List[string]
    $stageIndexes = New-Object System.Collections.Generic.List[int]
    for ($index = 0; $index -lt $collections.steps.Count; $index++) {
        $step = $collections.steps[$index]
        Test-HcrProfileStep $step "$.steps[$index]" $false @($applicationIds | ForEach-Object { [string]$_ }) $errors
        $id = Get-HcrPropertyValue $step 'id'
        if ($id -is [string]) { $executionIds.Add($id) }
        if ((Get-HcrPropertyValue $step 'type') -eq 'stageArtifact') { $stageIndexes.Add($index) }
    }
    if ($stageIndexes.Count -ne 1 -or $stageIndexes[0] -ne 0) {
        Add-HcrValidationError $errors '$.steps must contain exactly one first-position stageArtifact.'
    }
    $cleanupBudget = [int64]0
    for ($index = 0; $index -lt $collections.cleanupSteps.Count; $index++) {
        $step = $collections.cleanupSteps[$index]
        Test-HcrProfileStep $step "$.cleanupSteps[$index]" $true @($applicationIds | ForEach-Object { [string]$_ }) $errors
        $id = Get-HcrPropertyValue $step 'id'
        if ($id -is [string]) { $executionIds.Add($id) }
        $timeout = Get-HcrPropertyValue $step 'timeoutSeconds'
        if (Test-HcrInteger $timeout) { $cleanupBudget += [int64]$timeout }
    }
    if ($cleanupBudget -gt 300) {
        Add-HcrValidationError $errors '$.cleanupSteps exceeds the 300-second declared budget.'
    }
    for ($index = 0; $index -lt $collections.manualAssertions.Count; $index++) {
        $path = "$.manualAssertions[$index]"
        $assertion = $collections.manualAssertions[$index]
        if (-not (Test-HcrAllowedProperties $assertion @('id', 'description', 'required') $path $errors)) {
            continue
        }
        [void](Test-HcrRequiredProperties $assertion @('id', 'description', 'required') $path $errors)
        $id = Get-HcrPropertyValue $assertion 'id'
        if (-not (Test-HcrIdentifier $id)) {
            Add-HcrValidationError $errors "$path.id is invalid."
        }
        elseif ($id -is [string]) { $executionIds.Add($id) }
        $description = Get-HcrPropertyValue $assertion 'description'
        if ($description -isnot [string] -or $description.Length -lt 1 -or $description.Length -gt 2000) {
            Add-HcrValidationError $errors "$path.description is invalid."
        }
        if (-not (Test-HcrBoolean (Get-HcrPropertyValue $assertion 'required'))) {
            Add-HcrValidationError $errors "$path.required must be boolean."
        }
    }
    foreach ($group in ($executionIds | Group-Object | Where-Object { $_.Count -gt 1 })) {
        Add-HcrValidationError $errors "Execution id '$($group.Name)' is not globally unique."
    }
    return [pscustomobject][ordered]@{
        valid = $errors.Count -eq 0
        errors = @($errors | ForEach-Object { [string]$_ })
        cleanupBudgetSeconds = $cleanupBudget
    }
}

function Read-AndValidate-HcrProfileV1 {
    param([Parameter(Mandatory = $true)][string]$ProfilePath)

    $loaded = Read-HcrJsonDocument $ProfilePath 'PROFILE_INVALID' 2MB
    $validation = Test-HcrProfileDocument $loaded.document
    return [pscustomobject][ordered]@{
        path = $loaded.path
        profile = $loaded.document
        valid = $validation.valid
        errors = @($validation.errors)
        cleanupBudgetSeconds = $validation.cleanupBudgetSeconds
    }
}

function Get-HcrDerivedOverallStatus {
    param(
        [object[]]$AutomaticAssertions,
        [object[]]$ManualAssertions
    )

    $required = @(
        @($AutomaticAssertions) + @($ManualAssertions) |
            Where-Object { [bool](Get-HcrPropertyValue $_ 'required' $true) }
    )
    if (@($required | Where-Object { (Get-HcrPropertyValue $_ 'status') -eq 'failed' }).Count -gt 0) {
        return 'failed'
    }
    if (@($required | Where-Object { (Get-HcrPropertyValue $_ 'status') -ne 'passed' }).Count -gt 0) {
        return 'incomplete'
    }
    return 'passed'
}

function Test-HcrEvidenceReference {
    param(
        [AllowNull()][object]$Reference,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors
    )

    if (-not (Test-HcrAllowedProperties $Reference @('path', 'sha256') $Path $Errors)) {
        return
    }
    [void](Test-HcrRequiredProperties $Reference @('path', 'sha256') $Path $Errors)
    $referencePath = Get-HcrPropertyValue $Reference 'path'
    if (-not (Test-HcrSafeRelativePath $referencePath)) {
        Add-HcrValidationError $Errors "$Path.path is not a safe relative path."
    }
    $hash = Get-HcrPropertyValue $Reference 'sha256'
    if ($hash -isnot [string] -or $hash -notmatch '^[a-f0-9]{64}$') {
        Add-HcrValidationError $Errors "$Path.sha256 is invalid."
    }
}

function Test-HcrEvidenceAssertion {
    param(
        [AllowNull()][object]$Assertion,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][bool]$Manual,
        [Parameter(Mandatory = $true)][string]$OperationId,
        [Parameter(Mandatory = $true)][string]$ProfileId,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors
    )

    if ($Manual) {
        if (-not (Test-HcrAllowedProperties $Assertion @(
            'id', 'required', 'description', 'status', 'attestation'
        ) $Path $Errors)) { return }
        [void](Test-HcrRequiredProperties $Assertion @(
            'id', 'required', 'description', 'status', 'attestation'
        ) $Path $Errors)
    }
    else {
        if (-not (Test-HcrAllowedProperties $Assertion @(
            'id', 'required', 'status', 'summary', 'evidence'
        ) $Path $Errors)) { return }
        [void](Test-HcrRequiredProperties $Assertion @(
            'id', 'required', 'status', 'summary', 'evidence'
        ) $Path $Errors)
    }
    $id = Get-HcrPropertyValue $Assertion 'id'
    if ($id -isnot [string] -or [string]::IsNullOrWhiteSpace($id)) {
        Add-HcrValidationError $Errors "$Path.id is invalid."
    }
    if (-not (Test-HcrBoolean (Get-HcrPropertyValue $Assertion 'required'))) {
        Add-HcrValidationError $Errors "$Path.required must be boolean."
    }
    $status = Get-HcrPropertyValue $Assertion 'status'
    if (@('passed', 'failed', 'notPerformed', 'unsupported') -notcontains $status) {
        Add-HcrValidationError $Errors "$Path.status is invalid."
    }
    if (-not $Manual) {
        $summary = Get-HcrPropertyValue $Assertion 'summary'
        if ($summary -isnot [string] -or $summary.Length -gt 2000) {
            Add-HcrValidationError $Errors "$Path.summary is invalid."
        }
        $machineEvidence = Get-HcrPropertyValue $Assertion 'evidence'
        if ($null -ne $machineEvidence -and -not (Test-HcrObjectLike $machineEvidence)) {
            Add-HcrValidationError $Errors "$Path.evidence must be an object or null."
        }
        return
    }

    $description = Get-HcrPropertyValue $Assertion 'description'
    if ($description -isnot [string] -or $description.Length -lt 1 -or $description.Length -gt 2000) {
        Add-HcrValidationError $Errors "$Path.description is invalid."
    }
    $attestation = Get-HcrPropertyValue $Assertion 'attestation'
    if ($status -eq 'notPerformed') {
        if ($null -ne $attestation) {
            Add-HcrValidationError $Errors "$Path.attestation must be null when notPerformed."
        }
        return
    }
    if ($null -eq $attestation) {
        Add-HcrValidationError $Errors "$Path.attestation is required for a performed result."
        return
    }
    if (-not (Test-HcrAllowedProperties $attestation @(
        'operationId', 'profileId', 'assertionId', 'observer', 'observedAt',
        'method', 'summary', 'evidenceReferences'
    ) "$Path.attestation" $Errors)) { return }
    [void](Test-HcrRequiredProperties $attestation @(
        'operationId', 'profileId', 'assertionId', 'observer', 'observedAt',
        'method', 'summary', 'evidenceReferences'
    ) "$Path.attestation" $Errors)
    if ((Get-HcrPropertyValue $attestation 'operationId') -ne $OperationId -or
        (Get-HcrPropertyValue $attestation 'profileId') -ne $ProfileId -or
        (Get-HcrPropertyValue $attestation 'assertionId') -ne $id) {
        Add-HcrValidationError $Errors "$Path.attestation identity does not match the evidence assertion."
    }
    if (-not (Test-HcrUuid (Get-HcrPropertyValue $attestation 'operationId'))) {
        Add-HcrValidationError $Errors "$Path.attestation.operationId is invalid."
    }
    $observer = Get-HcrPropertyValue $attestation 'observer'
    if ($observer -isnot [string] -or $observer.Length -lt 1 -or $observer.Length -gt 512) {
        Add-HcrValidationError $Errors "$Path.attestation.observer is invalid."
    }
    if (-not (Test-HcrDateTimeString (Get-HcrPropertyValue $attestation 'observedAt'))) {
        Add-HcrValidationError $Errors "$Path.attestation.observedAt is invalid."
    }
    $method = Get-HcrPropertyValue $attestation 'method'
    if ($status -eq 'unsupported') {
        if ($method -ne 'declaredUnsupported') {
            Add-HcrValidationError $Errors "$Path.attestation.method must be declaredUnsupported."
        }
    }
    elseif (@('visualInspection', 'interactiveExercise', 'externalTool') -notcontains $method) {
        Add-HcrValidationError $Errors "$Path.attestation.method is invalid for passed or failed status."
    }
    $summary = Get-HcrPropertyValue $attestation 'summary'
    if ($summary -isnot [string] -or $summary.Length -lt 1 -or $summary.Length -gt 2000) {
        Add-HcrValidationError $Errors "$Path.attestation.summary is invalid."
    }
    $referencesValue = Get-HcrPropertyValue $attestation 'evidenceReferences' @()
    if ($referencesValue -isnot [System.Collections.IEnumerable] -or
        $referencesValue -is [string] -or
        $referencesValue -is [System.Collections.IDictionary]) {
        Add-HcrValidationError $Errors "$Path.attestation.evidenceReferences must be an array."
        return
    }
    $references = @($referencesValue)
    for ($index = 0; $index -lt $references.Count; $index++) {
        Test-HcrEvidenceReference $references[$index] "$Path.attestation.evidenceReferences[$index]" $Errors
    }
}

function Test-HcrEvidenceDocument {
    param(
        [AllowNull()][object]$Evidence,
        [AllowNull()][object]$OperationRecord = $null
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $rootFields = @(
        'schemaVersion', 'operationId', 'createdAt', 'profileId', 'baselineType',
        'vm', 'guest', 'artifact', 'automaticAssertions', 'manualAssertions',
        'cleanupTriggered', 'cleanupResults', 'overallStatus', 'warnings'
    )
    if (-not (Test-HcrAllowedProperties $Evidence $rootFields '$' $errors)) {
        return [pscustomobject]@{ valid = $false; errors = @($errors | ForEach-Object { [string]$_ }); derivedOverallStatus = $null }
    }
    [void](Test-HcrRequiredProperties $Evidence $rootFields '$' $errors)
    if ((Get-HcrPropertyValue $Evidence 'schemaVersion') -ne 1) {
        Add-HcrValidationError $errors '$.schemaVersion must equal 1.'
    }
    $operationId = [string](Get-HcrPropertyValue $Evidence 'operationId')
    $profileId = [string](Get-HcrPropertyValue $Evidence 'profileId')
    if (-not (Test-HcrUuid $operationId)) {
        Add-HcrValidationError $errors '$.operationId must be a UUID.'
    }
    if (-not (Test-HcrDateTimeString (Get-HcrPropertyValue $Evidence 'createdAt'))) {
        Add-HcrValidationError $errors '$.createdAt must be an ISO date-time.'
    }
    if ([string]::IsNullOrWhiteSpace($profileId)) {
        Add-HcrValidationError $errors '$.profileId is invalid.'
    }
    if (@('stock-clean', 'webview2-absent-derived') -notcontains
        (Get-HcrPropertyValue $Evidence 'baselineType')) {
        Add-HcrValidationError $errors '$.baselineType is invalid.'
    }

    $vm = Get-HcrPropertyValue $Evidence 'vm'
    if (Test-HcrAllowedProperties $vm @('id', 'name', 'checkpointName', 'ownershipVerified') '$.vm' $errors) {
        [void](Test-HcrRequiredProperties $vm @('id', 'name', 'checkpointName', 'ownershipVerified') '$.vm' $errors)
        foreach ($field in @('id', 'name')) {
            if ((Get-HcrPropertyValue $vm $field) -isnot [string]) {
                Add-HcrValidationError $errors "$.vm.$field must be a string."
            }
        }
        $checkpointName = Get-HcrPropertyValue $vm 'checkpointName'
        if ($null -ne $checkpointName -and $checkpointName -isnot [string]) {
            Add-HcrValidationError $errors '$.vm.checkpointName must be a string or null.'
        }
        if (-not (Test-HcrBoolean (Get-HcrPropertyValue $vm 'ownershipVerified'))) {
            Add-HcrValidationError $errors '$.vm.ownershipVerified must be boolean.'
        }
    }

    $guest = Get-HcrPropertyValue $Evidence 'guest'
    if (Test-HcrAllowedProperties $guest @(
        'windowsBuild', 'architecture', 'userName', 'isAdministrator',
        'isElevated', 'tokenIntegrity', 'profilePathContainsNonAscii'
    ) '$.guest' $errors) {
        [void](Test-HcrRequiredProperties $guest @(
            'windowsBuild', 'architecture', 'userName', 'isAdministrator',
            'isElevated', 'tokenIntegrity'
        ) '$.guest' $errors)
        foreach ($field in @('windowsBuild', 'userName')) {
            if ((Get-HcrPropertyValue $guest $field) -isnot [string]) {
                Add-HcrValidationError $errors "$.guest.$field must be a string."
            }
        }
        if ((Get-HcrPropertyValue $guest 'architecture') -ne 'x64') {
            Add-HcrValidationError $errors '$.guest.architecture must equal x64.'
        }
        foreach ($field in @('isAdministrator', 'isElevated')) {
            if (-not (Test-HcrBoolean (Get-HcrPropertyValue $guest $field))) {
                Add-HcrValidationError $errors "$.guest.$field must be boolean."
            }
        }
        if ((Test-HcrProperty $guest 'profilePathContainsNonAscii') -and
            -not (Test-HcrBoolean (Get-HcrPropertyValue $guest 'profilePathContainsNonAscii'))) {
            Add-HcrValidationError $errors '$.guest.profilePathContainsNonAscii must be boolean.'
        }
        if (@('low', 'medium', 'high', 'system') -notcontains
            (Get-HcrPropertyValue $guest 'tokenIntegrity')) {
            Add-HcrValidationError $errors '$.guest.tokenIntegrity is invalid.'
        }
    }

    $artifact = Get-HcrPropertyValue $Evidence 'artifact'
    if (Test-HcrAllowedProperties $artifact @('fileName', 'size', 'sourceSha256', 'guestSha256') '$.artifact' $errors) {
        [void](Test-HcrRequiredProperties $artifact @('fileName', 'size', 'sourceSha256', 'guestSha256') '$.artifact' $errors)
        if ((Get-HcrPropertyValue $artifact 'fileName') -isnot [string]) {
            Add-HcrValidationError $errors '$.artifact.fileName must be a string.'
        }
        $size = Get-HcrPropertyValue $artifact 'size'
        if (-not (Test-HcrInteger $size) -or [int64]$size -lt 0) {
            Add-HcrValidationError $errors '$.artifact.size is invalid.'
        }
        $sourceHash = Get-HcrPropertyValue $artifact 'sourceSha256'
        if ($sourceHash -isnot [string] -or $sourceHash -notmatch '^[a-f0-9]{64}$') {
            Add-HcrValidationError $errors '$.artifact.sourceSha256 is invalid.'
        }
        $guestHash = Get-HcrPropertyValue $artifact 'guestSha256'
        if ($null -ne $guestHash -and
            ($guestHash -isnot [string] -or $guestHash -notmatch '^[a-f0-9]{64}$')) {
            Add-HcrValidationError $errors '$.artifact.guestSha256 is invalid.'
        }
    }

    $assertionCollections = [ordered]@{}
    foreach ($name in @('automaticAssertions', 'manualAssertions', 'cleanupResults', 'warnings')) {
        $value = Get-HcrPropertyValue $Evidence $name @()
        if ($value -is [System.Collections.IEnumerable] -and
            $value -isnot [string] -and
            $value -isnot [System.Collections.IDictionary]) {
            $assertionCollections[$name] = @($value)
        }
        else {
            Add-HcrValidationError $errors "`$.$name must be an array."
            $assertionCollections[$name] = @()
        }
    }
    for ($index = 0; $index -lt $assertionCollections.automaticAssertions.Count; $index++) {
        Test-HcrEvidenceAssertion $assertionCollections.automaticAssertions[$index] `
            "$.automaticAssertions[$index]" $false $operationId $profileId $errors
    }
    for ($index = 0; $index -lt $assertionCollections.manualAssertions.Count; $index++) {
        Test-HcrEvidenceAssertion $assertionCollections.manualAssertions[$index] `
            "$.manualAssertions[$index]" $true $operationId $profileId $errors
    }
    foreach ($warning in $assertionCollections.warnings) {
        if ($warning -isnot [string] -or $warning.Length -gt 1000) {
            Add-HcrValidationError $errors '$.warnings contains an invalid entry.'
        }
    }
    if (-not (Test-HcrBoolean (Get-HcrPropertyValue $Evidence 'cleanupTriggered'))) {
        Add-HcrValidationError $errors '$.cleanupTriggered must be boolean.'
    }
    if ($assertionCollections.cleanupResults.Count -gt 16) {
        Add-HcrValidationError $errors '$.cleanupResults exceeds 16 entries.'
    }

    if ($null -ne $OperationRecord) {
        $expectedEvidenceDigest = [string](Get-HcrPropertyValue $OperationRecord 'evidenceSha256')
        if ($expectedEvidenceDigest -notmatch '^[a-f0-9]{64}$' -or
            (Get-HcrEvidenceDocumentDigest $Evidence) -ne $expectedEvidenceDigest) {
            Add-HcrValidationError $errors 'Evidence content does not match immutable operation state.'
        }
        if ((Get-HcrPropertyValue $Evidence 'baselineType') -ne
            (Get-HcrPropertyValue $OperationRecord 'baselineType')) {
            Add-HcrValidationError $errors '$.baselineType does not match immutable operation state.'
        }
        if ((Get-HcrPropertyValue $OperationRecord 'adapterMode') -eq 'mock' -and
            $assertionCollections.warnings -notcontains $script:HcrMockWarning) {
            Add-HcrValidationError $errors 'Mock-adapter evidence is missing its mandatory test-only warning.'
        }
        if ((Get-HcrPropertyValue $vm 'id') -ne (Get-HcrPropertyValue $OperationRecord 'vmId') -or
            (Get-HcrPropertyValue $vm 'name') -ne (Get-HcrPropertyValue $OperationRecord 'vmName') -or
            (Get-HcrPropertyValue $vm 'ownershipVerified') -ne
                (Get-HcrPropertyValue $OperationRecord 'ownershipVerified')) {
            Add-HcrValidationError $errors '$.vm does not match immutable operation identity.'
        }
        $operationGuest = Get-HcrPropertyValue $OperationRecord 'guest'
        foreach ($field in @(
                'windowsBuild', 'architecture', 'userName', 'isAdministrator',
                'isElevated', 'tokenIntegrity', 'profilePathContainsNonAscii'
            )) {
            if ((Get-HcrPropertyValue $guest $field) -ne
                (Get-HcrPropertyValue $operationGuest $field)) {
                Add-HcrValidationError $errors "$.guest.$field does not match immutable operation state."
            }
        }
        $operationArtifact = Get-HcrPropertyValue $OperationRecord 'artifact'
        foreach ($field in @('fileName', 'size', 'sourceSha256', 'guestSha256')) {
            if ((Get-HcrPropertyValue $artifact $field) -ne
                (Get-HcrPropertyValue $operationArtifact $field)) {
                Add-HcrValidationError $errors "$.artifact.$field does not match immutable operation state."
            }
        }
        $expectedAutomatic = @((Get-HcrPropertyValue $OperationRecord 'automaticAssertions' @()))
        if ($assertionCollections.automaticAssertions.Count -ne $expectedAutomatic.Count) {
            Add-HcrValidationError $errors '$.automaticAssertions count does not match immutable operation state.'
        }
        for ($index = 0; $index -lt [Math]::Min(
                $assertionCollections.automaticAssertions.Count,
                $expectedAutomatic.Count
            ); $index++) {
            $actual = $assertionCollections.automaticAssertions[$index]
            $expected = $expectedAutomatic[$index]
            if ((Get-HcrPropertyValue $actual 'id') -ne (Get-HcrPropertyValue $expected 'id') -or
                (Get-HcrPropertyValue $actual 'required') -ne
                    (Get-HcrPropertyValue $expected 'required')) {
                Add-HcrValidationError $errors `
                    "$.automaticAssertions[$index] does not match immutable order and identity."
            }
        }
        $stageIndexes = @(for ($index = 0; $index -lt $expectedAutomatic.Count; $index++) {
            if ([string](Get-HcrPropertyValue $expectedAutomatic[$index] 'type') -eq 'stageArtifact') {
                $index
            }
        })
        if ($stageIndexes.Count -ne 1 -or
            $stageIndexes[0] -ge $assertionCollections.automaticAssertions.Count) {
            Add-HcrValidationError $errors 'Immutable stageArtifact assertion identity is unavailable.'
        }
        else {
            $stageStatus = [string](Get-HcrPropertyValue `
                $assertionCollections.automaticAssertions[$stageIndexes[0]] `
                'status')
            $sourceHash = Get-HcrPropertyValue $artifact 'sourceSha256'
            $guestHash = Get-HcrPropertyValue $artifact 'guestSha256'
            $hashesVerified = $sourceHash -is [string] -and
                $guestHash -is [string] -and
                $sourceHash -eq $guestHash
            if (($hashesVerified -and $stageStatus -ne 'passed') -or
                (-not $hashesVerified -and $stageStatus -ne 'failed')) {
                Add-HcrValidationError $errors `
                    'Artifact hashes require a passed matching stageArtifact assertion or a failed null/mismatched stageArtifact assertion.'
            }
        }
        $expectedManual = @((Get-HcrPropertyValue $OperationRecord 'manualAssertions' @()))
        if ($assertionCollections.manualAssertions.Count -ne $expectedManual.Count) {
            Add-HcrValidationError $errors '$.manualAssertions count does not match immutable operation state.'
        }
        for ($index = 0; $index -lt [Math]::Min(
                $assertionCollections.manualAssertions.Count,
                $expectedManual.Count
            ); $index++) {
            $actual = $assertionCollections.manualAssertions[$index]
            $expected = $expectedManual[$index]
            if ((Get-HcrPropertyValue $actual 'id') -ne (Get-HcrPropertyValue $expected 'id') -or
                (Get-HcrPropertyValue $actual 'required') -ne
                    (Get-HcrPropertyValue $expected 'required') -or
                (Get-HcrPropertyValue $actual 'description') -ne
                    (Get-HcrPropertyValue $expected 'description')) {
                Add-HcrValidationError $errors `
                    "$.manualAssertions[$index] does not match immutable order and identity."
            }
        }
    }

    $immutableCleanupTriggered = $null
    $immutableCleanupSteps = @()
    if ($null -eq $OperationRecord) {
        Add-HcrValidationError $errors 'Immutable operation state is unavailable.'
    }
    else {
        if ((Get-HcrPropertyValue $OperationRecord 'operationId') -ne $operationId -or
            (Get-HcrPropertyValue $OperationRecord 'profileId') -ne $profileId) {
            Add-HcrValidationError $errors 'Evidence identity does not match immutable operation state.'
        }
        $immutableCleanupTriggered = Get-HcrPropertyValue $OperationRecord 'cleanupTriggered'
        $immutableCleanupSteps = @((Get-HcrPropertyValue $OperationRecord 'cleanupSteps' @()))
        if ((Get-HcrPropertyValue $Evidence 'cleanupTriggered') -ne $immutableCleanupTriggered) {
            Add-HcrValidationError $errors '$.cleanupTriggered does not match immutable operation state.'
        }
        if ($assertionCollections.cleanupResults.Count -ne $immutableCleanupSteps.Count) {
            Add-HcrValidationError $errors '$.cleanupResults does not match the declared cleanup-step count.'
        }
    }
    for ($index = 0; $index -lt $assertionCollections.cleanupResults.Count; $index++) {
        $path = "$.cleanupResults[$index]"
        $result = $assertionCollections.cleanupResults[$index]
        if (-not (Test-HcrAllowedProperties $result @(
            'operationId', 'profileId', 'cleanupStepId', 'cleanupStepType',
            'status', 'summary', 'evidence'
        ) $path $errors)) { continue }
        [void](Test-HcrRequiredProperties $result @(
            'operationId', 'profileId', 'cleanupStepId', 'cleanupStepType',
            'status', 'summary', 'evidence'
        ) $path $errors)
        if ((Get-HcrPropertyValue $result 'operationId') -ne $operationId -or
            (Get-HcrPropertyValue $result 'profileId') -ne $profileId) {
            Add-HcrValidationError $errors "$path identity does not match the evidence."
        }
        $stepType = Get-HcrPropertyValue $result 'cleanupStepType'
        if ($script:HcrCleanupStepTypes -notcontains $stepType) {
            Add-HcrValidationError $errors "$path.cleanupStepType is invalid."
        }
        $status = Get-HcrPropertyValue $result 'status'
        if (@('passed', 'failed', 'notPerformed', 'unsupported') -notcontains $status) {
            Add-HcrValidationError $errors "$path.status is invalid."
        }
        $summary = Get-HcrPropertyValue $result 'summary'
        if ($summary -isnot [string] -or $summary.Length -gt 2000) {
            Add-HcrValidationError $errors "$path.summary is invalid."
        }
        $machineEvidence = Get-HcrPropertyValue $result 'evidence'
        if ($status -eq 'notPerformed' -and $null -ne $machineEvidence) {
            Add-HcrValidationError $errors "$path.evidence must be null when notPerformed."
        }
        elseif ($null -ne $machineEvidence -and -not (Test-HcrObjectLike $machineEvidence)) {
            Add-HcrValidationError $errors "$path.evidence must be an object or null."
        }
        if ($immutableCleanupTriggered -eq $false -and $status -ne 'notPerformed') {
            Add-HcrValidationError $errors "$path was performed while cleanup was not triggered."
        }
        if ($index -lt $immutableCleanupSteps.Count) {
            $immutable = $immutableCleanupSteps[$index]
            if ((Get-HcrPropertyValue $result 'cleanupStepId') -ne
                (Get-HcrPropertyValue $immutable 'id') -or
                $stepType -ne (Get-HcrPropertyValue $immutable 'type')) {
                Add-HcrValidationError $errors "$path does not match immutable cleanup order and identity."
            }
        }
    }

    $derived = Get-HcrDerivedOverallStatus `
        $assertionCollections.automaticAssertions `
        $assertionCollections.manualAssertions
    if ((Get-HcrPropertyValue $Evidence 'overallStatus') -ne $derived) {
        Add-HcrValidationError $errors '$.overallStatus does not match required-assertion derivation.'
    }
    if ($derived -eq 'passed') {
        if ((Get-HcrPropertyValue $vm 'ownershipVerified') -ne $true -or
            (Get-HcrPropertyValue $guest 'isAdministrator') -ne $false -or
            (Get-HcrPropertyValue $guest 'isElevated') -ne $false -or
            (Get-HcrPropertyValue $guest 'tokenIntegrity') -ne 'medium') {
            Add-HcrValidationError $errors 'Passed evidence violates ownership or ordinary-user token invariants.'
        }
        if ((Get-HcrPropertyValue $artifact 'sourceSha256') -ne
            (Get-HcrPropertyValue $artifact 'guestSha256')) {
            Add-HcrValidationError $errors 'Passed evidence requires matching source and guest artifact SHA-256 values.'
        }
    }
    return [pscustomobject][ordered]@{
        valid = $errors.Count -eq 0
        errors = @($errors | ForEach-Object { [string]$_ })
        derivedOverallStatus = $derived
    }
}

function Read-AndValidate-HcrEvidenceV1 {
    param([Parameter(Mandatory = $true)][string]$EvidencePath)

    $loaded = Read-HcrJsonDocument $EvidencePath 'EVIDENCE_INVALID' 8MB
    $operation = $null
    $operationId = Get-HcrPropertyValue $loaded.document 'operationId'
    if (Test-HcrUuid $operationId) {
        try {
            $operation = Get-HcrOperationRecord ([string]$operationId)
        }
        catch {
            $operation = $null
        }
    }
    $validation = Test-HcrEvidenceDocument $loaded.document $operation
    return [pscustomobject][ordered]@{
        path = $loaded.path
        evidence = $loaded.document
        operation = $operation
        valid = $validation.valid
        errors = @($validation.errors)
        derivedOverallStatus = $validation.derivedOverallStatus
    }
}

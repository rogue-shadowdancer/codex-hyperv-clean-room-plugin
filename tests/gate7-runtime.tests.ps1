[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:AssertionCount = 0

function Assert-Gate7 {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:AssertionCount++
    if (-not $Condition) { throw $Message }
}

function Assert-Gate7Equal {
    param(
        [AllowNull()][object]$Actual,
        [AllowNull()][object]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:AssertionCount++
    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected', received '$Actual'."
    }
}

function ConvertTo-Gate7CanonicalJson {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return 'null' }
    if (Test-HcrObjectLike $Value) {
        $properties = @(Get-HcrPropertyNames $Value | Sort-Object | ForEach-Object {
            $encodedName = ConvertTo-Json -InputObject ([string]$_) -Compress
            $encodedValue = ConvertTo-Gate7CanonicalJson (Get-HcrPropertyValue $Value $_)
            return ($encodedName + ':' + $encodedValue)
        })
        return ('{' + ($properties -join ',') + '}')
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = @($Value | ForEach-Object { ConvertTo-Gate7CanonicalJson $_ })
        return ('[' + ($items -join ',') + ']')
    }
    return (ConvertTo-Json -InputObject $Value -Compress)
}

function Assert-Gate7Error {
    param(
        [Parameter(Mandatory = $true)][object]$Envelope,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )

    Assert-Gate7 (-not [bool]$Envelope.ok) "$Message The operation unexpectedly succeeded."
    Assert-Gate7Equal ([string]$Envelope.error.code) $Code $Message
}

function Write-Gate7Json {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    [IO.File]::WriteAllText(
        $Path,
        (($Value | ConvertTo-Json -Depth 100 -Compress) + "`n"),
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Invoke-Gate7MigrationCli {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    $windowsPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $windowsPowerShell
    $startInfo.Arguments = ('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass ' +
        '-File "{0}" -SourceProfilePath "{1}" -DestinationProfilePath "{2}"' -f
        $ScriptPath, $SourcePath, $DestinationPath)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject][ordered]@{
        exitCode = [int]$process.ExitCode
        output = (($standardOutput, $standardError) -join "`n").Trim()
    }
}

function Invoke-Gate7Tool {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][object]$Arguments = $null,
        [int]$EnvelopeSchemaVersion = 1
    )

    if ($null -eq $Arguments) { $Arguments = [pscustomobject]@{} }
    $result = Invoke-HcrToolCall $Name $Arguments
    Assert-Gate7Equal ([int]$result.schemaVersion) $EnvelopeSchemaVersion `
        "Tool '$Name' returned the wrong envelope schema version."
    Assert-Gate7 (Test-HcrUuid $result.operationId) `
        "Tool '$Name' returned an invalid operation ID."
    return $result
}

function Set-Gate7MutationFault {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$Phase
    )

    $state = Read-HcrMockAdapterState
    $state | Add-Member -NotePropertyName mutationFault -NotePropertyValue ([pscustomobject][ordered]@{
        operation = $Operation
        phase = $Phase
    }) -Force
    Write-HcrMockAdapterState $state
}

function Clear-Gate7MutationFault {
    $state = Read-HcrMockAdapterState
    if (Test-HcrProperty $state 'mutationFault') {
        $state.PSObject.Properties.Remove('mutationFault')
        Write-HcrMockAdapterState $state
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$pluginRoot = Join-Path $repoRoot 'hyperv-clean-room'
$testRoot = Join-Path $repoRoot ('.artifacts\gate7-tests-' + [Guid]::NewGuid().ToString('N'))
$vmRoot = Join-Path $testRoot 'vm-root'
$stateRoot = Join-Path $testRoot 'state'
$credentialRoot = Join-Path $testRoot 'credentials'
$mockPath = Join-Path $testRoot 'mock-adapter.json'
$isoPath = Join-Path $testRoot 'source.iso'
$portablePath = Join-Path $testRoot 'SampleProduct_0.2.0_windows-x64-portable.zip'
$fixtureDirectory = Join-Path $testRoot 'fixtures'
$fixturePath = Join-Path $fixtureDirectory 'sample-image.png'
$portableManifestPath = Join-Path $repoRoot 'tests\fixtures\v2\portable-manifest.valid.json'
$profilePath = Join-Path $testRoot 'portable-profile.json'
$manifestMismatchProfilePath = Join-Path $testRoot 'portable-manifest-mismatch-profile.json'
$unknownPath = Join-Path $testRoot 'unknown-profile.json'
$legacyV2ProfilePath = Join-Path $testRoot 'legacy-v2-profile.json'
$legacyArtifactPath = Join-Path $testRoot 'SampleApp-0.2.0-x64.exe'
$volumeRoot = [IO.Path]::GetPathRoot($testRoot)

foreach ($directory in @($vmRoot, $fixtureDirectory)) {
    [void](New-Item -ItemType Directory -Path $directory -Force)
}
[IO.File]::WriteAllBytes($isoPath, [byte[]](1..128))
$portableManifestBytes = [IO.File]::ReadAllBytes($portableManifestPath)
$portableManifestDocument = [Text.Encoding]::UTF8.GetString($portableManifestBytes) |
    ConvertFrom-Json -ErrorAction Stop
$portableCandidateSourceCommit = [string]$portableManifestDocument.sourceCommit
$portableManifestSha = [Security.Cryptography.SHA256]::Create()
try {
    $portableManifestHash = ([BitConverter]::ToString(
            $portableManifestSha.ComputeHash($portableManifestBytes)
        )).Replace('-', '').ToLowerInvariant()
}
finally {
    $portableManifestSha.Dispose()
}
[void](Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop)
$portableStream = [IO.File]::Open(
    $portablePath,
    [IO.FileMode]::Create,
    [IO.FileAccess]::ReadWrite,
    [IO.FileShare]::None
)
try {
    $portableArchive = New-Object IO.Compression.ZipArchive(
        $portableStream,
        [IO.Compression.ZipArchiveMode]::Create,
        $true
    )
    try {
        $portableEntry = $portableArchive.CreateEntry('portable-manifest.json')
        $portableEntryStream = $portableEntry.Open()
        try {
            $portableEntryStream.Write($portableManifestBytes, 0, $portableManifestBytes.Length)
        }
        finally {
            $portableEntryStream.Dispose()
        }
    }
    finally {
        $portableArchive.Dispose()
    }
}
finally {
    $portableStream.Dispose()
}
[IO.File]::WriteAllBytes($fixturePath, [byte[]](1..64))
[IO.File]::WriteAllBytes($legacyArtifactPath, [byte[]](1..80))

$mockState = [ordered]@{
    schemaVersion = 1
    host = [ordered]@{
        computerName = 'MOCK-HOST'
        windowsEdition = 'Windows 11 Pro'
        windowsBuild = '26100'
        architecture = 'AMD64'
        hyperVCommandsAvailable = $true
        hypervisorPresent = $true
        elevated = $true
        processorCount = 8
        memoryBytes = 17179869184
        switches = @([ordered]@{
            id = 'switch-1'
            name = 'Default Switch'
            type = 'Internal'
        })
        targetVolumes = @([ordered]@{
            uniqueId = 'mock-volume'
            root = $volumeRoot
            fileSystem = 'NTFS'
            availableBytes = 1099511627776
        })
    }
    vms = @()
    credentialProfiles = @([ordered]@{
        name = 'test-profile'
        vmName = 'cleanroom-v2'
    })
    guest = [ordered]@{
        windowsBuild = '26100'
        architecture = 'x64'
        userName = 'TEST\standard'
        userSid = 'S-1-5-21-1000-1000-1000-1001'
        isAdministrator = $false
        isElevated = $false
        tokenIntegrity = 'medium'
        profilePathContainsNonAscii = $true
    }
    stepResults = [ordered]@{}
    cleanupResults = [ordered]@{}
}
Write-Gate7Json $mockPath $mockState

$env:HCR_TEST_MODE = '1'
$env:HCR_ADAPTER_MODE = 'mock'
$env:HCR_MOCK_ADAPTER_PATH = $mockPath
$env:HCR_STATE_ROOT = $stateRoot
$env:HCR_CREDENTIAL_ROOT = $credentialRoot
$env:HCR_TEST_SOURCE_COMMIT = 'abcdef1234567890abcdef1234567890abcdef12'
$script:HcrInitialized = $false
foreach ($runtimeFile in @(
        'Common.ps1',
        'State.ps1',
        'ToolSchemas.ps1',
        'Validation.ps1',
        'Validation.V2.ps1',
        'Adapters.ps1',
        'Tools.Host.ps1',
        'Tools.Host.V2.ps1',
        'Tools.Guest.ps1',
        'Tools.Guest.V2.ps1',
        'Runtime.ps1'
    )) {
    . (Join-Path (Join-Path (Join-Path $pluginRoot 'mcp') 'lib') $runtimeFile)
}
Initialize-HcrRuntime $pluginRoot

$definitions = @(Get-HcrToolDefinitions)
$expectedNames = @(
    'inspect_host', 'list_vms', 'inspect_vm', 'validate_test_profile',
    'validate_evidence', 'plan_vm_create', 'apply_vm_create',
    'plan_checkpoint_create', 'apply_checkpoint_create',
    'plan_checkpoint_restore', 'apply_checkpoint_restore', 'inspect_guest',
    'stage_artifact', 'run_test_profile', 'collect_evidence',
    'record_manual_attestation', 'plan_vm_power', 'apply_vm_power',
    'plan_vm_network', 'apply_vm_network'
)
Assert-Gate7Equal $definitions.Count 20 'The schema-v2 runtime does not expose exactly 20 tools.'
Assert-Gate7Equal (($definitions.name -join ',')) ($expectedNames -join ',') `
    'The schema-v2 runtime tool order changed.'
$targetCatalog = Get-Content -LiteralPath (Join-Path $repoRoot 'contracts\v2\tool-catalog.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json
$catalogDefinitions = @($targetCatalog.tools | Select-Object -Skip 16 | ForEach-Object {
    [pscustomobject][ordered]@{
        name = $_.name
        description = $_.description
        inputSchema = $_.inputSchema
        annotations = $_.annotations
    }
})
Assert-Gate7Equal `
    (ConvertTo-Gate7CanonicalJson @($definitions | Select-Object -Skip 16)) `
    (ConvertTo-Gate7CanonicalJson $catalogDefinitions) `
    'The four schema-v2 production tools diverged from the authoritative target catalog.'
$v1Snapshot = Get-Content `
    -LiteralPath (Join-Path $PSScriptRoot 'fixtures\v2\compatibility\tool-catalog-v1.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Gate7Equal `
    ((@($definitions | Select-Object -First 16) | ConvertTo-Json -Depth 30 -Compress)) `
    ((@($v1Snapshot) | ConvertTo-Json -Depth 30 -Compress)) `
    'The first 16 schema-v1 tool definitions drifted during H2 integration.'

$vmPlan = Invoke-Gate7Tool 'plan_vm_create' ([pscustomobject]@{
    name = 'cleanroom-v2'
    isoPath = $isoPath
    vmRoot = $vmRoot
    switchName = 'Default Switch'
})
Assert-Gate7 $vmPlan.ok 'The mock VM baseline plan failed.'
$vmCreate = Invoke-Gate7Tool 'apply_vm_create' ([pscustomobject]@{
    planId = [string]$vmPlan.data.plan.planId
})
Assert-Gate7 $vmCreate.ok 'The mock VM baseline apply failed.'

$powerPlan = Invoke-Gate7Tool 'plan_vm_power' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    action = 'start'
}) -EnvelopeSchemaVersion 2
Assert-Gate7 $powerPlan.ok 'Power planning failed.'
Assert-Gate7Equal ([string]$powerPlan.data.plan.planKind) 'vmPower' `
    'Power planning returned the wrong plan kind.'
$powerApply = Invoke-Gate7Tool 'apply_vm_power' ([pscustomobject]@{
    planId = [string]$powerPlan.data.plan.planId
}) -EnvelopeSchemaVersion 2
Assert-Gate7 ($powerApply.ok -and $powerApply.changed) 'Power apply did not confirm a change.'
Assert-Gate7Equal ([string]$powerApply.data.currentState) 'Running' `
    'Power apply did not reach the exact target state.'
$powerReplay = Invoke-Gate7Tool 'apply_vm_power' ([pscustomobject]@{
    planId = [string]$powerPlan.data.plan.planId
}) -EnvelopeSchemaVersion 2
Assert-Gate7Error $powerReplay 'PLAN_ALREADY_CONSUMED' 'A power plan was reusable.'

$networkPlan = Invoke-Gate7Tool 'plan_vm_network' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    target = 'disconnected'
}) -EnvelopeSchemaVersion 2
Assert-Gate7 $networkPlan.ok `
    ('Network disconnect planning failed: ' +
        ((Get-HcrPropertyValue $networkPlan 'error') | ConvertTo-Json -Depth 10 -Compress))
$networkPairFiles = @(Get-ChildItem -LiteralPath (Join-Path $stateRoot 'plans') `
    -File -Filter 'network-pair-*.json')
Assert-Gate7Equal $networkPairFiles.Count 1 `
    'The disconnect change/recovery plans were not atomically published as one record.'
Assert-Gate7 (-not (Test-Path -LiteralPath (Get-HcrStateSubpath 'plans' (([string]$networkPlan.data.changePlan.planId) + '.json')))) `
    'The disconnect change plan was also published as a non-atomic standalone record.'
Assert-Gate7 (-not (Test-Path -LiteralPath (Get-HcrStateSubpath 'plans' (([string]$networkPlan.data.recoveryPlan.planId) + '.json')))) `
    'The disconnect recovery plan was also published as a non-atomic standalone record.'
Assert-Gate7 `
    ([string]$networkPlan.data.changePlan.pairedPlanId -eq
        [string]$networkPlan.data.recoveryPlan.planId) `
    'The disconnect plan was not paired to its recovery plan.'
$prematureRecovery = Invoke-Gate7Tool 'apply_vm_network' ([pscustomobject]@{
    planId = [string]$networkPlan.data.recoveryPlan.planId
}) -EnvelopeSchemaVersion 2
Assert-Gate7Error $prematureRecovery 'PLAN_DRIFT' `
    'A recovery plan applied before disconnect did not fail its preconditions.'
$pairAfterPrematureRecovery = Read-HcrJsonFile `
    $networkPairFiles[0].FullName 'PLAN_INVALID'
Assert-Gate7 (-not [bool]$pairAfterPrematureRecovery.recovery.consumed -and
        $null -eq $pairAfterPrematureRecovery.recovery.consumedAt) `
    'A recovery plan was consumed before its disconnected-state preconditions passed.'
$networkApply = Invoke-Gate7Tool 'apply_vm_network' ([pscustomobject]@{
    planId = [string]$networkPlan.data.changePlan.planId
}) -EnvelopeSchemaVersion 2
Assert-Gate7 ($networkApply.ok -and $networkApply.changed) `
    'Network disconnect apply did not confirm a change.'
Assert-Gate7 ([bool]$networkApply.data.recoveryRequired) `
    'A confirmed disconnect did not require recovery.'
$networkRecovery = Invoke-Gate7Tool 'apply_vm_network' ([pscustomobject]@{
    planId = [string]$networkPlan.data.recoveryPlan.planId
}) -EnvelopeSchemaVersion 2
Assert-Gate7 ($networkRecovery.ok -and $networkRecovery.changed) `
    'The paired network recovery did not restore the baseline.'

$driftPlan = Invoke-Gate7Tool 'plan_vm_network' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    target = 'disconnected'
}) -EnvelopeSchemaVersion 2
Assert-Gate7 $driftPlan.ok 'Network drift regression planning failed.'
$driftChangeId = [string]$driftPlan.data.changePlan.planId
$driftPairPath = Get-HcrStateSubpath 'plans' "network-pair-$driftChangeId.json"
$driftState = Read-HcrMockAdapterState
$originalSwitchName = [string]$driftState.vms[0].networkAdapters[0].switchName
$driftState.vms[0].networkAdapters[0].switchName = 'Drifted Switch'
Write-HcrMockAdapterState $driftState
$driftApply = Invoke-Gate7Tool 'apply_vm_network' ([pscustomobject]@{
    planId = $driftChangeId
}) -EnvelopeSchemaVersion 2
Assert-Gate7Error $driftApply 'PLAN_DRIFT' `
    'A drifted change plan did not fail closed.'
$driftPairAfterApply = Read-HcrJsonFile $driftPairPath 'PLAN_INVALID'
Assert-Gate7 ([bool]$driftPairAfterApply.change.consumed -and
        $null -ne $driftPairAfterApply.change.consumedAt) `
    'A well-formed drifted change plan was not consumed exactly once.'
$restoredDriftState = Read-HcrMockAdapterState
$restoredDriftState.vms[0].networkAdapters[0].switchName = $originalSwitchName
Write-HcrMockAdapterState $restoredDriftState
$driftReplay = Invoke-Gate7Tool 'apply_vm_network' ([pscustomobject]@{
    planId = $driftChangeId
}) -EnvelopeSchemaVersion 2
Assert-Gate7Error $driftReplay 'PLAN_ALREADY_CONSUMED' `
    'A stale change plan became reusable after adapter state was restored.'

$unavailableRecoveryPlan = Invoke-Gate7Tool 'plan_vm_network' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    target = 'disconnected'
}) -EnvelopeSchemaVersion 2
Assert-Gate7 $unavailableRecoveryPlan.ok 'Unavailable recovery regression planning failed.'
$unavailableChangeId = [string]$unavailableRecoveryPlan.data.changePlan.planId
$unavailablePairPath = Get-HcrStateSubpath 'plans' "network-pair-$unavailableChangeId.json"
$unavailablePair = Read-HcrJsonFile $unavailablePairPath 'PLAN_INVALID'
$unavailablePair.recovery.consumed = $true
$unavailablePair.recovery.consumedAt = [DateTimeOffset]::UtcNow.ToString('o')
Write-HcrJsonFile $unavailablePairPath $unavailablePair
$attachmentBeforeUnavailableApply = (Read-HcrMockAdapterState).vms[0].networkAdapters[0].switchName
$unavailableApply = Invoke-Gate7Tool 'apply_vm_network' ([pscustomobject]@{
    planId = $unavailableChangeId
}) -EnvelopeSchemaVersion 2
Assert-Gate7Error $unavailableApply 'PLAN_ALREADY_CONSUMED' `
    'A disconnect change proceeded without an available paired recovery plan.'
$unavailablePairAfterApply = Read-HcrJsonFile $unavailablePairPath 'PLAN_INVALID'
Assert-Gate7 ([bool]$unavailablePairAfterApply.change.consumed -and
        $null -ne $unavailablePairAfterApply.change.consumedAt) `
    'A disconnect change was not consumed before paired recovery availability was checked.'
$attachmentAfterUnavailableApply = (Read-HcrMockAdapterState).vms[0].networkAdapters[0].switchName
Assert-Gate7 ([string]$attachmentAfterUnavailableApply -eq
        [string]$attachmentBeforeUnavailableApply) `
    'The network changed even though the paired recovery plan was unavailable.'

$invalidRecoveryPlan = Invoke-Gate7Tool 'plan_vm_network' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    target = 'disconnected'
}) -EnvelopeSchemaVersion 2
Assert-Gate7 $invalidRecoveryPlan.ok 'Invalid paired recovery regression planning failed.'
$invalidRecoveryChangeId = [string]$invalidRecoveryPlan.data.changePlan.planId
$invalidRecoveryPairPath = Get-HcrStateSubpath 'plans' "network-pair-$invalidRecoveryChangeId.json"
$invalidRecoveryPair = Read-HcrJsonFile $invalidRecoveryPairPath 'PLAN_INVALID'
$invalidRecoveryPair.recovery.plan.targetAttachment = [pscustomobject][ordered]@{
    mode = 'disconnected'
}
Write-HcrJsonFile $invalidRecoveryPairPath $invalidRecoveryPair
$attachmentBeforeInvalidRecovery = (Read-HcrMockAdapterState).vms[0].networkAdapters[0].switchName
$invalidRecoveryApply = Invoke-Gate7Tool 'apply_vm_network' ([pscustomobject]@{
    planId = $invalidRecoveryChangeId
}) -EnvelopeSchemaVersion 2
Assert-Gate7Error $invalidRecoveryApply 'PLAN_INVALID' `
    'A disconnect change accepted a recovery plan with the wrong target attachment.'
$invalidRecoveryPairAfterApply = Read-HcrJsonFile $invalidRecoveryPairPath 'PLAN_INVALID'
Assert-Gate7 ([bool]$invalidRecoveryPairAfterApply.change.consumed) `
    'A disconnect change was not consumed before paired recovery binding validation.'
Assert-Gate7 ([string](Read-HcrMockAdapterState).vms[0].networkAdapters[0].switchName -eq
        [string]$attachmentBeforeInvalidRecovery) `
    'The network changed with an invalid paired recovery target.'

$expiredRecoveryPlan = Invoke-Gate7Tool 'plan_vm_network' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    target = 'disconnected'
}) -EnvelopeSchemaVersion 2
Assert-Gate7 $expiredRecoveryPlan.ok 'Expired paired recovery regression planning failed.'
$expiredRecoveryChangeId = [string]$expiredRecoveryPlan.data.changePlan.planId
$expiredRecoveryPairPath = Get-HcrStateSubpath 'plans' "network-pair-$expiredRecoveryChangeId.json"
$expiredRecoveryPair = Read-HcrJsonFile $expiredRecoveryPairPath 'PLAN_INVALID'
$expiredRecoveryPair.recovery.plan.expiresAt = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
Write-HcrJsonFile $expiredRecoveryPairPath $expiredRecoveryPair
$attachmentBeforeExpiredRecovery = (Read-HcrMockAdapterState).vms[0].networkAdapters[0].switchName
$expiredRecoveryApply = Invoke-Gate7Tool 'apply_vm_network' ([pscustomobject]@{
    planId = $expiredRecoveryChangeId
}) -EnvelopeSchemaVersion 2
Assert-Gate7Error $expiredRecoveryApply 'PLAN_EXPIRED' `
    'A disconnect change accepted an expired paired recovery plan.'
$expiredRecoveryPairAfterApply = Read-HcrJsonFile $expiredRecoveryPairPath 'PLAN_INVALID'
Assert-Gate7 ([bool]$expiredRecoveryPairAfterApply.change.consumed) `
    'A disconnect change was not consumed before paired recovery expiry validation.'
Assert-Gate7 ([string](Read-HcrMockAdapterState).vms[0].networkAdapters[0].switchName -eq
        [string]$attachmentBeforeExpiredRecovery) `
    'The network changed with an expired paired recovery plan.'

$faultPlan = Invoke-Gate7Tool 'plan_vm_network' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    target = 'disconnected'
}) -EnvelopeSchemaVersion 2
Set-Gate7MutationFault 'SetVmNetwork' 'entered'
$faultApply = Invoke-Gate7Tool 'apply_vm_network' ([pscustomobject]@{
    planId = [string]$faultPlan.data.changePlan.planId
}) -EnvelopeSchemaVersion 2
Clear-Gate7MutationFault
Assert-Gate7Error $faultApply 'NETWORK_RECOVERY_REQUIRED' `
    'An indeterminate disconnect did not return the recovery-required error.'
Assert-Gate7 ([bool]$faultApply.changed) `
    'An indeterminate network effect did not report changed=true.'
Assert-Gate7Equal `
    ([string]$faultApply.error.details.recoveryPlanId) `
    ([string]$faultPlan.data.recoveryPlan.planId) `
    'The network failure did not return its pre-created recovery plan ID.'

$fixtureHash = Get-HcrSha256File $fixturePath
$portableHash = Get-HcrSha256File $portablePath
$profile = [ordered]@{
    schemaVersion = 2
    id = 'portable-ui-smoke'
    workflowKind = 'portableAutomation'
    platform = 'windows-x64'
    baselineType = 'stock-clean'
    artifact = [ordered]@{
        packageKind = 'portableZip'
        fileNamePattern = [IO.Path]::GetFileName($portablePath)
        architecture = 'x64'
        sha256 = $portableHash
        sizeBytes = [int64](Get-Item -LiteralPath $portablePath).Length
        portableManifestEntryPath = 'portable-manifest.json'
        portableManifestSha256 = $portableManifestHash
    }
    fixtures = @([ordered]@{
        id = 'sample-image'
        sourceRelativePath = 'fixtures\sample-image.png'
        sizeBytes = [int64](Get-Item -LiteralPath $fixturePath).Length
        sha256 = $fixtureHash
        mediaType = 'image/png'
    })
    webDriver = [ordered]@{
        schemaVersion = 2
        id = 'edge-driver-138-0-3351-121'
        provider = 'microsoftEdgeDriver'
        browserKind = 'fixedVersionWebView2'
        browserVersion = '138.0.3351.121'
        driverVersion = '138.0.3351.121'
        architecture = 'x64'
        acquisition = [ordered]@{
            source = 'microsoftFixedEndpoint'
            archiveFileName = 'edgedriver_win64.zip'
            archiveSizeBytes = 10485760
            archiveSha256 = ('a' * 64)
            redirectPolicy = 'microsoftHttpsAllowlist'
        }
        executable = [ordered]@{
            relativePath = 'msedgedriver.exe'
            sizeBytes = 15728640
            sha256 = ('b' * 64)
            peArchitecture = 'x64'
            authenticodePublisher = 'Microsoft Corporation'
        }
        sessionPolicy = [ordered]@{
            listenAddress = '127.0.0.1'
            portPolicy = 'serverAllocatedEphemeral'
            browserArguments = @()
            allowNavigation = $false
            allowExecuteScript = $false
            allowArbitrarySelector = $false
        }
        files = @([ordered]@{
            path = 'msedgedriver.exe'
            sizeBytes = 15728640
            sha256 = ('b' * 64)
        })
    }
    applications = @([ordered]@{
        id = 'sample-product'
        packageKind = 'portableZip'
        executableRelativePath = 'SampleProduct.exe'
        dataDirectoryRelativePath = 'data'
        processName = 'SampleProduct.exe'
    })
    steps = @(
        [ordered]@{ id = 'stage-artifact'; type = 'stageArtifact'; timeoutSeconds = 120 },
        [ordered]@{ id = 'deploy-portable'; type = 'deployPortable'; application = 'sample-product'; timeoutSeconds = 300 },
        [ordered]@{ id = 'launch-application'; type = 'launchApplication'; application = 'sample-product'; timeoutSeconds = 60 },
        [ordered]@{ id = 'acquire-webdriver'; type = 'acquireWebDriver'; timeoutSeconds = 180 },
        [ordered]@{ id = 'start-ui-session'; type = 'startUiSession'; application = 'sample-product'; timeoutSeconds = 60 },
        [ordered]@{ id = 'upload-fixture'; type = 'uiUploadFixture'; testId = 'source-file-input'; fixtureId = 'sample-image'; timeoutSeconds = 30 },
        [ordered]@{ id = 'assert-review-visible'; type = 'assertUiElement'; testId = 'recognition-review'; state = 'visible'; timeoutSeconds = 60; required = $true },
        [ordered]@{ id = 'capture-review'; type = 'captureUiScreenshot'; evidenceName = 'recognition-review'; timeoutSeconds = 30 },
        [ordered]@{ id = 'stop-ui-session'; type = 'stopUiSession'; timeoutSeconds = 30 },
        [ordered]@{ id = 'stop-application'; type = 'stopApplication'; application = 'sample-product'; timeoutSeconds = 30 }
    )
    cleanupSteps = @()
    manualAssertions = @([ordered]@{
        id = 'visual-dpi-check'
        description = 'Confirm the portable UI is usable at the declared DPI.'
        required = $true
    })
}
Write-Gate7Json $profilePath $profile

$profileValidation = Invoke-Gate7Tool 'validate_test_profile' ([pscustomobject]@{
    profilePath = $profilePath
})
Assert-Gate7 $profileValidation.ok `
    ('The valid schema-v2 profile failed exact-version validation: ' +
        ((Get-HcrPropertyValue $profileValidation 'error') | ConvertTo-Json -Depth 10 -Compress))
$portableWithoutProcess = Copy-HcrObject ([pscustomobject]$profile)
$portableWithoutProcess.applications[0].PSObject.Properties.Remove('processName')
$portableWithoutProcessValidation = Test-HcrProfileDocumentV2 $portableWithoutProcess
Assert-Gate7 (-not $portableWithoutProcessValidation.valid) `
    'The native schema-v2 validator accepted a portable application without processName.'
$openStepProfile = Copy-HcrObject ([pscustomobject]$profile)
$openStepProfile.steps[0] | Add-Member -NotePropertyName arguments -NotePropertyValue @('--forbidden')
$openStepValidation = Test-HcrProfileDocumentV2 $openStepProfile
Assert-Gate7 (-not $openStepValidation.valid) `
    'The native schema-v2 validator accepted an open action-step payload.'
$missingExpectedProfile = Copy-HcrObject ([pscustomobject]$profile)
$missingExpectedProfile.steps[6].state = 'textEquals'
$missingExpectedValidation = Test-HcrProfileDocumentV2 $missingExpectedProfile
Assert-Gate7 (-not $missingExpectedValidation.valid) `
    'The native schema-v2 validator accepted a text assertion without expected.'
$outsideSessionProfile = Copy-HcrObject ([pscustomobject]$profile)
$temporaryStep = $outsideSessionProfile.steps[4]
$outsideSessionProfile.steps[4] = $outsideSessionProfile.steps[5]
$outsideSessionProfile.steps[5] = $temporaryStep
$outsideSessionValidation = Test-HcrProfileDocumentV2 $outsideSessionProfile
Assert-Gate7 (-not $outsideSessionValidation.valid) `
    'The native schema-v2 validator accepted a UI interaction outside the owned session.'
$missingLaunchProfile = Copy-HcrObject ([pscustomobject]$profile)
$missingLaunchProfile.steps = @($missingLaunchProfile.steps | Where-Object {
        [string](Get-HcrPropertyValue $_ 'type') -ne 'launchApplication'
    })
$missingLaunchValidation = Test-HcrProfileDocumentV2 $missingLaunchProfile
Assert-Gate7 (-not $missingLaunchValidation.valid) `
    'The native schema-v2 validator accepted a UI session without launching its application.'
$mismatchedApplicationProfile = Copy-HcrObject ([pscustomobject]$profile)
$secondApplication = Copy-HcrObject $mismatchedApplicationProfile.applications[0]
$secondApplication.id = 'other-product'
$mismatchedApplicationProfile.applications = @(
    $mismatchedApplicationProfile.applications[0],
    $secondApplication
)
$mismatchedStart = @($mismatchedApplicationProfile.steps | Where-Object {
        [string](Get-HcrPropertyValue $_ 'type') -eq 'startUiSession'
    })
$mismatchedStart[0].application = 'other-product'
$mismatchedApplicationValidation = Test-HcrProfileDocumentV2 $mismatchedApplicationProfile
Assert-Gate7 (-not $mismatchedApplicationValidation.valid) `
    'The native schema-v2 validator accepted a UI session bound to a different application.'
$optionalAssertionProfile = Copy-HcrObject ([pscustomobject]$profile)
$optionalAssertionProfile.steps[6].required = $false
$optionalAssertionProfile.manualAssertions[0].required = $false
$optionalAssertionValidation = Test-HcrProfileDocumentV2 $optionalAssertionProfile
Assert-Gate7 $optionalAssertionValidation.valid `
    'The native schema-v2 validator rejected contract-valid optional assertions.'
$unknown = Copy-HcrObject ([pscustomobject]$profile)
$unknown.schemaVersion = 3
Write-Gate7Json $unknownPath $unknown
$unknownValidation = Invoke-Gate7Tool 'validate_test_profile' ([pscustomobject]@{
    profilePath = $unknownPath
})
Assert-Gate7Error $unknownValidation 'UNSUPPORTED_SCHEMA_VERSION' `
    'An unknown profile schema version did not fail closed.'

$manifestMismatchProfile = Copy-HcrObject ([pscustomobject]$profile)
$manifestMismatchProfile.artifact.portableManifestSha256 = ('0' * 64)
Write-Gate7Json $manifestMismatchProfilePath $manifestMismatchProfile
$manifestMismatchRun = Invoke-Gate7Tool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    credentialProfile = 'test-profile'
    profilePath = $manifestMismatchProfilePath
    artifactPath = $portablePath
})
Assert-Gate7Error $manifestMismatchRun 'PORTABLE_MANIFEST_HASH_MISMATCH' `
    'The controller accepted candidate provenance from a manifest with the wrong hash.'

$portableRun = Invoke-Gate7Tool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    credentialProfile = 'test-profile'
    profilePath = $profilePath
    artifactPath = $portablePath
})
Assert-Gate7 $portableRun.ok `
    ('The schema-v2 mock portable workflow failed: ' +
        ((Get-HcrPropertyValue $portableRun 'error') | ConvertTo-Json -Depth 10 -Compress))
Assert-Gate7Equal ([string]$portableRun.data.machineStatus) 'passed' `
    'The schema-v2 mock workflow did not derive machineStatus=passed.'
Assert-Gate7Equal ([string]$portableRun.data.overallStatus) 'incomplete' `
    'An unperformed required manual assertion did not keep evidence incomplete.'
$portableOperation = Get-HcrOperationRecord ([string]$portableRun.data.testOperationId)
$portableEvidence = Read-HcrJsonFile ([string]$portableOperation.evidenceFile) 'EVIDENCE_NOT_READY'
Assert-Gate7Equal ([int]$portableEvidence.schemaVersion) 2 `
    'The schema-v2 workflow did not emit evidence v2.'
Assert-Gate7Equal ([string]$portableEvidence.candidate.sourceCommit) `
    $portableCandidateSourceCommit `
    'Evidence candidate provenance did not come from the portable manifest.'
Assert-Gate7Equal ([string]$portableEvidence.runtime.sourceCommit) `
    ([string]$env:HCR_TEST_SOURCE_COMMIT) `
    'Evidence runtime provenance did not come from the installed plugin manifest.'
Assert-Gate7 ([string]$portableEvidence.candidate.sourceCommit -ne
        [string]$portableEvidence.runtime.sourceCommit) `
    'Candidate and runtime source provenance were incorrectly collapsed.'
$evidenceValidation = Invoke-Gate7Tool 'validate_evidence' ([pscustomobject]@{
    evidencePath = [string]$portableOperation.evidenceFile
})
Assert-Gate7 $evidenceValidation.ok 'Generated schema-v2 evidence failed validation.'
$portableAttestation = Invoke-Gate7Tool 'record_manual_attestation' ([pscustomobject]@{
    operationId = [string]$portableRun.data.testOperationId
    assertionId = 'visual-dpi-check'
    status = 'unsupported'
    method = 'declaredUnsupported'
    summary = 'Interactive validation is unavailable in the mock test harness.'
})
Assert-Gate7 $portableAttestation.ok `
    'Schema-v2 manual attestation failed after operation-digest binding.'
$attestedPortableOperation = Get-HcrOperationRecord `
    ([string]$portableRun.data.testOperationId)
$attestedPortableValidation = Invoke-Gate7Tool 'validate_evidence' ([pscustomobject]@{
    evidencePath = [string]$attestedPortableOperation.evidenceFile
})
Assert-Gate7 $attestedPortableValidation.ok `
    'Schema-v2 evidence failed validation after its atomic attestation digest update.'
$hashDriftEvidence = Copy-HcrObject $portableEvidence
$hashDriftEvidence.artifacts[0].guestSha256 = ('0' * 64)
$hashDriftValidation = Test-HcrEvidenceDocumentV2 $hashDriftEvidence $portableOperation
Assert-Gate7 (-not $hashDriftValidation.valid) `
    'The native evidence-v2 validator accepted artifact hash drift.'
Assert-Gate7Equal ([string]$hashDriftValidation.derivedMachineStatus) 'failed' `
    'Artifact hash drift did not deterministically fail machine status.'

$cleanupFailureProfile = Copy-HcrObject ([pscustomobject]$profile)
$cleanupFailureProfile.id = 'portable-cleanup-failure'
$cleanupFailureProfile.cleanupSteps = @([pscustomobject][ordered]@{
    id = 'cleanup-stop-application'
    type = 'stopApplication'
    application = 'sample-product'
    timeoutSeconds = 30
})
$cleanupFailureProfilePath = Join-Path $testRoot 'portable-cleanup-failure.json'
Write-Gate7Json $cleanupFailureProfilePath $cleanupFailureProfile
$failureState = Read-HcrMockAdapterState
$failureState.stepResults | Add-Member -NotePropertyName 'acquire-webdriver' `
    -NotePropertyValue ([pscustomobject][ordered]@{
        status = 'failed'
        summary = 'The configured post-launch failure triggered cleanup.'
        evidence = $null
    }) -Force
Write-HcrMockAdapterState $failureState
$cleanupFailureRun = Invoke-Gate7Tool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    credentialProfile = 'test-profile'
    profilePath = $cleanupFailureProfilePath
    artifactPath = $portablePath
})
Assert-Gate7 $cleanupFailureRun.ok `
    'The mock schema-v2 failure workflow did not produce auditable failure evidence.'
Assert-Gate7Equal ([string]$cleanupFailureRun.data.machineStatus) 'failed' `
    'The configured schema-v2 failure did not derive machineStatus=failed.'
Assert-Gate7 ([bool]$cleanupFailureRun.data.cleanupTriggered) `
    'The configured post-launch schema-v2 failure did not trigger cleanup.'
Assert-Gate7Equal ([string]$cleanupFailureRun.data.cleanupResults[0].status) 'passed' `
    'The schema-v2 cleanup stop did not receive its current-operation process identity.'
Assert-Gate7 (@($cleanupFailureRun.data.cleanupResults[0].observations | Where-Object {
            $_.name -eq 'processidentityrevalidated' -and $_.value -eq $true
        }).Count -eq 1) `
    'The schema-v2 cleanup stop did not revalidate its current-operation process identity.'
$cleanupFailureOperation = Get-HcrOperationRecord `
    ([string]$cleanupFailureRun.data.testOperationId)
$cleanupFailureEvidence = Read-HcrJsonFile `
    ([string]$cleanupFailureOperation.evidenceFile) 'EVIDENCE_NOT_READY'
$cleanupFailureValidation = Test-HcrEvidenceDocumentV2 `
    $cleanupFailureEvidence $cleanupFailureOperation
Assert-Gate7 $cleanupFailureValidation.valid `
    ('The native validator rejected schema-valid failure evidence with null guest hashes: ' +
        ($cleanupFailureValidation.errors -join '; '))
Assert-Gate7 (@($cleanupFailureEvidence.artifacts | Where-Object {
            $_.status -ne 'passed' -and $null -eq $_.guestSha256
        }).Count -ge 2) `
    'The failure-evidence regression did not exercise absent guest hashes.'

$tamperedCleanupEvidence = Copy-HcrObject $cleanupFailureEvidence
$tamperedCleanupEvidence.cleanupResults[0].summary = 'forged cleanup summary'
Assert-Gate7 (-not (Test-HcrEvidenceDocumentV2 `
            $tamperedCleanupEvidence $cleanupFailureOperation).valid) `
    'The schema-v2 validator accepted cleanup evidence that diverged from the operation digest.'
$tamperedAssertionEvidence = Copy-HcrObject $cleanupFailureEvidence
$tamperedAssertionEvidence.automaticAssertions[0].id = 'forged-stage-identity'
Assert-Gate7 (-not (Test-HcrEvidenceDocumentV2 `
            $tamperedAssertionEvidence $cleanupFailureOperation).valid) `
    'The schema-v2 validator accepted assertion identity drift from immutable operation state.'

$cleanupFailureValidationTool = Invoke-Gate7Tool 'validate_evidence' ([pscustomobject]@{
    evidencePath = [string]$cleanupFailureOperation.evidenceFile
})
Assert-Gate7 $cleanupFailureValidationTool.ok `
    'The validate_evidence tool rejected immutable schema-v2 failure evidence.'
$v2ExportRoot = Join-Path $testRoot 'v2-export'
[void](New-Item -ItemType Directory -Path $v2ExportRoot)
$cleanupFailureExport = Invoke-Gate7Tool 'collect_evidence' ([pscustomobject]@{
    operationId = [string]$cleanupFailureRun.data.testOperationId
    outputDirectory = $v2ExportRoot
})
Assert-Gate7 $cleanupFailureExport.ok `
    ('The schema-v2 evidence export failed copied-version dispatch: ' +
        ((Get-HcrPropertyValue $cleanupFailureExport 'error') | ConvertTo-Json -Depth 10 -Compress))
Assert-Gate7 (Test-Path -LiteralPath $cleanupFailureExport.evidencePath -PathType Leaf) `
    'The schema-v2 evidence export did not publish its copied evidence file.'

$restoredState = Read-HcrMockAdapterState
$restoredState.stepResults.PSObject.Properties.Remove('acquire-webdriver')
Write-HcrMockAdapterState $restoredState

$uiContainmentProfile = Copy-HcrObject ([pscustomobject]$cleanupFailureProfile)
$uiContainmentProfile.id = 'portable-ui-session-containment'
$uiContainmentProfilePath = Join-Path $testRoot 'portable-ui-session-containment.json'
Write-Gate7Json $uiContainmentProfilePath $uiContainmentProfile
$uiFailureState = Read-HcrMockAdapterState
$uiFailureState.stepResults | Add-Member -NotePropertyName 'assert-review-visible' `
    -NotePropertyValue ([pscustomobject][ordered]@{
        status = 'failed'
        summary = 'The configured post-session UI failure triggered containment.'
        evidence = [pscustomobject]@{ matched = $false }
    }) -Force
Write-HcrMockAdapterState $uiFailureState
$uiContainmentRun = Invoke-Gate7Tool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    credentialProfile = 'test-profile'
    profilePath = $uiContainmentProfilePath
    artifactPath = $portablePath
})
Assert-Gate7 $uiContainmentRun.ok `
    'The mock post-session UI failure did not produce auditable containment evidence.'
Assert-Gate7 ([bool]$uiContainmentRun.data.cleanupTriggered) `
    'The mock post-session UI failure did not trigger cleanup.'
$uiContainmentAssertions = @($uiContainmentRun.data.automaticAssertions | Where-Object {
        [string]$_.id -eq 'automatic-ui-session-containment-1'
    })
Assert-Gate7Equal $uiContainmentAssertions.Count 1 `
    'The runner did not record exactly one automatic UI-session containment result.'
Assert-Gate7Equal ([string]$uiContainmentAssertions[0].status) 'passed' `
    'The automatic UI-session containment stop did not pass.'
$ordinaryUiStop = @($uiContainmentRun.data.automaticAssertions | Where-Object {
        [string]$_.id -eq 'stop-ui-session'
    })
Assert-Gate7Equal $ordinaryUiStop.Count 1 `
    'The ordinary UI-session stop result is missing from failure evidence.'
Assert-Gate7Equal ([string]$ordinaryUiStop[0].status) 'notPerformed' `
    'The regression did not exercise containment after the ordinary UI-session stop was skipped.'
$uiContainmentOperation = Get-HcrOperationRecord `
    ([string]$uiContainmentRun.data.testOperationId)
$uiContainmentEvidence = Read-HcrJsonFile `
    ([string]$uiContainmentOperation.evidenceFile) 'EVIDENCE_NOT_READY'
Assert-Gate7 (Test-HcrEvidenceDocumentV2 `
        $uiContainmentEvidence $uiContainmentOperation).valid `
    'The native validator rejected failure evidence with automatic UI-session containment.'
Assert-Gate7 (@($uiContainmentEvidence.automation.uiTrace | Where-Object {
            [string]$_.stepId -eq 'automatic-ui-session-containment-1' -and
            [string]$_.stepType -eq 'stopUiSession' -and
            [string]$_.status -eq 'passed'
        }).Count -eq 1) `
    'The UI trace did not bind the automatic containment stop.'
$restoredUiState = Read-HcrMockAdapterState
$restoredUiState.stepResults.PSObject.Properties.Remove('assert-review-visible')
Write-HcrMockAdapterState $restoredUiState

$failedStopState = Read-HcrMockAdapterState
$failedStopState.stepResults | Add-Member -NotePropertyName 'stop-ui-session' `
    -NotePropertyValue ([pscustomobject][ordered]@{
        status = 'failed'
        summary = 'The configured ordinary UI-session stop failed.'
        evidence = $null
    }) -Force
Write-HcrMockAdapterState $failedStopState
$failedStopContainmentRun = Invoke-Gate7Tool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    credentialProfile = 'test-profile'
    profilePath = $uiContainmentProfilePath
    artifactPath = $portablePath
})
Assert-Gate7 $failedStopContainmentRun.ok `
    'The mock failed ordinary UI-session stop did not produce auditable evidence.'
Assert-Gate7 ([bool]$failedStopContainmentRun.data.cleanupTriggered) `
    'A failed ordinary UI-session stop did not trigger containment and cleanup.'
Assert-Gate7Equal (@($failedStopContainmentRun.data.automaticAssertions | Where-Object {
            [string]$_.id -eq 'stop-ui-session' -and [string]$_.status -eq 'failed'
        }).Count) 1 `
    'The failed ordinary UI-session stop was not preserved in evidence.'
Assert-Gate7Equal (@($failedStopContainmentRun.data.automaticAssertions | Where-Object {
            [string]$_.id -eq 'automatic-ui-session-containment-1' -and
            [string]$_.status -eq 'passed'
        }).Count) 1 `
    'The failed ordinary UI-session stop did not receive a successful containment attempt.'
$failedStopOperation = Get-HcrOperationRecord `
    ([string]$failedStopContainmentRun.data.testOperationId)
$failedStopEvidence = Read-HcrJsonFile `
    ([string]$failedStopOperation.evidenceFile) 'EVIDENCE_NOT_READY'
Assert-Gate7 (Test-HcrEvidenceDocumentV2 `
        $failedStopEvidence $failedStopOperation).valid `
    'The native validator rejected failed-stop evidence with automatic containment.'
$restoredFailedStopState = Read-HcrMockAdapterState
$restoredFailedStopState.stepResults.PSObject.Properties.Remove('stop-ui-session')
Write-HcrMockAdapterState $restoredFailedStopState

$migrationInput = Get-Content `
    -LiteralPath (Join-Path $PSScriptRoot 'fixtures\v2\migration\test-profile.v1.input.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json
$migrationExpected = Get-Content `
    -LiteralPath (Join-Path $PSScriptRoot 'fixtures\v2\migration\test-profile.v2.expected.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json
$migrationScript = Join-Path $pluginRoot 'mcp\Migrate-TestProfile.ps1'
$standaloneInput = Copy-HcrObject $migrationInput
$standaloneInput.applications[0].PSObject.Properties.Remove('processName')
$standaloneInput.artifact | Add-Member -NotePropertyName sha256 `
    -NotePropertyValue (Get-HcrSha256File $legacyArtifactPath)
$standaloneSourcePath = Join-Path $testRoot 'migration-source.v1.json'
$standaloneDestinationPath = Join-Path $testRoot 'migration-destination.v2.json'
Write-Gate7Json $standaloneSourcePath $standaloneInput
$standaloneSourceHash = Get-HcrSha256File $standaloneSourcePath
$standaloneResult = Invoke-Gate7MigrationCli $migrationScript `
    $standaloneSourcePath $standaloneDestinationPath
Assert-Gate7Equal $standaloneResult.exitCode 0 `
    ('The standalone Windows PowerShell 5.1 migration CLI failed: ' + $standaloneResult.output)
Assert-Gate7 (Test-Path -LiteralPath $standaloneDestinationPath -PathType Leaf) `
    'The standalone migration CLI did not create its destination.'
Assert-Gate7Equal (Get-HcrSha256File $standaloneSourcePath) $standaloneSourceHash `
    'The standalone migration CLI modified its source bytes.'
$standaloneActual = Get-Content -LiteralPath $standaloneDestinationPath `
    -Raw -Encoding UTF8 | ConvertFrom-Json
$standaloneExpected = Convert-HcrProfileV1ToV2 $standaloneInput
Assert-Gate7Equal (ConvertTo-Gate7CanonicalJson $standaloneActual) `
    (ConvertTo-Gate7CanonicalJson $standaloneExpected) `
    'The standalone migration CLI did not emit the deterministic schema-v2 destination.'
$standaloneBytes = [IO.File]::ReadAllBytes($standaloneDestinationPath)
Assert-Gate7 ($standaloneBytes.Length -lt 3 -or -not (
        $standaloneBytes[0] -eq 0xEF -and $standaloneBytes[1] -eq 0xBB -and
        $standaloneBytes[2] -eq 0xBF)) `
    'The standalone migration CLI emitted a UTF-8 BOM.'

$standaloneDestinationHash = Get-HcrSha256File $standaloneDestinationPath
$existingDestinationResult = Invoke-Gate7MigrationCli $migrationScript `
    $standaloneSourcePath $standaloneDestinationPath
Assert-Gate7 ($existingDestinationResult.exitCode -ne 0 -and
        $existingDestinationResult.output -match 'never overwrites an existing destination') `
    'The standalone migration CLI did not fail closed for an existing destination.'
Assert-Gate7Equal (Get-HcrSha256File $standaloneSourcePath) $standaloneSourceHash `
    'The existing-destination rejection modified the source bytes.'
Assert-Gate7Equal (Get-HcrSha256File $standaloneDestinationPath) $standaloneDestinationHash `
    'The existing-destination rejection modified the destination bytes.'

$missingParentDestination = Join-Path $testRoot 'missing-parent\migration.v2.json'
$missingParentResult = Invoke-Gate7MigrationCli $migrationScript `
    $standaloneSourcePath $missingParentDestination
Assert-Gate7 ($missingParentResult.exitCode -ne 0 -and
        $missingParentResult.output -match 'destination parent directory does not exist') `
    'The standalone migration CLI did not fail closed for a missing destination parent.'
Assert-Gate7 (-not (Test-Path -LiteralPath $missingParentDestination)) `
    'The missing-parent migration rejection created a destination.'

$invalidSourcePath = Join-Path $testRoot 'migration-source.invalid.json'
[IO.File]::WriteAllText($invalidSourcePath, '{', (New-Object System.Text.UTF8Encoding($false)))
$invalidSourceHash = Get-HcrSha256File $invalidSourcePath
$invalidSourceDestination = Join-Path $testRoot 'invalid-source-destination.v2.json'
$invalidSourceResult = Invoke-Gate7MigrationCli $migrationScript `
    $invalidSourcePath $invalidSourceDestination
Assert-Gate7 ($invalidSourceResult.exitCode -ne 0 -and
        $invalidSourceResult.output -match 'file is not valid UTF-8 JSON') `
    'The standalone migration CLI did not fail closed for invalid source JSON.'
Assert-Gate7Equal (Get-HcrSha256File $invalidSourcePath) $invalidSourceHash `
    'The invalid-source rejection modified the source bytes.'
Assert-Gate7 (-not (Test-Path -LiteralPath $invalidSourceDestination)) `
    'The invalid-source rejection created a destination.'

$migrationActual = Convert-HcrProfileV1ToV2 $migrationInput
Assert-Gate7Equal `
    ($migrationActual | ConvertTo-Json -Depth 50 -Compress) `
    ($migrationExpected | ConvertTo-Json -Depth 50 -Compress) `
    'The production v1-to-v2 migration is not deterministic.'
$migrationRoundTrip = Convert-HcrLegacyProfileV2ToV1 $migrationActual
Assert-Gate7Equal `
    (ConvertTo-Gate7CanonicalJson $migrationRoundTrip) `
    (ConvertTo-Gate7CanonicalJson $migrationInput) `
    'The deterministic legacy migration cannot return to the preserved v1 lifecycle without semantic drift.'
$migrationWithIdentity = Copy-HcrObject $migrationActual
$migrationWithIdentity.artifact | Add-Member -NotePropertyName sha256 `
    -NotePropertyValue (Get-HcrSha256File $legacyArtifactPath)
$migrationWithIdentity.artifact | Add-Member -NotePropertyName sizeBytes `
    -NotePropertyValue ([int64](Get-Item -LiteralPath $legacyArtifactPath).Length)
$migrationWithIdentityValidation = Test-HcrProfileDocumentV2 $migrationWithIdentity
Assert-Gate7 $migrationWithIdentityValidation.valid `
    'The native schema-v2 validator rejected contract-valid legacy artifact identity fields.'
$invalidLegacyHash = Copy-HcrObject $migrationWithIdentity
$invalidLegacyHash.artifact.sha256 = ('A' * 64)
Assert-Gate7 (-not (Test-HcrProfileDocumentV2 $invalidLegacyHash).valid) `
    'The native schema-v2 validator accepted a non-lowercase legacy artifact hash.'
foreach ($invalidSize in @(0, -1)) {
    $invalidLegacySize = Copy-HcrObject $migrationWithIdentity
    $invalidLegacySize.artifact.sizeBytes = $invalidSize
    Assert-Gate7 (-not (Test-HcrProfileDocumentV2 $invalidLegacySize).valid) `
        "The native schema-v2 validator accepted legacy artifact sizeBytes=$invalidSize."
}
$mismatchedLegacyProfile = Copy-HcrObject $migrationWithIdentity
$mismatchedLegacyProfile.artifact.sizeBytes = `
    ([int64](Get-Item -LiteralPath $legacyArtifactPath).Length + 1)
$mismatchedLegacyProfilePath = Join-Path $testRoot 'legacy-v2-size-mismatch.json'
Write-Gate7Json $mismatchedLegacyProfilePath $mismatchedLegacyProfile
$mismatchedLegacyRun = Invoke-Gate7Tool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    credentialProfile = 'test-profile'
    profilePath = $mismatchedLegacyProfilePath
    artifactPath = $legacyArtifactPath
})
Assert-Gate7Error $mismatchedLegacyRun 'ARTIFACT_PROFILE_MISMATCH' `
    'The legacy schema-v2 runtime did not reject an artifact size mismatch.'

$migrationWithoutProcessInput = Copy-HcrObject $migrationInput
$migrationWithoutProcessInput.applications[0].PSObject.Properties.Remove('processName')
$migrationWithoutProcess = Convert-HcrProfileV1ToV2 $migrationWithoutProcessInput
Assert-Gate7 (Test-HcrProfileDocumentV2 $migrationWithoutProcess).valid `
    'The native schema-v2 validator rejected a migrated legacy application without processName.'
$migrationWithoutProcessRoundTrip = Convert-HcrLegacyProfileV2ToV1 $migrationWithoutProcess
Assert-Gate7Equal (ConvertTo-Gate7CanonicalJson $migrationWithoutProcessRoundTrip) `
    (ConvertTo-Gate7CanonicalJson $migrationWithoutProcessInput) `
    'A legacy application without processName did not preserve v1 round-trip semantics.'
$invalidLegacyProcess = Copy-HcrObject $migrationWithoutProcess
$invalidLegacyProcess.applications[0] | Add-Member -NotePropertyName processName `
    -NotePropertyValue 'invalid process.exe'
Assert-Gate7 (-not (Test-HcrProfileDocumentV2 $invalidLegacyProcess).valid) `
    'The native schema-v2 validator accepted an invalid non-empty legacy processName.'
$migrationWithoutProcessPath = Join-Path $testRoot 'legacy-v2-without-process.json'
Write-Gate7Json $migrationWithoutProcessPath $migrationWithoutProcess
$migrationWithoutProcessRun = Invoke-Gate7Tool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    credentialProfile = 'test-profile'
    profilePath = $migrationWithoutProcessPath
    artifactPath = $legacyArtifactPath
})
Assert-Gate7 $migrationWithoutProcessRun.ok `
    ('The preserved v1 runner rejected a migrated legacy application without processName: ' +
        ((Get-HcrPropertyValue $migrationWithoutProcessRun 'error') | ConvertTo-Json -Depth 10 -Compress))
Write-Gate7Json $legacyV2ProfilePath $migrationActual
$legacyV2Validation = Invoke-Gate7Tool 'validate_test_profile' ([pscustomobject]@{
    profilePath = $legacyV2ProfilePath
})
Assert-Gate7 $legacyV2Validation.ok 'The migrated schema-v2 legacy profile failed native validation.'
$legacyV2Run = Invoke-Gate7Tool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    credentialProfile = 'test-profile'
    profilePath = $legacyV2ProfilePath
    artifactPath = $legacyArtifactPath
})
Assert-Gate7 $legacyV2Run.ok `
    ('The migrated schema-v2 legacy workflow did not retain runnable v1 semantics: ' +
        ((Get-HcrPropertyValue $legacyV2Run 'error') | ConvertTo-Json -Depth 10 -Compress))
$legacyOperation = Get-HcrOperationRecord ([string]$legacyV2Run.data.testOperationId)
Assert-Gate7Equal ([int]$legacyOperation.schemaVersion) 1 `
    'A legacy schema-v2 profile did not preserve the non-synthesized v1 evidence lane.'
$legacyEvidence = Read-HcrJsonFile ([string]$legacyOperation.evidenceFile) 'EVIDENCE_NOT_READY'
Assert-Gate7Equal ([int]$legacyEvidence.schemaVersion) 1 `
    'A legacy schema-v2 run synthesized unsupported evidence-v2 provenance.'

[ordered]@{
    ok = $true
    gate = 7
    assertions = $script:AssertionCount
    tools = $definitions.Count
    v1ToolsPreserved = 16
    v2Tools = 4
    realHostOperations = 0
    realHyperVMutations = 0
    realGuestOperations = 0
    portableDeployments = 0
    webDriverLaunches = 0
    uiOperations = 0
} | ConvertTo-Json -Compress

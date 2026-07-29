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
$testRoot = if ([string]::IsNullOrWhiteSpace($env:HCR_GATE7_TEST_ROOT)) {
    Join-Path $repoRoot ('.artifacts\gate7-tests-' + [Guid]::NewGuid().ToString('N'))
}
else {
    $candidateRoot = [IO.Path]::GetFullPath($env:HCR_GATE7_TEST_ROOT)
    $repoPrefix = [IO.Path]::GetFullPath($repoRoot).TrimEnd('\', '/') + '\'
    if (-not (($candidateRoot.TrimEnd('\', '/') + '\').StartsWith(
                $repoPrefix,
                [StringComparison]::OrdinalIgnoreCase
            )) -or (Test-Path -LiteralPath $candidateRoot)) {
        throw 'The explicit isolated Gate 7 test root is invalid or already exists.'
    }
    $candidateRoot
}
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
$externalPortablePath = Join-Path $testRoot 'ContractSample_1.2.3_windows-x64-portable.zip'
$externalManifestPath = Join-Path $testRoot 'external-portable-manifest.json'
$externalProfilePath = Join-Path $testRoot 'external-portable-profile.json'
$externalUiManifestPath = Join-Path $testRoot 'external-portable-manifest-ui.json'
$externalUiProfilePath = Join-Path $testRoot 'external-portable-profile-ui.json'
$duplicateManifestPath = Join-Path $testRoot 'external-portable-manifest-duplicate.json'
$duplicateProfilePath = Join-Path $testRoot 'external-portable-profile-duplicate.json'
$unknownNestedManifestPath = Join-Path $testRoot 'external-portable-manifest-unknown-nested.json'
$unknownNestedProfilePath = Join-Path $testRoot 'external-portable-profile-unknown-nested.json'
$externalManifestAliasPath = Join-Path $testRoot 'external-portable-manifest-hardlink.json'
$externalManifestAliasProfilePath = Join-Path $testRoot 'external-portable-profile-hardlink.json'
$externalTrailingFixtureProfilePath = Join-Path $testRoot 'external-portable-profile-trailing-fixture.json'
$invalidUtf8ProfilePath = Join-Path $testRoot 'profile-invalid-utf8.json'
$externalCaseArtifactDirectory = Join-Path $testRoot 'external-case-artifact'
$externalFailureExportRoot = Join-Path $testRoot 'external-failure-export'
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

$externalExecutableBytes = [Text.Encoding]::UTF8.GetBytes('synthetic executable bytes')
$externalReadmeBytes = [Text.Encoding]::UTF8.GetBytes('synthetic end-user documentation')
$externalPayloads = [ordered]@{
    'ContractSample.exe' = $externalExecutableBytes
    'README.md' = $externalReadmeBytes
}
$externalStream = [IO.File]::Open(
    $externalPortablePath,
    [IO.FileMode]::Create,
    [IO.FileAccess]::ReadWrite,
    [IO.FileShare]::None
)
try {
    $externalArchive = New-Object IO.Compression.ZipArchive(
        $externalStream,
        [IO.Compression.ZipArchiveMode]::Create,
        $true
    )
    try {
        foreach ($entryName in $externalPayloads.Keys) {
            $entry = $externalArchive.CreateEntry($entryName)
            $entryStream = $entry.Open()
            try {
                $bytes = [byte[]]$externalPayloads[$entryName]
                $entryStream.Write($bytes, 0, $bytes.Length)
            }
            finally { $entryStream.Dispose() }
        }
    }
    finally { $externalArchive.Dispose() }
}
finally { $externalStream.Dispose() }
$externalZipItem = Get-Item -LiteralPath $externalPortablePath
$externalZipSha = (Get-FileHash -LiteralPath $externalPortablePath -Algorithm SHA256).Hash.ToLowerInvariant()
$externalFiles = @($externalPayloads.Keys | ForEach-Object {
    $bytes = [byte[]]$externalPayloads[$_]
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
    [ordered]@{ path=$_; size=[int64]$bytes.Length; sha256=$hash }
})
$readmeIdentity = @($externalFiles | Where-Object { $_.path -ceq 'README.md' })[0]
$documentationIdentity = [ordered]@{
    sourcePath='README.md'; archivePath='README.md'
    size=[int64]$readmeIdentity.size; sha256=[string]$readmeIdentity.sha256
}
$documentationBuilder = New-Object Text.StringBuilder
[void]$documentationBuilder.Append('README.md')
[void]$documentationBuilder.Append([char]0)
[void]$documentationBuilder.Append([string][int64]$readmeIdentity.size)
[void]$documentationBuilder.Append([char]0)
[void]$documentationBuilder.Append([string]$readmeIdentity.sha256)
[void]$documentationBuilder.Append([char]0)
[void]$documentationBuilder.Append('README.md')
[void]$documentationBuilder.Append("`n")
$documentationSha = [Security.Cryptography.SHA256]::Create()
try {
    $documentationDigest = ([BitConverter]::ToString(
        $documentationSha.ComputeHash(
            (New-Object Text.UTF8Encoding($false)).GetBytes(
                $documentationBuilder.ToString()
            )
        )
    )).Replace('-', '').ToLowerInvariant()
}
finally { $documentationSha.Dispose() }
$externalManifest = [ordered]@{
    schemaVersion=2; packageKind='windows-x64-portable'
    distributionBoundary='end-user-complete'
    fileName=$externalZipItem.Name; version='1.2.3'; architecture='x86_64'
    entrypoint='ContractSample.exe'; distributionMode='fixed-portable'
    dataRoot='data/'; unsigned=$true
    newZipSize=[int64]$externalZipItem.Length; newZipSha256=$externalZipSha
    documentationFiles=@($documentationIdentity)
    documentationSourceCommit=('4' * 40); documentationSourceTree=('5' * 40)
    documentationFileCount=1; documentationPayloadSize=[int64]$readmeIdentity.size
    documentationInventoryDigest=$documentationDigest
    runtimeSourceCommit=('9' * 40); runtimeSourceTree=('a' * 40)
    packagingCommit=('b' * 40); packagingTree=('c' * 40)
    oldRuntimeInventoryDigest=('7' * 64); newRuntimeInventoryDigest=('7' * 64)
    sbom=[ordered]@{
        path='SBOM.cdx.json'; size=1; sha256=('6' * 64)
        derivedFromPath='licenses/SBOM.cdx.json'
    }
    webView2=[ordered]@{
        trackedManifest='WebView2.manifest.json'
        trackedManifestSha256=('d' * 64)
        version='138.0.3351.121'
        architecture='x64'
        rootDirectory='WebView2'
        archiveSize=1
        archiveSha256=('e' * 64)
        fileCount=1
        totalSize=1
    }
    files=$externalFiles
}
Write-Gate7Json $externalManifestPath $externalManifest
$externalManifestItem = Get-Item -LiteralPath $externalManifestPath
$externalManifestSha = (Get-FileHash -LiteralPath $externalManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
$externalProfile = [ordered]@{
    schemaVersion=2; id='external-neutral-runtime'
    workflowKind='portableAutomation'; platform='windows-x64'
    baselineType='stock-clean'
    artifact=[ordered]@{
        packageKind='portableZip'; fileNamePattern=$externalZipItem.Name
        architecture='x64'; sha256=$externalZipSha
        sizeBytes=[int64]$externalZipItem.Length
        requiredDistributionBoundary='end-user-complete'
        portableManifestSource='externalProfileRelative'
        portableManifestRelativePath=$externalManifestItem.Name
        portableManifestSizeBytes=[int64]$externalManifestItem.Length
        portableManifestSha256=$externalManifestSha
    }
    fixtures=@()
    applications=@([ordered]@{
        id='app'; packageKind='portableZip'
        executableRelativePath='ContractSample.exe'
        dataDirectoryRelativePath='data'; processName='ContractSample'
    })
    steps=@(
        [ordered]@{id='stage';type='stageArtifact';timeoutSeconds=120;required=$true},
        [ordered]@{id='deploy';type='deployPortable';application='app';timeoutSeconds=120;required=$true},
        [ordered]@{id='launch';type='launchApplication';application='app';timeoutSeconds=120;required=$true},
        [ordered]@{id='stop';type='stopApplication';application='app';timeoutSeconds=120;required=$true}
    )
    cleanupSteps=@([ordered]@{
        id='cleanup-stop';type='stopApplication';application='app'
        timeoutSeconds=30;required=$true
    })
    manualAssertions=@()
}
Write-Gate7Json $externalProfilePath $externalProfile

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

$runtimeInstallRoot = Join-Path $testRoot 'runtime-install'
$runtimeInstallPluginDirectory = Join-Path $runtimeInstallRoot '.codex-plugin'
$runtimeInstallMcpDirectory = Join-Path $runtimeInstallRoot 'mcp'
[void](New-Item -ItemType Directory -Path $runtimeInstallPluginDirectory)
[void](New-Item -ItemType Directory -Path $runtimeInstallMcpDirectory)
$runtimeInstallPluginPath = Join-Path $runtimeInstallPluginDirectory 'plugin.json'
$runtimeInstallPayloadPath = Join-Path $runtimeInstallMcpDirectory 'runtime.ps1'
Write-Gate7Json $runtimeInstallPluginPath ([ordered]@{
    name = 'hyperv-clean-room'
    version = '0.3.1+codex.20260729090000'
})
[IO.File]::WriteAllText(
    $runtimeInstallPayloadPath,
    "runtime-payload`n",
    (New-Object Text.UTF8Encoding($false))
)
$runtimeInstallRows = @(
    $runtimeInstallPluginPath,
    $runtimeInstallPayloadPath
) | ForEach-Object {
    $item = Get-Item -LiteralPath $_
    [pscustomobject][ordered]@{
        path = $item.FullName.Substring(
            $runtimeInstallRoot.TrimEnd('\', '/').Length + 1
        ).Replace('\', '/')
        size = [int64]$item.Length
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).
            Hash.ToLowerInvariant()
    }
}
$runtimeInstallationId = [Guid]::NewGuid().ToString()
$runtimeOwnershipPath = Join-Path `
    $runtimeInstallPluginDirectory `
    'install-ownership.json'
Write-Gate7Json (
    $runtimeOwnershipPath
) ([ordered]@{
    installationId = $runtimeInstallationId
    owner = 'hyperv-clean-room-installer/v1'
    pluginName = 'hyperv-clean-room'
    schemaVersion = 1
    targetRoot = $runtimeInstallRoot
})
Write-Gate7Json (
    Join-Path $runtimeInstallPluginDirectory 'install-manifest.json'
) ([ordered]@{
    schemaVersion = 1
    pluginName = 'hyperv-clean-room'
    installationId = $runtimeInstallationId
    sourceRoot = $runtimeInstallRoot
    targetRoot = $runtimeInstallRoot
    sourceVersion = '0.3.1+codex.20260729090000'
    sourceCommit = ('e' * 40)
    cachebuster = '20260729090000'
    installedAtUtc = [DateTime]::UtcNow.ToString('o')
    files = @($runtimeInstallRows)
})
$originalPluginRoot = $script:HcrPluginRoot
try {
    $script:HcrPluginRoot = $runtimeInstallRoot
    $verifiedRuntimeIdentity = Get-HcrV2RuntimeIdentity
    $expectedRuntimeRows = @($runtimeInstallRows | ForEach-Object {
        "$($_.path)`t$($_.size)`t$($_.sha256)"
    } | Sort-Object)
    Assert-Gate7Equal ([string]$verifiedRuntimeIdentity.installedInventorySha256) `
        (Get-HcrSha256Text ($expectedRuntimeRows -join "`n")) `
        'Runtime identity did not rebind the exact installed bytes.'

    $wrongRuntimeOwnership = Read-HcrJsonFile `
        $runtimeOwnershipPath `
        'RUNTIME_PROVENANCE_INVALID'
    $wrongRuntimeOwnership.owner = 'wrong-owner/v1'
    Write-Gate7Json $runtimeOwnershipPath $wrongRuntimeOwnership
    $wrongRuntimeOwnerCode = $null
    try { [void](Get-HcrV2RuntimeIdentity) }
    catch {
        $wrongRuntimeOwnerCode = [string](Get-HcrExceptionData $_.Exception).code
    }
    Assert-Gate7Equal $wrongRuntimeOwnerCode 'RUNTIME_PROVENANCE_INVALID' `
        'Runtime identity accepted a non-installer ownership marker.'
    $wrongRuntimeOwnership.owner = 'hyperv-clean-room-installer/v1'
    Write-Gate7Json $runtimeOwnershipPath $wrongRuntimeOwnership

    [IO.File]::WriteAllText(
        $runtimeInstallPayloadPath,
        "tampered-runtime-payload`n",
        (New-Object Text.UTF8Encoding($false))
    )
    $tamperedRuntimeCode = $null
    try { [void](Get-HcrV2RuntimeIdentity) }
    catch { $tamperedRuntimeCode = [string](Get-HcrExceptionData $_.Exception).code }
    Assert-Gate7Equal $tamperedRuntimeCode 'RUNTIME_PROVENANCE_INVALID' `
        'Runtime identity trusted a manifest after installed payload mutation.'

    [IO.File]::WriteAllText(
        $runtimeInstallPayloadPath,
        "runtime-payload`n",
        (New-Object Text.UTF8Encoding($false))
    )
    $runtimeUnexpectedPath = Join-Path $runtimeInstallRoot 'unexpected.txt'
    [IO.File]::WriteAllText(
        $runtimeUnexpectedPath,
        "unexpected`n",
        (New-Object Text.UTF8Encoding($false))
    )
    $runtimeClosureCode = $null
    try { [void](Get-HcrV2RuntimeIdentity) }
    catch { $runtimeClosureCode = [string](Get-HcrExceptionData $_.Exception).code }
    Assert-Gate7Equal $runtimeClosureCode 'RUNTIME_PROVENANCE_INVALID' `
        'Runtime identity accepted a file outside the installed manifest closure.'

    Move-Item -LiteralPath $runtimeUnexpectedPath -Destination (
        Join-Path $testRoot 'runtime-unexpected-stashed.txt'
    )
    Move-Item -LiteralPath $runtimeInstallPayloadPath -Destination (
        Join-Path $testRoot 'runtime-payload-removed.ps1'
    )
    $runtimeMissingCode = $null
    try { [void](Get-HcrV2RuntimeIdentity) }
    catch { $runtimeMissingCode = [string](Get-HcrExceptionData $_.Exception).code }
    Assert-Gate7Equal $runtimeMissingCode 'RUNTIME_PROVENANCE_INVALID' `
        'Runtime identity trusted a manifest after an installed payload file disappeared.'
}
finally {
    $script:HcrPluginRoot = $originalPluginRoot
}

$pluginManifest = Get-Content -LiteralPath (Join-Path $pluginRoot '.codex-plugin\plugin.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
Assert-Gate7 ([string]$pluginManifest.version -match '^0\.3\.1(?:\+codex\.[a-z0-9]+(?:-[a-z0-9]+)*)?$') `
    'The loaded Gate 7 runtime does not expose the 0.3.1 patch version.'
$runtimeCatalog = Get-Content -LiteralPath (Join-Path $repoRoot 'contracts\v2\tool-catalog.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
Assert-Gate7Equal ([string]$runtimeCatalog.currentRuntimeVersion) '0.3.1' `
    'The tool catalog did not advance with the loaded runtime.'
foreach ($schemaName in @(
        'evidence.schema.json', 'operation-envelope.schema.json',
        'portable-manifest.schema.json', 'test-profile.schema.json',
        'vm-network-plan.schema.json', 'vm-power-plan.schema.json',
        'webdriver-manifest.schema.json'
    )) {
    $authoritative = [IO.File]::ReadAllBytes((Join-Path $repoRoot (Join-Path 'contracts\v2\schemas' $schemaName)))
    $installed = [IO.File]::ReadAllBytes((Join-Path $pluginRoot (Join-Path 'schemas\v2' $schemaName)))
    Assert-Gate7 ([Convert]::ToBase64String($authoritative) -eq [Convert]::ToBase64String($installed)) `
        "The installed schema-v2 copy drifted from the authority: $schemaName"
}

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

$nonElevatedPowerState = Read-HcrMockAdapterState
$nonElevatedPowerState.host.elevated = $false
Write-HcrMockAdapterState $nonElevatedPowerState
$powerPlan = Invoke-Gate7Tool 'plan_vm_power' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    action = 'start'
}) -EnvelopeSchemaVersion 2
Assert-Gate7 $powerPlan.ok 'Power planning failed.'
Assert-Gate7Equal ([string]$powerPlan.data.plan.planKind) 'vmPower' `
    'Power planning returned the wrong plan kind.'
$elevatedPowerState = Read-HcrMockAdapterState
$elevatedPowerState.host.elevated = $true
Write-HcrMockAdapterState $elevatedPowerState
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

$nonElevatedNetworkState = Read-HcrMockAdapterState
$nonElevatedNetworkState.host.elevated = $false
Write-HcrMockAdapterState $nonElevatedNetworkState
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
$elevatedNetworkState = Read-HcrMockAdapterState
$elevatedNetworkState.host.elevated = $true
Write-HcrMockAdapterState $elevatedNetworkState
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

$externalUiManifest = Copy-HcrObject ([pscustomobject]$externalManifest)
$externalUiManifest | Add-Member `
    -NotePropertyName webView2 `
    -NotePropertyValue ([pscustomobject][ordered]@{
    trackedManifest = 'WebView2.manifest.json'
    trackedManifestSha256 = ('d' * 64)
    version = [string]$profile.webDriver.browserVersion
    architecture = 'x64'
    rootDirectory = 'WebView2'
    archiveSize = 1
    archiveSha256 = ('e' * 64)
    fileCount = 1
    totalSize = 1
}) `
    -Force
Write-Gate7Json $externalUiManifestPath $externalUiManifest
$externalUiManifestItem = Get-Item -LiteralPath $externalUiManifestPath
$externalUiManifestSha = (Get-FileHash `
    -LiteralPath $externalUiManifestPath `
    -Algorithm SHA256).Hash.ToLowerInvariant()
$externalUiProfile = Copy-HcrObject ([pscustomobject]$externalProfile)
$externalUiProfile.id = 'external-ui-runtime'
$externalUiProfile.artifact.portableManifestRelativePath =
    $externalUiManifestItem.Name
$externalUiProfile.artifact.portableManifestSizeBytes =
    [int64]$externalUiManifestItem.Length
$externalUiProfile.artifact.portableManifestSha256 = $externalUiManifestSha
$externalUiProfile | Add-Member `
    -NotePropertyName webDriver `
    -NotePropertyValue (Copy-HcrObject $profile.webDriver) `
    -Force
$externalUiProfile.webDriver.driverVersion = '138.0.3351.122'
$externalUiProfile.steps = @(
    [pscustomobject][ordered]@{
        id='stage';type='stageArtifact';timeoutSeconds=120;required=$true
    },
    [pscustomobject][ordered]@{
        id='deploy';type='deployPortable';application='app'
        timeoutSeconds=120;required=$true
    },
    [pscustomobject][ordered]@{
        id='launch';type='launchApplication';application='app'
        timeoutSeconds=120;required=$true
    },
    [pscustomobject][ordered]@{
        id='driver';type='acquireWebDriver';timeoutSeconds=120;required=$true
    },
    [pscustomobject][ordered]@{
        id='ui-start';type='startUiSession';application='app'
        timeoutSeconds=60;required=$true
    },
    [pscustomobject][ordered]@{
        id='ui-click';type='uiClick';testId='open-settings'
        timeoutSeconds=30;required=$true
    },
    [pscustomobject][ordered]@{
        id='ui-stop';type='stopUiSession';timeoutSeconds=30;required=$true
    },
    [pscustomobject][ordered]@{
        id='stop';type='stopApplication';application='app'
        timeoutSeconds=30;required=$true
    }
)
Write-Gate7Json $externalUiProfilePath $externalUiProfile

$profileValidation = Invoke-Gate7Tool 'validate_test_profile' ([pscustomobject]@{
    profilePath = $profilePath
})
Assert-Gate7 $profileValidation.ok `
    ('The valid schema-v2 profile failed exact-version validation: ' +
        ((Get-HcrPropertyValue $profileValidation 'error') | ConvertTo-Json -Depth 10 -Compress))
$profileArrayScalarCases = [ordered]@{
    fixtures = $profile.fixtures[0]
    applications = $profile.applications[0]
    steps = $profile.steps[0]
    cleanupSteps = $externalProfile.cleanupSteps[0]
    manualAssertions = $profile.manualAssertions[0]
}
foreach ($profileArrayField in $profileArrayScalarCases.Keys) {
    $scalarArrayProfile = Copy-HcrObject ([pscustomobject]$profile)
    $scalarArrayProfile.$profileArrayField =
        Copy-HcrObject $profileArrayScalarCases[$profileArrayField]
    $scalarArrayValidation = Test-HcrProfileDocumentV2 $scalarArrayProfile
    $expectedArrayError = '$.' + $profileArrayField + ' must be an array.'
    Assert-Gate7 (
        -not $scalarArrayValidation.valid -and
        @($scalarArrayValidation.errors | Where-Object {
                [string]$_ -ceq $expectedArrayError
            }).Count -eq 1
    ) ("The native schema-v2 validator accepted or misclassified object-valued " +
        "$profileArrayField.")
}
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
$invalidPortProfile = Copy-HcrObject ([pscustomobject]$profile)
$invalidPortStep = [pscustomobject][ordered]@{
    id = 'assert-port-bound'
    type = 'assertPort'
    port = 70000
    timeoutSeconds = 30
}
$invalidPortProfile.steps = @(
    @($invalidPortProfile.steps | Select-Object -First 4)
    $invalidPortStep
    @($invalidPortProfile.steps | Select-Object -Skip 4)
)
$invalidPortProfilePath = Join-Path $testRoot 'portable-invalid-port.json'
Write-Gate7Json $invalidPortProfilePath $invalidPortProfile
$invalidPortToolValidation = Invoke-Gate7Tool 'validate_test_profile' ([pscustomobject]@{
    profilePath = $invalidPortProfilePath
})
Assert-Gate7Error $invalidPortToolValidation 'PROFILE_INVALID' `
    'validate_test_profile accepted a schema-v2 assertPort above 65535.'
$stringPortProfile = Copy-HcrObject $invalidPortProfile
$stringPortProfile.steps[4].port = '443'
$stringPortValidation = Test-HcrProfileDocumentV2 $stringPortProfile
Assert-Gate7 (-not $stringPortValidation.valid) `
    'The native schema-v2 validator accepted a string assertPort value.'
$validPortProfile = Copy-HcrObject $invalidPortProfile
$validPortProfile.steps[4].port = 443
$validPortValidation = Test-HcrProfileDocumentV2 $validPortProfile
Assert-Gate7 $validPortValidation.valid `
    'The native schema-v2 validator rejected an in-range integer assertPort value.'
$invalidCleanupTimeoutProfile = Copy-HcrObject ([pscustomobject]$profile)
$invalidCleanupTimeoutProfile.cleanupSteps = @([pscustomobject][ordered]@{
    id = 'cleanup-invalid-timeout'
    type = 'wait'
    timeoutSeconds = 'abc'
})
$invalidCleanupTimeoutPath = Join-Path $testRoot 'portable-invalid-cleanup-timeout.json'
Write-Gate7Json $invalidCleanupTimeoutPath $invalidCleanupTimeoutProfile
$invalidCleanupTimeoutValidation = Invoke-Gate7Tool 'validate_test_profile' ([pscustomobject]@{
    profilePath = $invalidCleanupTimeoutPath
})
Assert-Gate7Error $invalidCleanupTimeoutValidation 'PROFILE_INVALID' `
    'A non-integer cleanup timeout escaped as an internal validator failure.'
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

$externalNativeValidation = Read-AndValidate-HcrProfile $externalProfilePath
Assert-Gate7 $externalNativeValidation.valid `
    ('The mock external portable profile failed native validation: ' +
        ($externalNativeValidation.errors -join '; '))
Assert-Gate7Equal ([string]$externalNativeValidation.sha256) `
    (Get-HcrSha256File $externalProfilePath) `
    'Profile validation did not retain the exact bytes that were parsed.'

$invalidUtf8Prefix = [Text.Encoding]::UTF8.GetBytes(
    '{"schemaVersion":2,"description":"'
)
$invalidUtf8Suffix = [Text.Encoding]::UTF8.GetBytes('"}')
[IO.File]::WriteAllBytes(
    $invalidUtf8ProfilePath,
    [byte[]]@($invalidUtf8Prefix + [byte[]](0xC3,0x28) + $invalidUtf8Suffix)
)
$invalidUtf8Rejected = $false
try {
    [void](Read-HcrJsonDocument $invalidUtf8ProfilePath 'PROFILE_INVALID' 4MB)
}
catch {
    $invalidUtf8Rejected = $_.Exception.Message -eq
        'The file is not valid UTF-8 JSON.'
}
Assert-Gate7 $invalidUtf8Rejected `
    'The shared JSON reader accepted or misclassified malformed UTF-8 bytes.'

$trailingFixtureProfile = Copy-HcrObject ([pscustomobject]$externalProfile)
$trailingFixtureProfile.fixtures = @([pscustomobject][ordered]@{
    id='manifest-alias'
    sourceRelativePath=([string]$externalManifestItem.Name + '.')
    sizeBytes=[int64]$externalManifestItem.Length
    sha256=$externalManifestSha
    mediaType='application/json'
})
Write-Gate7Json $externalTrailingFixtureProfilePath $trailingFixtureProfile
$trailingFixtureValidation = Invoke-Gate7Tool 'validate_test_profile' ([pscustomobject]@{
    profilePath = $externalTrailingFixtureProfilePath
})
Assert-Gate7Error $trailingFixtureValidation 'PROFILE_INVALID' `
    'The external profile accepted a Windows-aliased trailing-dot fixture path.'

[void](New-Item -ItemType HardLink `
    -Path $externalManifestAliasPath `
    -Target $externalManifestPath)
$aliasFixtureProfile = Copy-HcrObject ([pscustomobject]$externalProfile)
$aliasFixtureProfile.fixtures = @([pscustomobject][ordered]@{
    id='manifest-alias'
    sourceRelativePath=[IO.Path]::GetFileName($externalManifestAliasPath)
    sizeBytes=[int64]$externalManifestItem.Length
    sha256=$externalManifestSha
    mediaType='application/json'
})
Write-Gate7Json $externalManifestAliasProfilePath $aliasFixtureProfile
$aliasFixtureValidation = Invoke-Gate7Tool 'validate_test_profile' ([pscustomobject]@{
    profilePath = $externalManifestAliasProfilePath
})
Assert-Gate7Error $aliasFixtureValidation 'PROFILE_INVALID' `
    'The external profile accepted a fixture resolving to the sidecar file identity.'

[void](New-Item -ItemType Directory -Path $externalCaseArtifactDirectory)
$externalCaseArtifactPath = Join-Path `
    $externalCaseArtifactDirectory `
    ([string]$externalZipItem.Name).ToUpperInvariant()
Copy-Item -LiteralPath $externalPortablePath -Destination $externalCaseArtifactPath
$caseMismatchedRun = Invoke-Gate7Tool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    credentialProfile = 'test-profile'
    profilePath = $externalProfilePath
    artifactPath = $externalCaseArtifactPath
})
Assert-Gate7Error $caseMismatchedRun 'ARTIFACT_PROFILE_MISMATCH' `
    'The external runtime accepted a case-insensitive ZIP leaf mismatch.'

$validExternalJson = [IO.File]::ReadAllText(
    $externalManifestPath,
    (New-Object Text.UTF8Encoding($false, $true))
)
$duplicateExternalJson = $validExternalJson.Replace(
    '"schemaVersion":2,',
    '"schemaVersion":2,"schemaVersion":2,'
)
[IO.File]::WriteAllText(
    $duplicateManifestPath,
    $duplicateExternalJson,
    (New-Object Text.UTF8Encoding($false))
)
$duplicateManifestItem = Get-Item -LiteralPath $duplicateManifestPath
$duplicateManifestSha = (Get-FileHash -LiteralPath $duplicateManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
$duplicateProfile = Copy-HcrObject ([pscustomobject]$externalProfile)
$duplicateProfile.artifact.portableManifestRelativePath = $duplicateManifestItem.Name
$duplicateProfile.artifact.portableManifestSizeBytes = [int64]$duplicateManifestItem.Length
$duplicateProfile.artifact.portableManifestSha256 = $duplicateManifestSha
Write-Gate7Json $duplicateProfilePath $duplicateProfile
$duplicateValidation = Invoke-Gate7Tool 'validate_test_profile' ([pscustomobject]@{
    profilePath = $duplicateProfilePath
})
Assert-Gate7Error $duplicateValidation 'PROFILE_INVALID' `
    'The external sidecar parser accepted a duplicate JSON property.'

foreach ($scalarCase in @(
        [pscustomobject]@{
            name = 'schemaVersion'
            value = '2'
        },
        [pscustomobject]@{
            name = 'unsigned'
            value = 'true'
        }
    )) {
    $scalarManifest = Copy-HcrObject ([pscustomobject]$externalManifest)
    $scalarManifest.($scalarCase.name) = $scalarCase.value
    $scalarManifestPath = Join-Path `
        $testRoot `
        "external-portable-manifest-$($scalarCase.name)-string.json"
    Write-Gate7Json $scalarManifestPath $scalarManifest
    $scalarManifestItem = Get-Item -LiteralPath $scalarManifestPath
    $scalarManifestSha = (Get-FileHash `
        -LiteralPath $scalarManifestPath `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    $scalarProfile = Copy-HcrObject ([pscustomobject]$externalProfile)
    $scalarProfile.artifact.portableManifestRelativePath =
        $scalarManifestItem.Name
    $scalarProfile.artifact.portableManifestSizeBytes =
        [int64]$scalarManifestItem.Length
    $scalarProfile.artifact.portableManifestSha256 = $scalarManifestSha
    $scalarProfilePath = Join-Path `
        $testRoot `
        "external-portable-profile-$($scalarCase.name)-string.json"
    Write-Gate7Json $scalarProfilePath $scalarProfile
    $scalarValidation = Invoke-Gate7Tool `
        'validate_test_profile' `
        ([pscustomobject]@{ profilePath = $scalarProfilePath })
    Assert-Gate7Error $scalarValidation 'PROFILE_INVALID' `
        "Native validation accepted string-typed $($scalarCase.name)."
}

foreach ($shapeCase in @(
        'files-object',
        'documentationFiles-object',
        'webView-files-object',
        'fileName-number',
        'entrypoint-number',
        'file-path-number',
        'documentation-sourcePath-number',
        'documentation-archivePath-number'
    )) {
    $shapeManifest = Copy-HcrObject ([pscustomobject]$externalManifest)
    switch ($shapeCase) {
        'files-object' {
            $shapeManifest.files = $shapeManifest.files[0]
        }
        'documentationFiles-object' {
            $shapeManifest.documentationFiles = $shapeManifest.documentationFiles[0]
        }
        'webView-files-object' {
            $shapeManifest.webView2 | Add-Member `
                -NotePropertyName files `
                -NotePropertyValue $shapeManifest.files[0] `
                -Force
        }
        'fileName-number' {
            $shapeManifest.fileName = 123
        }
        'entrypoint-number' {
            $shapeManifest.entrypoint = 123
        }
        'file-path-number' {
            $shapeManifest.files[0].path = 123
        }
        'documentation-sourcePath-number' {
            $shapeManifest.documentationFiles[0].sourcePath = 123
        }
        'documentation-archivePath-number' {
            $shapeManifest.documentationFiles[0].archivePath = 123
        }
    }
    $shapeManifestPath = Join-Path `
        $testRoot `
        "external-portable-manifest-$shapeCase.json"
    Write-Gate7Json $shapeManifestPath $shapeManifest
    $shapeManifestItem = Get-Item -LiteralPath $shapeManifestPath
    $shapeManifestSha = (Get-FileHash `
        -LiteralPath $shapeManifestPath `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    $shapeProfile = Copy-HcrObject ([pscustomobject]$externalProfile)
    $shapeProfile.artifact.portableManifestRelativePath =
        $shapeManifestItem.Name
    $shapeProfile.artifact.portableManifestSizeBytes =
        [int64]$shapeManifestItem.Length
    $shapeProfile.artifact.portableManifestSha256 = $shapeManifestSha
    $shapeProfilePath = Join-Path `
        $testRoot `
        "external-portable-profile-$shapeCase.json"
    Write-Gate7Json $shapeProfilePath $shapeProfile
    $shapeValidation = Invoke-Gate7Tool 'validate_test_profile' ([pscustomobject]@{
        profilePath = $shapeProfilePath
    })
    Assert-Gate7Error $shapeValidation 'PROFILE_INVALID' `
        "Native validation accepted schema-invalid external manifest shape $shapeCase."
}

$unknownNestedManifest = Copy-HcrObject ([pscustomobject]$externalManifest)
$unknownNestedManifest.sbom | Add-Member `
    -NotePropertyName unexpected `
    -NotePropertyValue $true `
    -Force
Write-Gate7Json $unknownNestedManifestPath $unknownNestedManifest
$unknownNestedManifestItem = Get-Item -LiteralPath $unknownNestedManifestPath
$unknownNestedManifestSha = (Get-FileHash `
    -LiteralPath $unknownNestedManifestPath `
    -Algorithm SHA256).Hash.ToLowerInvariant()
$unknownNestedProfile = Copy-HcrObject ([pscustomobject]$externalProfile)
$unknownNestedProfile.artifact.portableManifestRelativePath =
    $unknownNestedManifestItem.Name
$unknownNestedProfile.artifact.portableManifestSizeBytes =
    [int64]$unknownNestedManifestItem.Length
$unknownNestedProfile.artifact.portableManifestSha256 =
    $unknownNestedManifestSha
Write-Gate7Json $unknownNestedProfilePath $unknownNestedProfile
$unknownNestedValidation = Invoke-Gate7Tool 'validate_test_profile' ([pscustomobject]@{
    profilePath = $unknownNestedProfilePath
})
Assert-Gate7Error $unknownNestedValidation 'PROFILE_INVALID' `
    'Native external sidecar validation accepted an unknown nested provenance field.'

$externalRun = Invoke-Gate7Tool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    credentialProfile = 'test-profile'
    profilePath = $externalProfilePath
    artifactPath = $externalPortablePath
})
Assert-Gate7 $externalRun.ok `
    ('The external mock portable workflow failed: ' +
        ((Get-HcrPropertyValue $externalRun 'error') | ConvertTo-Json -Depth 20 -Compress))
Assert-Gate7Equal ([string]$externalRun.data.machineStatus) 'passed' `
    'The non-UI external mock run did not derive machineStatus=passed.'
Assert-Gate7Equal ([string]$externalRun.data.overallStatus) 'passed' `
    'The assertion-complete external mock run did not derive overallStatus=passed.'
$externalOperation = Get-HcrOperationRecord ([string]$externalRun.data.testOperationId)
$externalEvidence = Read-HcrJsonFile ([string]$externalOperation.evidenceFile) 'EVIDENCE_NOT_READY'
Assert-Gate7Equal ([string]$externalEvidence.evidenceKind) 'externalPortable' `
    'The external evidence structural discriminator is missing.'
Assert-Gate7Equal ([string]$externalEvidence.runtime.pluginBaseVersion) '0.3.1' `
    'External evidence did not bind the 0.3.1 runtime base.'
Assert-Gate7Equal ([string]$externalEvidence.candidate.packagingCommit) ('b' * 40) `
    'External evidence fabricated or lost the manifest packaging commit.'
Assert-Gate7Equal ([string]$externalEvidence.candidate.portableZipSourceSha256) `
    ([string]$externalEvidence.candidate.portableZipGuestSha256) `
    'External evidence did not independently rebind source and guest ZIP hashes.'
Assert-Gate7Equal ([string]$externalEvidence.candidate.portableManifestSourceSha256) `
    ([string]$externalEvidence.candidate.portableManifestGuestSha256) `
    'External evidence did not independently rebind source and guest sidecar hashes.'
Assert-Gate7 ($null -eq $externalEvidence.candidate.webDriverManifestSha256 -and
        -not [bool]$externalEvidence.automation.uiRequired -and
        $null -eq $externalEvidence.automation.fixedWebView2Version -and
        $null -eq $externalEvidence.automation.webDriverVersion) `
    'The non-UI external branch fabricated a conditional UI identity.'
$externalEvidenceValidation = Invoke-Gate7Tool 'validate_evidence' ([pscustomobject]@{
    evidencePath = [string]$externalOperation.evidenceFile
})
Assert-Gate7 $externalEvidenceValidation.ok `
    'Generated external schema-v2 evidence failed native validation.'

$deploymentDriftState = Read-HcrMockAdapterState
$deploymentDriftState | Add-Member -NotePropertyName portableActiveDeploymentOverride `
    -NotePropertyValue ([pscustomobject][ordered]@{
        applicationId = 'contract-sample'
        deploymentId = [Guid]::NewGuid().ToString()
        deploymentFingerprint = ('f' * 64)
        slotId = 'concurrent-replacement-slot'
    }) -Force
Write-HcrMockAdapterState $deploymentDriftState
$deploymentDriftRun = Invoke-Gate7Tool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    credentialProfile = 'test-profile'
    profilePath = $externalProfilePath
    artifactPath = $externalPortablePath
})
Assert-Gate7 $deploymentDriftRun.ok `
    'Concurrent portable deployment drift did not produce auditable failure evidence.'
Assert-Gate7Equal ([string]$deploymentDriftRun.data.machineStatus) 'failed' `
    'Concurrent portable deployment drift did not fail the machine result.'
$deploymentDriftAssertions = @($deploymentDriftRun.data.automaticAssertions | Where-Object {
        [string]$_.id -eq 'launch'
    })
Assert-Gate7Equal $deploymentDriftAssertions.Count 1 `
    'Concurrent portable deployment drift did not bind the launch assertion.'
Assert-Gate7 (
    [string]$deploymentDriftAssertions[0].status -eq 'failed' -and
    @($deploymentDriftAssertions[0].observations | Where-Object {
            [string]$_.name -eq 'errorcode' -and
            [string]$_.value -eq 'PORTABLE_DEPLOYMENT_DRIFT'
        }).Count -eq 1
) 'The launch did not fail closed with PORTABLE_DEPLOYMENT_DRIFT.'
$deploymentDriftOperation = Get-HcrOperationRecord `
    ([string]$deploymentDriftRun.data.testOperationId)
$deploymentDriftEvidence = Read-HcrJsonFile `
    ([string]$deploymentDriftOperation.evidenceFile) 'EVIDENCE_NOT_READY'
Assert-Gate7 (Test-HcrEvidenceDocumentV2 `
        $deploymentDriftEvidence $deploymentDriftOperation).valid `
    'The native validator rejected concurrent-deployment-drift evidence.'
$restoredDeploymentDriftState = Read-HcrMockAdapterState
$restoredDeploymentDriftState.PSObject.Properties.Remove(
    'portableActiveDeploymentOverride'
)
Write-HcrMockAdapterState $restoredDeploymentDriftState

$entrypointDriftState = Read-HcrMockAdapterState
$entrypointDriftState | Add-Member `
    -NotePropertyName portableEntrypointDriftOnLaunch `
    -NotePropertyValue $true `
    -Force
Write-HcrMockAdapterState $entrypointDriftState
$entrypointDriftRun = Invoke-Gate7Tool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    credentialProfile = 'test-profile'
    profilePath = $externalProfilePath
    artifactPath = $externalPortablePath
})
Assert-Gate7 $entrypointDriftRun.ok `
    'Portable entrypoint drift did not produce auditable failure evidence.'
Assert-Gate7Equal ([string]$entrypointDriftRun.data.machineStatus) 'failed' `
    'Portable entrypoint drift did not fail the machine result.'
$entrypointDriftAssertions = @(
    $entrypointDriftRun.data.automaticAssertions |
        Where-Object { [string]$_.id -eq 'launch' }
)
Assert-Gate7Equal $entrypointDriftAssertions.Count 1 `
    'Portable entrypoint drift did not bind the launch assertion.'
Assert-Gate7 (
    [string]$entrypointDriftAssertions[0].status -eq 'failed' -and
    @($entrypointDriftAssertions[0].observations | Where-Object {
            [string]$_.name -eq 'errorcode' -and
            [string]$_.value -eq 'PORTABLE_ENTRYPOINT_DRIFT'
        }).Count -eq 1
) 'The launch did not fail closed with PORTABLE_ENTRYPOINT_DRIFT.'
$entrypointDriftOperation = Get-HcrOperationRecord `
    ([string]$entrypointDriftRun.data.testOperationId)
$entrypointDriftEvidence = Read-HcrJsonFile `
    ([string]$entrypointDriftOperation.evidenceFile) `
    'EVIDENCE_NOT_READY'
Assert-Gate7 (Test-HcrEvidenceDocumentV2 `
        $entrypointDriftEvidence $entrypointDriftOperation).valid `
    'The native validator rejected portable-entrypoint-drift evidence.'
$restoredEntrypointDriftState = Read-HcrMockAdapterState
$restoredEntrypointDriftState.PSObject.Properties.Remove(
    'portableEntrypointDriftOnLaunch'
)
Write-HcrMockAdapterState $restoredEntrypointDriftState

$unknownRuntimeEvidence = Copy-HcrObject $externalEvidence
$unknownRuntimeEvidence.runtime | Add-Member `
    -NotePropertyName unexpected `
    -NotePropertyValue $true `
    -Force
$unknownRuntimeValidation = Test-HcrEvidenceDocumentV2 `
    $unknownRuntimeEvidence `
    $externalOperation
Assert-Gate7 (-not $unknownRuntimeValidation.valid) `
    'Native external evidence validation accepted an unknown runtime field.'
Assert-Gate7 (@($unknownRuntimeValidation.errors | Where-Object {
            [string]$_ -match '\$\.runtime contains unsupported field'
        }).Count -eq 1) `
    'Unknown external runtime provenance did not fail through closed-object validation.'

$externalStageFailureState = Read-HcrMockAdapterState
$externalStageFailureState | Add-Member -NotePropertyName stageAdapterFailure `
    -NotePropertyValue $true -Force
Write-HcrMockAdapterState $externalStageFailureState
$externalStageFailureRun = Invoke-Gate7Tool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    credentialProfile = 'test-profile'
    profilePath = $externalProfilePath
    artifactPath = $externalPortablePath
})
Assert-Gate7 (-not [bool]$externalStageFailureRun.ok) `
    'An external staging failure fabricated an evidence-ready result.'
Assert-Gate7Equal ([string]$externalStageFailureRun.error.code) 'MOCK_STAGE_FAILURE' `
    'An external staging failure did not preserve the adapter failure code.'
$externalStageFailureOperation = Get-HcrOperationRecord `
    ([string]$externalStageFailureRun.operationId)
Assert-Gate7 (
    $null -eq $externalStageFailureOperation.evidenceFile -and
    $null -eq $externalStageFailureOperation.portableZipGuestSha256 -and
    $null -eq $externalStageFailureOperation.portableManifestGuestSha256 -and
    $null -eq $externalStageFailureOperation.portableManifestGuestSizeBytes -and
    [string]$externalStageFailureOperation.preEvidenceFailure.code -eq
        'MOCK_STAGE_FAILURE'
) 'External staging failure state did not explicitly retain unavailable guest identities.'
[void](New-Item -ItemType Directory -Path $externalFailureExportRoot)
$externalStageFailureExport = Invoke-Gate7Tool 'collect_evidence' ([pscustomobject]@{
    operationId = [string]$externalStageFailureRun.operationId
    outputDirectory = $externalFailureExportRoot
})
Assert-Gate7 (
    -not [bool]$externalStageFailureExport.ok -and
    [string]$externalStageFailureExport.error.code -eq 'EVIDENCE_NOT_READY'
) 'collect_evidence exported a pre-evidence external staging failure.'
$restoredExternalStageState = Read-HcrMockAdapterState
$restoredExternalStageState.stageAdapterFailure = $false
Write-HcrMockAdapterState $restoredExternalStageState

$externalPostStageFailureState = Read-HcrMockAdapterState
$externalPostStageFailureState | Add-Member -NotePropertyName stepAdapterFailureId `
    -NotePropertyValue 'deploy' -Force
Write-HcrMockAdapterState $externalPostStageFailureState
$externalPostStageFailureRun = Invoke-Gate7Tool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    credentialProfile = 'test-profile'
    profilePath = $externalProfilePath
    artifactPath = $externalPortablePath
})
Assert-Gate7 $externalPostStageFailureRun.ok `
    'A post-staging external failure did not produce auditable failure evidence.'
Assert-Gate7Equal ([string]$externalPostStageFailureRun.data.machineStatus) 'failed' `
    'A post-staging external failure did not derive machineStatus=failed.'
$externalPostStageFailureOperation = Get-HcrOperationRecord `
    ([string]$externalPostStageFailureRun.data.testOperationId)
$externalPostStageFailureEvidence = Read-HcrJsonFile `
    ([string]$externalPostStageFailureOperation.evidenceFile) `
    'EVIDENCE_NOT_READY'
$externalPostStageFailureValidation = Test-HcrEvidenceDocumentV2 `
    $externalPostStageFailureEvidence `
    $externalPostStageFailureOperation
Assert-Gate7 $externalPostStageFailureValidation.valid `
    ('Native validation rejected post-staging external failure evidence: ' +
        ($externalPostStageFailureValidation.errors -join '; '))
Assert-Gate7 (
    [string]$externalPostStageFailureEvidence.candidate.portableZipGuestSha256 -eq
        [string]$externalPostStageFailureEvidence.candidate.portableZipSourceSha256 -and
    [string]$externalPostStageFailureEvidence.candidate.portableManifestGuestSha256 -eq
        [string]$externalPostStageFailureEvidence.candidate.portableManifestSourceSha256 -and
    [int64]$externalPostStageFailureEvidence.candidate.portableManifestGuestSizeBytes -eq
        [int64]$externalPostStageFailureEvidence.candidate.portableManifestSourceSizeBytes
) 'Post-staging external failure evidence lost independently observed guest identities.'
$externalPostStageFailureExport = Invoke-Gate7Tool 'collect_evidence' ([pscustomobject]@{
    operationId = [string]$externalPostStageFailureRun.data.testOperationId
    outputDirectory = $externalFailureExportRoot
})
Assert-Gate7 $externalPostStageFailureExport.ok `
    'collect_evidence rejected post-staging external failure evidence.'
$restoredExternalPostStageState = Read-HcrMockAdapterState
$restoredExternalPostStageState.stepAdapterFailureId = $null
Write-HcrMockAdapterState $restoredExternalPostStageState

$externalUiValidation = Invoke-Gate7Tool 'validate_test_profile' ([pscustomobject]@{
    profilePath = $externalUiProfilePath
})
Assert-Gate7 $externalUiValidation.ok `
    'The external UI profile failed native validation.'
$externalUiRun = Invoke-Gate7Tool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    credentialProfile = 'test-profile'
    profilePath = $externalUiProfilePath
    artifactPath = $externalPortablePath
})
Assert-Gate7 $externalUiRun.ok `
    ('The external mock UI workflow failed: ' +
        ((Get-HcrPropertyValue $externalUiRun 'error') |
            ConvertTo-Json -Depth 20 -Compress))
$externalUiOperation = Get-HcrOperationRecord `
    ([string]$externalUiRun.data.testOperationId)
$externalUiEvidence = Read-HcrJsonFile `
    ([string]$externalUiOperation.evidenceFile) `
    'EVIDENCE_NOT_READY'
Assert-Gate7 ([bool]$externalUiEvidence.automation.uiRequired -and
        [string]$externalUiEvidence.automation.fixedWebView2Version -eq
            [string]$externalUiManifest.webView2.version -and
        [string]$externalUiEvidence.automation.webDriverVersion -eq
            [string]$externalUiProfile.webDriver.driverVersion -and
        $null -ne $externalUiEvidence.automation.webDriverManifestSha256) `
    'The external UI branch did not bind its conditional component and driver identity.'
$externalUiEvidenceValidation = Invoke-Gate7Tool 'validate_evidence' ([pscustomobject]@{
    evidencePath = [string]$externalUiOperation.evidenceFile
})
Assert-Gate7 $externalUiEvidenceValidation.ok `
    'Generated external UI evidence failed native validation.'

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

$stageAdapterFailureState = Read-HcrMockAdapterState
$stageAdapterFailureState | Add-Member -NotePropertyName stageAdapterFailure `
    -NotePropertyValue $true -Force
Write-HcrMockAdapterState $stageAdapterFailureState
$stageAdapterFailureRun = Invoke-Gate7Tool 'run_test_profile' ([pscustomobject]@{
    vmName = 'cleanroom-v2'
    credentialProfile = 'test-profile'
    profilePath = $profilePath
    artifactPath = $portablePath
})
Assert-Gate7 $stageAdapterFailureRun.ok `
    'A schema-v2 staging adapter failure escaped without auditable evidence.'
Assert-Gate7 ([bool]$stageAdapterFailureRun.data.cleanupTriggered) `
    'A schema-v2 staging adapter failure did not trigger cleanup state.'
Assert-Gate7Equal (@($stageAdapterFailureRun.data.automaticAssertions | Where-Object {
            [string]$_.id -eq 'stage-artifact' -and [string]$_.status -eq 'failed'
        }).Count) 1 `
    'The schema-v2 staging adapter failure did not bind a failed stage assertion.'
$stageAdapterFailureOperation = Get-HcrOperationRecord `
    ([string]$stageAdapterFailureRun.data.testOperationId)
$stageAdapterFailureEvidence = Read-HcrJsonFile `
    ([string]$stageAdapterFailureOperation.evidenceFile) 'EVIDENCE_NOT_READY'
Assert-Gate7 (Test-HcrEvidenceDocumentV2 `
        $stageAdapterFailureEvidence $stageAdapterFailureOperation).valid `
    'The native validator rejected schema-v2 staging-failure evidence.'
Assert-Gate7 (@($stageAdapterFailureEvidence.artifacts | Where-Object {
            [string]$_.role -eq 'portableZip' -and
            [string]$_.status -eq 'failed' -and $null -eq $_.guestSha256
        }).Count -eq 1) `
    'The staging-failure evidence did not preserve the failed ZIP identity.'
Assert-Gate7 (@($stageAdapterFailureEvidence.artifacts | Where-Object {
            [string]$_.role -eq 'fixture' -and
            [string]$_.status -eq 'notPerformed' -and $null -eq $_.guestSha256
        }).Count -eq 1) `
    'Fixture staging was not safely skipped after the ZIP staging failure.'
$restoredStageAdapterState = Read-HcrMockAdapterState
$restoredStageAdapterState.stageAdapterFailure = $false
Write-HcrMockAdapterState $restoredStageAdapterState

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
    testRoot = $testRoot
} | ConvertTo-Json -Compress

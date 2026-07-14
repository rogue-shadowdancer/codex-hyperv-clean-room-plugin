[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:HcrInstallSchemaVersion = 1
$script:HcrPluginName = 'hyperv-clean-room'
$script:HcrInstallerOwner = 'hyperv-clean-room-installer/v1'
$script:HcrOwnershipRelativePath = '.codex-plugin/install-ownership.json'
$script:HcrManifestRelativePath = '.codex-plugin/install-manifest.json'
$script:HcrExpectedPayloadFileCount = 20
$script:HcrUtf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Assert-HcrInstallCondition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) { throw $Message }
}

function Read-HcrInstallJson {
    param([Parameter(Mandatory = $true)][string]$Path)

    Assert-HcrInstallCondition (Test-Path -LiteralPath $Path -PathType Leaf) `
        "Required JSON file is missing: $Path"
    Assert-HcrPlainFile -Path $Path
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "JSON file is unreadable: $Path"
    }
}

function Write-HcrInstallJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value,
        [string]$ContainmentRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($ContainmentRoot)) {
        $containment = Get-HcrCanonicalPath $ContainmentRoot
        $canonicalPath = Get-HcrCanonicalPath $Path
        Assert-HcrInstallCondition ($canonicalPath.StartsWith(
                $containment + '\',
                [StringComparison]::OrdinalIgnoreCase
            )) "JSON output escapes its containment root: $canonicalPath"
        Assert-HcrPathComponentsOrdinary -Path $canonicalPath
    }
    elseif (Test-Path -LiteralPath $Path) {
        Assert-HcrPlainFile -Path $Path
    }
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        Assert-HcrPathComponentsOrdinary -Path $parent
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    Assert-HcrPathComponentsOrdinary -Path $parent
    if (Test-Path -LiteralPath $Path) { Assert-HcrPlainFile -Path $Path }
    $json = $Value | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, $script:HcrUtf8NoBom)
    Assert-HcrPlainFile -Path $Path
}

function Get-HcrCanonicalPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Assert-HcrPlainFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    Assert-HcrInstallCondition (-not $item.PSIsContainer) "Path is not a file: $Path"
    Assert-HcrInstallCondition (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) `
        "File must not be a reparse point: $Path"
    $linkType = if ($null -ne $item.PSObject.Properties['LinkType']) {
        [string]$item.LinkType
    }
    else { '' }
    Assert-HcrInstallCondition ($linkType -ine 'HardLink') `
        "File must not be a hard link: $Path"
    try { $streams = @(Get-Item -LiteralPath $Path -Stream * -ErrorAction Stop) }
    catch { throw "File streams could not be enumerated safely: $Path" }
    $namedStreams = @($streams | Where-Object { [string]$_.Stream -cne ':$DATA' })
    Assert-HcrInstallCondition ($streams.Count -eq 1 -and $namedStreams.Count -eq 0) `
        "File must contain only the unnamed data stream: $Path"
}

function Assert-HcrPathComponentsOrdinary {
    param([Parameter(Mandatory = $true)][string]$Path)

    $canonical = [IO.Path]::GetFullPath($Path)
    $pathRoot = [IO.Path]::GetPathRoot($canonical)
    Assert-HcrInstallCondition (-not [string]::IsNullOrWhiteSpace($pathRoot)) `
        "Path has no local filesystem root: $canonical"
    $relative = $canonical.Substring($pathRoot.Length)
    $current = $pathRoot
    foreach ($segment in @($relative -split '[\\/]' | Where-Object { $_ -ne '' })) {
        $current = Join-Path $current $segment
        if (-not (Test-Path -LiteralPath $current)) { break }
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        Assert-HcrInstallCondition (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) `
            "Path components must not be reparse points: $current"
        if (-not $item.PSIsContainer) {
            Assert-HcrInstallCondition ((Get-HcrCanonicalPath $current) -ieq
                (Get-HcrCanonicalPath $canonical)) "A path ancestor is not a directory: $current"
            Assert-HcrPlainFile -Path $current
        }
    }
}

function Assert-HcrUniqueRelativePaths {
    param([Parameter(Mandatory = $true)][string[]]$Paths)

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' `
        ([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $Paths) {
        Assert-HcrInstallCondition ($seen.Add($path)) `
            "Plugin source contains a case-insensitive duplicate relative path: $path"
    }
}

function Assert-HcrRepositoryScratchPath {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$ScratchRoot,
        [switch]$RequireExisting
    )

    $repository = Get-HcrCanonicalPath $RepositoryRoot
    $artifacts = Get-HcrCanonicalPath (Join-Path $repository '.artifacts')
    $scratch = Get-HcrCanonicalPath $ScratchRoot
    Assert-HcrPathComponentsOrdinary -Path $repository
    Assert-HcrInstallCondition ($scratch.StartsWith(
            $artifacts + '\',
            [StringComparison]::OrdinalIgnoreCase
        )) "Scratch path escapes repository artifacts: $scratch"
    Assert-HcrPathComponentsOrdinary -Path $artifacts
    Assert-HcrPathComponentsOrdinary -Path $scratch
    if ($RequireExisting) {
        Assert-HcrInstallCondition (Test-Path -LiteralPath $scratch -PathType Container) `
            "Required repository scratch directory is missing: $scratch"
        $item = Get-Item -LiteralPath $scratch -Force
        Assert-HcrInstallCondition (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) `
            "Repository scratch directory must not be a reparse point: $scratch"
        $null = Get-HcrOrdinaryFiles -Root $scratch
    }
}

function Remove-HcrRepositoryScratchTree {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$ScratchRoot
    )

    Assert-HcrRepositoryScratchPath `
        -RepositoryRoot $RepositoryRoot `
        -ScratchRoot $ScratchRoot `
        -RequireExisting
    Remove-Item -LiteralPath (Get-HcrCanonicalPath $ScratchRoot) -Recurse -Force
}

function Invoke-HcrRepositoryScratchAction {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$ScratchRoot,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    $repository = Get-HcrCanonicalPath $RepositoryRoot
    $artifacts = Get-HcrCanonicalPath (Join-Path $repository '.artifacts')
    $scratch = Get-HcrCanonicalPath $ScratchRoot
    Assert-HcrRepositoryScratchPath -RepositoryRoot $repository -ScratchRoot $scratch
    Assert-HcrInstallCondition (-not (Test-Path -LiteralPath $scratch)) `
        "Repository scratch directory already exists: $scratch"

    if (-not (Test-Path -LiteralPath $artifacts -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $artifacts
    }
    Assert-HcrRepositoryScratchPath -RepositoryRoot $repository -ScratchRoot $scratch
    $null = New-Item -ItemType Directory -Path $scratch

    try {
        Assert-HcrRepositoryScratchPath `
            -RepositoryRoot $repository `
            -ScratchRoot $scratch `
            -RequireExisting
        & $Action $scratch
        Assert-HcrRepositoryScratchPath `
            -RepositoryRoot $repository `
            -ScratchRoot $scratch `
            -RequireExisting
    }
    finally {
        if (Test-Path -LiteralPath $scratch) {
            Remove-HcrRepositoryScratchTree `
                -RepositoryRoot $repository `
                -ScratchRoot $scratch
        }
    }
}

function Get-HcrRelativeInstallPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $canonicalRoot = Get-HcrCanonicalPath $Root
    $canonicalPath = Get-HcrCanonicalPath $Path
    $prefix = $canonicalRoot + [IO.Path]::DirectorySeparatorChar
    Assert-HcrInstallCondition ($canonicalPath.StartsWith(
            $prefix,
            [StringComparison]::OrdinalIgnoreCase
        )) "Path escapes the expected root: $canonicalPath"
    $relative = $canonicalPath.Substring($prefix.Length).Replace('\', '/')
    Assert-HcrInstallCondition (-not [string]::IsNullOrWhiteSpace($relative)) `
        'An empty relative install path is invalid.'
    Assert-HcrInstallCondition ($relative -match '^[A-Za-z0-9._/-]+$') `
        "Install path contains unsupported characters: $relative"
    Assert-HcrInstallCondition ($relative -notmatch '(^|/)\.\.?(/|$)' -and $relative -notmatch ':') `
        "Install path is unsafe: $relative"
    return $relative
}

function Get-HcrOrdinaryFiles {
    param([Parameter(Mandatory = $true)][string]$Root)

    $canonicalRoot = Get-HcrCanonicalPath $Root
    Assert-HcrPathComponentsOrdinary -Path $canonicalRoot
    $rootItem = Get-Item -LiteralPath $canonicalRoot -Force -ErrorAction Stop
    Assert-HcrInstallCondition $rootItem.PSIsContainer "Path is not a directory: $canonicalRoot"
    Assert-HcrInstallCondition (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) `
        "Directory must not be a reparse point: $canonicalRoot"

    $pending = New-Object System.Collections.Generic.Stack[string]
    $pending.Push($canonicalRoot)
    $files = New-Object System.Collections.Generic.List[object]
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)) {
            Assert-HcrInstallCondition (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) `
                "Install trees must not contain reparse points: $($item.FullName)"
            if ($item.PSIsContainer) {
                $pending.Push($item.FullName)
            }
            else {
                Assert-HcrPlainFile -Path $item.FullName
                $null = $files.Add($item)
            }
        }
    }
    return @($files.ToArray() | Sort-Object FullName)
}

function Get-HcrPluginVersionInfo {
    param([Parameter(Mandatory = $true)][string]$Version)

    $match = [regex]::Match(
        $Version,
        '^0\.1\.0(?:\+codex\.(?<cachebuster>[a-z0-9]+(?:-[a-z0-9]+)*))?$'
    )
    Assert-HcrInstallCondition $match.Success `
        "Plugin version must be 0.1.0 with at most one +codex.<cachebuster> suffix: $Version"
    $cachebuster = if ($match.Groups['cachebuster'].Success) {
        [string]$match.Groups['cachebuster'].Value
    }
    else { $null }
    return [pscustomobject][ordered]@{
        version = $Version
        baseVersion = '0.1.0'
        cachebuster = $cachebuster
    }
}

function Get-HcrSourceInventory {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [switch]$RequireCachebuster
    )

    $source = Get-HcrCanonicalPath $SourceRoot
    Assert-HcrInstallCondition (Test-Path -LiteralPath $source -PathType Container) `
        "Plugin source directory is missing: $source"
    $repositoryRoot = Get-HcrCanonicalPath (Split-Path -Parent $source)
    Assert-HcrInstallCondition ((Split-Path -Leaf $source) -ceq $script:HcrPluginName) `
        "Plugin source folder must be named $($script:HcrPluginName)."

    $gitTop = @(& git -C $repositoryRoot rev-parse --show-toplevel 2>$null)
    Assert-HcrInstallCondition ($LASTEXITCODE -eq 0 -and $gitTop.Count -eq 1) `
        'Plugin source must be inside a readable Git worktree.'
    Assert-HcrInstallCondition ((Get-HcrCanonicalPath ([string]$gitTop[0])) -ieq $repositoryRoot) `
        'Plugin source must be the hyperv-clean-room directory directly below the repository root.'
    $sourceCommitOutput = @(& git -C $repositoryRoot rev-parse HEAD 2>$null)
    Assert-HcrInstallCondition ($LASTEXITCODE -eq 0 -and $sourceCommitOutput.Count -eq 1 -and
        [string]$sourceCommitOutput[0] -match '^[0-9a-f]{40}$') `
        'The source Git commit could not be resolved.'
    $sourceCommit = [string]$sourceCommitOutput[0]

    $files = @(Get-HcrOrdinaryFiles $source)
    Assert-HcrInstallCondition ($files.Count -eq $script:HcrExpectedPayloadFileCount) `
        "The Gate 4 plugin payload must contain exactly $($script:HcrExpectedPayloadFileCount) files."
    $relativeFiles = @($files | ForEach-Object {
            Get-HcrRelativeInstallPath -Root $source -Path $_.FullName
        })
    Assert-HcrUniqueRelativePaths -Paths $relativeFiles
    Assert-HcrInstallCondition ($relativeFiles -notcontains $script:HcrOwnershipRelativePath -and
        $relativeFiles -notcontains $script:HcrManifestRelativePath) `
        'Plugin source contains reserved installed-state files.'

    $trackedOutput = @(& git -C $repositoryRoot ls-files -- $script:HcrPluginName 2>$null)
    Assert-HcrInstallCondition ($LASTEXITCODE -eq 0) 'The tracked plugin file set could not be read.'
    $trackedRelative = @($trackedOutput | ForEach-Object {
            $value = ([string]$_).Replace('\', '/')
            $prefix = $script:HcrPluginName + '/'
            Assert-HcrInstallCondition ($value.StartsWith(
                    $prefix,
                    [StringComparison]::Ordinal
                )) "Unexpected tracked plugin path: $value"
            $value.Substring($prefix.Length)
        } | Sort-Object)
    $actualRelative = @($relativeFiles | Sort-Object)
    Assert-HcrInstallCondition (($trackedRelative -join "`n") -ceq ($actualRelative -join "`n")) `
        'Plugin source must contain exactly the Git-tracked payload files; untracked or missing files are rejected.'

    $requiredPaths = @(
        '.codex-plugin/plugin.json',
        '.mcp.json',
        'mcp/server.ps1',
        'mcp/Initialize-GuestCredential.ps1',
        'skills/manage-hyperv-clean-room/SKILL.md',
        'skills/manage-hyperv-clean-room/agents/openai.yaml'
    )
    foreach ($required in $requiredPaths) {
        Assert-HcrInstallCondition ($actualRelative -ccontains $required) `
            "Required plugin payload file is missing: $required"
    }
    $schemas = @($actualRelative | Where-Object { $_ -match '^schemas/[^/]+\.schema\.json$' })
    Assert-HcrInstallCondition ($schemas.Count -eq 5) 'Plugin source must contain exactly five public schemas.'
    $forbidden = @($actualRelative | Where-Object {
            $_ -match '(?i)(^|/)(credentials?|evidence|\.state)(/|$)' -or
            $_ -match '(?i)\.(clixml|iso|vhd|vhdx|pfx|pem|key|log|exe|dll)$'
        })
    Assert-HcrInstallCondition ($forbidden.Count -eq 0) `
        "Plugin source contains forbidden payload files: $($forbidden -join ', ')"

    $manifest = Read-HcrInstallJson (Join-Path $source '.codex-plugin\plugin.json')
    Assert-HcrInstallCondition ([string]$manifest.name -ceq $script:HcrPluginName) `
        'Plugin manifest name is not hyperv-clean-room.'
    $versionInfo = Get-HcrPluginVersionInfo ([string]$manifest.version)
    if ($RequireCachebuster) {
        Assert-HcrInstallCondition (-not [string]::IsNullOrWhiteSpace([string]$versionInfo.cachebuster)) `
            'A Codex cachebuster is required for this validation.'
    }
    Assert-HcrInstallCondition ([string]$manifest.mcpServers -ceq './.mcp.json') `
        'Plugin manifest must use the canonical MCP configuration path.'
    Assert-HcrInstallCondition ([string]$manifest.skills -ceq './skills/') `
        'Plugin manifest must use the canonical skills path.'

    $rows = New-Object System.Collections.Generic.List[object]
    [long]$totalBytes = 0
    foreach ($file in $files) {
        Assert-HcrPathComponentsOrdinary -Path $file.FullName
        Assert-HcrPlainFile -Path $file.FullName
        $relative = Get-HcrRelativeInstallPath -Root $source -Path $file.FullName
        Assert-HcrInstallCondition ($file.Length -le 1048576) `
            "Plugin payload file exceeds the one-MiB Gate 4 bound: $relative"
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $totalBytes += [long]$file.Length
        $null = $rows.Add([pscustomobject][ordered]@{
                path = $relative
                size = [long]$file.Length
                sha256 = $hash
            })
    }
    Assert-HcrInstallCondition ($totalBytes -le 4194304) `
        'Plugin payload exceeds the four-MiB Gate 4 total bound.'

    return [pscustomobject][ordered]@{
        schemaVersion = $script:HcrInstallSchemaVersion
        pluginName = $script:HcrPluginName
        sourceRoot = $source
        repositoryRoot = $repositoryRoot
        sourceVersion = [string]$versionInfo.version
        baseVersion = [string]$versionInfo.baseVersion
        cachebuster = $versionInfo.cachebuster
        sourceCommit = $sourceCommit
        fileCount = $rows.Count
        totalBytes = $totalBytes
        files = @($rows.ToArray())
    }
}

function Test-HcrOwnershipMarker {
    param(
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [switch]$ThrowOnFailure
    )

    try {
        $target = Get-HcrCanonicalPath $TargetRoot
        $path = Join-Path $target $script:HcrOwnershipRelativePath.Replace('/', '\')
        $marker = Read-HcrInstallJson $path
        $names = @($marker.PSObject.Properties.Name | Sort-Object)
        $expectedNames = @('installationId', 'owner', 'pluginName', 'schemaVersion', 'targetRoot') | Sort-Object
        Assert-HcrInstallCondition (($names -join ',') -ceq ($expectedNames -join ',')) `
            'The install ownership marker has an unexpected shape.'
        Assert-HcrInstallCondition ([int]$marker.schemaVersion -eq $script:HcrInstallSchemaVersion -and
            [string]$marker.owner -ceq $script:HcrInstallerOwner -and
            [string]$marker.pluginName -ceq $script:HcrPluginName -and
            (Get-HcrCanonicalPath ([string]$marker.targetRoot)) -ieq $target) `
            'The install ownership marker does not own this target.'
        $parsedId = [Guid]::Empty
        Assert-HcrInstallCondition ([Guid]::TryParse([string]$marker.installationId, [ref]$parsedId) -and
            $parsedId -ne [Guid]::Empty) 'The install ownership marker has an invalid installation ID.'
        return [pscustomobject][ordered]@{ owned = $true; marker = $marker; error = $null }
    }
    catch {
        if ($ThrowOnFailure) { throw }
        return [pscustomobject][ordered]@{ owned = $false; marker = $null; error = $_.Exception.Message }
    }
}

function Install-HcrPluginPayload {
    param(
        [Parameter(Mandatory = $true)]$SourceInventory,
        [Parameter(Mandatory = $true)][string]$TargetRoot
    )

    $source = Get-HcrCanonicalPath ([string]$SourceInventory.sourceRoot)
    $target = Get-HcrCanonicalPath $TargetRoot
    $sourcePrefix = $source + '\'
    $targetPrefix = $target + '\'
    Assert-HcrInstallCondition (-not $target.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase) -and
        -not $source.StartsWith($targetPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        $source -ine $target) 'Source and install target must not contain one another.'

    $targetExists = Test-Path -LiteralPath $target
    if ($targetExists) {
        Assert-HcrPathComponentsOrdinary -Path $target
        Assert-HcrInstallCondition (Test-Path -LiteralPath $target -PathType Container) `
            "Install target exists but is not a directory: $target"
        $targetItem = Get-Item -LiteralPath $target -Force
        Assert-HcrInstallCondition (($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) `
            'The install target must not be a reparse point.'
        $ownership = Test-HcrOwnershipMarker -TargetRoot $target -ThrowOnFailure
        $allowed = @($SourceInventory.files | ForEach-Object { [string]$_.path }) + @(
            $script:HcrOwnershipRelativePath,
            $script:HcrManifestRelativePath
        )
        $unexpected = @(Get-HcrOrdinaryFiles $target | ForEach-Object {
                Get-HcrRelativeInstallPath -Root $target -Path $_.FullName
            } | Where-Object { $allowed -cnotcontains $_ })
        Assert-HcrInstallCondition ($unexpected.Count -eq 0) `
            "Owned install contains unexpected files; the installer will not delete them: $($unexpected -join ', ')"
    }
    else {
        Assert-HcrPathComponentsOrdinary -Path $target
        $null = New-Item -ItemType Directory -Path $target
        Assert-HcrPathComponentsOrdinary -Path $target
        $installationId = [Guid]::NewGuid().ToString('D')
        $marker = [ordered]@{
            schemaVersion = $script:HcrInstallSchemaVersion
            owner = $script:HcrInstallerOwner
            pluginName = $script:HcrPluginName
            installationId = $installationId
            targetRoot = $target
        }
        Write-HcrInstallJson -Path (
            Join-Path $target $script:HcrOwnershipRelativePath.Replace('/', '\')
        ) -Value $marker -ContainmentRoot $target
        $ownership = Test-HcrOwnershipMarker -TargetRoot $target -ThrowOnFailure
    }

    foreach ($row in @($SourceInventory.files)) {
        $relative = [string]$row.path
        $sourcePath = Join-Path $source $relative.Replace('/', '\')
        $targetPath = Join-Path $target $relative.Replace('/', '\')
        Assert-HcrPathComponentsOrdinary -Path $sourcePath
        Assert-HcrPlainFile -Path $sourcePath
        Assert-HcrPathComponentsOrdinary -Path $targetPath
        $parent = Split-Path -Parent $targetPath
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            Assert-HcrPathComponentsOrdinary -Path $parent
            $null = New-Item -ItemType Directory -Path $parent -Force
        }
        Assert-HcrPathComponentsOrdinary -Path $parent
        if (Test-Path -LiteralPath $targetPath) {
            $existing = Get-Item -LiteralPath $targetPath -Force
            Assert-HcrInstallCondition (-not $existing.PSIsContainer -and
                ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) `
                "Installed payload path is not an ordinary file: $relative"
        }
        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
        Assert-HcrPathComponentsOrdinary -Path $targetPath
        Assert-HcrPlainFile -Path $targetPath
        $copied = Get-Item -LiteralPath $targetPath -Force
        $copiedHash = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-HcrInstallCondition ([long]$copied.Length -eq [long]$row.size -and
            $copiedHash -ceq [string]$row.sha256) `
            "Installed file did not match the source after copy: $relative"
    }

    $installManifest = [ordered]@{
        schemaVersion = $script:HcrInstallSchemaVersion
        pluginName = $script:HcrPluginName
        installationId = [string]$ownership.marker.installationId
        sourceRoot = [string]$SourceInventory.sourceRoot
        targetRoot = $target
        sourceVersion = [string]$SourceInventory.sourceVersion
        sourceCommit = [string]$SourceInventory.sourceCommit
        cachebuster = $SourceInventory.cachebuster
        installedAtUtc = [DateTime]::UtcNow.ToString('o')
        files = @($SourceInventory.files)
    }
    Write-HcrInstallJson -Path (
        Join-Path $target $script:HcrManifestRelativePath.Replace('/', '\')
    ) -Value $installManifest -ContainmentRoot $target
    return $installManifest
}

function Get-HcrInstalledPayloadState {
    param(
        [Parameter(Mandatory = $true)]$SourceInventory,
        [Parameter(Mandatory = $true)][string]$TargetRoot
    )

    $target = Get-HcrCanonicalPath $TargetRoot
    $installed = Test-Path -LiteralPath $target -PathType Container
    $ownership = if ($installed) { Test-HcrOwnershipMarker -TargetRoot $target } else {
        [pscustomobject][ordered]@{ owned = $false; marker = $null; error = 'Install target is missing.' }
    }
    $matches = $false
    $installedVersion = $null
    $installedSourceCommit = $null
    $installedCachebuster = $null
    $errorMessage = $ownership.error
    if ($installed -and $ownership.owned) {
        try {
            $manifestPath = Join-Path $target $script:HcrManifestRelativePath.Replace('/', '\')
            $installManifest = Read-HcrInstallJson $manifestPath
            $pluginManifest = Read-HcrInstallJson (Join-Path $target '.codex-plugin\plugin.json')
            $installedVersion = [string]$pluginManifest.version
            $installedVersionInfo = Get-HcrPluginVersionInfo $installedVersion
            $installedCachebuster = $installedVersionInfo.cachebuster
            $installedSourceCommit = [string]$installManifest.sourceCommit
            $expectedFiles = @($SourceInventory.files | Sort-Object path)
            $claimedFiles = @($installManifest.files | Sort-Object path)
            Assert-HcrInstallCondition ($claimedFiles.Count -eq $expectedFiles.Count) `
                'Installed manifest file count differs from source.'
            for ($index = 0; $index -lt $expectedFiles.Count; $index++) {
                $expected = $expectedFiles[$index]
                $claimed = $claimedFiles[$index]
                Assert-HcrInstallCondition ([string]$claimed.path -ceq [string]$expected.path -and
                    [long]$claimed.size -eq [long]$expected.size -and
                    [string]$claimed.sha256 -ceq [string]$expected.sha256) `
                    'Installed manifest inventory differs from source.'
                $installedPath = Join-Path $target ([string]$expected.path).Replace('/', '\')
                Assert-HcrPathComponentsOrdinary -Path $installedPath
                Assert-HcrPlainFile -Path $installedPath
                $item = Get-Item -LiteralPath $installedPath -Force -ErrorAction Stop
                Assert-HcrInstallCondition (-not $item.PSIsContainer -and
                    ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
                    [long]$item.Length -eq [long]$expected.size) `
                    "Installed payload file has the wrong type or size: $($expected.path)"
                $hash = (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash.ToLowerInvariant()
                Assert-HcrInstallCondition ($hash -ceq [string]$expected.sha256) `
                    "Installed payload hash differs from source: $($expected.path)"
            }
            $allFiles = @(Get-HcrOrdinaryFiles $target | ForEach-Object {
                    Get-HcrRelativeInstallPath -Root $target -Path $_.FullName
                } | Sort-Object)
            $allowedFiles = @($expectedFiles | ForEach-Object { [string]$_.path }) + @(
                $script:HcrOwnershipRelativePath,
                $script:HcrManifestRelativePath
            ) | Sort-Object
            Assert-HcrInstallCondition (($allFiles -join "`n") -ceq ($allowedFiles -join "`n")) `
                'Installed copy contains unexpected or missing files.'
            Assert-HcrInstallCondition ([int]$installManifest.schemaVersion -eq $script:HcrInstallSchemaVersion -and
                [string]$installManifest.pluginName -ceq $script:HcrPluginName -and
                [string]$installManifest.installationId -ceq [string]$ownership.marker.installationId -and
                (Get-HcrCanonicalPath ([string]$installManifest.sourceRoot)) -ieq
                    (Get-HcrCanonicalPath ([string]$SourceInventory.sourceRoot)) -and
                (Get-HcrCanonicalPath ([string]$installManifest.targetRoot)) -ieq $target -and
                [string]$installManifest.sourceVersion -ceq [string]$SourceInventory.sourceVersion -and
                [string]$installManifest.sourceCommit -ceq [string]$SourceInventory.sourceCommit -and
                [string]$installedVersion -ceq [string]$SourceInventory.sourceVersion -and
                [string]$installedCachebuster -ceq [string]$SourceInventory.cachebuster -and
                [string]$installManifest.cachebuster -ceq [string]$SourceInventory.cachebuster) `
                'Installed metadata differs from the current source.'
            $matches = $true
            $errorMessage = $null
        }
        catch {
            $errorMessage = $_.Exception.Message
        }
    }

    return [pscustomobject][ordered]@{
        installed = [bool]$installed
        owned = [bool]$ownership.owned
        matches = [bool]$matches
        installedVersion = $installedVersion
        installedSourceCommit = $installedSourceCommit
        installedCachebuster = $installedCachebuster
        error = $errorMessage
    }
}

function Get-HcrMarketplaceState {
    param(
        [Parameter(Mandatory = $true)][string]$MarketplacePath,
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedVersion
    )

    $entryCount = 0
    $entryValid = $false
    $cliVisible = $false
    $errorMessage = $null
    try {
        $marketplace = Read-HcrInstallJson $MarketplacePath
        Assert-HcrInstallCondition ([string]$marketplace.name -ceq 'personal') `
            'The personal marketplace name is not personal.'
        $entries = @($marketplace.plugins | Where-Object { [string]$_.name -ceq $script:HcrPluginName })
        $entryCount = $entries.Count
        Assert-HcrInstallCondition ($entryCount -eq 1) `
            'The personal marketplace must contain exactly one hyperv-clean-room entry.'
        $entry = $entries[0]
        $entryValid = [string]$entry.source.source -ceq 'local' -and
            [string]$entry.source.path -ceq './plugins/hyperv-clean-room' -and
            [string]$entry.policy.installation -ceq 'AVAILABLE' -and
            [string]$entry.policy.authentication -ceq 'ON_INSTALL' -and
            [string]$entry.category -ceq 'Developer Tools'
        Assert-HcrInstallCondition $entryValid 'The personal marketplace entry is not canonical.'

        $codex = Get-Command codex -ErrorAction Stop
        $lines = @(& $codex.Source plugin list 2>$null)
        Assert-HcrInstallCondition ($LASTEXITCODE -eq 0) 'codex plugin list failed.'
        $selectorLines = @($lines | Where-Object { $_ -match '^\s*hyperv-clean-room@personal\s+' })
        Assert-HcrInstallCondition ($selectorLines.Count -eq 1) `
            'codex plugin list did not return exactly one personal plugin row.'
        $line = [string]$selectorLines[0]
        $cliVisible = $line -match '\sinstalled, enabled\s+' -and
            $line.Contains($ExpectedVersion) -and
            $line.IndexOf(
                (Get-HcrCanonicalPath $TargetRoot),
                [StringComparison]::OrdinalIgnoreCase
            ) -ge 0
        Assert-HcrInstallCondition $cliVisible `
            'Codex does not report the expected personal plugin as installed and enabled.'
    }
    catch {
        $errorMessage = $_.Exception.Message
    }
    return [pscustomobject][ordered]@{
        marketplaceVisible = [bool]($entryValid -and $cliVisible)
        marketplaceEntryCount = $entryCount
        error = $errorMessage
    }
}

function Get-HcrInstallCheck {
    param(
        [Parameter(Mandatory = $true)]$SourceInventory,
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$MarketplacePath
    )

    $payload = Get-HcrInstalledPayloadState -SourceInventory $SourceInventory -TargetRoot $TargetRoot
    $marketplace = Get-HcrMarketplaceState `
        -MarketplacePath $MarketplacePath `
        -TargetRoot $TargetRoot `
        -ExpectedVersion ([string]$SourceInventory.sourceVersion)
    return [pscustomobject][ordered]@{
        installed = [bool]$payload.installed
        owned = [bool]$payload.owned
        matches = [bool]$payload.matches
        marketplaceVisible = [bool]$marketplace.marketplaceVisible
        sourceVersion = [string]$SourceInventory.sourceVersion
        installedVersion = $payload.installedVersion
        sourceCommit = [string]$SourceInventory.sourceCommit
        installedSourceCommit = $payload.installedSourceCommit
        cachebuster = $SourceInventory.cachebuster
        installedCachebuster = $payload.installedCachebuster
        marketplaceEntryCount = [int]$marketplace.marketplaceEntryCount
        sourceFileCount = [int]$SourceInventory.fileCount
        installRoot = Get-HcrCanonicalPath $TargetRoot
        payloadError = $payload.error
        marketplaceError = $marketplace.error
    }
}

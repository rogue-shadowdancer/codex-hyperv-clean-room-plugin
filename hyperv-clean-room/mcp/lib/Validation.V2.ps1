function Get-HcrExactSchemaVersion {
    param(
        [Parameter(Mandatory = $true)][object]$Document,
        [Parameter(Mandatory = $true)][string]$DocumentKind
    )

    if (-not (Test-HcrProperty $Document 'schemaVersion') -or
        -not (Test-HcrInteger (Get-HcrPropertyValue $Document 'schemaVersion'))) {
        Throw-HcrError 'UNSUPPORTED_SCHEMA_VERSION' "$DocumentKind requires an exact integer schemaVersion."
    }
    $versionValue = Get-HcrPropertyValue $Document 'schemaVersion'
    if ([decimal]$versionValue -lt 1 -or [decimal]$versionValue -gt 2) {
        Throw-HcrError 'UNSUPPORTED_SCHEMA_VERSION' "$DocumentKind schemaVersion is not supported."
    }
    $version = [int][decimal]$versionValue
    return $version
}

function Skip-HcrStrictJsonWhitespace {
    param(
        [Parameter(Mandatory = $true)][string]$Json,
        [Parameter(Mandatory = $true)][ref]$Index
    )

    while ($Index.Value -lt $Json.Length -and
        @([char]0x20, [char]0x09, [char]0x0a, [char]0x0d) -contains
            $Json[$Index.Value]) {
        $Index.Value++
    }
}

function Read-HcrStrictJsonStringToken {
    param(
        [Parameter(Mandatory = $true)][string]$Json,
        [Parameter(Mandatory = $true)][ref]$Index,
        [Parameter(Mandatory = $true)][string]$ErrorCode
    )

    if ($Index.Value -ge $Json.Length -or $Json[$Index.Value] -ne [char]0x22) {
        Throw-HcrError $ErrorCode 'The JSON document contains an invalid property name.'
    }
    $Index.Value++
    $builder = New-Object Text.StringBuilder
    while ($Index.Value -lt $Json.Length) {
        $character = $Json[$Index.Value]
        $Index.Value++
        if ($character -eq [char]0x22) {
            return $builder.ToString()
        }
        if ([int]$character -lt 0x20) {
            Throw-HcrError $ErrorCode 'The JSON document contains an unescaped control character.'
        }
        if ($character -ne [char]0x5c) {
            [void]$builder.Append($character)
            continue
        }
        if ($Index.Value -ge $Json.Length) {
            Throw-HcrError $ErrorCode 'The JSON document ends inside an escape sequence.'
        }
        $escape = $Json[$Index.Value]
        $Index.Value++
        switch ($escape) {
            ([char]0x22) { [void]$builder.Append([char]0x22); break }
            ([char]0x5c) { [void]$builder.Append([char]0x5c); break }
            ([char]0x2f) { [void]$builder.Append([char]0x2f); break }
            'b' { [void]$builder.Append([char]0x08); break }
            'f' { [void]$builder.Append([char]0x0c); break }
            'n' { [void]$builder.Append([char]0x0a); break }
            'r' { [void]$builder.Append([char]0x0d); break }
            't' { [void]$builder.Append([char]0x09); break }
            'u' {
                if ($Index.Value + 4 -gt $Json.Length) {
                    Throw-HcrError $ErrorCode 'The JSON document contains a truncated Unicode escape.'
                }
                $hex = $Json.Substring($Index.Value, 4)
                if ($hex -notmatch '^[0-9a-fA-F]{4}$') {
                    Throw-HcrError $ErrorCode 'The JSON document contains an invalid Unicode escape.'
                }
                [void]$builder.Append([char][Convert]::ToUInt16($hex, 16))
                $Index.Value += 4
                break
            }
            default {
                Throw-HcrError $ErrorCode 'The JSON document contains an invalid escape sequence.'
            }
        }
    }
    Throw-HcrError $ErrorCode 'The JSON document ends inside a string.'
}

function Assert-HcrStrictJsonValue {
    param(
        [Parameter(Mandatory = $true)][string]$Json,
        [Parameter(Mandatory = $true)][ref]$Index,
        [Parameter(Mandatory = $true)][string]$ErrorCode,
        [int]$Depth = 0
    )

    if ($Depth -gt 100) {
        Throw-HcrError $ErrorCode 'The JSON document exceeds the nesting limit.'
    }
    Skip-HcrStrictJsonWhitespace $Json $Index
    if ($Index.Value -ge $Json.Length) {
        Throw-HcrError $ErrorCode 'The JSON document ends before a value.'
    }
    $character = $Json[$Index.Value]
    if ($character -eq [char]0x7b) {
        $Index.Value++
        Skip-HcrStrictJsonWhitespace $Json $Index
        $names = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        if ($Index.Value -lt $Json.Length -and $Json[$Index.Value] -eq [char]0x7d) {
            $Index.Value++
            return
        }
        while ($true) {
            $name = Read-HcrStrictJsonStringToken $Json $Index $ErrorCode
            if (-not $names.Add($name)) {
                Throw-HcrError $ErrorCode 'The JSON document contains a duplicate object property.'
            }
            Skip-HcrStrictJsonWhitespace $Json $Index
            if ($Index.Value -ge $Json.Length -or $Json[$Index.Value] -ne [char]0x3a) {
                Throw-HcrError $ErrorCode 'The JSON document contains an invalid object separator.'
            }
            $Index.Value++
            Assert-HcrStrictJsonValue $Json $Index $ErrorCode ($Depth + 1)
            Skip-HcrStrictJsonWhitespace $Json $Index
            if ($Index.Value -ge $Json.Length) {
                Throw-HcrError $ErrorCode 'The JSON document ends inside an object.'
            }
            if ($Json[$Index.Value] -eq [char]0x7d) {
                $Index.Value++
                return
            }
            if ($Json[$Index.Value] -ne [char]0x2c) {
                Throw-HcrError $ErrorCode 'The JSON document contains an invalid object delimiter.'
            }
            $Index.Value++
            Skip-HcrStrictJsonWhitespace $Json $Index
        }
    }
    if ($character -eq [char]0x5b) {
        $Index.Value++
        Skip-HcrStrictJsonWhitespace $Json $Index
        if ($Index.Value -lt $Json.Length -and $Json[$Index.Value] -eq [char]0x5d) {
            $Index.Value++
            return
        }
        while ($true) {
            Assert-HcrStrictJsonValue $Json $Index $ErrorCode ($Depth + 1)
            Skip-HcrStrictJsonWhitespace $Json $Index
            if ($Index.Value -ge $Json.Length) {
                Throw-HcrError $ErrorCode 'The JSON document ends inside an array.'
            }
            if ($Json[$Index.Value] -eq [char]0x5d) {
                $Index.Value++
                return
            }
            if ($Json[$Index.Value] -ne [char]0x2c) {
                Throw-HcrError $ErrorCode 'The JSON document contains an invalid array delimiter.'
            }
            $Index.Value++
            Skip-HcrStrictJsonWhitespace $Json $Index
        }
    }
    if ($character -eq [char]0x22) {
        [void](Read-HcrStrictJsonStringToken $Json $Index $ErrorCode)
        return
    }
    $start = $Index.Value
    while ($Index.Value -lt $Json.Length -and
        @([char]0x20, [char]0x09, [char]0x0a, [char]0x0d,
            [char]0x2c, [char]0x5d, [char]0x7d) -notcontains
            $Json[$Index.Value]) {
        $Index.Value++
    }
    if ($Index.Value -eq $start) {
        Throw-HcrError $ErrorCode 'The JSON document contains an invalid value.'
    }
}

function ConvertFrom-HcrStrictJsonBytes {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$ErrorCode
    )

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xef -and
        $Bytes[1] -eq 0xbb -and $Bytes[2] -eq 0xbf) {
        Throw-HcrError $ErrorCode 'The JSON document must be UTF-8 without a BOM.'
    }
    try {
        $json = (New-Object Text.UTF8Encoding($false, $true)).GetString($Bytes)
    }
    catch {
        Throw-HcrError $ErrorCode 'The JSON document is not strict UTF-8.'
    }
    if ($json.IndexOf([char]0) -ge 0) {
        Throw-HcrError $ErrorCode 'The JSON document contains a NUL character.'
    }
    $index = 0
    Assert-HcrStrictJsonValue $json ([ref]$index) $ErrorCode
    Skip-HcrStrictJsonWhitespace $json ([ref]$index)
    if ($index -ne $json.Length) {
        Throw-HcrError $ErrorCode 'The JSON document contains trailing content.'
    }
    try {
        return $json | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Throw-HcrError $ErrorCode 'The JSON document is invalid.'
    }
}

function Test-HcrV2WindowsSafeRelativePath {
    param([AllowNull()][object]$Value)

    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $false
    }
    $path = [string]$Value
    if ($path.Length -gt 512 -or
        $path -cne $path.Normalize([Text.NormalizationForm]::FormC) -or
        [IO.Path]::IsPathRooted($path) -or
        $path.StartsWith('\') -or $path.StartsWith('/') -or
        $path.Contains(':') -or $path.Contains('%') -or
        $path.IndexOf([char]0) -ge 0) {
        return $false
    }
    foreach ($segment in ($path -split '[\\/]')) {
        if ([string]::IsNullOrWhiteSpace($segment) -or
            $segment -eq '.' -or $segment -eq '..' -or
            $segment.EndsWith('.') -or $segment.EndsWith(' ') -or
            $segment.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            return $false
        }
        foreach ($character in $segment.ToCharArray()) {
            if ([int]$character -lt 32 -or [int]$character -eq 127) {
                return $false
            }
        }
        $stem = ($segment -split '\.')[0]
        if ($stem -match '^(?i:CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|COM[1-9\u00B9\u00B2\u00B3]|LPT[1-9\u00B9\u00B2\u00B3])$') {
            return $false
        }
    }
    return $true
}

function Get-HcrV2PortableInventoryIdentity {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Files)

    $lines = New-Object System.Collections.Generic.List[string]
    $total = [int64]0
    foreach ($file in $Files) {
        $path = ([string](Get-HcrPropertyValue $file 'path')).Replace('\', '/').Normalize(
            [Text.NormalizationForm]::FormC
        )
        $size = [int64](Get-HcrPropertyValue $file 'size')
        $sha256 = ([string](Get-HcrPropertyValue $file 'sha256')).ToLowerInvariant()
        $total += $size
        $lines.Add("$path`t$size`t$sha256")
    }
    $array = $lines.ToArray()
    [Array]::Sort($array, [StringComparer]::Ordinal)
    return [pscustomobject][ordered]@{
        fileCount = $Files.Count
        payloadSizeBytes = $total
        sha256 = Get-HcrSha256Text ([string]::Join("`n", $array))
    }
}

function Get-HcrV2DocumentationInventoryDigest {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Files)
    $byArchivePath = New-Object 'Collections.Generic.Dictionary[string,object]' (
        [StringComparer]::Ordinal
    )
    foreach ($file in $Files) {
        $archivePath = [string](Get-HcrPropertyValue $file 'archivePath')
        if ($byArchivePath.ContainsKey($archivePath)) {
            Throw-HcrError 'PORTABLE_MANIFEST_INVALID' 'The documentation inventory contains a duplicate archive path.'
        }
        $byArchivePath.Add($archivePath, $file)
    }
    [string[]]$paths = @($byArchivePath.Keys)
    [Array]::Sort($paths, [StringComparer]::Ordinal)
    $builder = New-Object Text.StringBuilder
    foreach ($path in $paths) {
        $file = $byArchivePath[$path]
        [void]$builder.Append($path)
        [void]$builder.Append([char]0)
        [void]$builder.Append([string][int64](Get-HcrPropertyValue $file 'size'))
        [void]$builder.Append([char]0)
        [void]$builder.Append(([string](Get-HcrPropertyValue $file 'sha256')).ToLowerInvariant())
        [void]$builder.Append([char]0)
        [void]$builder.Append([string](Get-HcrPropertyValue $file 'sourcePath'))
        [void]$builder.Append("`n")
    }
    return Get-HcrSha256Text $builder.ToString()
}

function Test-HcrV2Sha256 {
    param([AllowNull()][object]$Value)
    return $Value -is [string] -and $Value -cmatch '^[a-f0-9]{64}$'
}

function Test-HcrV2BoundedInteger {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][decimal]$Minimum,
        [Parameter(Mandatory = $true)][decimal]$Maximum
    )
    return (Test-HcrInteger $Value) -and
        [decimal]$Value -ge $Minimum -and [decimal]$Value -le $Maximum
}

function Test-HcrV2BoundedString {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][int]$Maximum
    )
    return $Value -is [string] -and $Value.Length -ge 1 -and
        $Value.Length -le $Maximum
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

function Test-HcrV2ExternalFileInventory {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Errors
    )

    if ($null -eq $Value -or $Value -is [string] -or
        -not ($Value -is [Collections.IEnumerable]) -or
        (Test-HcrObjectLike $Value)) {
        Add-HcrValidationError $Errors "$Path must be an array."
        return
    }
    $items = @($Value)
    if ($items.Count -gt 4096) {
        Add-HcrValidationError $Errors "$Path exceeds the inventory bound."
        return
    }
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $items) {
        if (-not (Test-HcrV2ClosedObject `
                $item `
                @('path', 'size', 'sha256') `
                @('path', 'size', 'sha256') `
                "$Path[]" `
                $Errors)) {
            continue
        }
        $itemPath = [string](Get-HcrPropertyValue $item 'path')
        $size = Get-HcrPropertyValue $item 'size'
        if (-not (Test-HcrV2WindowsSafeRelativePath $itemPath) -or
            -not $seen.Add($itemPath) -or
            -not (Test-HcrInteger $size) -or [decimal]$size -lt 0 -or
            [decimal]$size -gt 2GB -or
            -not (Test-HcrV2Sha256 (Get-HcrPropertyValue $item 'sha256'))) {
            Add-HcrValidationError $Errors "$Path contains an invalid or colliding file identity."
        }
    }
}

function Test-HcrV2ExternalManifestProvenance {
    param(
        [Parameter(Mandatory = $true)][object]$Manifest,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Errors
    )

    $sbom = Get-HcrPropertyValue $Manifest 'sbom'
    if (Test-HcrV2ClosedObject `
            $sbom `
            @('path', 'size', 'sha256', 'derivedFromPath') `
            @('path', 'size', 'sha256', 'derivedFromPath') `
            '$manifest.sbom' `
            $Errors) {
        $sbomSize = Get-HcrPropertyValue $sbom 'size'
        if (-not (Test-HcrV2WindowsSafeRelativePath (
                    Get-HcrPropertyValue $sbom 'path'
                )) -or
            -not (Test-HcrInteger $sbomSize) -or [decimal]$sbomSize -lt 1 -or
            [decimal]$sbomSize -gt 1GB -or
            -not (Test-HcrV2Sha256 (Get-HcrPropertyValue $sbom 'sha256')) -or
            -not (Test-HcrV2WindowsSafeRelativePath (
                    Get-HcrPropertyValue $sbom 'derivedFromPath'
                ))) {
            Add-HcrValidationError $Errors '$manifest.sbom is invalid.'
        }
    }

    if (Test-HcrProperty $Manifest 'host') {
        $hostIdentity = Get-HcrPropertyValue $Manifest 'host'
        if (Test-HcrV2ClosedObject `
                $hostIdentity `
                @('path', 'size', 'sha256', 'machine', 'authenticode') `
                @('path', 'size', 'sha256', 'machine', 'authenticode') `
                '$manifest.host' `
                $Errors) {
            $hostSize = Get-HcrPropertyValue $hostIdentity 'size'
            if (-not (Test-HcrV2WindowsSafeRelativePath (
                        Get-HcrPropertyValue $hostIdentity 'path'
                    )) -or
                -not (Test-HcrInteger $hostSize) -or [decimal]$hostSize -lt 1 -or
                [decimal]$hostSize -gt 2GB -or
                -not (Test-HcrV2Sha256 (
                        Get-HcrPropertyValue $hostIdentity 'sha256'
                    )) -or
                (Get-HcrPropertyValue $hostIdentity 'machine') -ne 'AMD64' -or
                @('NotSigned', 'Valid', 'UnknownError', 'HashMismatch') -notcontains
                    (Get-HcrPropertyValue $hostIdentity 'authenticode')) {
                Add-HcrValidationError $Errors '$manifest.host is invalid.'
            }
        }
    }

    if (Test-HcrProperty $Manifest 'webView2') {
        $webView2 = Get-HcrPropertyValue $Manifest 'webView2'
        $requiredWebView2 = @(
            'trackedManifest', 'trackedManifestSha256', 'version',
            'architecture', 'rootDirectory', 'archiveSize', 'archiveSha256',
            'fileCount', 'totalSize'
        )
        if (Test-HcrV2ClosedObject `
                $webView2 `
                @($requiredWebView2 + @('inventorySha256', 'files')) `
                $requiredWebView2 `
                '$manifest.webView2' `
                $Errors) {
            $archiveSize = Get-HcrPropertyValue $webView2 'archiveSize'
            $fileCount = Get-HcrPropertyValue $webView2 'fileCount'
            $totalSize = Get-HcrPropertyValue $webView2 'totalSize'
            if (-not (Test-HcrV2WindowsSafeRelativePath (
                        Get-HcrPropertyValue $webView2 'trackedManifest'
                    )) -or
                -not (Test-HcrV2Sha256 (
                        Get-HcrPropertyValue $webView2 'trackedManifestSha256'
                    )) -or
                [string](Get-HcrPropertyValue $webView2 'version') -notmatch
                    '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' -or
                (Get-HcrPropertyValue $webView2 'architecture') -ne 'x64' -or
                -not (Test-HcrV2WindowsSafeRelativePath (
                        Get-HcrPropertyValue $webView2 'rootDirectory'
                    )) -or
                -not (Test-HcrInteger $archiveSize) -or
                [decimal]$archiveSize -lt 1 -or [decimal]$archiveSize -gt 2GB -or
                -not (Test-HcrV2Sha256 (
                        Get-HcrPropertyValue $webView2 'archiveSha256'
                    )) -or
                -not (Test-HcrInteger $fileCount) -or
                [decimal]$fileCount -lt 1 -or [decimal]$fileCount -gt 4096 -or
                -not (Test-HcrInteger $totalSize) -or
                [decimal]$totalSize -lt 1 -or [decimal]$totalSize -gt 8GB) {
                Add-HcrValidationError $Errors '$manifest.webView2 is invalid.'
            }
            if (Test-HcrProperty $webView2 'inventorySha256') {
                if (-not (Test-HcrV2Sha256 (
                            Get-HcrPropertyValue $webView2 'inventorySha256'
                        ))) {
                    Add-HcrValidationError $Errors '$manifest.webView2.inventorySha256 is invalid.'
                }
            }
            if (Test-HcrProperty $webView2 'files') {
                $webViewFiles = @((Get-HcrPropertyValue $webView2 'files'))
                Test-HcrV2ExternalFileInventory `
                    $webViewFiles `
                    '$manifest.webView2.files' `
                    $Errors
                try {
                    $webViewInventory = Get-HcrV2PortableInventoryIdentity $webViewFiles
                    if ([int](Get-HcrPropertyValue $webView2 'fileCount') -ne
                            [int]$webViewInventory.fileCount -or
                        [int64](Get-HcrPropertyValue $webView2 'totalSize') -ne
                            [int64]$webViewInventory.payloadSizeBytes -or
                        (Test-HcrProperty $webView2 'inventorySha256') -and
                            [string](Get-HcrPropertyValue $webView2 'inventorySha256') -cne
                                [string]$webViewInventory.sha256) {
                        Add-HcrValidationError $Errors '$manifest.webView2 inventory summary is inconsistent.'
                    }
                }
                catch {
                    Add-HcrValidationError $Errors '$manifest.webView2 inventory could not be derived.'
                }
            }
        }
    }

    if (Test-HcrProperty $Manifest 'sourceInputs') {
        $sourceInputs = Get-HcrPropertyValue $Manifest 'sourceInputs'
        $sourceFields = @(
            'birdsgoneTrackedFiles', 'excludedBirdsgoneTrackedFiles',
            'preparedAgentFiles', 'maaInventoriedFiles', 'maaInventoryAuthority'
        )
        if (Test-HcrV2ClosedObject `
                $sourceInputs $sourceFields $sourceFields `
                '$manifest.sourceInputs' $Errors) {
            foreach ($field in @(
                    'birdsgoneTrackedFiles', 'preparedAgentFiles',
                    'maaInventoriedFiles'
                )) {
                Test-HcrV2ExternalFileInventory `
                    (Get-HcrPropertyValue $sourceInputs $field) `
                    "$.manifest.sourceInputs.$field" `
                    $Errors
            }
            $excluded = Get-HcrPropertyValue $sourceInputs 'excludedBirdsgoneTrackedFiles'
            if ($null -eq $excluded -or $excluded -is [string] -or
                -not ($excluded -is [Collections.IEnumerable]) -or
                (Test-HcrObjectLike $excluded) -or @($excluded).Count -gt 4096) {
                Add-HcrValidationError $Errors '$manifest.sourceInputs.excludedBirdsgoneTrackedFiles must be a bounded array.'
            }
            else {
                foreach ($path in @($excluded)) {
                    if (-not (Test-HcrV2WindowsSafeRelativePath $path)) {
                        Add-HcrValidationError $Errors '$manifest.sourceInputs.excludedBirdsgoneTrackedFiles contains an unsafe path.'
                    }
                }
            }
            if (-not (Test-HcrV2WindowsSafeRelativePath (
                        Get-HcrPropertyValue $sourceInputs 'maaInventoryAuthority'
                    ))) {
                Add-HcrValidationError $Errors '$manifest.sourceInputs.maaInventoryAuthority is invalid.'
            }
        }
    }

    if (Test-HcrProperty $Manifest 'maa') {
        $maa = Get-HcrPropertyValue $Manifest 'maa'
        $maaFields = @(
            'runtimeManifestPath', 'runtimeManifestSha256',
            'nativeInventoryPath', 'nativeInventorySha256', 'runtimeVersion',
            'bindingVersion', 'platform', 'agent'
        )
        if (Test-HcrV2ClosedObject $maa $maaFields $maaFields '$manifest.maa' $Errors) {
            foreach ($field in @('runtimeManifestPath', 'nativeInventoryPath')) {
                if (-not (Test-HcrV2WindowsSafeRelativePath (
                            Get-HcrPropertyValue $maa $field
                        ))) {
                    Add-HcrValidationError $Errors "$.manifest.maa.$field is invalid."
                }
            }
            foreach ($field in @('runtimeManifestSha256', 'nativeInventorySha256')) {
                if (-not (Test-HcrV2Sha256 (Get-HcrPropertyValue $maa $field))) {
                    Add-HcrValidationError $Errors "$.manifest.maa.$field is invalid."
                }
            }
            foreach ($field in @('runtimeVersion', 'bindingVersion', 'platform')) {
                $value = [string](Get-HcrPropertyValue $maa $field)
                $maximum = if ($field -eq 'platform') { 128 } else { 64 }
                if ($value.Length -lt 1 -or $value.Length -gt $maximum) {
                    Add-HcrValidationError $Errors "$.manifest.maa.$field is invalid."
                }
            }
            $agent = Get-HcrPropertyValue $maa 'agent'
            $agentFields = @(
                'inventoryPath', 'inventorySha256', 'executablePath',
                'executableSha256', 'maaBinding', 'maaCore', 'targetTriple'
            )
            if (Test-HcrV2ClosedObject `
                    $agent $agentFields $agentFields '$manifest.maa.agent' $Errors) {
                foreach ($field in @('inventoryPath', 'executablePath')) {
                    if (-not (Test-HcrV2WindowsSafeRelativePath (
                                Get-HcrPropertyValue $agent $field
                            ))) {
                        Add-HcrValidationError $Errors "$.manifest.maa.agent.$field is invalid."
                    }
                }
                foreach ($field in @('inventorySha256', 'executableSha256')) {
                    if (-not (Test-HcrV2Sha256 (
                                Get-HcrPropertyValue $agent $field
                            ))) {
                        Add-HcrValidationError $Errors "$.manifest.maa.agent.$field is invalid."
                    }
                }
                foreach ($field in @('maaBinding', 'maaCore', 'targetTriple')) {
                    $value = [string](Get-HcrPropertyValue $agent $field)
                    $maximum = if ($field -eq 'targetTriple') { 128 } else { 64 }
                    if ($value.Length -lt 1 -or $value.Length -gt $maximum) {
                        Add-HcrValidationError $Errors "$.manifest.maa.agent.$field is invalid."
                    }
                }
            }
        }
    }

    foreach ($field in @('removedFiles')) {
        if (Test-HcrProperty $Manifest $field) {
            Test-HcrV2ExternalFileInventory `
                (Get-HcrPropertyValue $Manifest $field) `
                "$.manifest.$field" `
                $Errors
        }
    }

    foreach ($field in @('targetTriple', 'compileFeature')) {
        if (Test-HcrProperty $Manifest $field) {
            if (-not (Test-HcrV2BoundedString (
                        Get-HcrPropertyValue $Manifest $field
                    ) 128)) {
                Add-HcrValidationError $Errors "$.manifest.$field is invalid."
            }
        }
    }
    if (Test-HcrProperty $Manifest 'derivedFromZipFileName') {
        $derivedLeaf = [string](Get-HcrPropertyValue $Manifest 'derivedFromZipFileName')
        if (-not (Test-HcrV2WindowsSafeRelativePath $derivedLeaf) -or
            $derivedLeaf.Contains('\') -or $derivedLeaf.Contains('/') -or
            -not ($derivedLeaf -cmatch '\.zip$')) {
            Add-HcrValidationError $Errors '$manifest.derivedFromZipFileName is invalid.'
        }
    }
    foreach ($field in @('derivedFromZipSha256')) {
        if (Test-HcrProperty $Manifest $field) {
            if (-not (Test-HcrV2Sha256 (Get-HcrPropertyValue $Manifest $field))) {
                Add-HcrValidationError $Errors "$.manifest.$field is invalid."
            }
        }
    }
    $boundedIntegers = @(
        [pscustomobject]@{ name='derivedFromZipSize'; minimum=1; maximum=8GB },
        [pscustomobject]@{ name='oldFileCount'; minimum=0; maximum=4096 },
        [pscustomobject]@{ name='newFileCount'; minimum=1; maximum=4096 },
        [pscustomobject]@{ name='oldPayloadSize'; minimum=0; maximum=8GB },
        [pscustomobject]@{ name='newPayloadSize'; minimum=1; maximum=8GB }
    )
    foreach ($field in $boundedIntegers) {
        if (Test-HcrProperty $Manifest $field.name) {
            if (-not (Test-HcrV2BoundedInteger `
                    (Get-HcrPropertyValue $Manifest $field.name) `
                    ([decimal]$field.minimum) `
                    ([decimal]$field.maximum))) {
                Add-HcrValidationError $Errors "$.manifest.$($field.name) is invalid."
            }
        }
    }
    if (Test-HcrProperty $Manifest 'removedPaths') {
        $removedPaths = Get-HcrPropertyValue $Manifest 'removedPaths'
        if ($null -eq $removedPaths -or $removedPaths -is [string] -or
            -not ($removedPaths -is [Collections.IEnumerable]) -or
            (Test-HcrObjectLike $removedPaths) -or @($removedPaths).Count -gt 4096) {
            Add-HcrValidationError $Errors '$manifest.removedPaths must be a bounded array.'
        }
        else {
            foreach ($path in @($removedPaths)) {
                if (-not (Test-HcrV2WindowsSafeRelativePath $path)) {
                    Add-HcrValidationError $Errors '$manifest.removedPaths contains an unsafe path.'
                }
            }
        }
    }
    if (Test-HcrProperty $Manifest 'runtimeBuildRunId') {
        $runId = Get-HcrPropertyValue $Manifest 'runtimeBuildRunId'
        if (-not (
                (Test-HcrV2BoundedString $runId 128) -or
                (Test-HcrV2BoundedInteger $runId 1 ([decimal][int64]::MaxValue))
            )) {
            Add-HcrValidationError $Errors '$manifest.runtimeBuildRunId is invalid.'
        }
    }
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
            'stopUiSession' { [pscustomobject]@{ Allowed=@(); Required=@() }; break }
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
    if (-not (Test-HcrInteger $timeout) -or [decimal]$timeout -lt 1 -or [decimal]$timeout -gt $maximum) {
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
    if ($type -eq 'assertPort') {
        $port = Get-HcrPropertyValue $Step 'port'
        if (-not (Test-HcrInteger $port) -or [decimal]$port -lt 1 -or [decimal]$port -gt 65535) {
            Add-HcrValidationError $Errors "$Path.port is outside 1..65535."
        }
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
    $externalPortable = $workflow -eq 'portableAutomation' -and
        [string](Get-HcrPropertyValue $artifact 'portableManifestSource') -eq
            'externalProfileRelative'
    if ($workflow -eq 'portableAutomation') {
        $portableFields = if ($externalPortable) {
            @(
                'packageKind', 'fileNamePattern', 'architecture', 'sha256',
                'sizeBytes', 'requiredDistributionBoundary',
                'portableManifestSource', 'portableManifestRelativePath',
                'portableManifestSizeBytes', 'portableManifestSha256'
            )
        }
        else {
            @(
                'packageKind', 'fileNamePattern', 'architecture', 'sha256',
                'sizeBytes', 'portableManifestEntryPath',
                'portableManifestSha256'
            )
        }
        [void](Test-HcrV2ClosedObject $artifact $portableFields $portableFields '$.artifact' $errors)
        if ($packageKind -ne 'portableZip' -or (Get-HcrPropertyValue $artifact 'architecture') -ne 'x64' -or
            -not (Test-HcrV2Sha256 (Get-HcrPropertyValue $artifact 'sha256')) -or
            -not (Test-HcrV2Sha256 (Get-HcrPropertyValue $artifact 'portableManifestSha256'))) {
            Add-HcrValidationError $errors '$.artifact is not a fixed portable ZIP contract.'
        }
        if ($externalPortable) {
            $manifestSize = Get-HcrPropertyValue $artifact 'portableManifestSizeBytes'
            if ((Get-HcrPropertyValue $artifact 'requiredDistributionBoundary') -ne
                    'end-user-complete' -or
                -not (Test-HcrV2WindowsSafeRelativePath (
                        Get-HcrPropertyValue $artifact 'portableManifestRelativePath'
                    )) -or
                -not (Test-HcrInteger $manifestSize) -or
                [decimal]$manifestSize -lt 1 -or
                [decimal]$manifestSize -gt 16MB) {
                Add-HcrValidationError $errors '$.artifact external manifest binding is invalid.'
            }
        }
        elseif ((Get-HcrPropertyValue $artifact 'portableManifestEntryPath') -ne
                'portable-manifest.json') {
            Add-HcrValidationError $errors '$.artifact embedded manifest entry is invalid.'
        }
        $size = Get-HcrPropertyValue $artifact 'sizeBytes'
        if (-not (Test-HcrInteger $size) -or [decimal]$size -lt 1 -or [decimal]$size -gt 8GB) { Add-HcrValidationError $errors '$.artifact.sizeBytes is invalid.' }
        $name = [string](Get-HcrPropertyValue $artifact 'fileNamePattern')
        if (($externalPortable -and (
                    -not (Test-HcrV2WindowsSafeRelativePath $name) -or
                    $name.Contains('\') -or $name.Contains('/') -or
                    -not ($name -cmatch '\.zip$')
                )) -or
            (-not $externalPortable -and
                $name -notmatch '^[^\\/:*?"<>|%]+\.zip$')) {
            Add-HcrValidationError $errors '$.artifact.fileNamePattern is invalid.'
        }
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
            if (-not (Test-HcrInteger $size) -or [decimal]$size -lt 1) {
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
        if (-not (Test-HcrInteger $fixtureSize) -or [decimal]$fixtureSize -lt 1 -or [decimal]$fixtureSize -gt 1GB) { Add-HcrValidationError $errors "$path.sizeBytes is invalid." }
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
        if (-not $externalPortable -and $fixtures.Count -lt 1) {
            Add-HcrValidationError $errors '$.fixtures requires at least one hash-bound fixture for embedded portable evidence.'
        }
        $requiredPortableStepTypes = if ($externalPortable) {
            @('deployPortable', 'launchApplication')
        }
        else {
            @('deployPortable', 'launchApplication', 'acquireWebDriver')
        }
        foreach ($requiredType in $requiredPortableStepTypes) {
            if (@($stepTypes | Where-Object { $_ -eq $requiredType }).Count -ne 1) { Add-HcrValidationError $errors "$.steps requires exactly one $requiredType." }
        }
        $cleanupTypes = @(@((Get-HcrPropertyValue $Profile 'cleanupSteps' @())) |
            ForEach-Object { [string](Get-HcrPropertyValue $_ 'type') })
        $declaresUi = @(@($stepTypes + $cleanupTypes) | Where-Object {
                $script:HcrV2UiStepTypes -contains $_
            }).Count -gt 0
        $uiRequired = -not $externalPortable -or $declaresUi
        if ($uiRequired) {
            foreach ($requiredType in @('acquireWebDriver', 'startUiSession', 'stopUiSession')) {
                if (@($stepTypes | Where-Object { $_ -eq $requiredType }).Count -ne 1) {
                    Add-HcrValidationError $errors "$.steps requires exactly one $requiredType for UI automation."
                }
            }
        }
        elseif (@($stepTypes | Where-Object {
                    $script:HcrV2UiStepTypes -contains $_
                }).Count -gt 0) {
            Add-HcrValidationError $errors '$.steps contains an incomplete UI lifecycle.'
        }
        $positions = @{}; for ($index = 0; $index -lt $stepTypes.Count; $index++) { if (-not $positions.ContainsKey($stepTypes[$index])) { $positions[$stepTypes[$index]] = $index } }
        if ($positions['deployPortable'] -le $positions['stageArtifact'] -or
            $positions['launchApplication'] -le $positions['deployPortable']) {
            Add-HcrValidationError $errors '$.steps violates the closed portable/UI lifecycle order.'
        }
        if ($uiRequired -and (
                $positions['acquireWebDriver'] -le $positions['deployPortable'] -or
                $positions['startUiSession'] -le $positions['launchApplication'] -or
                $positions['startUiSession'] -le $positions['acquireWebDriver'] -or
                $positions['stopUiSession'] -le $positions['startUiSession']
            )) {
            Add-HcrValidationError $errors '$.steps violates the closed portable/UI lifecycle order.'
        }
        if ($uiRequired -and
            $positions.ContainsKey('launchApplication') -and
            $positions.ContainsKey('startUiSession') -and
            [string](Get-HcrPropertyValue $steps[$positions['launchApplication']] 'application') -ne
                [string](Get-HcrPropertyValue $steps[$positions['startUiSession']] 'application')) {
            Add-HcrValidationError $errors '$.steps must launch the application bound to the UI session.'
        }
        $uiInteractionTypes = @('uiClick', 'uiSetText', 'uiPressKey', 'uiSelectOption', 'uiUploadFixture', 'assertUiElement', 'captureUiScreenshot')
        for ($index = 0; $index -lt $stepTypes.Count; $index++) {
            if ($uiRequired -and $uiInteractionTypes -contains $stepTypes[$index] -and
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
        if ($uiRequired) {
            if (-not (Test-HcrProperty $Profile 'webDriver')) {
                Add-HcrValidationError $errors '$.webDriver is required for portable UI automation.'
            }
            else {
                Test-HcrWebDriverManifestV2 `
                    (Get-HcrPropertyValue $Profile 'webDriver') `
                    '$.webDriver' `
                    $errors `
                    -AllowFourthSegmentDifference:$externalPortable
            }
        }
        elseif (Test-HcrProperty $Profile 'webDriver') {
            Add-HcrValidationError $errors '$.webDriver is forbidden when portable automation has no UI step.'
        }
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
        $cleanupTimeout = Get-HcrPropertyValue $cleanup[$index] 'timeoutSeconds' 0
        if ((Test-HcrInteger $cleanupTimeout) -and
            [decimal]$cleanupTimeout -ge 1 -and [decimal]$cleanupTimeout -le 120) {
            $cleanupBudgetSeconds += [int]$cleanupTimeout
        }
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
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Errors,
        [switch]$AllowFourthSegmentDifference
    )

    $fields = @('schemaVersion', 'id', 'provider', 'browserKind', 'browserVersion', 'driverVersion', 'architecture', 'acquisition', 'executable', 'sessionPolicy', 'files')
    [void](Test-HcrV2ClosedObject $Manifest $fields $fields $Path $Errors)
    $browserVersion = [string](Get-HcrPropertyValue $Manifest 'browserVersion')
    $driverVersion = [string](Get-HcrPropertyValue $Manifest 'driverVersion')
    $versionMatch = if ($AllowFourthSegmentDifference) {
        $browserParts = @($browserVersion -split '\.')
        $driverParts = @($driverVersion -split '\.')
        $browserParts.Count -eq 4 -and $driverParts.Count -eq 4 -and
            [string]::Join('.', $browserParts[0..2]) -ceq
                [string]::Join('.', $driverParts[0..2])
    }
    else {
        $browserVersion -ceq $driverVersion
    }
    if ((Get-HcrPropertyValue $Manifest 'schemaVersion') -ne 2 -or
        -not (Test-HcrIdentifier (Get-HcrPropertyValue $Manifest 'id')) -or
        (Get-HcrPropertyValue $Manifest 'provider') -ne 'microsoftEdgeDriver' -or
        (Get-HcrPropertyValue $Manifest 'browserKind') -ne 'fixedVersionWebView2' -or
        (Get-HcrPropertyValue $Manifest 'architecture') -ne 'x64' -or
        $browserVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' -or
        $driverVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' -or
        -not $versionMatch) {
        Add-HcrValidationError $Errors "$Path has an incompatible fixed driver identity."
    }
    $acquisition = Get-HcrPropertyValue $Manifest 'acquisition'
    $acquisitionFields = @('source', 'archiveFileName', 'archiveSizeBytes', 'archiveSha256', 'redirectPolicy')
    [void](Test-HcrV2ClosedObject $acquisition $acquisitionFields $acquisitionFields "$Path.acquisition" $Errors)
    $archiveSize = Get-HcrPropertyValue $acquisition 'archiveSizeBytes'
    if ((Get-HcrPropertyValue $acquisition 'source') -ne 'microsoftFixedEndpoint' -or (Get-HcrPropertyValue $acquisition 'archiveFileName') -ne 'edgedriver_win64.zip' -or (Get-HcrPropertyValue $acquisition 'redirectPolicy') -ne 'microsoftHttpsAllowlist' -or -not (Test-HcrInteger $archiveSize) -or [decimal]$archiveSize -lt 1 -or [decimal]$archiveSize -gt 512MB -or -not (Test-HcrV2Sha256 (Get-HcrPropertyValue $acquisition 'archiveSha256'))) { Add-HcrValidationError $Errors "$Path.acquisition is not fixed and hash-bound." }
    $executable = Get-HcrPropertyValue $Manifest 'executable'
    $executableFields = @('relativePath', 'sizeBytes', 'sha256', 'peArchitecture', 'authenticodePublisher')
    [void](Test-HcrV2ClosedObject $executable $executableFields $executableFields "$Path.executable" $Errors)
    $executableSize = Get-HcrPropertyValue $executable 'sizeBytes'
    if ((Get-HcrPropertyValue $executable 'relativePath') -ne 'msedgedriver.exe' -or -not (Test-HcrInteger $executableSize) -or [decimal]$executableSize -lt 1 -or [decimal]$executableSize -gt 512MB -or (Get-HcrPropertyValue $executable 'peArchitecture') -ne 'x64' -or (Get-HcrPropertyValue $executable 'authenticodePublisher') -ne 'Microsoft Corporation' -or -not (Test-HcrV2Sha256 (Get-HcrPropertyValue $executable 'sha256'))) { Add-HcrValidationError $Errors "$Path.executable is not the fixed verified driver." }
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
        if (-not (Test-HcrSafeRelativePath $relative) -or -not $paths.Add($relative) -or -not (Test-HcrInteger $size) -or [decimal]$size -lt 1 -or [decimal]$size -gt 512MB -or -not (Test-HcrV2Sha256 (Get-HcrPropertyValue $file 'sha256'))) { Add-HcrValidationError $Errors "$filePath is unsafe, duplicated, or not hash-bound." }
    }
    if (-not $paths.Contains('msedgedriver.exe')) { Add-HcrValidationError $Errors "$Path.files does not contain the fixed executable." }
}

function Test-HcrExternalPortableManifestV2 {
    param(
        [Parameter(Mandatory = $true)][object]$Manifest,
        [Parameter(Mandatory = $true)][object]$Profile
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $allowed = @(
        'schemaVersion', 'packageKind', 'distributionBoundary', 'fileName',
        'version', 'architecture', 'entrypoint', 'distributionMode', 'dataRoot',
        'unsigned', 'newZipSize', 'newZipSha256', 'documentationFiles',
        'documentationSourceCommit', 'documentationSourceTree',
        'documentationFileCount', 'documentationPayloadSize',
        'documentationInventoryDigest', 'targetTriple', 'compileFeature',
        'runtimeSourceCommit', 'runtimeSourceTree', 'packagingCommit',
        'packagingTree', 'derivedFromZipFileName', 'derivedFromZipSize',
        'derivedFromZipSha256', 'oldRuntimeInventoryDigest',
        'newRuntimeInventoryDigest', 'oldFileCount', 'newFileCount',
        'oldPayloadSize', 'newPayloadSize', 'removedPaths', 'removedFiles',
        'runtimeBuildRunId', 'sourceInputs', 'host', 'maa', 'webView2', 'sbom',
        'files'
    )
    $required = @(
        'schemaVersion', 'packageKind', 'distributionBoundary', 'fileName',
        'version', 'architecture', 'entrypoint', 'distributionMode', 'dataRoot',
        'unsigned', 'newZipSize', 'newZipSha256', 'documentationFiles',
        'documentationSourceCommit', 'documentationSourceTree',
        'documentationFileCount', 'documentationPayloadSize',
        'documentationInventoryDigest', 'runtimeSourceCommit',
        'runtimeSourceTree', 'packagingCommit', 'packagingTree',
        'oldRuntimeInventoryDigest', 'newRuntimeInventoryDigest', 'sbom',
        'files'
    )
    if (-not (Test-HcrV2ClosedObject $Manifest $allowed $required '$manifest' $errors)) {
        return [pscustomobject][ordered]@{
            valid = $false
            errors = @($errors)
            inventory = $null
            uiRequired = $false
        }
    }
    $artifact = Get-HcrPropertyValue $Profile 'artifact'
    $fileName = [string](Get-HcrPropertyValue $Manifest 'fileName')
    $entrypoint = [string](Get-HcrPropertyValue $Manifest 'entrypoint')
    $zipSize = Get-HcrPropertyValue $Manifest 'newZipSize'
    if ((Get-HcrPropertyValue $Manifest 'schemaVersion') -ne 2 -or
        (Get-HcrPropertyValue $Manifest 'packageKind') -ne
            'windows-x64-portable' -or
        (Get-HcrPropertyValue $Manifest 'distributionBoundary') -ne
            'end-user-complete' -or
        (Get-HcrPropertyValue $Manifest 'architecture') -ne 'x86_64' -or
        (Get-HcrPropertyValue $Manifest 'distributionMode') -ne
            'fixed-portable' -or
        (Get-HcrPropertyValue $Manifest 'dataRoot') -ne 'data/' -or
        (Get-HcrPropertyValue $Manifest 'unsigned') -ne $true -or
        -not (Test-HcrV2WindowsSafeRelativePath $fileName) -or
        $fileName.Contains('\') -or $fileName.Contains('/') -or
        -not ($fileName -cmatch '\.zip$') -or
        -not (Test-HcrV2WindowsSafeRelativePath $entrypoint) -or
        -not ($entrypoint -cmatch '\.exe$') -or
        [string](Get-HcrPropertyValue $Manifest 'version') -notmatch
            '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$' -or
        -not (Test-HcrInteger $zipSize) -or [decimal]$zipSize -lt 1 -or
        [decimal]$zipSize -gt 8GB -or
        -not (Test-HcrV2Sha256 (
                Get-HcrPropertyValue $Manifest 'newZipSha256'
            ))) {
        Add-HcrValidationError $errors '$manifest violates the executable end-user-complete core.'
    }
    if ($fileName -cne [string](Get-HcrPropertyValue $artifact 'fileNamePattern') -or
        [int64]$zipSize -ne [int64](Get-HcrPropertyValue $artifact 'sizeBytes') -or
        [string](Get-HcrPropertyValue $Manifest 'newZipSha256') -cne
            [string](Get-HcrPropertyValue $artifact 'sha256') -or
        [string](Get-HcrPropertyValue $artifact 'requiredDistributionBoundary') -cne
            'end-user-complete') {
        Add-HcrValidationError $errors 'PORTABLE_ARTIFACT_IDENTITY_MISMATCH'
    }
    foreach ($name in @(
            'runtimeSourceCommit', 'runtimeSourceTree', 'packagingCommit',
            'packagingTree', 'documentationSourceCommit',
            'documentationSourceTree'
        )) {
        if ([string](Get-HcrPropertyValue $Manifest $name) -notmatch
            '^[a-f0-9]{40}$') {
            Add-HcrValidationError $errors "$.manifest.$name is invalid."
        }
    }
    foreach ($name in @(
            'documentationInventoryDigest', 'oldRuntimeInventoryDigest',
            'newRuntimeInventoryDigest'
        )) {
        if (-not (Test-HcrV2Sha256 (Get-HcrPropertyValue $Manifest $name))) {
            Add-HcrValidationError $errors "$.manifest.$name is invalid."
        }
    }
    if ([string](Get-HcrPropertyValue $Manifest 'oldRuntimeInventoryDigest') -cne
        [string](Get-HcrPropertyValue $Manifest 'newRuntimeInventoryDigest')) {
        Add-HcrValidationError $errors 'The retained runtime/legal inventory digest drifted.'
    }

    $files = @((Get-HcrPropertyValue $Manifest 'files' @()))
    if ($files.Count -lt 1 -or $files.Count -gt 4096) {
        Add-HcrValidationError $errors '$manifest.files has an invalid count.'
    }
    $paths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $fileByPath = New-Object 'Collections.Generic.Dictionary[string,object]' (
        [StringComparer]::OrdinalIgnoreCase
    )
    $entrypointMatches = 0
    foreach ($file in $files) {
        [void](Test-HcrV2ClosedObject `
                $file `
                @('path', 'size', 'sha256') `
                @('path', 'size', 'sha256') `
                '$manifest.files[]' `
                $errors)
        $path = ([string](Get-HcrPropertyValue $file 'path')).Replace('\', '/')
        $size = Get-HcrPropertyValue $file 'size'
        if (-not (Test-HcrV2WindowsSafeRelativePath $path) -or
            -not $paths.Add($path) -or -not (Test-HcrInteger $size) -or
            [decimal]$size -lt 0 -or [decimal]$size -gt 2GB -or
            -not (Test-HcrV2Sha256 (Get-HcrPropertyValue $file 'sha256'))) {
            Add-HcrValidationError $errors '$manifest.files contains an invalid or colliding identity.'
            continue
        }
        $lower = $path.ToLowerInvariant()
        if ($lower -eq 'portable-manifest.json' -or
            $lower -eq 'sha256sums' -or $lower -eq 'sbom.cdx.json' -or
            $lower -eq 'licenses/sbom.cdx.json' -or $lower -eq 'data' -or
            $lower.StartsWith('data/')) {
            Add-HcrValidationError $errors '$manifest.files contains a forbidden sidecar or mutable data path.'
        }
        $fileByPath[$path] = $file
        if ([StringComparer]::OrdinalIgnoreCase.Equals($path, $entrypoint)) {
            $entrypointMatches++
            if ([int64]$size -lt 1) {
                Add-HcrValidationError $errors '$manifest.entrypoint is empty.'
            }
        }
    }
    if ($entrypointMatches -ne 1) {
        Add-HcrValidationError $errors '$manifest.entrypoint is not uniquely inventoried.'
    }

    $documentation = @((Get-HcrPropertyValue $Manifest 'documentationFiles' @()))
    if ($documentation.Count -lt 1 -or $documentation.Count -gt 4096) {
        Add-HcrValidationError $errors '$manifest.documentationFiles has an invalid count.'
    }
    $documentationSources = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $documentationArchives = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $documentationBytes = [int64]0
    foreach ($mapping in $documentation) {
        [void](Test-HcrV2ClosedObject `
                $mapping `
                @('sourcePath', 'archivePath', 'size', 'sha256') `
                @('sourcePath', 'archivePath', 'size', 'sha256') `
                '$manifest.documentationFiles[]' `
                $errors)
        $sourcePath = ([string](Get-HcrPropertyValue $mapping 'sourcePath')).Replace('\', '/')
        $archivePath = ([string](Get-HcrPropertyValue $mapping 'archivePath')).Replace('\', '/')
        $size = Get-HcrPropertyValue $mapping 'size'
        if (-not (Test-HcrV2WindowsSafeRelativePath $sourcePath) -or
            -not (Test-HcrV2WindowsSafeRelativePath $archivePath) -or
            -not $documentationSources.Add($sourcePath) -or
            -not $documentationArchives.Add($archivePath) -or
            -not (Test-HcrInteger $size) -or [decimal]$size -lt 0 -or
            -not (Test-HcrV2Sha256 (Get-HcrPropertyValue $mapping 'sha256'))) {
            Add-HcrValidationError $errors '$manifest.documentationFiles contains an invalid identity.'
            continue
        }
        $documentationBytes += [int64]$size
        $archive = if ($fileByPath.ContainsKey($archivePath)) {
            $fileByPath[$archivePath]
        }
        else { $null }
        if ($null -eq $archive -or
            [int64](Get-HcrPropertyValue $archive 'size') -ne [int64]$size -or
            [string](Get-HcrPropertyValue $archive 'sha256') -cne
                [string](Get-HcrPropertyValue $mapping 'sha256')) {
            Add-HcrValidationError $errors 'A documentation mapping is not byte-identical to the ZIP inventory.'
        }
    }
    if (-not (Test-HcrInteger (
                Get-HcrPropertyValue $Manifest 'documentationFileCount'
            )) -or
        [int](Get-HcrPropertyValue $Manifest 'documentationFileCount') -ne
            $documentation.Count -or
        -not (Test-HcrInteger (
                Get-HcrPropertyValue $Manifest 'documentationPayloadSize'
            )) -or
        [int64](Get-HcrPropertyValue $Manifest 'documentationPayloadSize') -ne
            $documentationBytes -or $documentationBytes -gt 8GB) {
        Add-HcrValidationError $errors 'The documentation inventory summary is inconsistent.'
    }
    try {
        if ((Get-HcrV2DocumentationInventoryDigest $documentation) -cne
            [string](Get-HcrPropertyValue $Manifest 'documentationInventoryDigest')) {
            Add-HcrValidationError $errors 'The canonical documentation inventory digest is inconsistent.'
        }
    }
    catch {
        Add-HcrValidationError $errors 'The canonical documentation inventory digest could not be derived.'
    }

    $manifestRelative = [string](Get-HcrPropertyValue $artifact 'portableManifestRelativePath')
    foreach ($fixture in @((Get-HcrPropertyValue $Profile 'fixtures' @()))) {
        if ([StringComparer]::OrdinalIgnoreCase.Equals(
                ([string](Get-HcrPropertyValue $fixture 'sourceRelativePath')).Replace('\', '/'),
                $manifestRelative.Replace('\', '/')
            )) {
            Add-HcrValidationError $errors 'PORTABLE_MANIFEST_FIXTURE_PATH_COLLISION'
        }
    }
    $launches = @(@((Get-HcrPropertyValue $Profile 'steps' @())) |
        Where-Object { [string](Get-HcrPropertyValue $_ 'type') -eq 'launchApplication' })
    $applications = @{}
    foreach ($application in @((Get-HcrPropertyValue $Profile 'applications' @()))) {
        $applications[[string](Get-HcrPropertyValue $application 'id')] = $application
    }
    if ($launches.Count -ne 1) {
        Add-HcrValidationError $errors 'PORTABLE_LAUNCH_IDENTITY_REQUIRED'
    }
    else {
        $application = $applications[[string](Get-HcrPropertyValue $launches[0] 'application')]
        if ($null -eq $application -or
            [string](Get-HcrPropertyValue $application 'executableRelativePath') -cne
                $entrypoint -or
            ([string](Get-HcrPropertyValue $application 'dataDirectoryRelativePath') + '/') -cne
                [string](Get-HcrPropertyValue $Manifest 'dataRoot')) {
            Add-HcrValidationError $errors 'PORTABLE_APPLICATION_IDENTITY_MISMATCH'
        }
    }

    $allSteps = @(
        @((Get-HcrPropertyValue $Profile 'steps' @())) +
        @((Get-HcrPropertyValue $Profile 'cleanupSteps' @()))
    )
    $uiRequired = @($allSteps | Where-Object {
            $script:HcrV2UiStepTypes -contains
                [string](Get-HcrPropertyValue $_ 'type')
        }).Count -gt 0
    $webDriver = Get-HcrPropertyValue $Profile 'webDriver'
    $webView2 = Get-HcrPropertyValue $Manifest 'webView2'
    if ($uiRequired) {
        if ($null -eq $webDriver -or $null -eq $webView2) {
            Add-HcrValidationError $errors 'PORTABLE_UI_COMPONENT_OR_DRIVER_REQUIRED'
        }
        else {
            $webViewVersion = [string](Get-HcrPropertyValue $webView2 'version')
            $browserVersion = [string](Get-HcrPropertyValue $webDriver 'browserVersion')
            $driverVersion = [string](Get-HcrPropertyValue $webDriver 'driverVersion')
            $webViewParts = @($webViewVersion -split '\.')
            $driverParts = @($driverVersion -split '\.')
            if ($webViewVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' -or
                (Get-HcrPropertyValue $webView2 'architecture') -ne 'x64' -or
                $browserVersion -cne $webViewVersion -or
                $webViewParts.Count -ne 4 -or $driverParts.Count -ne 4 -or
                [string]::Join('.', $webViewParts[0..2]) -cne
                    [string]::Join('.', $driverParts[0..2])) {
                Add-HcrValidationError $errors 'WEBDRIVER_VERSION_MISMATCH'
            }
        }
    }
    elseif ($null -ne $webDriver) {
        Add-HcrValidationError $errors 'The non-UI external branch must omit WebDriver.'
    }
    Test-HcrV2ExternalManifestProvenance $Manifest $errors

    $inventory = $null
    try {
        $inventory = Get-HcrV2PortableInventoryIdentity $files
    }
    catch {
        Add-HcrValidationError $errors 'The portable inventory identity could not be derived.'
    }
    return [pscustomobject][ordered]@{
        valid = $errors.Count -eq 0
        errors = @($errors | ForEach-Object { [string]$_ })
        inventory = $inventory
        uiRequired = $uiRequired
    }
}

function Resolve-HcrExternalPortableManifestV2 {
    param(
        [Parameter(Mandatory = $true)][object]$Profile,
        [Parameter(Mandatory = $true)][string]$ProfilePath
    )

    $artifact = Get-HcrPropertyValue $Profile 'artifact'
    if ([string](Get-HcrPropertyValue $artifact 'portableManifestSource') -ne
        'externalProfileRelative') {
        Throw-HcrError 'EXTERNAL_PORTABLE_BRANCH_REQUIRED' 'The profile does not select the external portable-manifest branch.'
    }
    $relative = [string](Get-HcrPropertyValue $artifact 'portableManifestRelativePath')
    if (-not (Test-HcrV2WindowsSafeRelativePath $relative)) {
        Throw-HcrError 'PORTABLE_MANIFEST_INVALID' 'The external portable-manifest path is unsafe.'
    }
    $profileRoot = Get-HcrNormalizedPath (Split-Path -Parent $ProfilePath)
    [void](Assert-HcrNoReparsePath $profileRoot 'PORTABLE_MANIFEST_INVALID')
    $path = Get-HcrNormalizedPath (Join-Path $profileRoot $relative)
    if (-not (Test-HcrPathWithin $path $profileRoot)) {
        Throw-HcrError 'PORTABLE_MANIFEST_INVALID' 'The external portable-manifest path escapes the profile directory.'
    }
    $item = Assert-HcrRegularLocalFile $path 'PORTABLE_MANIFEST_INVALID'
    if ([int64]$item.Length -gt 16MB -or
        [int64]$item.Length -ne [int64](Get-HcrPropertyValue $artifact 'portableManifestSizeBytes')) {
        Throw-HcrError 'PORTABLE_MANIFEST_SIZE_MISMATCH' 'The external portable-manifest size does not match the profile.'
    }
    $bytes = [IO.File]::ReadAllBytes($item.FullName)
    $sha256 = Get-HcrSha256File $item.FullName
    if ($sha256 -cne [string](Get-HcrPropertyValue $artifact 'portableManifestSha256')) {
        Throw-HcrError 'PORTABLE_MANIFEST_HASH_MISMATCH' 'The external portable-manifest SHA-256 does not match the profile.'
    }
    $document = ConvertFrom-HcrStrictJsonBytes $bytes 'PORTABLE_MANIFEST_INVALID'
    $validation = Test-HcrExternalPortableManifestV2 $document $Profile
    if (-not $validation.valid) {
        Throw-HcrError 'PORTABLE_MANIFEST_INVALID' 'The external portable manifest failed validation.' ([ordered]@{
            errors = @($validation.errors)
        })
    }
    return [pscustomobject][ordered]@{
        item = $item
        document = $document
        sha256 = $sha256
        sizeBytes = [int64]$item.Length
        inventory = $validation.inventory
        uiRequired = [bool]$validation.uiRequired
    }
}

function Read-AndValidate-HcrProfile {
    param([Parameter(Mandatory = $true)][string]$ProfilePath)

    $loaded = Read-HcrJsonDocument $ProfilePath 'PROFILE_INVALID' 4MB
    $version = Get-HcrExactSchemaVersion $loaded.document 'Profile'
    if ($version -eq 1) { return Read-AndValidate-HcrProfileV1 $loaded.path }
    $validation = Test-HcrProfileDocumentV2 $loaded.document
    if ($validation.valid -and
        [string](Get-HcrPropertyValue (
                Get-HcrPropertyValue $loaded.document 'artifact'
            ) 'portableManifestSource') -eq 'externalProfileRelative') {
        try {
            [void](Resolve-HcrExternalPortableManifestV2 $loaded.document $loaded.path)
        }
        catch {
            $failure = Get-HcrExceptionData $_.Exception
            $validation = [pscustomobject][ordered]@{
                valid = $false
                errors = @(
                    "External portable manifest validation failed: $($failure.code)."
                )
            }
        }
    }
    $cleanupBudgetSeconds = 0
    foreach ($cleanupStep in @((Get-HcrPropertyValue $loaded.document 'cleanupSteps' @()))) {
        $cleanupTimeout = Get-HcrPropertyValue $cleanupStep 'timeoutSeconds' 0
        if ((Test-HcrInteger $cleanupTimeout) -and
            [decimal]$cleanupTimeout -ge 1 -and [decimal]$cleanupTimeout -le 120) {
            $cleanupBudgetSeconds += [int]$cleanupTimeout
        }
    }
    return [pscustomobject][ordered]@{ path = $loaded.path; profile = $loaded.document; valid = $validation.valid; errors = @($validation.errors); cleanupBudgetSeconds = $cleanupBudgetSeconds }
}

function Test-HcrEvidenceDocumentV2 {
    param(
        [Parameter(Mandatory = $true)][object]$Evidence,
        [AllowNull()][object]$OperationRecord
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $externalPortable = [string](Get-HcrPropertyValue $Evidence 'evidenceKind') -eq
        'externalPortable'
    $fields = @('schemaVersion', 'operationId', 'createdAt', 'profile', 'candidate', 'runtime', 'baselineType', 'vm', 'guest', 'artifacts', 'automation', 'powerOperations', 'networkOperations', 'networkRecovery', 'automaticAssertions', 'manualAssertions', 'cleanupTriggered', 'cleanupResults', 'machineStatus', 'overallStatus', 'warnings')
    $requiredFields = @($fields)
    if ($externalPortable) {
        $fields = @($fields + @('evidenceKind', 'fixtureIdentities'))
        $requiredFields = @($requiredFields + @('evidenceKind', 'fixtureIdentities'))
    }
    [void](Test-HcrV2ClosedObject $Evidence $fields $requiredFields '$' $errors)
    $operationId = [string](Get-HcrPropertyValue $Evidence 'operationId')
    if ((Get-HcrPropertyValue $Evidence 'schemaVersion') -ne 2 -or -not (Test-HcrUuid $operationId)) { Add-HcrValidationError $errors '$.schemaVersion or operationId is invalid.' }
    if ($null -eq $OperationRecord -or [string](Get-HcrPropertyValue $OperationRecord 'operationId') -ne $operationId -or [int](Get-HcrPropertyValue $OperationRecord 'schemaVersion' 0) -ne 2) { Add-HcrValidationError $errors 'Immutable schema-v2 operation state is unavailable or mismatched.' }
    $profile = Get-HcrPropertyValue $Evidence 'profile'; $candidate = Get-HcrPropertyValue $Evidence 'candidate'; $runtime = Get-HcrPropertyValue $Evidence 'runtime'
    $profileFields = if ($externalPortable) {
        @('id','schemaVersion','sha256','fixtureIds')
    } else { @('id','schemaVersion','sha256') }
    [void](Test-HcrV2ClosedObject $profile $profileFields $profileFields '$.profile' $errors)
    if ((Get-HcrPropertyValue $profile 'schemaVersion') -ne 2 -or
        -not (Test-HcrV2Sha256 (Get-HcrPropertyValue $profile 'sha256'))) {
        Add-HcrValidationError $errors '$.profile provenance is invalid.'
    }
    if ($externalPortable) {
        $candidateFields = @(
            'sourceCommit','runtimeSourceCommit','runtimeSourceTree',
            'packagingCommit','packagingTree','portableZipFileName',
            'portableZipSizeBytes','portableZipSha256','portableZipSourceSha256',
            'portableZipGuestSha256','profileSha256',
            'requiredDistributionBoundary','portableManifestDistributionBoundary',
            'portableManifestSource','portableManifestRelativePath',
            'portableManifestSizeBytes','portableManifestSourceSizeBytes',
            'portableManifestGuestSizeBytes','portableManifestSha256',
            'portableManifestSourceSha256','portableManifestGuestSha256',
            'portableInventoryFileCount','portableInventorySizeBytes',
            'portableInventorySha256','documentationSourceCommit',
            'documentationSourceTree','documentationFileCount',
            'documentationPayloadSize','documentationInventoryDigest',
            'oldRuntimeInventoryDigest','newRuntimeInventoryDigest',
            'fixtureSetSha256','webDriverManifestSha256'
        )
        [void](Test-HcrV2ClosedObject $candidate $candidateFields $candidateFields '$.candidate' $errors)
        $runtimeFields = @(
            'pluginBaseVersion','pluginBuildVersion','sourceCommit',
            'installedInventorySha256','adapterMode'
        )
        [void](Test-HcrV2ClosedObject `
                $runtime $runtimeFields $runtimeFields '$.runtime' $errors)
        foreach ($field in @(
                'sourceCommit','runtimeSourceCommit','runtimeSourceTree',
                'packagingCommit','packagingTree','documentationSourceCommit',
                'documentationSourceTree'
            )) {
            if ([string](Get-HcrPropertyValue $candidate $field) -notmatch
                '^[a-f0-9]{40}$') {
                Add-HcrValidationError $errors "$.candidate.$field is invalid."
            }
        }
        foreach ($field in @(
                'portableZipSha256','portableZipSourceSha256',
                'portableZipGuestSha256','profileSha256','portableManifestSha256',
                'portableManifestSourceSha256','portableManifestGuestSha256',
                'portableInventorySha256','documentationInventoryDigest',
                'oldRuntimeInventoryDigest','newRuntimeInventoryDigest',
                'fixtureSetSha256'
            )) {
            if (-not (Test-HcrV2Sha256 (Get-HcrPropertyValue $candidate $field))) {
                Add-HcrValidationError $errors "$.candidate.$field is invalid."
            }
        }
        $driverHash = Get-HcrPropertyValue $candidate 'webDriverManifestSha256'
        if ($null -ne $driverHash -and -not (Test-HcrV2Sha256 $driverHash)) {
            Add-HcrValidationError $errors '$.candidate.webDriverManifestSha256 is invalid.'
        }
        if ((Get-HcrPropertyValue $candidate 'requiredDistributionBoundary') -ne
                'end-user-complete' -or
            (Get-HcrPropertyValue $candidate 'portableManifestDistributionBoundary') -ne
                'end-user-complete' -or
            (Get-HcrPropertyValue $candidate 'portableManifestSource') -ne
                'externalProfileRelative') {
            Add-HcrValidationError $errors '$.candidate external dispatch boundary is invalid.'
        }
        $zipLeaf = [string](Get-HcrPropertyValue $candidate 'portableZipFileName')
        $manifestRelative = [string](Get-HcrPropertyValue $candidate 'portableManifestRelativePath')
        if (-not (Test-HcrV2WindowsSafeRelativePath $zipLeaf) -or
            $zipLeaf.Contains('\') -or $zipLeaf.Contains('/') -or
            -not ($zipLeaf -cmatch '\.zip$') -or
            -not (Test-HcrV2WindowsSafeRelativePath $manifestRelative)) {
            Add-HcrValidationError $errors '$.candidate external portable paths are invalid.'
        }
        foreach ($bound in @(
                [pscustomobject]@{ name='portableZipSizeBytes'; minimum=1; maximum=8GB },
                [pscustomobject]@{ name='portableManifestSizeBytes'; minimum=1; maximum=16MB },
                [pscustomobject]@{ name='portableManifestSourceSizeBytes'; minimum=1; maximum=16MB },
                [pscustomobject]@{ name='portableManifestGuestSizeBytes'; minimum=1; maximum=16MB },
                [pscustomobject]@{ name='portableInventoryFileCount'; minimum=1; maximum=4096 },
                [pscustomobject]@{ name='portableInventorySizeBytes'; minimum=1; maximum=8GB },
                [pscustomobject]@{ name='documentationFileCount'; minimum=1; maximum=4096 },
                [pscustomobject]@{ name='documentationPayloadSize'; minimum=0; maximum=8GB }
            )) {
            if (-not (Test-HcrV2BoundedInteger `
                    (Get-HcrPropertyValue $candidate $bound.name) `
                    ([decimal]$bound.minimum) `
                    ([decimal]$bound.maximum))) {
                Add-HcrValidationError $errors "$.candidate.$($bound.name) is invalid."
            }
        }
        if ([string](Get-HcrPropertyValue $runtime 'pluginBaseVersion') -ne '0.3.0' -or
            [string](Get-HcrPropertyValue $runtime 'pluginBuildVersion') -notmatch
                '^0\.3\.0\+codex\.[0-9]{14}$' -or
            [string](Get-HcrPropertyValue $runtime 'sourceCommit') -notmatch
                '^[a-f0-9]{40}$' -or
            -not (Test-HcrV2Sha256 (Get-HcrPropertyValue $runtime 'installedInventorySha256')) -or
            @('mock', 'production') -notcontains (Get-HcrPropertyValue $runtime 'adapterMode')) {
            Add-HcrValidationError $errors '$.runtime external provenance is invalid.'
        }
    }
    else {
        foreach ($field in @('sourceCommit', 'portableZipSha256', 'profileSha256', 'fixtureSetSha256', 'webDriverManifestSha256')) {
            $value=[string](Get-HcrPropertyValue $candidate $field)
            if (($field -eq 'sourceCommit' -and $value -notmatch '^[a-f0-9]{40}$') -or
                ($field -ne 'sourceCommit' -and -not (Test-HcrV2Sha256 $value))) {
                Add-HcrValidationError $errors "$.candidate.$field is invalid."
            }
        }
        if ((Get-HcrPropertyValue $runtime 'pluginVersion') -ne '0.2.0' -or
            [string](Get-HcrPropertyValue $runtime 'sourceCommit') -notmatch
                '^[a-f0-9]{40}$' -or
            @('mock', 'production') -notcontains (Get-HcrPropertyValue $runtime 'adapterMode')) {
            Add-HcrValidationError $errors '$.runtime provenance is invalid.'
        }
    }
    $guest = Get-HcrPropertyValue $Evidence 'guest'; $automation = Get-HcrPropertyValue $Evidence 'automation'; $vm = Get-HcrPropertyValue $Evidence 'vm'
    if ($externalPortable) {
        $guestFields = @(
            'windowsBuild','architecture','userSid','userName',
            'isAdministrator','isElevated','tokenIntegrity',
            'profilePathContainsNonAscii','orchestration'
        )
        [void](Test-HcrV2ClosedObject $guest $guestFields $guestFields '$.guest' $errors)
        $orchestration = Get-HcrPropertyValue $guest 'orchestration'
        $orchestrationFields = @(
            'userSid','isAdministrator','isElevated','tokenIntegrity'
        )
        [void](Test-HcrV2ClosedObject `
                $orchestration $orchestrationFields $orchestrationFields `
                '$.guest.orchestration' $errors)
        if (-not (Test-HcrV2BoundedString (
                    Get-HcrPropertyValue $guest 'windowsBuild'
                ) 128) -or
            (Get-HcrPropertyValue $guest 'architecture') -ne 'x64' -or
            [string](Get-HcrPropertyValue $guest 'userSid') -notmatch
                '^S-1-[0-9-]+$' -or
            -not (Test-HcrV2BoundedString (
                    Get-HcrPropertyValue $guest 'userName'
                ) 512) -or
            (Get-HcrPropertyValue $guest 'isAdministrator') -ne $false -or
            (Get-HcrPropertyValue $guest 'isElevated') -ne $false -or
            (Get-HcrPropertyValue $guest 'tokenIntegrity') -ne 'medium' -or
            (Get-HcrPropertyValue $guest 'profilePathContainsNonAscii') -isnot
                [bool] -or
            [string](Get-HcrPropertyValue $orchestration 'userSid') -notmatch
                '^S-1-[0-9-]+$' -or
            (Get-HcrPropertyValue $orchestration 'isAdministrator') -ne $true -or
            (Get-HcrPropertyValue $orchestration 'isElevated') -ne $true -or
            @('high','system') -notcontains
                (Get-HcrPropertyValue $orchestration 'tokenIntegrity')) {
            Add-HcrValidationError $errors '$.guest external identities are invalid.'
        }

        $automationFields = @(
            'deploymentId','deploymentFingerprint','dataPreserved',
            'previousDataInventorySha256','deployedDataInventorySha256',
            'webDriverManifestSha256','fixedWebView2Version',
            'webDriverVersion','loopbackOnly','uiTrace','deploymentSlotId',
            'entrypoint','uiRequired'
        )
        [void](Test-HcrV2ClosedObject `
                $automation $automationFields $automationFields `
                '$.automation' $errors)
        $previousData = Get-HcrPropertyValue $automation 'previousDataInventorySha256'
        $driverManifest = Get-HcrPropertyValue $automation 'webDriverManifestSha256'
        $fixedVersion = Get-HcrPropertyValue $automation 'fixedWebView2Version'
        $driverVersionValue = Get-HcrPropertyValue $automation 'webDriverVersion'
        $uiTrace = Get-HcrPropertyValue $automation 'uiTrace'
        if (-not (Test-HcrUuid ([string](Get-HcrPropertyValue $automation 'deploymentId'))) -or
            -not (Test-HcrV2Sha256 (
                    Get-HcrPropertyValue $automation 'deploymentFingerprint'
                )) -or
            (Get-HcrPropertyValue $automation 'dataPreserved') -isnot [bool] -or
            ($null -ne $previousData -and -not (Test-HcrV2Sha256 $previousData)) -or
            -not (Test-HcrV2Sha256 (
                    Get-HcrPropertyValue $automation 'deployedDataInventorySha256'
                )) -or
            ($null -ne $driverManifest -and
                -not (Test-HcrV2Sha256 $driverManifest)) -or
            ($null -ne $fixedVersion -and
                [string]$fixedVersion -notmatch
                    '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$') -or
            ($null -ne $driverVersionValue -and
                [string]$driverVersionValue -notmatch
                    '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$') -or
            (Get-HcrPropertyValue $automation 'loopbackOnly') -isnot [bool] -or
            $null -eq $uiTrace -or $uiTrace -is [string] -or
            -not ($uiTrace -is [Collections.IEnumerable]) -or
            (Test-HcrObjectLike $uiTrace) -or @($uiTrace).Count -gt 512 -or
            [string](Get-HcrPropertyValue $automation 'deploymentSlotId') -notmatch
                '^[a-zA-Z0-9._-]{1,128}$' -or
            -not (Test-HcrV2WindowsSafeRelativePath (
                    Get-HcrPropertyValue $automation 'entrypoint'
                )) -or
            (Get-HcrPropertyValue $automation 'uiRequired') -isnot [bool]) {
            Add-HcrValidationError $errors '$.automation external identity is invalid.'
        }
    }
    $automatic = @((Get-HcrPropertyValue $Evidence 'automaticAssertions' @())); $manual = @((Get-HcrPropertyValue $Evidence 'manualAssertions' @())); $cleanup = @((Get-HcrPropertyValue $Evidence 'cleanupResults' @()))
    foreach ($collection in @($automatic, $manual, $cleanup)) { foreach ($entry in @($collection)) { if (@('passed', 'failed', 'notPerformed', 'unsupported') -notcontains (Get-HcrPropertyValue $entry 'status')) { Add-HcrValidationError $errors 'Evidence contains an unsupported result status.' } } }
    $requiredAutomaticFailed = @($automatic | Where-Object { (Get-HcrPropertyValue $_ 'required' $true) -eq $true -and (Get-HcrPropertyValue $_ 'status') -ne 'passed' }).Count -gt 0
    $invariants = (Get-HcrPropertyValue $vm 'ownershipVerified') -eq $true -and (Get-HcrPropertyValue $guest 'isAdministrator') -eq $false -and (Get-HcrPropertyValue $guest 'isElevated') -eq $false -and (Get-HcrPropertyValue $guest 'tokenIntegrity') -eq 'medium' -and (Get-HcrPropertyValue $automation 'dataPreserved') -eq $true -and (Get-HcrPropertyValue $automation 'loopbackOnly') -eq $true
    $machineFactsPassed = -not $requiredAutomaticFailed -and $invariants
    $artifacts = @((Get-HcrPropertyValue $Evidence 'artifacts' @()))
    $uiRequired = if ($externalPortable) {
        [bool](Get-HcrPropertyValue $automation 'uiRequired' $false)
    }
    else { $true }
    $requiredRoles = @('portableZip', 'portableManifest', 'deployedPayload')
    if ($uiRequired) {
        $requiredRoles = @($requiredRoles + @('webDriverArchive','webDriverExecutable'))
    }
    foreach ($role in $requiredRoles) {
        if (@($artifacts | Where-Object { (Get-HcrPropertyValue $_ 'role') -eq $role }).Count -ne 1) { Add-HcrValidationError $errors "Evidence requires exactly one $role artifact."; $machineFactsPassed = $false }
    }
    $fixtureArtifacts = @($artifacts | Where-Object {
        (Get-HcrPropertyValue $_ 'role') -eq 'fixture'
    })
    if (-not $externalPortable -and $fixtureArtifacts.Count -lt 1) {
        Add-HcrValidationError $errors 'Embedded evidence requires at least one fixture artifact.'
        $machineFactsPassed = $false
    }
    if ($externalPortable) {
        $unexpectedDriverArtifacts = @($artifacts | Where-Object {
            @('webDriverArchive','webDriverExecutable') -contains
                (Get-HcrPropertyValue $_ 'role')
        })
        if ((-not $uiRequired -and $unexpectedDriverArtifacts.Count -ne 0) -or
            ($uiRequired -and $unexpectedDriverArtifacts.Count -ne 2)) {
            Add-HcrValidationError $errors 'External driver artifacts do not match the conditional UI branch.'
            $machineFactsPassed = $false
        }
    }
    foreach ($artifact in $artifacts) {
        $artifactFields = @(
            'role','id','fileName','sizeBytes','sourceSha256','guestSha256',
            'status'
        )
        [void](Test-HcrV2ClosedObject `
                $artifact $artifactFields $artifactFields `
                '$.artifacts[]' $errors)
        $artifactStatus = [string](Get-HcrPropertyValue $artifact 'status')
        $artifactGuestHash = Get-HcrPropertyValue $artifact 'guestSha256'
        if (@(
                'portableZip','portableManifest','fixture','webDriverArchive',
                'webDriverExecutable','deployedPayload','screenshot','trace',
                'export'
            ) -notcontains (Get-HcrPropertyValue $artifact 'role') -or
            -not (Test-HcrIdentifier (Get-HcrPropertyValue $artifact 'id')) -or
            -not (Test-HcrV2BoundedString (
                    Get-HcrPropertyValue $artifact 'fileName'
                ) 260) -or
            -not (Test-HcrV2BoundedInteger (
                    Get-HcrPropertyValue $artifact 'sizeBytes'
                ) 0 8GB) -or
            -not (Test-HcrV2Sha256 (
                    Get-HcrPropertyValue $artifact 'sourceSha256'
                )) -or
            ($null -ne $artifactGuestHash -and
                -not (Test-HcrV2Sha256 $artifactGuestHash)) -or
            @('passed','failed','notPerformed','unsupported') -notcontains
                $artifactStatus) {
            Add-HcrValidationError $errors '$.artifacts[] identity is invalid.'
            $machineFactsPassed = $false
        }
        if ($artifactStatus -ne 'passed') { $machineFactsPassed = $false }
        if (($artifactStatus -eq 'passed' -or $null -ne $artifactGuestHash) -and
            [string](Get-HcrPropertyValue $artifact 'sourceSha256') -ne [string]$artifactGuestHash) {
            Add-HcrValidationError $errors "Artifact role '$([string](Get-HcrPropertyValue $artifact 'role'))' has hash drift."
            $machineFactsPassed = $false
        }
    }
    if ([string](Get-HcrPropertyValue $profile 'sha256') -ne [string](Get-HcrPropertyValue $candidate 'profileSha256')) { Add-HcrValidationError $errors 'The profile hash is not bound to the candidate.'; $machineFactsPassed = $false }
    if ([string](Get-HcrPropertyValue $automation 'webDriverManifestSha256') -ne
        [string](Get-HcrPropertyValue $candidate 'webDriverManifestSha256')) {
        Add-HcrValidationError $errors 'The WebDriver manifest hash is not bound to the candidate.'
        $machineFactsPassed = $false
    }
    $browserVersion = Get-HcrPropertyValue $automation 'fixedWebView2Version'
    $driverVersion = Get-HcrPropertyValue $automation 'webDriverVersion'
    if ($externalPortable) {
        if (-not $uiRequired -and ($null -ne $browserVersion -or $null -ne $driverVersion -or
                $null -ne (Get-HcrPropertyValue $candidate 'webDriverManifestSha256'))) {
            Add-HcrValidationError $errors 'The non-UI external branch must omit driver identity.'
            $machineFactsPassed = $false
        }
        elseif ($uiRequired) {
            $browserSegments = ([string]$browserVersion).Split('.')
            $driverSegments = ([string]$driverVersion).Split('.')
            if ($browserSegments.Count -ne 4 -or $driverSegments.Count -ne 4 -or
                ($browserSegments[0..2] -join '.') -cne
                    ($driverSegments[0..2] -join '.')) {
                Add-HcrValidationError $errors 'The external WebView2 and driver first-three version segments do not match.'
                $machineFactsPassed = $false
            }
        }
    }
    elseif ([string]$browserVersion -ne [string]$driverVersion) {
        Add-HcrValidationError $errors 'The fixed WebView2 and WebDriver versions do not match.'
        $machineFactsPassed = $false
    }
    $portableArtifacts = @($artifacts | Where-Object { (Get-HcrPropertyValue $_ 'role') -eq 'portableZip' })
    if ($portableArtifacts.Count -eq 1 -and [string](Get-HcrPropertyValue $portableArtifacts[0] 'sourceSha256') -ne [string](Get-HcrPropertyValue $candidate 'portableZipSha256')) { Add-HcrValidationError $errors 'The portable ZIP hash is not bound to the candidate.'; $machineFactsPassed = $false }
    if ($externalPortable) {
        if ([string](Get-HcrPropertyValue $candidate 'portableZipSha256') -cne
                [string](Get-HcrPropertyValue $candidate 'portableZipSourceSha256') -or
            [string](Get-HcrPropertyValue $candidate 'portableZipSha256') -cne
                [string](Get-HcrPropertyValue $candidate 'portableZipGuestSha256') -or
            [string](Get-HcrPropertyValue $candidate 'portableManifestSha256') -cne
                [string](Get-HcrPropertyValue $candidate 'portableManifestSourceSha256') -or
            [string](Get-HcrPropertyValue $candidate 'portableManifestSha256') -cne
                [string](Get-HcrPropertyValue $candidate 'portableManifestGuestSha256') -or
            [int64](Get-HcrPropertyValue $candidate 'portableManifestSizeBytes') -ne
                [int64](Get-HcrPropertyValue $candidate 'portableManifestSourceSizeBytes') -or
            [int64](Get-HcrPropertyValue $candidate 'portableManifestSizeBytes') -ne
                [int64](Get-HcrPropertyValue $candidate 'portableManifestGuestSizeBytes') -or
            [string](Get-HcrPropertyValue $candidate 'oldRuntimeInventoryDigest') -cne
                [string](Get-HcrPropertyValue $candidate 'newRuntimeInventoryDigest')) {
            Add-HcrValidationError $errors 'External candidate source/guest or retained-runtime bindings drifted.'
            $machineFactsPassed = $false
        }
        $manifestArtifacts = @($artifacts | Where-Object {
            (Get-HcrPropertyValue $_ 'role') -eq 'portableManifest'
        })
        $payloadArtifacts = @($artifacts | Where-Object {
            (Get-HcrPropertyValue $_ 'role') -eq 'deployedPayload'
        })
        if ($manifestArtifacts.Count -eq 1 -and (
                [int64](Get-HcrPropertyValue $manifestArtifacts[0] 'sizeBytes') -ne
                    [int64](Get-HcrPropertyValue $candidate 'portableManifestSizeBytes') -or
                [string](Get-HcrPropertyValue $manifestArtifacts[0] 'sourceSha256') -cne
                    [string](Get-HcrPropertyValue $candidate 'portableManifestSha256')
            )) {
            Add-HcrValidationError $errors 'External manifest artifact is not bound to the candidate.'
            $machineFactsPassed = $false
        }
        if ($payloadArtifacts.Count -eq 1 -and (
                [int64](Get-HcrPropertyValue $payloadArtifacts[0] 'sizeBytes') -ne
                    [int64](Get-HcrPropertyValue $candidate 'portableInventorySizeBytes') -or
                [string](Get-HcrPropertyValue $payloadArtifacts[0] 'sourceSha256') -cne
                    [string](Get-HcrPropertyValue $candidate 'portableInventorySha256')
            )) {
            Add-HcrValidationError $errors 'External deployed inventory is not bound to the candidate.'
            $machineFactsPassed = $false
        }
        $fixtureIdentities = @((Get-HcrPropertyValue $Evidence 'fixtureIdentities' @()))
        $profileFixtureIds = @((Get-HcrPropertyValue $profile 'fixtureIds' @()))
        if (($profileFixtureIds -join "`n") -cne
            (@($fixtureIdentities | ForEach-Object {
                        [string](Get-HcrPropertyValue $_ 'id')
                    }) -join "`n") -or
            $fixtureIdentities.Count -ne $fixtureArtifacts.Count) {
            Add-HcrValidationError $errors 'External fixture identities do not match the validated profile identity.'
            $machineFactsPassed = $false
        }
        foreach ($fixture in $fixtureIdentities) {
            $fixtureFields = @(
                'id','sourceRelativePath','profileSizeBytes','sourceSizeBytes',
                'guestSizeBytes','profileSha256','sourceSha256','guestSha256',
                'status'
            )
            [void](Test-HcrV2ClosedObject `
                    $fixture $fixtureFields $fixtureFields `
                    '$.fixtureIdentities[]' $errors)
            if (-not (Test-HcrIdentifier (Get-HcrPropertyValue $fixture 'id')) -or
                -not (Test-HcrV2WindowsSafeRelativePath (
                        Get-HcrPropertyValue $fixture 'sourceRelativePath'
                    )) -or
                -not (Test-HcrV2BoundedInteger (
                        Get-HcrPropertyValue $fixture 'profileSizeBytes'
                    ) 1 1GB) -or
                -not (Test-HcrV2BoundedInteger (
                        Get-HcrPropertyValue $fixture 'sourceSizeBytes'
                    ) 1 1GB) -or
                -not (Test-HcrV2BoundedInteger (
                        Get-HcrPropertyValue $fixture 'guestSizeBytes'
                    ) 1 1GB) -or
                -not (Test-HcrV2Sha256 (
                        Get-HcrPropertyValue $fixture 'profileSha256'
                    )) -or
                -not (Test-HcrV2Sha256 (
                        Get-HcrPropertyValue $fixture 'sourceSha256'
                    )) -or
                -not (Test-HcrV2Sha256 (
                        Get-HcrPropertyValue $fixture 'guestSha256'
                    )) -or
                @('passed','failed','notPerformed','unsupported') -notcontains
                    (Get-HcrPropertyValue $fixture 'status')) {
                Add-HcrValidationError $errors '$.fixtureIdentities[] identity is invalid.'
                $machineFactsPassed = $false
            }
            if ((Get-HcrPropertyValue $fixture 'status') -ne 'passed' -or
                [int64](Get-HcrPropertyValue $fixture 'profileSizeBytes') -ne
                    [int64](Get-HcrPropertyValue $fixture 'sourceSizeBytes') -or
                [int64](Get-HcrPropertyValue $fixture 'profileSizeBytes') -ne
                    [int64](Get-HcrPropertyValue $fixture 'guestSizeBytes') -or
                [string](Get-HcrPropertyValue $fixture 'profileSha256') -cne
                    [string](Get-HcrPropertyValue $fixture 'sourceSha256') -or
                [string](Get-HcrPropertyValue $fixture 'profileSha256') -cne
                    [string](Get-HcrPropertyValue $fixture 'guestSha256')) {
                Add-HcrValidationError $errors 'An external fixture source/guest binding drifted.'
                $machineFactsPassed = $false
            }
        }
    }
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
        $attestationBindings = @(
            'sourceCommit','portableZipSha256','profileSha256',
            'fixtureSetSha256','webDriverManifestSha256'
        )
        if ($externalPortable) {
            $attestationBindings = @(
                $attestationBindings + @(
                    'runtimeSourceCommit','runtimeSourceTree','packagingCommit',
                    'packagingTree','portableZipFileName','portableZipSizeBytes',
                    'portableZipSourceSha256','portableZipGuestSha256',
                    'requiredDistributionBoundary',
                    'portableManifestDistributionBoundary',
                    'portableManifestSource','portableManifestRelativePath',
                    'portableManifestSizeBytes','portableManifestSourceSizeBytes',
                    'portableManifestGuestSizeBytes','portableManifestSha256',
                    'portableManifestSourceSha256','portableManifestGuestSha256',
                    'portableInventoryFileCount','portableInventorySizeBytes',
                    'portableInventorySha256','documentationSourceCommit',
                    'documentationSourceTree','documentationFileCount',
                    'documentationPayloadSize','documentationInventoryDigest',
                    'oldRuntimeInventoryDigest','newRuntimeInventoryDigest'
                )
            )
        }
        foreach ($field in $attestationBindings) {
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
        if ($externalPortable) {
            foreach ($binding in @(
                    'portableZipSourceSha256','portableZipGuestSha256',
                    'portableManifestRelativePath','portableManifestSizeBytes',
                    'portableManifestSourceSizeBytes','portableManifestGuestSizeBytes',
                    'portableManifestSha256','portableManifestSourceSha256',
                    'portableManifestGuestSha256','portableInventorySha256'
                )) {
                if ([string](Get-HcrPropertyValue $candidate $binding) -cne
                    [string](Get-HcrPropertyValue $OperationRecord $binding)) {
                    Add-HcrValidationError $errors "$.candidate.$binding does not match immutable external operation state."
                }
            }
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

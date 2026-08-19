from __future__ import annotations

import hashlib
import json
import os
import re
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource


ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / "hyperv-clean-room"
CONTRACT = ROOT / "contracts" / "v2"
V1_NAMES = (
    "checkpoint-plan.schema.json",
    "evidence.schema.json",
    "operation-envelope.schema.json",
    "test-profile.schema.json",
    "vm-plan.schema.json",
)
V2_NAMES = (
    "evidence.schema.json",
    "operation-envelope.schema.json",
    "portable-manifest.schema.json",
    "test-profile.schema.json",
    "vm-network-plan.schema.json",
    "vm-power-plan.schema.json",
    "webdriver-manifest.schema.json",
)


def read(path: Path) -> str:
    data = path.read_bytes()
    if data.startswith(b"\xef\xbb\xbf"):
        raise AssertionError(f"UTF-8 BOM found: {path.relative_to(ROOT)}")
    return data.decode("utf-8", errors="strict")


def load(path: Path) -> object:
    return json.loads(read(path))


def load_strict(path: Path) -> object:
    """Mirror the external sidecar's wire-format invariants in test fixtures."""

    raw = path.read_bytes()
    if raw.startswith(b"\xef\xbb\xbf"):
        raise AssertionError(f"external sidecar has a UTF-8 BOM: {path.relative_to(ROOT)}")
    if b"\0" in raw:
        raise AssertionError(f"external sidecar has a NUL byte: {path.relative_to(ROOT)}")

    def reject_duplicate_properties(pairs: list[tuple[str, object]]) -> dict[str, object]:
        result: dict[str, object] = {}
        for key, value in pairs:
            if key in result:
                raise AssertionError(
                    f"external sidecar has a duplicate JSON property {key!r}: "
                    f"{path.relative_to(ROOT)}"
                )
            result[key] = value
        return result

    return json.loads(raw.decode("utf-8", errors="strict"), object_pairs_hook=reject_duplicate_properties)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require_tokens(source: str, label: str, tokens: tuple[str, ...]) -> None:
    missing = [token for token in tokens if token not in source]
    if missing:
        raise AssertionError(f"{label} is missing required P3.2 seam(s): {', '.join(missing)}")


def main() -> int:
    compatibility = load(CONTRACT / "compatibility.json")
    catalog = load(CONTRACT / "tool-catalog.json")
    manifest = load(PLUGIN / ".codex-plugin" / "plugin.json")
    if not re.fullmatch(
        r"0\.4\.1(?:\+codex\.[a-z0-9]+(?:-[a-z0-9]+)*)?",
        str(manifest["version"]),
    ):
        raise AssertionError(
            "the integrated plugin version must expose base 0.4.1 with at "
            "most one Codex cachebuster"
        )
    if (
        catalog["targetPluginVersion"] != "0.3.0"
        or compatibility["targetPluginVersion"] != "0.3.0"
        or catalog["currentRuntimeVersion"] != "0.4.1"
        or compatibility["currentRuntimeVersion"] != "0.4.1"
    ):
        raise AssertionError("P3.2 target/runtime integration metadata drifted")
    if len(catalog["tools"]) != 20:
        raise AssertionError("the integrated target must expose exactly 20 tools")

    v1_hashes = compatibility["schemaV1Sha256"]
    for name in V1_NAMES:
        if sha(PLUGIN / "schemas" / name) != v1_hashes[name]:
            raise AssertionError(f"schema-v1 bytes drifted: {name}")
    for name in V2_NAMES:
        source = CONTRACT / "schemas" / name
        installed = PLUGIN / "schemas" / "v2" / name
        if source.read_bytes() != installed.read_bytes():
            raise AssertionError(f"installable schema-v2 copy drifted: {name}")

    common = read(PLUGIN / "mcp" / "lib" / "Common.ps1")
    runtime = read(PLUGIN / "mcp" / "lib" / "Runtime.ps1")
    server = read(PLUGIN / "mcp" / "server.ps1")
    host_v1 = read(PLUGIN / "mcp" / "lib" / "Tools.Host.ps1")
    host_v2 = read(PLUGIN / "mcp" / "lib" / "Tools.Host.V2.ps1")
    guest_v1 = read(PLUGIN / "mcp" / "lib" / "Tools.Guest.ps1")
    guest_v2 = read(PLUGIN / "mcp" / "lib" / "Tools.Guest.V2.ps1")
    worker = read(PLUGIN / "mcp" / "lib" / "GuestWorker.ps1")
    validation_v1 = read(PLUGIN / "mcp" / "lib" / "Validation.ps1")
    validation = read(PLUGIN / "mcp" / "lib" / "Validation.V2.ps1")
    adapters = read(PLUGIN / "mcp" / "lib" / "Adapters.ps1")
    state = read(PLUGIN / "mcp" / "lib" / "State.ps1")
    migration = read(PLUGIN / "mcp" / "Migrate-TestProfile.ps1")

    for token in ("$script:HcrPluginVersion = '0.4.1'", "plan_vm_power", "apply_vm_power", "plan_vm_network", "apply_vm_network"):
        if token not in common:
            raise AssertionError(f"integrated runtime token is missing: {token}")
    for token in ("Validation.V2.ps1", "Tools.Host.V2.ps1", "Tools.Guest.V2.ps1", "$script:HcrPluginVersion"):
        if token not in server:
            raise AssertionError(f"server integration seam is missing: {token}")
    for token in ("Consume-HcrPlanRecord", "network-pair-", "AddMinutes(15)", "AddHours(24)", "NETWORK_RECOVERY_REQUIRED", "SetVmPower", "SetVmNetwork"):
        if token not in host_v2 and token not in adapters:
            raise AssertionError(f"guarded host transition seam is missing: {token}")
    if runtime.count("New-HcrEnvelope") < 2 or "$envelopeSchemaVersion" not in runtime:
        raise AssertionError("runtime does not route v1/v2 result envelopes explicitly")
    for token in (
        "S-1-5-32-578",
        "hyperVAdministratorsTokenEnabled",
        "hyperVAuthorized",
        "authorizationMode",
        "HYPERV_AUTHORIZATION_REQUIRED",
        "BROADER_PRIVILEGE_CONTEXT",
    ):
        if token not in common + runtime + host_v1 + host_v2 + adapters:
            raise AssertionError(f"least-privilege authorization seam is missing: {token}")
    if adapters.count("[void](Assert-HcrCurrentProcessHyperVAuthorized)") != 5:
        raise AssertionError(
            "real VM create, checkpoint create/restore, power, and network "
            "mutation boundaries do not all recompute token authorization"
        )
    if "Assert-HcrRuntimeHyperVAuthorized" not in adapters or "Assert-HcrRuntimeHyperVAuthorized" not in host_v1:
        raise AssertionError(
            "VM-create apply does not check current authorization before host drift probes"
        )
    if host_v1.count("[void](Assert-HcrRuntimeHyperVAuthorized)") != 3:
        raise AssertionError(
            "VM create and checkpoint create/restore Apply paths do not all "
            "check current authorization before host drift probes"
        )
    if "$identity.Dispose()" not in adapters:
        raise AssertionError("current-token authorization leaks its Windows identity handle")
    if "ELEVATION_REQUIRED" in host_v1 + host_v2 + adapters:
        raise AssertionError("a host path still requires elevation instead of Hyper-V authorization")
    for token in (
        "ISO_ACCESS_DENIED",
        "VM_ROOT_ACCESS_DENIED",
        "STATE_ROOT_ACCESS_DENIED",
    ):
        if token not in common + host_v1 + state:
            raise AssertionError(f"least-privilege path preflight is missing: {token}")
    for token in (
        "Assert-HcrWritableStateDirectory",
        "Get-HcrStateFiles",
        "Initialize-HcrStateManagedDirectory",
        "Get-HcrStateItems",
        "Assert-HcrStateRegularFile",
        "Copy-HcrStateFile",
        "DeleteOnClose",
    ):
        if token not in state:
            raise AssertionError(f"state-root access seam is missing: {token}")
    for token in (
        "Initialize-HcrStateManagedDirectory",
        "Get-HcrStateItems",
        "Assert-HcrStateRegularFile",
        "Get-HcrStateFileSha256",
        "Copy-HcrStateFile",
    ):
        if token not in guest_v1 + guest_v2:
            raise AssertionError(f"evidence-staging state access seam is missing: {token}")

    for token in (
        "ZipArchive", "4096", "8GB", "200", "portable-manifest.json",
        "Move-Item -LiteralPath $staging -Destination $slotPath",
        "dataInventorySha256", "Microsoft Corporation", "Test-WorkerPeX64",
        "127.0.0.1", "serverAllocatedEphemeral", "data-testid",
        "allowExecuteScript", "allowArbitrarySelector",
    ):
        sources = worker + validation
        if token not in sources:
            raise AssertionError(f"portable/driver closed seam is missing: {token}")
    for forbidden in (
        "Invoke-Expression", "ScriptBlock]::Create", "cmd.exe", "powershell -Command",
        "execute/sync", "/url", "xpath", "Invoke-WebRequest", "DownloadString",
    ):
        if forbidden.casefold() in worker.casefold():
            raise AssertionError(f"guest worker exposes a forbidden escape seam: {forbidden}")
    if not re.search(r"Get-WorkerWebDriverElement[\s\S]+\[data-testid=", worker):
        raise AssertionError("UI element resolution is not derived from closed data-testid values")
    if "Get-WorkerProperty $Step 'expected'" not in worker:
        raise AssertionError("closed UI text/value assertions are not bound to the contract field")
    if "PORTABLE_ARCHIVE_UNDECLARED_ENTRY" not in worker or "driver archive contains an undeclared" not in worker:
        raise AssertionError("portable or fixed-driver archive inventory is not fail closed")
    if "UNSUPPORTED_SCHEMA_VERSION" not in validation or "Convert-HcrProfileV1ToV2" not in validation:
        raise AssertionError("exact-version routing or deterministic migration is missing")
    if "MIGRATION_DESTINATION_EXISTS" not in migration or "Write-HcrJsonFile" not in migration:
        raise AssertionError("the standalone migration is not additive and fail closed")
    loader_match = re.search(r"foreach \(\$file in @\(([^)]+)\)\)", migration)
    if not loader_match or "'State.ps1'" not in loader_match.group(1):
        raise AssertionError("the standalone migration loader omits the atomic JSON writer")
    if "HCR_TEST_SOURCE_COMMIT" not in guest_v2 or "RUNTIME_PROVENANCE_INVALID" not in guest_v2:
        raise AssertionError("runtime plugin provenance is not fail closed")
    for token in (
        "Get-HcrV2PortableCandidateSourceCommit",
        "$candidateSourceCommit",
        "$runtimeSourceCommit",
        "sourceCommit=$candidateSourceCommit",
        "sourceCommit=$runtimeSourceCommit",
    ):
        if token not in guest_v2:
            raise AssertionError(f"candidate/runtime provenance separation is missing: {token}")
    if "'deployPortable', 'launchApplication', 'acquireWebDriver'" not in validation:
        raise AssertionError("portable UI validation does not require application launch")
    if "PORTABLE_MUTABLE_DATA_FORBIDDEN" not in worker or "StartsWith('data/'" not in worker:
        raise AssertionError("portable worker accepts packaged mutable data entries")
    if not re.search(
        r"\$copiedValidation = if \([\s\S]+?Test-HcrEvidenceDocumentV2",
        guest_v1,
    ):
        raise AssertionError("copied evidence does not retain schema-version dispatch")
    if "Evidence content does not match immutable operation state." not in validation:
        raise AssertionError("schema-v2 evidence is not bound to its operation digest")
    if "launchedProcess = $launchedProcess" not in guest_v2:
        raise AssertionError("schema-v2 cleanup does not pass operation-scoped process identity")
    if host_v2.count("Get-HcrV2HostInvariantFingerprint") != 5:
        raise AssertionError("schema-v2 plans do not consistently use the elevation-invariant host fingerprint")
    if "Get-HcrHostFingerprint $hostSnapshot" in host_v2:
        raise AssertionError("schema-v2 plan drift remains bound to caller elevation")
    if "$Path.port is outside 1..65535." not in validation:
        raise AssertionError("schema-v2 assertPort lacks native integer/range validation")
    stop_ui_index = worker.find("if($type-eq'stopUiSession')")
    driver_lookup_index = worker.find("$driver=Get-Process", stop_ui_index)
    delete_index = worker.find("Invoke-WorkerWebDriverRequest $state DELETE", stop_ui_index)
    finally_index = worker.find("finally{", delete_index)
    terminate_index = worker.find(
        "TerminateAndWait($driverHandle,0,500)", finally_index
    )
    if not (
        0
        <= stop_ui_index
        < driver_lookup_index
        < delete_index
        < finally_index
        < terminate_index
    ) or "$protocolTimeoutMilliseconds" not in worker:
        raise AssertionError("UI-session stop does not contain the exact driver after bounded DELETE")
    if "Stop-VM -VM $verifiedVm -ErrorAction Stop" not in adapters:
        raise AssertionError("graceful shutdown does not use the default Stop-VM path")
    if "Stop-VM -VM $verifiedVm -Shutdown" in adapters:
        raise AssertionError("graceful shutdown uses a nonexistent Stop-VM switch")
    preview_index = host_v2.find("$previewRecord = Get-HcrNetworkPlanRecord")
    recovery_branch_index = host_v2.find("if ($planRole -eq 'recovery')", preview_index)
    first_drift_index = host_v2.find(
        "Assert-HcrVmNetworkPlanDriftFree $previewPlan", preview_index
    )
    consume_index = host_v2.find(
        "Consume-HcrNetworkPlanRecord $planId $expectedPlanSha256",
        first_drift_index,
    )
    paired_lookup_index = host_v2.find(
        "Get-HcrNetworkPlanRecord $pairedRecoveryId", consume_index
    )
    mutation_index = host_v2.find("Invoke-HcrAdapter 'SetVmNetwork'", consume_index)
    if not (
        0
        <= preview_index
        < recovery_branch_index
        < first_drift_index
        < consume_index
        < paired_lookup_index
        < mutation_index
    ):
        raise AssertionError(
            "network recovery ordering does not preserve recovery while consuming change once"
        )
    if "Assert-HcrPairedNetworkRecoveryUsable $plan $pairedRecoveryRecord" not in host_v2:
        raise AssertionError("disconnect mutation does not validate exact paired recovery bindings")

    # P3.2 external portable execution must be a strict, isolated branch.  These
    # probes intentionally inspect only implementation text; the Gate 7 runner
    # remains mock-only and must never touch a real profile, guest, ZIP, or driver.
    external_sources = common + validation + guest_v2 + worker
    require_tokens(
        external_sources,
        "external sidecar parser",
        (
            "externalProfileRelative",
            "portableManifestRelativePath",
            "portableManifestSizeBytes",
            "portableManifestSha256",
            "UTF8Encoding",
            "NUL",
            "ReparsePoint",
            "duplicate",
        ),
    )
    for label, pattern in (
        (
            "external sidecar schemaVersion scalar binding",
            r"Test-HcrInteger \(\s*"
            r"Get-HcrPropertyValue \$Manifest 'schemaVersion'\s*\)",
        ),
        (
            "external sidecar unsigned scalar binding",
            r"Test-HcrBoolean \(\s*"
            r"Get-HcrPropertyValue \$Manifest 'unsigned'\s*\)",
        ),
    ):
        if not re.search(pattern, validation):
            raise AssertionError(f"{label} is missing")
    require_tokens(
        worker,
        "worker external sidecar scalar bindings",
        (
            "Test-WorkerInteger (Get-WorkerProperty $manifest 'schemaVersion')",
            "Test-WorkerBoolean (Get-WorkerProperty $manifest 'unsigned')",
        ),
    )
    worker_manifest_start = worker.index("function Read-WorkerPortableManifest {")
    worker_manifest_end = worker.index("\nfunction ", worker_manifest_start + 1)
    worker_manifest_reader = worker[worker_manifest_start:worker_manifest_end]
    require_tokens(
        worker_manifest_reader,
        "worker exact Test2 selected-source fields",
        (
            "'sourceMode'",
            "'sourceManifestSize'",
            "'sourceManifestSha256'",
            "Resolve-WorkerStagedPortableManifest",
        ),
    )
    worker_manifest_resolver_start = worker.index(
        "function Resolve-WorkerStagedPortableManifest {"
    )
    worker_manifest_resolver_end = worker.index(
        "\nfunction ", worker_manifest_resolver_start + 1
    )
    worker_manifest_resolver = worker[
        worker_manifest_resolver_start:worker_manifest_resolver_end
    ]
    require_tokens(
        worker_manifest_resolver,
        "worker staged sidecar byte binding",
        (
            "guestSizeBytes",
            "guestSha256",
            "Get-WorkerSha256File",
        ),
    )
    require_tokens(
        common + validation,
        "single-read external sidecar identity",
        (
            "function Get-HcrSha256Bytes",
            "$bytes = [IO.File]::ReadAllBytes($item.FullName)",
            "$sha256 = Get-HcrSha256Bytes $bytes",
            "ConvertFrom-HcrStrictJsonBytes $bytes",
        ),
    )
    if "Get-HcrSha256File $item.FullName" in validation:
        raise AssertionError(
            "external sidecar validation hashes the path separately from parsed bytes"
        )
    require_tokens(
        validation + guest_v2,
        "single-read profile identity",
        (
            "sha256 = Get-HcrSha256Bytes $bytes",
            "sha256 = [string]$loaded.sha256",
            "$profileSha = [string]$profileValidation.sha256",
        ),
    )
    if "Get-HcrSha256File $profileValidation.path" in guest_v2:
        raise AssertionError(
            "runtime hashes the profile path separately from the parsed profile bytes"
        )
    require_tokens(
        validation_v1,
        "strict shared JSON UTF-8 decoding",
        (
            "Text.UTF8Encoding($false, $true)",
            "The file is not valid UTF-8 JSON.",
        ),
    )
    require_tokens(
        external_sources,
        "external candidate rebinding",
        (
            "portableManifestSourceSizeBytes",
            "portableManifestGuestSizeBytes",
            "portableManifestSourceSha256",
            "portableManifestGuestSha256",
            "portableZipSourceSizeBytes",
            "portableZipGuestSizeBytes",
            "portableZipSourceSha256",
            "portableZipGuestSha256",
        ),
    )
    require_tokens(
        common + validation,
        "external fixture file-identity separation",
        (
            "function Get-HcrLocalFileIdentity",
            "GetFileInformationByHandle",
            "Test-HcrV2WindowsSafeRelativePath $fixtureRelative",
            "PORTABLE_MANIFEST_FIXTURE_PATH_COLLISION",
        ),
    )
    require_tokens(
        guest_v2,
        "external exact ZIP leaf and failure evidence",
        (
            "$artifactItem.Name -ceq",
            "Get-HcrPropertyValue $externalManifest.document 'fileName'",
            "portableZipGuestSha256 = $null",
            "portableManifestGuestSizeBytes = $null",
            "if ($externalPortable -and $stageStatus -ne 'passed')",
            "preEvidenceFailure",
            "portableZipGuestSha256=$artifactGuestHash",
            "portableManifestGuestSha256=$portableManifestGuestHash",
            "guestSizeBytes=$fixtureGuestSize",
        ),
    )
    require_tokens(
        external_sources,
        "external ZIP inventory closure",
        (
            "PORTABLE_ARCHIVE_UNDECLARED_ENTRY",
            "portable-manifest.json",
            "SHA256SUMS",
            "SBOM.cdx.json",
            "licenses/SBOM.cdx.json",
            "data/",
            "inventoryDigest",
        ),
    )
    require_tokens(
        external_sources,
        "external evidence provenance",
        (
            "evidenceKind",
            "externalPortable",
            "runtimeSourceCommit",
            "runtimeSourceTree",
            "packagingCommit",
            "packagingTree",
            "documentationInventoryDigest",
            "oldRuntimeInventoryDigest",
            "newRuntimeInventoryDigest",
            "machineStatus",
            "overallStatus",
        ),
    )
    require_tokens(
        adapters,
        "production orchestration evidence binding",
        (
            "orchestrationIdentity",
            "administratorProbe",
            "userSid",
            "isElevated = [bool](Get-HcrPropertyValue $administratorProbe 'isElevated')",
            "tokenIntegrity",
            "-NotePropertyName orchestration",
        ),
    )
    require_tokens(
        common + validation,
        "closed nested external manifest provenance",
        (
            "Test-HcrV2ExternalManifestProvenance",
            "$manifest.sbom",
            "$manifest.sourceInputs",
            "$manifest.maa.agent",
            "$manifest.webView2",
            "contains unsupported field",
        ),
    )
    require_tokens(
        validation,
        "exact Test2 manifest compatibility",
        (
            "Test-HcrV2ExternalSourceInputInventory",
            "Test-HcrV2ExactPropertyNames",
            "Test-HcrV2ExternalSelectedSourceBinding",
            "Test-HcrV2ExternalSourceInputBindings",
            "Test-HcrV2ExternalAgentFileBindings",
            "fresh-exact-head",
            "sourceManifestSize",
            "sourceManifestSha256",
            "inventorySize",
            "executableSize",
            "does not match removedFiles portable-manifest.json",
            "not represented in the ZIP inventory",
            "not byte-bound to the ZIP inventory",
            "incorrectly cased field",
        ),
    )
    require_tokens(
        external_sources,
        "conditional external UI branch",
        (
            "webView2",
            "webDriver",
            "cleanupSteps",
            "driverVersion",
            "browserVersion",
        ),
    )
    require_tokens(
        worker,
        "worker conditional UI compatibility",
        (
            "Test-WorkerDriverVersionCompatibility",
            "[string]::Join('.', $browserParts[0..2])",
            "[string]::Join('.', $driverParts[0..2])",
            "(-not $uiRequired -and $null -ne $webDriver)",
            "Get-WorkerProperty $WorkerInput 'uiRequired' $false",
        ),
    )
    require_tokens(
        worker,
        "failed portable deployment cleanup",
        (
            "$deploymentPublished=$false",
            "if(-not $deploymentPublished -and $null-ne$slotsRoot)",
            "Test-WorkerPathWithin $cleanupPath $slotsRoot",
            "Remove-Item -LiteralPath $cleanupPath -Recurse -Force",
            "PORTABLE_STAGING_CLEANUP_FAILED",
            "$deploymentFailure.Exception.Data['GuestWorkerCleanupCode']",
            "throw $deploymentFailure",
        ),
    )
    require_tokens(
        guest_v2 + adapters + worker,
        "operation-owned portable launch binding",
        (
            "deployment = Copy-HcrObject $Context.deployment",
            "$context.deployment = [pscustomobject][ordered]@{",
            "$input.deployment = Copy-HcrObject",
            "function Get-WorkerBoundPortableDeployment",
            "PORTABLE_DEPLOYMENT_BINDING_INVALID",
            "PORTABLE_DEPLOYMENT_DRIFT",
            "$activeFingerprint -cne",
            "portableActiveDeploymentOverride",
        ),
    )
    require_tokens(
        guest_v2 + adapters + worker,
        "portable entrypoint byte rebinding immediately before launch",
        (
            "entrypointSizeBytes",
            "entrypointSha256",
            "Open-WorkerVerifiedPortableEntrypoint",
            "PORTABLE_ENTRYPOINT_DRIFT",
            "portableEntrypointDriftOnLaunch",
            "[IO.FileShare]::Read",
            "OpenDirectoryForLaunch",
            "FileFlagOpenReparsePoint",
            "FileShareRead | FileShareWrite",
            "function Open-WorkerPortableLaunchPath",
            "Get-WorkerPortableProductRoot $Application",
            "[string]$env:LOCALAPPDATA",
            "@('GUEST_PATH_INVALID', 'GUEST_REPARSE_FORBIDDEN')",
            "$portableEntrypointBinding.stream.Dispose()",
        ),
    )
    launch_scope = worker[worker.index("if ($type -eq 'launchApplication')"):]
    portable_index = launch_scope.index("$portableApplication = $schemaVersion -eq 2")
    generic_guard_index = launch_scope.index("if (-not $portableApplication -and")
    verified_open_index = launch_scope.index(
        "$portableEntrypointBinding = Open-WorkerVerifiedPortableEntrypoint"
    )
    process_start_index = launch_scope.index("Start-Process -FilePath $executable")
    stream_dispose_index = launch_scope.index(
        "$portableEntrypointBinding.stream.Dispose()"
    )
    if not (
        portable_index < generic_guard_index < verified_open_index <
        process_start_index < stream_dispose_index
    ):
        raise AssertionError(
            "portable entrypoint verification is not held across process creation"
        )
    require_tokens(
        guest_v2,
        "installed runtime byte rebinding",
        (
            "function Get-HcrV2VerifiedInstalledInventory",
            "Assert-HcrRegularLocalFile $installedPath",
            "Get-HcrSha256File $item.FullName",
            "$actualPaths.SetEquals($expectedPaths)",
            "The installed plugin version differs from its provenance manifest.",
            "hyperv-clean-room-installer/v1",
        ),
    )
    require_tokens(
        validation,
        "external manifest array and path scalar closure",
        (
            "$filesValue -isnot [Array]",
            "$documentationValue -isnot [Array]",
            "$fileNameValue -isnot [string]",
            "$entrypointValue -isnot [string]",
            "$pathValue -isnot [string]",
            "$sourcePathValue -isnot [string]",
            "$archivePathValue -isnot [string]",
            "$webViewFilesValue = Get-HcrPropertyValue",
            "Test-HcrV2ExternalFileInventory",
            "$webViewFilesValue -is [Array]",
        ),
    )
    require_tokens(
        validation,
        "profile root array scalar closure",
        (
            "$fixturesValue -is [Array]",
            "$applicationsValue -is [Array]",
            "$stepsValue -is [Array]",
            "$cleanupStepsValue -is [Array]",
            "$manualAssertionsValue -is [Array]",
            "' must be an array.'",
        ),
    )
    require_tokens(
        worker,
        "worker external manifest array and path scalar closure",
        (
            "$externalFiles -isnot [Array]",
            "$externalDocumentation -isnot [Array]",
            "$externalFileName -isnot [string]",
            "$externalEntrypoint -isnot [string]",
            "$pathValue -isnot [string]",
            "$sourcePathValue -isnot [string]",
            "$archivePathValue -isnot [string]",
            "$manifestFilesValue-isnot[Array]",
        ),
    )

    fixture_root = ROOT / "tests" / "fixtures" / "v3"
    external_manifest = load_strict(
        fixture_root / "portable-manifest.external-neutral.valid.json"
    )
    external_profile = load_strict(
        fixture_root / "test-profile.external-neutral.valid.json"
    )
    external_ui_profile = load_strict(
        fixture_root / "test-profile.external-ui.valid.json"
    )
    external_evidence = load_strict(
        fixture_root / "evidence.external-neutral.valid.json"
    )
    legacy_manifest = load_strict(
        fixture_root / "portable-manifest.external-legacy-historical.valid.json"
    )
    test2_manifest = load_strict(
        fixture_root / "portable-manifest.external-test2-provenance.valid.json"
    )
    if external_profile["artifact"]["portableManifestSource"] != "externalProfileRelative":
        raise AssertionError("external profile fixture no longer selects the sidecar branch")
    if external_manifest["distributionBoundary"] != "end-user-complete":
        raise AssertionError("executable external fixture no longer requires end-user-complete")
    if "webDriver" in external_profile or any(
        step["type"] in {"acquireWebDriver", "startUiSession", "stopUiSession"}
        for step in [*external_profile["steps"], *external_profile["cleanupSteps"]]
    ):
        raise AssertionError("generic non-UI external fixture accidentally requires the UI branch")
    if any(
        "webview2" in entry["path"].casefold() or "maafw" in entry["path"].casefold()
        for entry in external_manifest["files"]
    ):
        raise AssertionError("generic non-UI external manifest includes a product-specific component")
    if "webDriver" not in external_ui_profile or not any(
        step["type"] == "stopUiSession" for step in external_ui_profile["cleanupSteps"]
    ):
        raise AssertionError("external cleanup UI fixture does not trigger the fixed UI branch")
    browser = external_ui_profile["webDriver"]["browserVersion"].split(".")
    driver = external_ui_profile["webDriver"]["driverVersion"].split(".")
    if browser[:3] != driver[:3] or browser == driver:
        raise AssertionError("external UI fixture does not pin the exact first-three version rule")
    candidate = external_evidence["candidate"]
    for field in (
        "portableZipSourceSha256", "portableZipGuestSha256",
        "portableManifestSourceSizeBytes", "portableManifestGuestSizeBytes",
        "portableManifestSourceSha256", "portableManifestGuestSha256",
        "portableInventorySha256", "portableInventoryFileCount",
        "portableInventorySizeBytes",
        "runtimeSourceCommit", "runtimeSourceTree", "packagingCommit", "packagingTree",
    ):
        if field not in candidate:
            raise AssertionError(f"external evidence fixture lost immutable candidate binding: {field}")
    if external_evidence.get("evidenceKind") != "externalPortable":
        raise AssertionError("external evidence fixture lost its structural discriminator")
    if legacy_manifest["distributionBoundary"] != "runtime-and-legal-only":
        raise AssertionError("historical external manifest branch is no longer retained")
    if (
        test2_manifest.get("sourceMode") != "fresh-exact-head"
        or not all(
            isinstance(item, str)
            for field in (
                "birdsgoneTrackedFiles",
                "preparedAgentFiles",
                "maaInventoriedFiles",
            )
            for item in test2_manifest["sourceInputs"][field]
        )
        or not {"inventorySize", "executableSize"}.issubset(
            test2_manifest["maa"]["agent"]
        )
    ):
        raise AssertionError("exact Test2 compatibility fixture lost its provenance shape")

    artifact_root_value = os.environ.get("HCR_GATE7_ARTIFACT_ROOT")
    if not artifact_root_value:
        raise AssertionError("HCR_GATE7_ARTIFACT_ROOT is required for isolated Gate 7 evidence")
    artifact_root = Path(artifact_root_value).resolve()
    if not artifact_root.is_relative_to(ROOT.resolve()) or not artifact_root.is_dir():
        raise AssertionError("isolated Gate 7 artifact root is invalid")
    evidence_paths = list(artifact_root.glob("state/evidence-staging/*/evidence.json"))
    v2_evidence_paths = [path for path in evidence_paths if load(path).get("schemaVersion") == 2]
    if len(v2_evidence_paths) != 10:
        raise AssertionError(
            "Gate 7 runtime must emit three passed and seven failed schema-v2 evidence documents"
        )
    schemas = {name: load(CONTRACT / "schemas" / name) for name in V2_NAMES}
    registry = Registry()
    for schema in schemas.values():
        registry = registry.with_resource(schema["$id"], Resource.from_contents(schema))
    evidence_documents = [load(path) for path in v2_evidence_paths]
    for evidence in evidence_documents:
        errors = list(
            Draft202012Validator(
                schemas["evidence.schema.json"],
                registry=registry,
                format_checker=FormatChecker(),
            ).iter_errors(evidence)
        )
        if errors:
            raise AssertionError(
                f"generated evidence-v2 violates its schema: {errors[0].message}"
            )
    if any(evidence["runtime"]["adapterMode"] != "mock" for evidence in evidence_documents):
        raise AssertionError("Gate 7 runtime evidence escaped its mock-only boundary")
    if sorted(evidence["machineStatus"] for evidence in evidence_documents) != [
        "failed",
        "failed",
        "failed",
        "failed",
        "failed",
        "failed",
        "failed",
        "passed",
        "passed",
        "passed",
    ]:
        raise AssertionError("Gate 7 runtime did not preserve passed and failed evidence")

    print(
        json.dumps(
            {
                "ok": True,
                "gate": 7,
                "pluginVersion": manifest["version"],
                "tools": len(catalog["tools"]),
                "v1ToolsPreserved": 16,
                "v1SchemasPreserved": len(V1_NAMES),
                "v2SchemasInstalled": len(V2_NAMES),
                "generatedEvidenceValidated": len(evidence_documents),
                "realHostOperations": 0,
                "realGuestOperations": 0,
                "portableDeployments": 0,
                "webDriverLaunches": 0,
                "uiOperations": 0,
            },
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

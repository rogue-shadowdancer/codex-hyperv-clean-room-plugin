from __future__ import annotations

import hashlib
import json
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


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    compatibility = load(CONTRACT / "compatibility.json")
    catalog = load(CONTRACT / "tool-catalog.json")
    manifest = load(PLUGIN / ".codex-plugin" / "plugin.json")
    if not re.fullmatch(
        r"0\.2\.0(?:\+codex\.[a-z0-9]+(?:-[a-z0-9]+)*)?",
        str(manifest["version"]),
    ):
        raise AssertionError(
            "the integrated plugin version must preserve base 0.2.0 with at "
            "most one Codex cachebuster"
        )
    if catalog["currentRuntimeVersion"] != "0.2.0" or compatibility["currentRuntimeVersion"] != "0.2.0":
        raise AssertionError("contract integration metadata is not current")
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
    host_v2 = read(PLUGIN / "mcp" / "lib" / "Tools.Host.V2.ps1")
    guest_v1 = read(PLUGIN / "mcp" / "lib" / "Tools.Guest.ps1")
    guest_v2 = read(PLUGIN / "mcp" / "lib" / "Tools.Guest.V2.ps1")
    worker = read(PLUGIN / "mcp" / "lib" / "GuestWorker.ps1")
    validation = read(PLUGIN / "mcp" / "lib" / "Validation.V2.ps1")
    adapters = read(PLUGIN / "mcp" / "lib" / "Adapters.ps1")
    migration = read(PLUGIN / "mcp" / "Migrate-TestProfile.ps1")

    for token in ("$script:HcrPluginVersion = '0.2.0'", "plan_vm_power", "apply_vm_power", "plan_vm_network", "apply_vm_network"):
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

    artifact_roots = sorted(
        (ROOT / ".artifacts").glob("gate7-tests-*"),
        key=lambda path: path.stat().st_mtime_ns,
        reverse=True,
    )
    if not artifact_roots:
        raise AssertionError("Gate 7 runtime evidence is unavailable")
    evidence_paths = list(artifact_roots[0].glob("state/evidence-staging/*/evidence.json"))
    v2_evidence_paths = [path for path in evidence_paths if load(path).get("schemaVersion") == 2]
    if len(v2_evidence_paths) != 5:
        raise AssertionError(
            "Gate 7 runtime must emit one passed and four failed schema-v2 evidence documents"
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

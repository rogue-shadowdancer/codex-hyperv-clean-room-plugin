from __future__ import annotations

import hashlib
import json
import re
import subprocess
import unicodedata
from collections import Counter
from copy import deepcopy
from datetime import datetime
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource


REPO_ROOT = Path(__file__).resolve().parents[1]
CONTRACT_ROOT = REPO_ROOT / "contracts" / "v2"
SCHEMA_ROOT = CONTRACT_ROOT / "schemas"
FIXTURE_ROOT = Path(__file__).resolve().parent / "fixtures" / "v2"
V1_SCHEMA_ROOT = REPO_ROOT / "hyperv-clean-room" / "schemas"
TOOL_SCHEMAS_PATH = (
    REPO_ROOT / "hyperv-clean-room" / "mcp" / "lib" / "ToolSchemas.ps1"
)
PLUGIN_MANIFEST_PATH = (
    REPO_ROOT / "hyperv-clean-room" / ".codex-plugin" / "plugin.json"
)

EXPECTED_V2_SCHEMAS = {
    "operation-envelope.schema.json",
    "vm-power-plan.schema.json",
    "vm-network-plan.schema.json",
    "portable-manifest.schema.json",
    "webdriver-manifest.schema.json",
    "test-profile.schema.json",
    "evidence.schema.json",
}
EXPECTED_V2_SCHEMA_IDS = {
    name: (
        "https://github.com/rogue-shadowdancer/"
        "codex-hyperv-clean-room-plugin/contracts/v2/schemas/" + name
    )
    for name in EXPECTED_V2_SCHEMAS
}
V1_TOOL_NAMES = [
    "inspect_host",
    "list_vms",
    "inspect_vm",
    "validate_test_profile",
    "validate_evidence",
    "plan_vm_create",
    "apply_vm_create",
    "plan_checkpoint_create",
    "apply_checkpoint_create",
    "plan_checkpoint_restore",
    "apply_checkpoint_restore",
    "inspect_guest",
    "stage_artifact",
    "run_test_profile",
    "collect_evidence",
    "record_manual_attestation",
]
V2_ADDITIVE_TOOL_NAMES = [
    "plan_vm_power",
    "apply_vm_power",
    "plan_vm_network",
    "apply_vm_network",
]
EXPECTED_TOOL_NAMES = V1_TOOL_NAMES + V2_ADDITIVE_TOOL_NAMES
EXPECTED_FAILURE_CODES = {
    "plan_vm_power": [
        "HYPERV_UNAVAILABLE",
        "INVALID_ARGUMENT",
        "OWNERSHIP_UNVERIFIED",
        "STATE_BUSY",
        "VM_NOT_FOUND",
        "VM_STATE_UNSUPPORTED",
    ],
    "apply_vm_power": [
        "ELEVATION_REQUIRED",
        "HYPERV_UNAVAILABLE",
        "INVALID_ARGUMENT",
        "OWNERSHIP_UNVERIFIED",
        "PLAN_ALREADY_CONSUMED",
        "PLAN_DRIFT",
        "PLAN_EXPIRED",
        "PLAN_INVALID",
        "PLAN_KIND_MISMATCH",
        "PLAN_NOT_FOUND",
        "POWER_TRANSITION_FAILED",
        "STATE_BUSY",
        "VM_STATE_UNSUPPORTED",
    ],
    "plan_vm_network": [
        "BASELINE_UNAVAILABLE",
        "HYPERV_UNAVAILABLE",
        "INVALID_ARGUMENT",
        "OWNERSHIP_UNVERIFIED",
        "PRIMARY_ADAPTER_UNVERIFIED",
        "STATE_BUSY",
        "VM_NOT_FOUND",
    ],
    "apply_vm_network": [
        "BASELINE_UNAVAILABLE",
        "ELEVATION_REQUIRED",
        "HYPERV_UNAVAILABLE",
        "INVALID_ARGUMENT",
        "NETWORK_RECOVERY_REQUIRED",
        "NETWORK_TRANSITION_FAILED",
        "OWNERSHIP_UNVERIFIED",
        "PLAN_ALREADY_CONSUMED",
        "PLAN_DRIFT",
        "PLAN_EXPIRED",
        "PLAN_INVALID",
        "PLAN_KIND_MISMATCH",
        "PLAN_NOT_FOUND",
        "PRIMARY_ADAPTER_UNVERIFIED",
        "STATE_BUSY",
    ],
}
FORBIDDEN_TOOL_INPUT_FIELDS = {
    "arguments",
    "command",
    "executable",
    "javascript",
    "password",
    "script",
    "selector",
    "shell",
    "url",
}
UI_STEP_TYPES = {
    "acquireWebDriver",
    "startUiSession",
    "stopUiSession",
    "uiClick",
    "uiSetText",
    "uiPressKey",
    "uiSelectOption",
    "uiUploadFixture",
    "assertUiElement",
    "captureUiScreenshot",
}
UI_ASSERT_STATES = {
    "visible",
    "hidden",
    "enabled",
    "disabled",
    "checked",
    "unchecked",
    "textEquals",
    "textContains",
    "valueEquals",
}
SCHEMA_BY_FIXTURE_PREFIX = {
    "operation-envelope": "operation-envelope.schema.json",
    "vm-power-plan": "vm-power-plan.schema.json",
    "vm-network-plan": "vm-network-plan.schema.json",
    "portable-manifest": "portable-manifest.schema.json",
    "webdriver-manifest": "webdriver-manifest.schema.json",
    "test-profile": "test-profile.schema.json",
    "evidence": "evidence.schema.json",
}


def reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for name, value in pairs:
        if name in result:
            raise ValueError(f"duplicate JSON property: {name}")
        result[name] = value
    return result


def load_json(path: Path) -> Any:
    return json.loads(
        path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicate_pairs
    )


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def duplicate_values(values: list[str]) -> list[str]:
    return sorted(value for value, count in Counter(values).items() if count > 1)


def property_names(value: Any) -> set[str]:
    names: set[str] = set()
    if isinstance(value, dict):
        properties = value.get("properties")
        if isinstance(properties, dict):
            names.update(str(name) for name in properties)
        for child in value.values():
            names.update(property_names(child))
    elif isinstance(value, list):
        for child in value:
            names.update(property_names(child))
    return names


def live_v1_tools() -> list[dict[str, Any]]:
    script_path = str(TOOL_SCHEMAS_PATH).replace("'", "''")
    command = (
        "[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false); "
        f". '{script_path}'; "
        "ConvertTo-Json -Compress -Depth 30 -InputObject @(Get-HcrToolDefinitions)"
    )
    completed = subprocess.run(
        ["powershell", "-NoProfile", "-Command", command],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    parsed = json.loads(completed.stdout)
    if not isinstance(parsed, list):
        raise AssertionError("live v1 tool registry did not serialize as an array")
    if len(parsed) != 20:
        raise AssertionError("live schema-v2 tool registry must expose exactly 20 tools")
    return parsed[:16]


def schema_registry(schemas: dict[str, dict[str, Any]]) -> Registry:
    registry = Registry()
    for schema in schemas.values():
        registry = registry.with_resource(
            schema["$id"], Resource.from_contents(schema)
        )
    return registry


def validator_for(
    schema_name: str,
    schemas: dict[str, dict[str, Any]],
    registry: Registry,
) -> Draft202012Validator:
    return Draft202012Validator(
        schemas[schema_name],
        format_checker=FormatChecker(),
        registry=registry,
    )


def is_safe_relative_path(value: object) -> bool:
    if not isinstance(value, str) or not value or "\x00" in value:
        return False
    if value != unicodedata.normalize("NFC", value):
        return False
    normalized = value.replace("/", "\\")
    if normalized.startswith("\\") or re.match(r"^[A-Za-z]:", normalized):
        return False
    if any(ord(character) < 32 for character in normalized):
        return False
    if any(character in '<>:"|?*%' for character in normalized):
        return False
    parts = normalized.split("\\")
    if any(part in {"", ".", ".."} for part in parts):
        return False
    if any(part.rstrip(" .") != part for part in parts):
        return False
    for part in parts:
        device = part.split(".", 1)[0].casefold()
        if device in {"con", "prn", "aux", "nul"} or re.fullmatch(
            r"(?:com|lpt)(?:[1-9]|[¹²³])", device
        ):
            return False
    return True


def normalized_archive_path(value: str) -> str:
    return unicodedata.normalize("NFC", value.replace("\\", "/")).casefold()


def validate_portable_manifest_semantics(manifest: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    files = manifest.get("files", [])
    paths = [item.get("path") for item in files if isinstance(item, dict)]
    string_paths = [path for path in paths if isinstance(path, str)]
    for path in string_paths:
        if not is_safe_relative_path(path):
            errors.append(f"unsafe portable manifest path: {path!r}")
    normalized = [normalized_archive_path(path) for path in string_paths]
    duplicates = duplicate_values(normalized)
    if duplicates:
        errors.append(f"case-insensitive duplicate portable paths: {duplicates}")
    entry_point = manifest.get("entryPointRelativePath")
    if isinstance(entry_point, str) and normalized_archive_path(entry_point) not in normalized:
        errors.append("portable entry point is absent from the exact inventory")
    elif isinstance(entry_point, str):
        entry_items = [
            item
            for item in files
            if isinstance(item, dict)
            and isinstance(item.get("path"), str)
            and normalized_archive_path(item["path"])
            == normalized_archive_path(entry_point)
        ]
        if len(entry_items) != 1 or entry_items[0].get("sizeBytes", 0) < 1:
            errors.append("portable entry point is not a unique non-empty file")
    if "portable-manifest.json" in normalized:
        errors.append("portable manifest cannot contain its own recursive file hash")
    if any(path == "data" or path.startswith("data/") for path in normalized):
        errors.append("portable payload inventory contains mutable data")
    return errors


def validate_webdriver_manifest_semantics(manifest: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if manifest.get("browserVersion") != manifest.get("driverVersion"):
        errors.append("WebDriver version does not exactly match fixed WebView2")
    files = manifest.get("files", [])
    paths = [item.get("path") for item in files if isinstance(item, dict)]
    string_paths = [path for path in paths if isinstance(path, str)]
    if any(not is_safe_relative_path(path) for path in string_paths):
        errors.append("WebDriver inventory contains an unsafe Windows path")
    if duplicate_values([normalized_archive_path(path) for path in string_paths]):
        errors.append("WebDriver inventory contains colliding Windows paths")
    executable = manifest.get("executable", {})
    executable_path = executable.get("relativePath")
    matches = [item for item in files if item.get("path") == executable_path]
    if len(matches) != 1:
        errors.append("fixed WebDriver executable is not uniquely inventoried")
    elif (
        matches[0].get("sha256") != executable.get("sha256")
        or matches[0].get("sizeBytes") != executable.get("sizeBytes")
    ):
        errors.append("WebDriver executable identity differs from its inventory")
    return errors


def parse_datetime(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def validate_power_plan_semantics(plan: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    lifetime = parse_datetime(plan["expiresAt"]) - parse_datetime(plan["createdAt"])
    if lifetime.total_seconds() != 900:
        errors.append("power plan lifetime is not exactly 15 minutes")
    expected = {
        "start": ("Off", "Running"),
        "gracefulShutdown": ("Running", "Off"),
    }.get(plan.get("action"))
    if expected and (plan.get("currentState"), plan.get("targetState")) != expected:
        errors.append("power action does not match its current and target state")
    return errors


def validate_network_plan_semantics(plan: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    lifetime = parse_datetime(plan["expiresAt"]) - parse_datetime(plan["createdAt"])
    expected_lifetime = 86400 if plan.get("planRole") == "recovery" else 900
    if lifetime.total_seconds() != expected_lifetime:
        errors.append("network plan lifetime differs from its fixed role policy")
    target = plan.get("target")
    target_attachment = plan.get("targetAttachment")
    baseline = plan.get("baselineAttachment")
    if target == "baseline" and canonical_json(target_attachment) != canonical_json(
        baseline
    ):
        errors.append("baseline target does not equal the recorded baseline attachment")
    if target == "disconnected" and canonical_json(
        plan.get("currentAttachment")
    ) != canonical_json(baseline):
        errors.append("disconnect plan does not start from its recorded baseline")
    if target == "disconnected" and plan.get("planRole") == "change":
        if not isinstance(plan.get("pairedPlanId"), str):
            errors.append("disconnect plan lacks its pre-created recovery plan identity")
    if target == "baseline" and plan.get("planRole") == "change":
        if plan.get("pairedPlanId") is not None:
            errors.append("baseline change plan has an unnecessary recovery pair")
    if plan.get("planRole") == "recovery":
        if target != "baseline" or not isinstance(plan.get("pairedPlanId"), str):
            errors.append("network recovery is not paired back to the baseline")
    return errors


def validate_profile_semantics(profile: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    steps = profile.get("steps", [])
    cleanup_steps = profile.get("cleanupSteps", [])
    manual_assertions = profile.get("manualAssertions", [])
    fixtures = profile.get("fixtures", [])
    applications = profile.get("applications", [])

    ids = [
        item.get("id")
        for item in [*steps, *cleanup_steps, *manual_assertions]
        if isinstance(item, dict)
    ]
    duplicates = duplicate_values([item for item in ids if isinstance(item, str)])
    if duplicates:
        errors.append(f"execution IDs are not globally unique: {duplicates}")

    stage_indexes = [
        index for index, step in enumerate(steps) if step.get("type") == "stageArtifact"
    ]
    if stage_indexes != [0]:
        errors.append("steps must start with exactly one stageArtifact")

    fixture_ids = {item.get("id") for item in fixtures if isinstance(item, dict)}
    if len(fixture_ids) != len(fixtures):
        errors.append("fixture IDs are not unique")
    application_ids = {
        item.get("id") for item in applications if isinstance(item, dict)
    }
    if len(application_ids) != len(applications):
        errors.append("application IDs are not unique")

    for fixture in fixtures:
        if not is_safe_relative_path(fixture.get("sourceRelativePath")):
            errors.append(f"fixture {fixture.get('id')!r} has an unsafe source path")
    for application in applications:
        if not is_safe_relative_path(application.get("executableRelativePath")):
            errors.append(
                f"application {application.get('id')!r} has an unsafe executable path"
            )

    ui_steps = [step for step in steps if step.get("type") in UI_STEP_TYPES]
    if ui_steps and "webDriver" not in profile:
        errors.append("UI steps require a fixed WebDriver manifest")
    acquire_indexes = [
        index for index, step in enumerate(steps) if step.get("type") == "acquireWebDriver"
    ]
    start_indexes = [
        index for index, step in enumerate(steps) if step.get("type") == "startUiSession"
    ]
    stop_indexes = [
        index for index, step in enumerate(steps) if step.get("type") == "stopUiSession"
    ]
    if ui_steps and (
        len(acquire_indexes) != 1
        or len(start_indexes) != 1
        or len(stop_indexes) != 1
        or not acquire_indexes[0] < start_indexes[0] < stop_indexes[0]
    ):
        errors.append("UI lifecycle must acquire, start, and stop exactly once in order")
    elif ui_steps:
        interaction_types = UI_STEP_TYPES - {
            "acquireWebDriver",
            "startUiSession",
            "stopUiSession",
        }
        if any(
            not start_indexes[0] < index < stop_indexes[0]
            for index, step in enumerate(steps)
            if step.get("type") in interaction_types
        ):
            errors.append("UI interactions must occur inside the owned UI session")

    for index, step in enumerate([*steps, *cleanup_steps]):
        application = step.get("application")
        if application is not None and application not in application_ids:
            errors.append(f"step {index} references an unknown application")
        fixture_id = step.get("fixtureId")
        if fixture_id is not None and fixture_id not in fixture_ids:
            errors.append(f"step {index} references an unknown fixture")

    if profile.get("workflowKind") == "portableAutomation":
        portable_artifact = profile.get("artifact", {})
        if portable_artifact.get("packageKind") != "portableZip":
            errors.append("portable automation requires a portable ZIP artifact")
        portable_name = portable_artifact.get("fileNamePattern")
        if (
            not is_safe_relative_path(portable_name)
            or "\\" in portable_name
            or "/" in portable_name
        ):
            errors.append("portable artifact requires one exact safe ZIP file name")
        forbidden_types = {"installPackage", "uninstallPackage"}
        if any(step.get("type") in forbidden_types for step in steps):
            errors.append("portable automation contains installer lifecycle steps")
        deploy_indexes = [
            index for index, step in enumerate(steps) if step.get("type") == "deployPortable"
        ]
        if len(deploy_indexes) != 1:
            errors.append("portable automation must deploy exactly once")
        elif any(
            index < deploy_indexes[0]
            for index, step in enumerate(steps)
            if step.get("type")
            in {
                "launchApplication",
                "acquireWebDriver",
                "startUiSession",
                *UI_STEP_TYPES,
            }
        ):
            errors.append("portable launch/UI work cannot precede atomic deployment")
        launch_indexes = [
            index for index, step in enumerate(steps) if step.get("type") == "launchApplication"
        ]
        if len(launch_indexes) != 1:
            errors.append("portable automation must launch exactly one application")
        elif (
            len(deploy_indexes) == 1
            and len(start_indexes) == 1
            and (
                not deploy_indexes[0] < launch_indexes[0] < start_indexes[0]
                or steps[launch_indexes[0]].get("application")
                != steps[start_indexes[0]].get("application")
            )
        ):
            errors.append("portable UI session is not bound to its launched application")

    cleanup_timeout = sum(
        item.get("timeoutSeconds", 0)
        for item in cleanup_steps
        if isinstance(item.get("timeoutSeconds"), int)
    )
    if cleanup_timeout > 300:
        errors.append("cleanup timeout budget exceeds 300 seconds")
    forbidden_cleanup = {"deployPortable", "installPackage", "uninstallPackage"}
    if any(step.get("type") in forbidden_cleanup for step in cleanup_steps):
        errors.append("cleanup contains a deployment or package mutation")
    if any(
        step.get("type") in {"stopUiSession", "captureUiScreenshot"}
        for step in cleanup_steps
    ) and "webDriver" not in profile:
        errors.append("UI cleanup requires the fixed WebDriver contract")
    cleanup_fields = {
        "stopApplication": {"application"},
        "stopUiSession": set(),
        "captureUiScreenshot": {"evidenceName"},
        "wait": set(),
        "assertFile": {"path", "expected"},
        "assertShortcut": {"path", "expected"},
        "assertRegistry": {"registryPath", "registryName", "expected"},
        "assertProcess": {"application", "processName", "expected"},
        "assertModule": {"application", "moduleRelativePath", "expected"},
        "assertPort": {"port", "expected"},
        "assertSentinel": {"sentinelId", "expected"},
    }
    cleanup_required_fields = {
        "stopApplication": {"application"},
        "captureUiScreenshot": {"evidenceName"},
        "assertFile": {"path"},
        "assertShortcut": {"path"},
        "assertRegistry": {"registryPath"},
        "assertModule": {"application", "moduleRelativePath"},
        "assertPort": {"port"},
        "assertSentinel": {"sentinelId"},
    }
    cleanup_actions = {"stopApplication", "stopUiSession", "captureUiScreenshot", "wait"}
    for step in cleanup_steps:
        step_type = step.get("type")
        allowed = {"id", "type", "timeoutSeconds", "required"} | cleanup_fields.get(
            step_type, set()
        )
        if set(step) - allowed:
            errors.append(f"cleanup step {step.get('id')!r} has fields invalid for its type")
        if not cleanup_required_fields.get(step_type, set()).issubset(step):
            errors.append(f"cleanup step {step.get('id')!r} lacks its bound target")
        if step_type == "assertProcess" and (
            ("application" in step) == ("processName" in step)
        ):
            errors.append("cleanup assertProcess requires exactly one bound process target")
        if step_type in cleanup_actions and step.get("required", True) is not True:
            errors.append(f"cleanup action {step.get('id')!r} cannot be optional")
    return errors


def derive_status(results: list[dict[str, Any]]) -> str:
    required = [result for result in results if result.get("required") is True]
    if any(result.get("status") == "failed" for result in required):
        return "failed"
    if any(
        result.get("status") in {"notPerformed", "unsupported"}
        for result in required
    ):
        return "incomplete"
    return "passed"


def validate_evidence_semantics(evidence: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    automatic = evidence.get("automaticAssertions", [])
    manual = evidence.get("manualAssertions", [])
    machine_facts_passed = all(
        result.get("status") == "passed"
        for result in automatic
        if result.get("required") is True
    )
    recovery = evidence.get("networkRecovery", {})
    network_operations = evidence.get("networkOperations", [])
    disconnect_effects = [
        operation
        for operation in network_operations
        if operation.get("planRole") == "change"
        and operation.get("target") == "disconnected"
        and operation.get("effectState") in {"confirmed", "indeterminate"}
    ]
    if recovery.get("required") is not bool(disconnect_effects):
        errors.append("network recovery requirement does not match disconnect effects")
        machine_facts_passed = False
    if recovery.get("required") is True and recovery.get("status") != "passed":
        machine_facts_passed = False
    if recovery.get("required") is True and recovery.get("status") == "passed":
        if (
            not isinstance(recovery.get("recoveryOperationId"), str)
            or recovery.get("finalFingerprint") != recovery.get("initialFingerprint")
        ):
            errors.append("passed network recovery is not bound to restored baseline state")
            machine_facts_passed = False
        change_matches = [
            operation
            for operation in disconnect_effects
            if operation.get("planId") == recovery.get("changePlanId")
            and operation.get("beforeFingerprint") == recovery.get("initialFingerprint")
        ]
        recovery_matches = [
            operation
            for operation in network_operations
            if operation.get("operationId") == recovery.get("recoveryOperationId")
            and operation.get("planId") == recovery.get("recoveryPlanId")
            and operation.get("planRole") == "recovery"
            and operation.get("target") == "baseline"
            and operation.get("status") == "passed"
            and operation.get("afterFingerprint") == recovery.get("finalFingerprint")
        ]
        if len(change_matches) != 1 or len(recovery_matches) != 1:
            errors.append("network recovery is not bound to its change/recovery operations")
            machine_facts_passed = False

    artifacts = evidence.get("artifacts", [])
    roles = [item.get("role") for item in artifacts]
    required_roles = {
        "portableZip",
        "portableManifest",
        "webDriverArchive",
        "webDriverExecutable",
        "deployedPayload",
    }
    if (
        any(roles.count(role) != 1 for role in required_roles)
        or roles.count("fixture") < 1
    ):
        errors.append("portable evidence is missing required artifact roles")
        machine_facts_passed = False
    for artifact in artifacts:
        if artifact.get("status") != "passed":
            machine_facts_passed = False
        if artifact.get("sourceSha256") != artifact.get("guestSha256"):
            errors.append(f"artifact role {artifact.get('role')!r} has hash drift")
            machine_facts_passed = False

    vm = evidence.get("vm", {})
    guest = evidence.get("guest", {})
    automation = evidence.get("automation", {})
    if (
        vm.get("ownershipVerified") is not True
        or guest.get("isAdministrator") is not False
        or guest.get("isElevated") is not False
        or guest.get("tokenIntegrity") != "medium"
        or automation.get("dataPreserved") is not True
        or automation.get("loopbackOnly") is not True
    ):
        machine_facts_passed = False
    previous_data_hash = automation.get("previousDataInventorySha256")
    if previous_data_hash is not None and previous_data_hash != automation.get(
        "deployedDataInventorySha256"
    ):
        errors.append("portable data inventory was not preserved byte-for-byte")
        machine_facts_passed = False
    automatic_by_id = {item.get("id"): item for item in automatic}
    for item in automation.get("uiTrace", []):
        assertion = automatic_by_id.get(item.get("stepId"))
        if item.get("status") != "passed" and not (
            isinstance(assertion, dict) and assertion.get("required") is False
        ):
            machine_facts_passed = False
    if any(
        item.get("status") != "passed"
        for item in [
            *evidence.get("powerOperations", []),
            *network_operations,
        ]
    ):
        machine_facts_passed = False

    candidate = evidence.get("candidate", {})
    if evidence.get("profile", {}).get("sha256") != candidate.get("profileSha256"):
        errors.append("profile hash is not bound to the candidate")
        machine_facts_passed = False
    if automation.get("webDriverManifestSha256") != candidate.get(
        "webDriverManifestSha256"
    ):
        errors.append("WebDriver manifest hash is not bound to the candidate")
        machine_facts_passed = False
    if automation.get("fixedWebView2Version") != automation.get("webDriverVersion"):
        errors.append("fixed WebView2 and WebDriver versions do not match")
        machine_facts_passed = False
    portable_artifacts = [
        item for item in artifacts if item.get("role") == "portableZip"
    ]
    if len(portable_artifacts) == 1 and portable_artifacts[0].get(
        "sourceSha256"
    ) != candidate.get("portableZipSha256"):
        errors.append("portable ZIP hash is not bound to the candidate")
        machine_facts_passed = False

    expected_machine = "passed" if machine_facts_passed else "failed"
    if evidence.get("machineStatus") != expected_machine:
        errors.append("machineStatus does not match required automatic/infrastructure facts")

    expected_overall = derive_status(manual)
    if expected_machine == "failed":
        expected_overall = "failed"
    if evidence.get("overallStatus") != expected_overall:
        errors.append("overallStatus does not match required machine/manual facts")

    attestations = [
        (result, result.get("attestation"))
        for result in manual
        if isinstance(result.get("attestation"), dict)
    ]
    for result, attestation in attestations:
        if (
            attestation.get("operationId") != evidence.get("operationId")
            or attestation.get("profileId") != evidence.get("profile", {}).get("id")
            or attestation.get("assertionId") != result.get("id")
        ):
            errors.append("manual attestation is not bound to its operation/profile/assertion")
        for field in (
            "sourceCommit",
            "portableZipSha256",
            "profileSha256",
            "fixtureSetSha256",
            "webDriverManifestSha256",
        ):
            if attestation.get("candidate", {}).get(field) != candidate.get(field):
                errors.append(f"manual attestation is not bound to candidate {field}")
    return errors


def semantic_errors(prefix: str, instance: dict[str, Any]) -> list[str]:
    if prefix == "vm-power-plan":
        return validate_power_plan_semantics(instance)
    if prefix == "vm-network-plan":
        return validate_network_plan_semantics(instance)
    if prefix == "portable-manifest":
        return validate_portable_manifest_semantics(instance)
    if prefix == "webdriver-manifest":
        return validate_webdriver_manifest_semantics(instance)
    if prefix == "test-profile":
        return validate_profile_semantics(instance)
    if prefix == "evidence":
        return validate_evidence_semantics(instance)
    return []


def migrate_v1_profile(profile: dict[str, Any]) -> dict[str, Any]:
    kinds = {
        application.get("installerType")
        for application in profile.get("applications", [])
    }
    if kinds not in ({"nsis"}, {"msi"}):
        raise ValueError("MIGRATION_AMBIGUOUS_PACKAGE_KIND")
    package_kind = next(iter(kinds))
    migrated: dict[str, Any] = {
        "schemaVersion": 2,
        "id": profile["id"],
        "workflowKind": "legacyPackageLifecycle",
        "platform": profile["platform"],
        "baselineType": profile["baselineType"],
        "artifact": {"packageKind": package_kind, **profile["artifact"]},
        "fixtures": [],
        "applications": [],
        "steps": deepcopy(profile["steps"]),
        "cleanupSteps": deepcopy(profile["cleanupSteps"]),
        "manualAssertions": deepcopy(profile["manualAssertions"]),
    }
    if "description" in profile:
        migrated["description"] = profile["description"]
    for application in profile["applications"]:
        converted = {
            key: deepcopy(value)
            for key, value in application.items()
            if key != "installerType"
        }
        converted["packageKind"] = application["installerType"]
        migrated["applications"].append(converted)
    return migrated


def assert_contract_metadata(catalog: dict[str, Any]) -> None:
    if catalog.get("contractVersion") != 2:
        raise AssertionError("tool catalog contractVersion must be 2")
    if catalog.get("targetPluginVersion") != "0.2.0":
        raise AssertionError("tool catalog target plugin version must be 0.2.0")
    if catalog.get("currentRuntimeVersion") != "0.2.0":
        raise AssertionError("H2 must integrate executable runtime 0.2.0")
    envelopes = catalog.get("resultEnvelopes", {})
    if envelopes != {
        "exactV1Tools": "hyperv-clean-room/schemas/operation-envelope.schema.json",
        "schemaV2Tools": EXPECTED_V2_SCHEMA_IDS["operation-envelope.schema.json"],
    }:
        raise AssertionError("v1 and v2 result envelopes are not independently routed")
    if catalog.get("dispatch") != {
        "profileAndEvidenceVersionField": "schemaVersion",
        "strategy": "exactInteger",
        "unknownVersionError": "UNSUPPORTED_SCHEMA_VERSION",
        "fallback": False,
    }:
        raise AssertionError("tool catalog schema dispatch is not exact and fail closed")
    manifest = load_json(PLUGIN_MANIFEST_PATH)
    if not re.fullmatch(
        r"0\.2\.0(?:\+codex\.[a-z0-9]+(?:-[a-z0-9]+)*)?",
        str(manifest["version"]),
    ):
        raise AssertionError(
            "the integrated manifest must preserve base 0.2.0 with at most "
            "one Codex cachebuster"
        )


def assert_v1_compatibility(catalog: dict[str, Any]) -> tuple[int, int]:
    compatibility = load_json(CONTRACT_ROOT / "compatibility.json")
    live_tools = live_v1_tools()
    snapshot_tools = load_json(FIXTURE_ROOT / "compatibility" / "tool-catalog-v1.json")
    if canonical_json(live_tools) != canonical_json(snapshot_tools):
        raise AssertionError("live schema-v1 tool registry differs from its H1 snapshot")
    if [tool["name"] for tool in live_tools] != V1_TOOL_NAMES:
        raise AssertionError("live schema-v1 tool names or order changed")

    catalog_tools = catalog["tools"]
    compatibility_fixture = (
        "tests/fixtures/v2/compatibility/tool-catalog-v1.json"
    )
    for index, (live, declared) in enumerate(
        zip(live_tools, catalog_tools[: len(V1_TOOL_NAMES)])
    ):
        if declared != {
            "name": live["name"],
            "introducedIn": "0.1.0",
            "compatibility": "exactV1",
            "compatibilityRef": f"{compatibility_fixture}#/{index}",
        }:
            raise AssertionError(f"v2 catalog rewrites v1 tool {live['name']}")

    schema_hashes = compatibility.get("schemaV1Sha256", {})
    expected_names = {
        "operation-envelope.schema.json",
        "vm-plan.schema.json",
        "checkpoint-plan.schema.json",
        "test-profile.schema.json",
        "evidence.schema.json",
    }
    if set(schema_hashes) != expected_names:
        raise AssertionError("v1 compatibility hash inventory is incomplete")
    for name, expected_hash in schema_hashes.items():
        if sha256_file(V1_SCHEMA_ROOT / name) != expected_hash:
            raise AssertionError(f"schema-v1 contract drifted: {name}")

    document_policy = compatibility.get("documents", {})
    profile_policy = document_policy.get("profileV1", {})
    if (
        profile_policy.get("migration") != "explicitLosslessOnly"
        or profile_policy.get("requiresAuthoring") is not True
        or profile_policy.get("ambiguousPackageKindError")
        != "MIGRATION_AMBIGUOUS_PACKAGE_KIND"
    ):
        raise AssertionError("v1 profile migration policy is not exact and fail closed")
    if document_policy.get("evidenceV1", {}).get("migration") != "preserveV1":
        raise AssertionError("v1 evidence must never be synthetically upgraded")
    unknown_policy = document_policy.get("unknownSchemaVersion", {})
    if unknown_policy != {
        "behavior": "reject",
        "errorCode": "UNSUPPORTED_SCHEMA_VERSION",
    }:
        raise AssertionError("unknown schema versions must fail closed")
    if compatibility.get("runtimeDispatch") != {
        "strategy": "exactIntegerSchemaVersion",
        "fallback": False,
        "tryV2ThenV1": False,
    }:
        raise AssertionError("schema version dispatch permits fallback")
    if compatibility.get("stateV1") != {
        "stateRoot": "%LOCALAPPDATA%\\Codex\\hyperv-clean-room\\v1",
        "ownershipMarkerPrefix": "hyperv-clean-room/v1:",
        "rewriteExistingRecords": False,
        "adoptUnmanagedResources": False,
    }:
        raise AssertionError("schema-v2 target rewrites or adopts schema-v1 state")
    return len(live_tools), len(schema_hashes)


def assert_v2_tool_contract(
    catalog: dict[str, Any],
    schemas: dict[str, dict[str, Any]],
    registry: Registry,
) -> None:
    tools = catalog.get("tools", [])
    names = [tool.get("name") for tool in tools]
    if names != EXPECTED_TOOL_NAMES:
        raise AssertionError(f"expected exact 20-tool catalog, found {names}")
    if len(set(names)) != len(names):
        raise AssertionError("tool catalog contains duplicate names")
    for tool in tools[len(V1_TOOL_NAMES) :]:
        input_schema = tool.get("inputSchema")
        if not isinstance(input_schema, dict):
            raise AssertionError(f"tool lacks input schema: {tool.get('name')}")
        if input_schema.get("type") != "object" or input_schema.get(
            "additionalProperties"
        ) is not False:
            raise AssertionError(f"tool input is not closed: {tool.get('name')}")
        forbidden = property_names(input_schema) & FORBIDDEN_TOOL_INPUT_FIELDS
        if forbidden:
            raise AssertionError(
                f"tool {tool.get('name')} exposes forbidden input fields: {sorted(forbidden)}"
            )

    by_name = {tool["name"]: tool for tool in tools}
    power = by_name["plan_vm_power"]["inputSchema"]
    if power["properties"]["action"].get("enum") != [
        "start",
        "gracefulShutdown",
    ]:
        raise AssertionError("power plan exposes an unsafe transition")
    network = by_name["plan_vm_network"]["inputSchema"]
    if network["properties"]["target"].get("enum") != [
        "baseline",
        "disconnected",
    ]:
        raise AssertionError("network plan exposes arbitrary adapter/switch mutation")
    for name in ("apply_vm_power", "apply_vm_network"):
        schema = by_name[name]["inputSchema"]
        if schema.get("required") != ["planId"] or set(
            schema.get("properties", {})
        ) != {"planId"}:
            raise AssertionError(f"{name} must accept only planId")

    plan_power = load_json(FIXTURE_ROOT / "vm-power-plan.start.valid.json")
    network_change = load_json(FIXTURE_ROOT / "vm-network-plan.change.valid.json")
    network_recovery = load_json(FIXTURE_ROOT / "vm-network-plan.recovery.valid.json")
    success_samples = {
        "plan_vm_power": {"plan": plan_power},
        "apply_vm_power": {
            "planId": plan_power["planId"],
            "vmId": plan_power["vmId"],
            "vmName": plan_power["vmName"],
            "action": "start",
            "previousState": "Off",
            "currentState": "Running",
            "effectState": "confirmed",
        },
        "plan_vm_network": {
            "changePlan": network_change,
            "recoveryPlan": network_recovery,
        },
        "apply_vm_network": {
            "planId": network_change["planId"],
            "pairedPlanId": network_change["pairedPlanId"],
            "planRole": "change",
            "vmId": network_change["vmId"],
            "vmName": network_change["vmName"],
            "adapterId": network_change["adapter"]["id"],
            "target": "disconnected",
            "previousAttachment": network_change["currentAttachment"],
            "currentAttachment": network_change["targetAttachment"],
            "effectState": "confirmed",
            "recoveryRequired": True,
        },
    }
    invalid_success_samples = {
        "apply_vm_power": {
            **deepcopy(success_samples["apply_vm_power"]),
            "currentState": "Off",
        },
        "plan_vm_network": {
            "changePlan": network_change,
            "recoveryPlan": None,
        },
        "apply_vm_network": {
            **deepcopy(success_samples["apply_vm_network"]),
            "recoveryRequired": False,
        },
    }
    envelope_id = schemas["operation-envelope.schema.json"]["$id"]
    for name in V2_ADDITIVE_TOOL_NAMES:
        contract = by_name[name].get("resultContract")
        if not isinstance(contract, dict) or set(contract) != {
            "envelopeSchema",
            "successChanged",
            "successDataSchema",
            "failureCodes",
        }:
            raise AssertionError(f"{name} lacks an exact result contract")
        if contract["envelopeSchema"] != envelope_id:
            raise AssertionError(f"{name} uses an unexpected result envelope")
        expected_changed = name.startswith("apply_")
        if contract["successChanged"] is not expected_changed:
            raise AssertionError(f"{name} freezes an incorrect changed flag")
        failure_codes = contract["failureCodes"]
        if (
            failure_codes != EXPECTED_FAILURE_CODES[name]
            or failure_codes != sorted(failure_codes)
            or len(failure_codes) != len(set(failure_codes))
            or any(not re.fullmatch(r"[A-Z][A-Z0-9_]*", code) for code in failure_codes)
        ):
            raise AssertionError(f"{name} failure codes are not stable and canonical")
        success_schema = contract["successDataSchema"]
        Draft202012Validator.check_schema(success_schema)
        errors = list(
            Draft202012Validator(
                success_schema,
                format_checker=FormatChecker(),
                registry=registry,
            ).iter_errors(success_samples[name])
        )
        if errors:
            raise AssertionError(
                f"{name} success sample violates its result contract: {errors[0].message}"
            )
        invalid_sample = invalid_success_samples.get(name)
        if invalid_sample is not None and not list(
            Draft202012Validator(
                success_schema,
                format_checker=FormatChecker(),
                registry=registry,
            ).iter_errors(invalid_sample)
        ):
            raise AssertionError(f"{name} result contract accepted an unsafe success shape")

    baseline_change = deepcopy(network_recovery)
    baseline_change["planRole"] = "change"
    baseline_change["planId"] = "33111111-1111-4111-8111-111111111111"
    baseline_change["pairedPlanId"] = None
    baseline_change["expiresAt"] = "2026-07-21T08:15:00Z"
    baseline_plan_result = {"changePlan": baseline_change, "recoveryPlan": None}
    baseline_plan_schema = by_name["plan_vm_network"]["resultContract"][
        "successDataSchema"
    ]
    if list(
        Draft202012Validator(
            baseline_plan_schema,
            format_checker=FormatChecker(),
            registry=registry,
        ).iter_errors(baseline_plan_result)
    ):
        raise AssertionError("valid baseline reconnect planning result was rejected")

    baseline_apply_result = {
        "planId": network_recovery["planId"],
        "pairedPlanId": network_recovery["pairedPlanId"],
        "planRole": "recovery",
        "vmId": network_recovery["vmId"],
        "vmName": network_recovery["vmName"],
        "adapterId": network_recovery["adapter"]["id"],
        "target": "baseline",
        "previousAttachment": network_recovery["currentAttachment"],
        "currentAttachment": network_recovery["targetAttachment"],
        "effectState": "confirmed",
        "recoveryRequired": False,
    }
    baseline_apply_schema = by_name["apply_vm_network"]["resultContract"][
        "successDataSchema"
    ]
    if list(
        Draft202012Validator(
            baseline_apply_schema,
            format_checker=FormatChecker(),
            registry=registry,
        ).iter_errors(baseline_apply_result)
    ):
        raise AssertionError("valid baseline recovery apply result was rejected")


def main() -> int:
    required_contract_files = {
        CONTRACT_ROOT / "tool-catalog.json",
        CONTRACT_ROOT / "compatibility.json",
        CONTRACT_ROOT / "README.md",
    }
    missing_contract_files = sorted(
        str(path.relative_to(REPO_ROOT))
        for path in required_contract_files
        if not path.is_file()
    )
    if missing_contract_files:
        raise AssertionError(f"missing v2 contract files: {missing_contract_files}")

    schema_paths = sorted(SCHEMA_ROOT.glob("*.schema.json"))
    if {path.name for path in schema_paths} != EXPECTED_V2_SCHEMAS:
        raise AssertionError(
            "v2 schema inventory differs: "
            f"{[path.name for path in schema_paths]}"
        )
    schemas = {path.name: load_json(path) for path in schema_paths}
    for name, schema in schemas.items():
        Draft202012Validator.check_schema(schema)
        if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
            raise AssertionError(f"unexpected JSON Schema dialect: {name}")
        if schema.get("$id") != EXPECTED_V2_SCHEMA_IDS[name]:
            raise AssertionError(f"unstable v2 schema ID: {name}")
        if schema.get("properties", {}).get("schemaVersion", {}).get("const") != 2:
            raise AssertionError(f"v2 schema does not require schemaVersion 2: {name}")

    forbidden_profile_fields = property_names(schemas["test-profile.schema.json"]) & {
        "arguments",
        "command",
        "javascript",
        "script",
        "selector",
        "shell",
        "url",
    }
    if forbidden_profile_fields:
        raise AssertionError(
            "schema-v2 profile exposes forbidden fields: "
            f"{sorted(forbidden_profile_fields)}"
        )
    assert_ui_states = set(
        schemas["test-profile.schema.json"]["$defs"]["assertUiElementStep"][
            "allOf"
        ][1]["properties"]["state"]["enum"]
    )
    if assert_ui_states != UI_ASSERT_STATES:
        raise AssertionError(
            f"closed UI assertion state set drifted: {sorted(assert_ui_states)}"
        )

    registry = schema_registry(schemas)
    catalog = load_json(CONTRACT_ROOT / "tool-catalog.json")
    assert_contract_metadata(catalog)
    assert_v2_tool_contract(catalog, schemas, registry)
    v1_tool_count, v1_schema_count = assert_v1_compatibility(catalog)

    fixtures = sorted(FIXTURE_ROOT.glob("*.json"))
    if not fixtures:
        raise AssertionError("no schema-v2 fixtures found")
    valid_count = 0
    schema_invalid_count = 0
    semantic_invalid_count = 0
    for fixture_path in fixtures:
        expects_semantic_invalid = fixture_path.name.endswith(
            ".semantic-invalid.json"
        )
        expects_schema_invalid = (
            fixture_path.name.endswith(".invalid.json")
            and not expects_semantic_invalid
        )
        expects_valid = fixture_path.name.endswith(".valid.json")
        if sum((expects_valid, expects_schema_invalid, expects_semantic_invalid)) != 1:
            raise AssertionError(
                f"fixture name lacks one validity marker: {fixture_path.name}"
            )
        prefix = fixture_path.name.split(".", 1)[0]
        schema_name = SCHEMA_BY_FIXTURE_PREFIX.get(prefix)
        if schema_name is None:
            raise AssertionError(f"fixture has no schema mapping: {fixture_path.name}")
        instance = load_json(fixture_path)
        errors = sorted(
            validator_for(schema_name, schemas, registry).iter_errors(instance),
            key=lambda error: list(error.absolute_path),
        )
        if expects_schema_invalid:
            if not errors:
                raise AssertionError(
                    f"schema-invalid v2 fixture accepted: {fixture_path.name}"
                )
            schema_invalid_count += 1
            continue
        if errors:
            messages = "; ".join(error.message for error in errors[:5])
            raise AssertionError(
                f"schema-valid v2 fixture rejected: {fixture_path.name}: {messages}"
            )
        semantic = semantic_errors(prefix, instance)
        if expects_semantic_invalid:
            if not semantic:
                raise AssertionError(
                    f"semantic-invalid v2 fixture accepted: {fixture_path.name}"
                )
            semantic_invalid_count += 1
            continue
        if semantic:
            raise AssertionError(
                f"valid v2 fixture failed semantics: {fixture_path.name}: "
                + "; ".join(semantic[:5])
            )
        valid_count += 1

    portable_probe = load_json(FIXTURE_ROOT / "portable-manifest.valid.json")
    portable_probe["files"].append(
        {
            "path": "portable-manifest.json",
            "sizeBytes": 512,
            "sha256": "d" * 64,
        }
    )
    if not validate_portable_manifest_semantics(portable_probe):
        raise AssertionError("self-referential portable manifest inventory was accepted")
    mutable_data_probe = load_json(FIXTURE_ROOT / "portable-manifest.valid.json")
    mutable_data_probe["files"].append(
        {"path": "data/seed.json", "sizeBytes": 2, "sha256": "e" * 64}
    )
    if not validate_portable_manifest_semantics(mutable_data_probe):
        raise AssertionError("packaged mutable data inventory was accepted")
    reserved_path_probe = load_json(FIXTURE_ROOT / "portable-manifest.valid.json")
    reserved_path_probe["files"][0]["path"] = "CON.txt"
    reserved_path_probe["entryPointRelativePath"] = "CON.txt"
    if not validate_portable_manifest_semantics(reserved_path_probe):
        raise AssertionError("reserved Windows device path was accepted")

    profile_probe = load_json(FIXTURE_ROOT / "test-profile.portable.valid.json")
    click_index = next(
        index
        for index, step in enumerate(profile_probe["steps"])
        if step["type"] == "uiClick"
    )
    click = profile_probe["steps"].pop(click_index)
    profile_probe["steps"].insert(1, click)
    if not validate_profile_semantics(profile_probe):
        raise AssertionError("UI interaction outside the owned session was accepted")
    missing_launch_probe = load_json(FIXTURE_ROOT / "test-profile.portable.valid.json")
    missing_launch_probe["steps"] = [
        step for step in missing_launch_probe["steps"] if step["type"] != "launchApplication"
    ]
    if not validate_profile_semantics(missing_launch_probe):
        raise AssertionError("portable UI profile without application launch was accepted")
    cleanup_probe = load_json(FIXTURE_ROOT / "test-profile.portable.valid.json")
    del cleanup_probe["cleanupSteps"][0]["application"]
    if not validate_profile_semantics(cleanup_probe):
        raise AssertionError("unbound cleanup action was accepted")

    network_change = load_json(FIXTURE_ROOT / "vm-network-plan.change.valid.json")
    network_recovery = load_json(FIXTURE_ROOT / "vm-network-plan.recovery.valid.json")
    pair_fields = (
        "createdAt",
        "hostFingerprint",
        "vmId",
        "vmName",
        "ownershipId",
        "ownershipRecordSha256",
        "vmFingerprint",
        "adapter",
        "baselineAttachment",
    )
    if (
        network_change["pairedPlanId"] != network_recovery["planId"]
        or network_recovery["pairedPlanId"] != network_change["planId"]
        or any(
            canonical_json(network_change[field])
            != canonical_json(network_recovery[field])
            for field in pair_fields
        )
    ):
        raise AssertionError("network change/recovery fixture pair is not cross-bound")

    migration_input = load_json(
        FIXTURE_ROOT / "migration" / "test-profile.v1.input.json"
    )
    migration_expected = load_json(
        FIXTURE_ROOT / "migration" / "test-profile.v2.expected.json"
    )
    migration_original = deepcopy(migration_input)
    migration_actual = migrate_v1_profile(migration_input)
    if migration_input != migration_original:
        raise AssertionError("v1 profile migration mutated its input")
    if canonical_json(migration_actual) != canonical_json(migration_expected):
        raise AssertionError("v1-to-v2 profile migration is not deterministic")
    migration_errors = list(
        validator_for("test-profile.schema.json", schemas, registry).iter_errors(
            migration_actual
        )
    )
    if migration_errors or validate_profile_semantics(migration_actual):
        raise AssertionError("deterministically migrated v2 profile is invalid")
    ambiguous = deepcopy(migration_input)
    ambiguous["applications"].append(
        {
            **ambiguous["applications"][0],
            "id": "second-app",
            "installerType": "msi",
        }
    )
    try:
        migrate_v1_profile(ambiguous)
    except ValueError as error:
        if str(error) != "MIGRATION_AMBIGUOUS_PACKAGE_KIND":
            raise
    else:
        raise AssertionError("ambiguous v1 package kinds migrated silently")

    evidence_probe = load_json(
        FIXTURE_ROOT / "evidence.machine-passed-manual-incomplete.valid.json"
    )
    evidence_validator = validator_for("evidence.schema.json", schemas, registry)
    recovery_probe = deepcopy(evidence_probe)
    recovery_probe["networkRecovery"] = {
        "required": True,
        "changePlanId": "61111111-1111-4111-8111-111111111111",
        "recoveryPlanId": "62222222-2222-4222-8222-222222222222",
        "recoveryOperationId": "63333333-3333-4333-8333-333333333333",
        "status": "failed",
        "initialFingerprint": "a" * 64,
        "finalFingerprint": "b" * 64,
    }
    if not validate_evidence_semantics(recovery_probe):
        raise AssertionError("failed required network recovery did not fail evidence")

    recovery_drift_probe = deepcopy(evidence_probe)
    recovery_drift_probe["networkRecovery"] = {
        "required": True,
        "changePlanId": "61111111-1111-4111-8111-111111111111",
        "recoveryPlanId": "62222222-2222-4222-8222-222222222222",
        "recoveryOperationId": "63333333-3333-4333-8333-333333333333",
        "status": "passed",
        "initialFingerprint": "a" * 64,
        "finalFingerprint": "b" * 64,
    }
    if not validate_evidence_semantics(recovery_drift_probe):
        raise AssertionError("drifted baseline fingerprint passed network recovery")

    recovery_success_probe = deepcopy(evidence_probe)
    recovery_success_probe["networkOperations"] = [
        {
            "operationId": "64111111-1111-4111-8111-111111111111",
            "planId": "61111111-1111-4111-8111-111111111111",
            "planRole": "change",
            "target": "disconnected",
            "beforeFingerprint": "a" * 64,
            "afterFingerprint": "b" * 64,
            "effectState": "confirmed",
            "status": "passed",
        },
        {
            "operationId": "63333333-3333-4333-8333-333333333333",
            "planId": "62222222-2222-4222-8222-222222222222",
            "planRole": "recovery",
            "target": "baseline",
            "beforeFingerprint": "b" * 64,
            "afterFingerprint": "a" * 64,
            "effectState": "confirmed",
            "status": "passed",
        },
    ]
    recovery_success_probe["networkRecovery"] = {
        "required": True,
        "changePlanId": "61111111-1111-4111-8111-111111111111",
        "recoveryPlanId": "62222222-2222-4222-8222-222222222222",
        "recoveryOperationId": "63333333-3333-4333-8333-333333333333",
        "status": "passed",
        "initialFingerprint": "a" * 64,
        "finalFingerprint": "a" * 64,
    }
    if list(evidence_validator.iter_errors(recovery_success_probe)) or (
        validate_evidence_semantics(recovery_success_probe)
    ):
        raise AssertionError("valid paired network recovery evidence was rejected")

    infrastructure_probe = deepcopy(evidence_probe)
    infrastructure_probe["artifacts"][0]["status"] = "failed"
    if not validate_evidence_semantics(infrastructure_probe):
        raise AssertionError("failed candidate artifact preserved machine-passed evidence")

    data_drift_probe = deepcopy(evidence_probe)
    data_drift_probe["automation"]["previousDataInventorySha256"] = "c" * 64
    data_drift_probe["automation"]["deployedDataInventorySha256"] = "d" * 64
    if not validate_evidence_semantics(data_drift_probe):
        raise AssertionError("portable data inventory drift preserved machine-passed evidence")

    driver_version_probe = deepcopy(evidence_probe)
    driver_version_probe["automation"]["webDriverVersion"] = "138.0.3351.122"
    if not validate_evidence_semantics(driver_version_probe):
        raise AssertionError("fixed WebView2/WebDriver version drift passed evidence")

    attested_probe = deepcopy(evidence_probe)
    attested_probe["manualAssertions"][0]["status"] = "passed"
    attested_probe["manualAssertions"][0]["attestation"] = {
        "operationId": attested_probe["operationId"],
        "profileId": attested_probe["profile"]["id"],
        "assertionId": attested_probe["manualAssertions"][0]["id"],
        "observer": "reviewer",
        "observedAt": "2026-07-21T08:40:00Z",
        "method": "visualInspection",
        "summary": "The declared visual assertion was observed.",
        "candidate": deepcopy(attested_probe["candidate"]),
        "evidenceReferences": [],
    }
    attested_probe["overallStatus"] = "passed"
    if list(evidence_validator.iter_errors(attested_probe)) or validate_evidence_semantics(
        attested_probe
    ):
        raise AssertionError("candidate-bound manual attestation did not complete evidence")
    attested_probe["manualAssertions"][0]["attestation"]["candidate"][
        "portableZipSha256"
    ] = "f" * 64
    if not validate_evidence_semantics(attested_probe):
        raise AssertionError("manual attestation accepted candidate hash drift")

    print(
        json.dumps(
            {
                "ok": True,
                "targetPluginVersion": "0.2.0",
                "currentRuntimeVersion": "0.2.0",
                "v1ToolsPreserved": v1_tool_count,
                "v2ToolsDeclared": len(EXPECTED_TOOL_NAMES),
                "v1SchemasPreserved": v1_schema_count,
                "v2Schemas": len(schemas),
                "validFixtures": valid_count,
                "schemaInvalidFixtures": schema_invalid_count,
                "semanticInvalidFixtures": semantic_invalid_count,
                "migrationFixtures": 2,
                "dynamicCompatibilityChecks": 15,
                "realHyperVMutations": 0,
                "realGuestOperations": 0,
            },
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

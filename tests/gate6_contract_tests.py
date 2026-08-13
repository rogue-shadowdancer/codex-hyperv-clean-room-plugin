from __future__ import annotations

import ctypes
import hashlib
import json
import re
import subprocess
import sys
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
P3_1_FIXTURE_ROOT = Path(__file__).resolve().parent / "fixtures" / "v3"
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
        "HYPERV_AUTHORIZATION_REQUIRED",
        "HYPERV_UNAVAILABLE",
        "INVALID_ARGUMENT",
        "OWNERSHIP_UNVERIFIED",
        "STATE_BUSY",
        "STATE_ROOT_ACCESS_DENIED",
        "VM_NOT_FOUND",
        "VM_STATE_UNSUPPORTED",
    ],
    "apply_vm_power": [
        "HYPERV_AUTHORIZATION_REQUIRED",
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
        "STATE_ROOT_ACCESS_DENIED",
        "VM_STATE_UNSUPPORTED",
    ],
    "plan_vm_network": [
        "BASELINE_UNAVAILABLE",
        "HYPERV_AUTHORIZATION_REQUIRED",
        "HYPERV_UNAVAILABLE",
        "INVALID_ARGUMENT",
        "OWNERSHIP_UNVERIFIED",
        "PRIMARY_ADAPTER_UNVERIFIED",
        "STATE_BUSY",
        "STATE_ROOT_ACCESS_DENIED",
        "VM_NOT_FOUND",
    ],
    "apply_vm_network": [
        "BASELINE_UNAVAILABLE",
        "HYPERV_AUTHORIZATION_REQUIRED",
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
        "STATE_ROOT_ACCESS_DENIED",
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
SAFE_RELATIVE_PATH_FIELDS = {
    "archivePath",
    "derivedFromPath",
    "entrypoint",
    "entryPointRelativePath",
    "executablePath",
    "executableRelativePath",
    "inventoryPath",
    "maaInventoryAuthority",
    "moduleRelativePath",
    "nativeInventoryPath",
    "path",
    "portableManifestRelativePath",
    "registryPath",
    "rootDirectory",
    "runtimeManifestPath",
    "sourcePath",
    "sourceRelativePath",
    "trackedManifest",
}
SAFE_RELATIVE_PATH_ARRAY_FIELDS = {
    "excludedBirdsgoneTrackedFiles",
    "removedPaths",
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


def compact_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


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


def contains_schema_version_2(value: Any) -> bool:
    if isinstance(value, dict):
        properties = value.get("properties")
        if (
            isinstance(properties, dict)
            and isinstance(properties.get("schemaVersion"), dict)
            and properties["schemaVersion"].get("const") == 2
        ):
            return True
        return any(contains_schema_version_2(child) for child in value.values())
    if isinstance(value, list):
        return any(contains_schema_version_2(child) for child in value)
    return False


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
    if any(ord(character) < 32 or ord(character) == 127 for character in normalized):
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
        if (
            device in {"con", "prn", "aux", "nul", "conin$", "conout$"}
            or re.fullmatch(r"(?:com|lpt)(?:[1-9]|[¹²³])", device)
        ):
            return False
    return True


def iter_bound_relative_paths(value: object) -> list[object]:
    paths: list[object] = []
    if isinstance(value, dict):
        for key, child in value.items():
            if key in SAFE_RELATIVE_PATH_FIELDS:
                paths.append(child)
            elif key in SAFE_RELATIVE_PATH_ARRAY_FIELDS and isinstance(child, list):
                paths.extend(child)
            if isinstance(child, (dict, list)):
                paths.extend(iter_bound_relative_paths(child))
    elif isinstance(value, list):
        for child in value:
            if isinstance(child, (dict, list)):
                paths.extend(iter_bound_relative_paths(child))
    return paths


def schema_bound_relative_path_fields(
    schema: dict[str, Any],
) -> tuple[set[str], set[str]]:
    scalar_fields: set[str] = set()
    array_fields: set[str] = set()

    def resolve_local_ref(reference: str) -> object:
        if not reference.startswith("#/"):
            return {}
        current: object = schema
        for raw_token in reference[2:].split("/"):
            token = raw_token.replace("~1", "/").replace("~0", "~")
            if not isinstance(current, dict) or token not in current:
                return {}
            current = current[token]
        return current

    def directly_references_safe_path(
        node: object,
        followed_refs: frozenset[str] = frozenset(),
    ) -> bool:
        if not isinstance(node, dict):
            return False
        reference = node.get("$ref")
        if isinstance(reference, str):
            if reference == "#/$defs/safeRelativePath":
                return True
            if reference not in followed_refs:
                return directly_references_safe_path(
                    resolve_local_ref(reference),
                    followed_refs | {reference},
                )
        return any(
            directly_references_safe_path(item, followed_refs)
            for keyword in ("allOf", "anyOf", "oneOf")
            for item in node.get(keyword, [])
        )

    def walk(node: object) -> None:
        if isinstance(node, dict):
            properties = node.get("properties")
            if isinstance(properties, dict):
                for name, definition in properties.items():
                    if directly_references_safe_path(definition):
                        scalar_fields.add(name)
                    if (
                        isinstance(definition, dict)
                        and isinstance(definition.get("items"), dict)
                        and directly_references_safe_path(definition["items"])
                    ):
                        array_fields.add(name)
            for child in node.values():
                walk(child)
        elif isinstance(node, list):
            for child in node:
                walk(child)

    walk(schema)
    return scalar_fields, array_fields


def normalized_archive_path(value: str) -> str:
    return unicodedata.normalize("NFC", value.replace("\\", "/"))


def utf16_code_unit_count(value: str) -> int:
    return len(value.encode("utf-16-le", errors="surrogatepass")) // 2


def windows_ordinal_ignore_case_equal(left: str, right: str) -> bool:
    left_normalized = normalized_archive_path(left)
    right_normalized = normalized_archive_path(right)
    if sys.platform != "win32":
        raise AssertionError(
            "Windows OrdinalIgnoreCase validation requires the supported Windows host"
        )
    compare = ctypes.windll.kernel32.CompareStringOrdinal
    compare.argtypes = [
        ctypes.c_wchar_p,
        ctypes.c_int,
        ctypes.c_wchar_p,
        ctypes.c_int,
        ctypes.c_bool,
    ]
    compare.restype = ctypes.c_int
    result = compare(
        left_normalized,
        utf16_code_unit_count(left_normalized),
        right_normalized,
        utf16_code_unit_count(right_normalized),
        True,
    )
    if result == 0:
        raise ctypes.WinError()
    return result == 2


def duplicate_windows_paths(paths: list[str]) -> list[str]:
    buckets: dict[int, list[str]] = {}
    duplicates: list[str] = []
    for path in paths:
        normalized = normalized_archive_path(path)
        bucket = buckets.setdefault(utf16_code_unit_count(normalized), [])
        if any(
            windows_ordinal_ignore_case_equal(normalized, prior)
            for prior in bucket
        ):
            duplicates.append(normalized)
        else:
            bucket.append(normalized)
    return duplicates


def windows_ordinal_key(value: str) -> tuple[int, ...]:
    encoded = value.encode("utf-16-le", errors="surrogatepass")
    return tuple(
        encoded[index] | (encoded[index + 1] << 8)
        for index in range(0, len(encoded), 2)
    )


def validate_portable_manifest_semantics(manifest: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    unsafe_bound_paths = [
        path
        for path in iter_bound_relative_paths(manifest)
        if not is_safe_relative_path(path)
    ]
    if unsafe_bound_paths:
        errors.append(f"manifest contains unsafe bound relative paths: {unsafe_bound_paths!r}")
    files = manifest.get("files", [])
    paths = [item.get("path") for item in files if isinstance(item, dict)]
    string_paths = [path for path in paths if isinstance(path, str)]
    for path in string_paths:
        if not is_safe_relative_path(path):
            errors.append(f"unsafe portable manifest path: {path!r}")
    normalized = [normalized_archive_path(path) for path in string_paths]
    duplicates = duplicate_windows_paths(string_paths)
    if duplicates:
        errors.append(f"case-insensitive duplicate portable paths: {duplicates}")
    boundary = manifest.get("distributionBoundary")
    external = boundary in {"runtime-and-legal-only", "end-user-complete"}
    portable_zip_name = manifest.get("fileName")
    if external and (
        not is_safe_relative_path(portable_zip_name)
        or "\\" in portable_zip_name
        or "/" in portable_zip_name
    ):
        errors.append("external manifest requires one exact safe ZIP file name")
    entry_point = (
        manifest.get("entrypoint")
        if external
        else manifest.get("entryPointRelativePath")
    )
    if isinstance(entry_point, str) and not any(
        windows_ordinal_ignore_case_equal(entry_point, path)
        for path in normalized
    ):
        errors.append("portable entry point is absent from the exact inventory")
    elif isinstance(entry_point, str):
        entry_items = [
            item
            for item in files
            if isinstance(item, dict)
            and isinstance(item.get("path"), str)
            and windows_ordinal_ignore_case_equal(item["path"], entry_point)
        ]
        size_field = "size" if external else "sizeBytes"
        if len(entry_items) != 1 or entry_items[0].get(size_field, 0) < 1:
            errors.append("portable entry point is not a unique non-empty file")
    forbidden_sidecars = {
        "portable-manifest.json",
        "sha256sums",
        "sbom.cdx.json",
        "licenses/sbom.cdx.json",
    }
    if any(
        windows_ordinal_ignore_case_equal(path, sidecar)
        for path in normalized
        for sidecar in forbidden_sidecars
    ):
        errors.append("portable inventory contains a forbidden sidecar")
    if any(
        windows_ordinal_ignore_case_equal(path, "data")
        or (
            len(path) >= 5
            and windows_ordinal_ignore_case_equal(path[:5], "data/")
        )
        for path in normalized
    ):
        errors.append("portable payload inventory contains mutable data")
    if boundary == "end-user-complete":
        documentation = manifest.get("documentationFiles", [])
        source_paths = [
            item.get("sourcePath")
            for item in documentation
            if isinstance(item, dict) and isinstance(item.get("sourcePath"), str)
        ]
        archive_paths = [
            item.get("archivePath")
            for item in documentation
            if isinstance(item, dict) and isinstance(item.get("archivePath"), str)
        ]
        if any(not is_safe_relative_path(path) for path in source_paths + archive_paths):
            errors.append("documentation mapping contains an unsafe relative path")
        if duplicate_windows_paths(source_paths):
            errors.append("documentation source mapping is not unique")
        if duplicate_windows_paths(archive_paths):
            errors.append("documentation archive mapping is not unique")
        if manifest.get("documentationFileCount") != len(documentation):
            errors.append("documentation file count does not match the mapping")
        payload_size = sum(
            item.get("size", 0)
            for item in documentation
            if isinstance(item, dict) and isinstance(item.get("size"), int)
        )
        if manifest.get("documentationPayloadSize") != payload_size:
            errors.append("documentation payload size does not match the mapping")
        for item in documentation:
            if not isinstance(item, dict) or not isinstance(
                item.get("archivePath"), str
            ):
                continue
            archived = next(
                (
                    file
                    for file in files
                    if isinstance(file, dict)
                    and isinstance(file.get("path"), str)
                    and windows_ordinal_ignore_case_equal(
                        file["path"], item["archivePath"]
                    )
                ),
                None,
            )
            if (
                archived is None
                or archived.get("size") != item.get("size")
                or archived.get("sha256") != item.get("sha256")
            ):
                errors.append(
                    "documentation mapping is not byte-identical to the archive inventory"
                )
                break
        if manifest.get("oldRuntimeInventoryDigest") != manifest.get(
            "newRuntimeInventoryDigest"
        ):
            errors.append("retained runtime/legal inventory digest drifted")
        selected_source_fields = {
            "sourceMode",
            "sourceManifestSize",
            "sourceManifestSha256",
        }
        present_selected_source_fields = selected_source_fields & set(manifest)
        if present_selected_source_fields:
            if present_selected_source_fields != selected_source_fields:
                errors.append("selected-source binding is partial")
            elif manifest.get("sourceMode") != "fresh-exact-head":
                errors.append("selected-source mode is not fresh-exact-head")
            else:
                removed_source_manifests = [
                    item
                    for item in manifest.get("removedFiles", [])
                    if isinstance(item, dict)
                    and item.get("path") == "portable-manifest.json"
                ]
                if len(removed_source_manifests) != 1 or any(
                    removed_source_manifests[0].get(field)
                    != manifest.get(f"sourceManifest{field.capitalize()}")
                    for field in ("size", "sha256")
                ):
                    errors.append(
                        "selected-source binding differs from removed portable manifest"
                    )
        source_inputs = manifest.get("sourceInputs")
        if isinstance(source_inputs, dict):
            for field, prefix in (
                ("birdsgoneTrackedFiles", "birdsgone/"),
                ("preparedAgentFiles", ""),
                ("maaInventoriedFiles", "maafw/"),
            ):
                source_paths = source_inputs.get(field)
                if not isinstance(source_paths, list) or not source_paths or not all(
                    isinstance(item, str) for item in source_paths
                ):
                    continue
                if duplicate_windows_paths(source_paths):
                    errors.append(
                        f"{field} contains colliding Windows relative paths"
                    )
                for source_path in source_paths:
                    archive_path = prefix + normalized_archive_path(source_path)
                    if not any(
                        windows_ordinal_ignore_case_equal(archive_path, path)
                        for path in string_paths
                    ):
                        errors.append(
                            f"{field} path is absent from the archive inventory"
                        )
        agent = manifest.get("maa", {}).get("agent", {})
        if isinstance(agent, dict) and {
            "inventorySize",
            "executableSize",
        }.issubset(agent):
            for path_field, size_field, sha_field in (
                ("inventoryPath", "inventorySize", "inventorySha256"),
                ("executablePath", "executableSize", "executableSha256"),
            ):
                agent_file = next(
                    (
                        item
                        for item in files
                        if isinstance(item, dict)
                        and isinstance(item.get("path"), str)
                        and windows_ordinal_ignore_case_equal(
                            item["path"], agent.get(path_field)
                        )
                    ),
                    None,
                )
                if (
                    agent_file is None
                    or agent_file.get("size") != agent.get(size_field)
                    or agent_file.get("sha256") != agent.get(sha_field)
                ):
                    errors.append(
                        f"agent {path_field} identity differs from archive inventory"
                    )
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
    if duplicate_windows_paths(string_paths):
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
    unsafe_bound_paths = [
        path
        for path in iter_bound_relative_paths(profile)
        if not is_safe_relative_path(path)
    ]
    if unsafe_bound_paths:
        errors.append(f"profile contains unsafe bound relative paths: {unsafe_bound_paths!r}")
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
        if portable_artifact.get(
            "portableManifestSource"
        ) == "externalProfileRelative" and not is_safe_relative_path(
            portable_artifact.get("portableManifestRelativePath")
        ):
            errors.append("external portable manifest path is not profile-relative safe")
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


def validate_external_ui_bindings(
    profile: dict[str, Any], manifest: dict[str, Any]
) -> list[str]:
    errors: list[str] = []
    ui_required = any(
        step.get("type") in UI_STEP_TYPES
        for step in [
            *profile.get("steps", []),
            *profile.get("cleanupSteps", []),
        ]
    )
    if not ui_required:
        return errors

    webview = manifest.get("webView2")
    if not isinstance(webview, dict):
        errors.append("PORTABLE_UI_COMPONENT_REQUIRED")
        return errors

    driver = profile.get("webDriver")
    if not isinstance(driver, dict):
        errors.append("PORTABLE_UI_DRIVER_REQUIRED")
        return errors
    browser_version = driver.get("browserVersion")
    driver_version = driver.get("driverVersion")
    manifest_version = webview.get("version")
    if (
        browser_version != manifest_version
        or str(driver_version).split(".")[:3]
        != str(manifest_version).split(".")[:3]
    ):
        errors.append("WEBDRIVER_VERSION_MISMATCH")
    return errors


def validate_external_portable_bindings(
    profile: dict[str, Any], manifest: dict[str, Any]
) -> list[str]:
    errors: list[str] = []
    artifact = profile.get("artifact", {})
    if (
        profile.get("workflowKind") != "portableAutomation"
        or manifest.get("distributionBoundary") != "end-user-complete"
    ):
        errors.append("EXTERNAL_PORTABLE_BRANCH_REQUIRED")
        return errors
    if (
        artifact.get("fileNamePattern") != manifest.get("fileName")
        or artifact.get("sizeBytes") != manifest.get("newZipSize")
        or artifact.get("sha256") != manifest.get("newZipSha256")
    ):
        errors.append("PORTABLE_ARTIFACT_IDENTITY_MISMATCH")
    manifest_path = artifact.get("portableManifestRelativePath")
    if isinstance(manifest_path, str) and any(
        windows_ordinal_ignore_case_equal(
            str(fixture.get("sourceRelativePath", "")), manifest_path
        )
        for fixture in profile.get("fixtures", [])
        if isinstance(fixture, dict)
    ):
        errors.append("PORTABLE_MANIFEST_FIXTURE_PATH_COLLISION")

    launch_steps = [
        step
        for step in profile.get("steps", [])
        if step.get("type") == "launchApplication"
    ]
    applications = {
        application.get("id"): application
        for application in profile.get("applications", [])
        if isinstance(application, dict)
    }
    if len(launch_steps) != 1:
        errors.append("PORTABLE_LAUNCH_IDENTITY_REQUIRED")
    else:
        application = applications.get(launch_steps[0].get("application"))
        if not isinstance(application, dict):
            errors.append("PORTABLE_LAUNCH_APPLICATION_UNKNOWN")
        elif (
            application.get("executableRelativePath") != manifest.get("entrypoint")
            or f"{application.get('dataDirectoryRelativePath')}/"
            != manifest.get("dataRoot")
        ):
            errors.append("PORTABLE_APPLICATION_IDENTITY_MISMATCH")

    errors.extend(validate_external_ui_bindings(profile, manifest))
    return errors


def external_manifest_inventory_identity(
    manifest: dict[str, Any],
) -> tuple[int, int, str]:
    entries = [
        (
            unicodedata.normalize("NFC", item["path"].replace("\\", "/")),
            item["size"],
            item["sha256"].lower(),
        )
        for item in manifest.get("files", [])
    ]
    entries.sort(key=lambda item: windows_ordinal_key(item[0]))
    canonical = "\n".join(
        f"{path}\t{size}\t{sha256}" for path, size, sha256 in entries
    )
    return (
        len(entries),
        sum(size for _, size, _ in entries),
        hashlib.sha256(canonical.encode("utf-8")).hexdigest(),
    )


def external_profile_fixture_set_sha256(profile: dict[str, Any]) -> str:
    identities = [
        {
            "id": fixture.get("id"),
            "sourceRelativePath": str(
                fixture.get("sourceRelativePath", "")
            ).replace("\\", "/"),
            "sizeBytes": fixture.get("sizeBytes"),
            "sha256": fixture.get("sha256"),
            "mediaType": fixture.get("mediaType"),
        }
        for fixture in profile.get("fixtures", [])
        if isinstance(fixture, dict)
    ]
    return hashlib.sha256(compact_json(identities).encode("utf-8")).hexdigest()


def external_profile_webdriver_sha256(profile: dict[str, Any]) -> str | None:
    webdriver = profile.get("webDriver")
    if not isinstance(webdriver, dict):
        return None
    return hashlib.sha256(compact_json(webdriver).encode("utf-8")).hexdigest()


def external_evidence_candidate_bindings(
    profile: dict[str, Any],
    manifest: dict[str, Any],
    profile_sha256: str,
) -> dict[str, object]:
    artifact = profile.get("artifact", {})
    inventory_count, inventory_size, inventory_sha256 = (
        external_manifest_inventory_identity(manifest)
    )
    return {
        "sourceCommit": manifest.get("packagingCommit"),
        "runtimeSourceCommit": manifest.get("runtimeSourceCommit"),
        "runtimeSourceTree": manifest.get("runtimeSourceTree"),
        "packagingCommit": manifest.get("packagingCommit"),
        "packagingTree": manifest.get("packagingTree"),
        "portableZipFileName": manifest.get("fileName"),
        "portableZipSizeBytes": manifest.get("newZipSize"),
        "portableZipSha256": manifest.get("newZipSha256"),
        "portableZipSourceSha256": manifest.get("newZipSha256"),
        "portableZipGuestSha256": manifest.get("newZipSha256"),
        "profileSha256": profile_sha256,
        "requiredDistributionBoundary": artifact.get(
            "requiredDistributionBoundary"
        ),
        "portableManifestDistributionBoundary": manifest.get(
            "distributionBoundary"
        ),
        "portableManifestSource": artifact.get("portableManifestSource"),
        "portableManifestRelativePath": artifact.get(
            "portableManifestRelativePath"
        ),
        "portableManifestSizeBytes": artifact.get("portableManifestSizeBytes"),
        "portableManifestSourceSizeBytes": artifact.get(
            "portableManifestSizeBytes"
        ),
        "portableManifestGuestSizeBytes": artifact.get(
            "portableManifestSizeBytes"
        ),
        "portableManifestSha256": artifact.get("portableManifestSha256"),
        "portableManifestSourceSha256": artifact.get("portableManifestSha256"),
        "portableManifestGuestSha256": artifact.get("portableManifestSha256"),
        "portableInventoryFileCount": inventory_count,
        "portableInventorySizeBytes": inventory_size,
        "portableInventorySha256": inventory_sha256,
        "documentationSourceCommit": manifest.get("documentationSourceCommit"),
        "documentationSourceTree": manifest.get("documentationSourceTree"),
        "documentationFileCount": manifest.get("documentationFileCount"),
        "documentationPayloadSize": manifest.get("documentationPayloadSize"),
        "documentationInventoryDigest": manifest.get(
            "documentationInventoryDigest"
        ),
        "oldRuntimeInventoryDigest": manifest.get("oldRuntimeInventoryDigest"),
        "newRuntimeInventoryDigest": manifest.get("newRuntimeInventoryDigest"),
        "fixtureSetSha256": external_profile_fixture_set_sha256(profile),
        "webDriverManifestSha256": external_profile_webdriver_sha256(profile),
    }


def validate_external_operation_bindings(
    profile: dict[str, Any],
    manifest: dict[str, Any],
    evidence: dict[str, Any],
    profile_sha256: str,
) -> list[str]:
    errors = validate_external_portable_bindings(profile, manifest)
    candidate = evidence.get("candidate", {})
    for field, expected in external_evidence_candidate_bindings(
        profile, manifest, profile_sha256
    ).items():
        if candidate.get(field) != expected:
            errors.append(f"EXTERNAL_EVIDENCE_{field}_MISMATCH")
    profile_identity = evidence.get("profile", {})
    expected_fixture_ids = [
        fixture.get("id")
        for fixture in profile.get("fixtures", [])
        if isinstance(fixture, dict)
    ]
    if profile_identity.get("id") != profile.get("id"):
        errors.append("EXTERNAL_EVIDENCE_PROFILE_ID_MISMATCH")
    if profile_identity.get("fixtureIds") != expected_fixture_ids:
        errors.append("EXTERNAL_EVIDENCE_FIXTURE_IDS_MISMATCH")
    expected_fixtures = {
        fixture.get("id"): {
            "sourceRelativePath": str(
                fixture.get("sourceRelativePath", "")
            ).replace("\\", "/"),
            "profileSizeBytes": fixture.get("sizeBytes"),
            "sourceSizeBytes": fixture.get("sizeBytes"),
            "guestSizeBytes": fixture.get("sizeBytes"),
            "profileSha256": fixture.get("sha256"),
            "sourceSha256": fixture.get("sha256"),
            "guestSha256": fixture.get("sha256"),
            "status": "passed",
        }
        for fixture in profile.get("fixtures", [])
        if isinstance(fixture, dict)
    }
    evidence_fixtures = evidence.get("fixtureIdentities", [])
    actual_fixtures = {
        fixture.get("id"): {
            "sourceRelativePath": str(
                fixture.get("sourceRelativePath", "")
            ).replace("\\", "/"),
            "profileSizeBytes": fixture.get("profileSizeBytes"),
            "sourceSizeBytes": fixture.get("sourceSizeBytes"),
            "guestSizeBytes": fixture.get("guestSizeBytes"),
            "profileSha256": fixture.get("profileSha256"),
            "sourceSha256": fixture.get("sourceSha256"),
            "guestSha256": fixture.get("guestSha256"),
            "status": fixture.get("status"),
        }
        for fixture in evidence_fixtures
        if isinstance(fixture, dict)
    }
    if (
        len(expected_fixtures) != len(profile.get("fixtures", []))
        or len(actual_fixtures) != len(evidence_fixtures)
        or actual_fixtures != expected_fixtures
    ):
        errors.append("EXTERNAL_EVIDENCE_FIXTURE_IDENTITIES_MISMATCH")
    automation = evidence.get("automation", {})
    if automation.get("entrypoint") != manifest.get("entrypoint"):
        errors.append("EXTERNAL_EVIDENCE_ENTRYPOINT_MISMATCH")
    ui_required = any(
        step.get("type") in UI_STEP_TYPES
        for step in [
            *profile.get("steps", []),
            *profile.get("cleanupSteps", []),
        ]
    )
    if automation.get("uiRequired") is not ui_required:
        errors.append("EXTERNAL_EVIDENCE_UI_REQUIREMENT_MISMATCH")
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
    unsafe_bound_paths = [
        path
        for path in iter_bound_relative_paths(evidence)
        if not is_safe_relative_path(path)
    ]
    if unsafe_bound_paths:
        errors.append(f"evidence contains unsafe bound relative paths: {unsafe_bound_paths!r}")
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
    external = evidence.get("evidenceKind") == "externalPortable"
    candidate = evidence.get("candidate", {})
    automation = evidence.get("automation", {})
    required_roles = {"portableZip", "portableManifest", "deployedPayload"}
    if not external or automation.get("uiRequired") is True:
        required_roles.update({"webDriverArchive", "webDriverExecutable"})
    fixture_identities = evidence.get("fixtureIdentities", [])
    expected_fixture_ids = (
        evidence.get("profile", {}).get("fixtureIds", []) if external else []
    )
    expected_fixture_count = (
        len(expected_fixture_ids) if external else max(1, roles.count("fixture"))
    )
    if any(roles.count(role) != 1 for role in required_roles) or roles.count(
        "fixture"
    ) != expected_fixture_count:
        errors.append("portable evidence is missing required artifact roles")
        machine_facts_passed = False
    if external:
        portable_zip_name = candidate.get("portableZipFileName")
        if (
            not is_safe_relative_path(portable_zip_name)
            or "\\" in portable_zip_name
            or "/" in portable_zip_name
        ):
            errors.append("external evidence requires one exact safe ZIP file name")
            machine_facts_passed = False
        fixture_identity_ids = [
            fixture.get("id") for fixture in fixture_identities
        ]
        fixture_artifact_ids = [
            artifact.get("id")
            for artifact in artifacts
            if artifact.get("role") == "fixture"
        ]
        if (
            len(expected_fixture_ids) != len(set(expected_fixture_ids))
            or len(fixture_identity_ids) != len(set(fixture_identity_ids))
            or len(fixture_artifact_ids) != len(set(fixture_artifact_ids))
            or set(fixture_identity_ids) != set(expected_fixture_ids)
            or set(fixture_artifact_ids) != set(expected_fixture_ids)
        ):
            errors.append(
                "external fixture identities do not match the candidate expected set"
            )
            machine_facts_passed = False
    for artifact in artifacts:
        if artifact.get("status") != "passed":
            machine_facts_passed = False
        if artifact.get("sourceSha256") != artifact.get("guestSha256"):
            errors.append(f"artifact role {artifact.get('role')!r} has hash drift")
            machine_facts_passed = False

    vm = evidence.get("vm", {})
    guest = evidence.get("guest", {})
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

    if evidence.get("profile", {}).get("sha256") != candidate.get("profileSha256"):
        errors.append("profile hash is not bound to the candidate")
        machine_facts_passed = False
    if automation.get("webDriverManifestSha256") != candidate.get(
        "webDriverManifestSha256"
    ):
        errors.append("WebDriver manifest hash is not bound to the candidate")
        machine_facts_passed = False
    browser_version = automation.get("fixedWebView2Version")
    driver_version = automation.get("webDriverVersion")
    if external:
        if automation.get("uiRequired") is True:
            browser_segments = str(browser_version).split(".")
            driver_segments = str(driver_version).split(".")
            if (
                len(browser_segments) != 4
                or len(driver_segments) != 4
                or browser_segments[:3] != driver_segments[:3]
            ):
                errors.append(
                    "fixed WebView2 and WebDriver first three segments do not match"
                )
                machine_facts_passed = False
        elif any(
            value is not None
            for value in (
                automation.get("webDriverManifestSha256"),
                browser_version,
                driver_version,
            )
        ):
            errors.append("non-UI external evidence contains WebDriver identity")
            machine_facts_passed = False
    elif browser_version != driver_version:
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
    if external:
        if len(portable_artifacts) == 1 and (
            portable_artifacts[0].get("fileName")
            != candidate.get("portableZipFileName")
            or portable_artifacts[0].get("sizeBytes")
            != candidate.get("portableZipSizeBytes")
            or portable_artifacts[0].get("sourceSha256")
            != candidate.get("portableZipSourceSha256")
            or portable_artifacts[0].get("guestSha256")
            != candidate.get("portableZipGuestSha256")
        ):
            errors.append("external portable ZIP artifact is not bound to the candidate")
            machine_facts_passed = False
        if (
            candidate.get("requiredDistributionBoundary") != "end-user-complete"
            or candidate.get("portableManifestDistributionBoundary")
            != "end-user-complete"
        ):
            errors.append("external evidence does not bind end-user-complete")
            machine_facts_passed = False
        if candidate.get("oldRuntimeInventoryDigest") != candidate.get(
            "newRuntimeInventoryDigest"
        ):
            errors.append("external evidence records runtime/legal inventory drift")
            machine_facts_passed = False
        zip_hashes = {
            candidate.get("portableZipSha256"),
            candidate.get("portableZipSourceSha256"),
            candidate.get("portableZipGuestSha256"),
        }
        manifest_hashes = {
            candidate.get("portableManifestSha256"),
            candidate.get("portableManifestSourceSha256"),
            candidate.get("portableManifestGuestSha256"),
        }
        manifest_sizes = {
            candidate.get("portableManifestSizeBytes"),
            candidate.get("portableManifestSourceSizeBytes"),
            candidate.get("portableManifestGuestSizeBytes"),
        }
        if len(zip_hashes) != 1:
            errors.append("external portable ZIP identities do not agree")
            machine_facts_passed = False
        if len(manifest_hashes) != 1 or len(manifest_sizes) != 1:
            errors.append("external portable manifest identities do not agree")
            machine_facts_passed = False
        manifest_artifacts = [
            item for item in artifacts if item.get("role") == "portableManifest"
        ]
        if len(manifest_artifacts) == 1 and (
            manifest_artifacts[0].get("fileName")
            != candidate.get("portableManifestRelativePath")
            or manifest_artifacts[0].get("sizeBytes")
            != candidate.get("portableManifestSizeBytes")
            or manifest_artifacts[0].get("sourceSha256")
            != candidate.get("portableManifestSourceSha256")
            or manifest_artifacts[0].get("guestSha256")
            != candidate.get("portableManifestGuestSha256")
        ):
            errors.append("external manifest artifact is not bound to the candidate")
            machine_facts_passed = False
        deployed_artifacts = [
            item for item in artifacts if item.get("role") == "deployedPayload"
        ]
        if len(deployed_artifacts) == 1 and (
            deployed_artifacts[0].get("sourceSha256")
            != candidate.get("portableInventorySha256")
            or deployed_artifacts[0].get("guestSha256")
            != candidate.get("portableInventorySha256")
        ):
            errors.append(
                "external deployed payload is not bound to the candidate inventory"
            )
            machine_facts_passed = False
        fixture_artifacts = {
            item.get("id"): item
            for item in artifacts
            if item.get("role") == "fixture"
        }
        for fixture in fixture_identities:
            artifact = fixture_artifacts.get(fixture.get("id"))
            if (
                not isinstance(artifact, dict)
                or fixture.get("status") != "passed"
                or len(
                    {
                        fixture.get("profileSha256"),
                        fixture.get("sourceSha256"),
                        fixture.get("guestSha256"),
                    }
                )
                != 1
                or len(
                    {
                        fixture.get("profileSizeBytes"),
                        fixture.get("sourceSizeBytes"),
                        fixture.get("guestSizeBytes"),
                    }
                )
                != 1
                or artifact.get("sizeBytes") != fixture.get("sourceSizeBytes")
                or artifact.get("sourceSha256") != fixture.get("sourceSha256")
                or artifact.get("guestSha256") != fixture.get("guestSha256")
            ):
                errors.append(
                    f"external fixture identity is incomplete: {fixture.get('id')!r}"
                )
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
        if canonical_json(attestation.get("candidate", {})) != canonical_json(candidate):
            errors.append("manual attestation is not bound to the complete candidate")
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
    if catalog.get("targetPluginVersion") != "0.3.0":
        raise AssertionError("tool catalog target plugin version must be 0.3.0")
    if catalog.get("currentRuntimeVersion") != "0.4.1":
        raise AssertionError("the executable list-repair runtime must be 0.4.1")
    if catalog.get("consumerContract") != "contracts/v2/consumer-contract.json":
        raise AssertionError("tool catalog does not bind the P3.1 consumer contract")
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
        r"0\.4\.1(?:\+codex\.[a-z0-9]+(?:-[a-z0-9]+)*)?",
        str(manifest["version"]),
    ):
        raise AssertionError(
            "the integrated manifest must expose base 0.4.1 with at most "
            "one Codex cachebuster"
        )


def assert_v1_compatibility(catalog: dict[str, Any]) -> tuple[int, int]:
    compatibility = load_json(CONTRACT_ROOT / "compatibility.json")
    if (
        compatibility.get("targetPluginVersion") != "0.3.0"
        or compatibility.get("currentRuntimeVersion") != "0.4.1"
    ):
        raise AssertionError("target/runtime compatibility versions drifted")
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
    runtime_schema_hashes = compatibility.get("schemaV2RuntimeSha256", {})
    if set(runtime_schema_hashes) != EXPECTED_V2_SCHEMAS:
        raise AssertionError("runtime schema-v2 hash inventory is incomplete")
    runtime_schema_root = REPO_ROOT / "hyperv-clean-room" / "schemas" / "v2"
    for name, expected_hash in runtime_schema_hashes.items():
        if sha256_file(runtime_schema_root / name) != expected_hash:
            raise AssertionError(f"runtime schema-v2 copy drifted during P3.1: {name}")
    copy_policy = compatibility.get("schemaV2CopyPolicy", {})
    if copy_policy != {
        "authoritativePath": "contracts/v2/schemas",
        "installedCopyPath": "hyperv-clean-room/schemas/v2",
        "targetAheadOfRuntime": (
            "installed copies must match schemaV2RuntimeSha256"
        ),
        "targetEqualsRuntime": (
            "installed copies must be byte-identical to authoritative schemas"
        ),
    }:
        raise AssertionError("schema-v2 installed-copy policy is not explicit")

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


def assert_p3_1_contract(
    schemas: dict[str, dict[str, Any]],
    registry: Registry,
) -> tuple[int, int, int, bool]:
    consumer = load_json(CONTRACT_ROOT / "consumer-contract.json")
    source = consumer.get("source", {})
    if (
        consumer.get("contractVersion") != 4
        or consumer.get("gate") != "G7/P3.1"
        or consumer.get("targetPluginVersion") != "0.3.0"
        or consumer.get("currentRuntimeVersion") != "0.2.0"
        or source
        != {
            "repository": "rogue-shadowdancer/birdsgone",
            "protectedBranch": "main",
            "commit": "5eba3c60e4b95fa461a39adb9d9c1dfb066ce15c",
            "tree": "dbe98a0b0621353ed09cebff79d7cde64145881d",
            "path": "docs/gates/hyperv-clean-room-0.3-contract.md",
            "blob": "e2202a8de07cc90d6b31389853437e9fa025843a",
            "sizeBytes": 37610,
            "sha256": (
                "489555e9bb0365160fb61aa4964e8264"
                "05afadcec6345220178d65fc45d9102b"
            ),
            "pullRequest": 21,
            "candidateCommit": "4ea9de2627f52a47506416b8f71da1932081a184",
            "mergeCommit": "f3f54181769a6187eb9d584fbd2599561319d8f9",
        }
    ):
        raise AssertionError("P3.1 immutable consumer-contract provenance drifted")
    distribution_contract = consumer.get("distributionContract", {})
    if (
        distribution_contract
        != {
            "path": "docs/release/end-user-distribution-contract.json",
            "blob": "65f6559b5275a5f7bb26d66caaf67c6968749980",
            "sizeBytes": 14330,
            "sha256": (
                "dcb70fbf91155d4db25813458043d302"
                "55c2189ce8d8861a49fb05b0105f1bcb"
            ),
        }
    ):
        raise AssertionError("P3.1 end-user distribution authority drifted")
    amendment = consumer.get("endUserCompletenessAmendment", {})
    if (
        amendment.get("protectedCoverage") != "frozen"
        or amendment.get("distributionBoundary") != "end-user-complete"
        or amendment.get("documentationFileCount") != 62
        or amendment.get("documentationPayloadSize") != 1371442
        or amendment.get("documentationInventoryDigest")
        != "dbd8e7fcc1b8222ccc53a94c8ce9a320e766650e05da5a50e3cdbc81499769fc"
        or amendment.get("nonDeveloperPrerequisiteCount") != 14
        or amendment.get("manualReleaseAssetCount") != 4
        or amendment.get("legacyBoundaryPolicy") != "historicalOnlyFailClosed"
        or amendment.get("disposition") != "consumedFromProtectedBirdsgoneMain"
    ):
        raise AssertionError("P3.1 end-user completeness amendment is incomplete")
    expected_root_mappings = [
        {"sourcePath": path, "archivePath": path}
        for path in (
            "README.md",
            "CONTRIBUTING.md",
            "LICENSE",
            "NOTICE",
            "THIRD_PARTY_NOTICES",
            "UPSTREAM.md",
        )
    ]
    required_manual_paths = {
        "docs/user/README.md",
        "docs/user/quick-start.md",
        "docs/user/install-and-first-run.md",
        "docs/user/projects-snapshots-and-recovery.md",
        "docs/user/import-and-recognition.md",
        "docs/user/ocr-review.md",
        "docs/user/members-and-conflicts.md",
        "docs/user/monthly-report-and-excel.md",
        "docs/user/models-and-ocr-backends.md",
        "docs/user/mxu-general-features.md",
        "docs/user/settings-webui-and-security.md",
        "docs/user/troubleshooting-and-data.md",
    }
    declared_manual_paths = {
        path
        for group in amendment.get("requiredUserDocumentation", [])
        for path in group.get("paths", [])
    }
    prerequisite_ids = {
        item.get("id") for item in amendment.get("nonDeveloperPrerequisites", [])
    }
    expected_prerequisite_ids = {
        "windows-11-x64",
        "ordinary-user-writable-extraction-directory",
        "four-asset-integrity-verification",
        "unsigned-smartscreen-decision",
        "bundled-fixed-webview2",
        "portable-data-space-and-whole-directory-backup",
        "explicit-ocr-backend-selection",
        "maa-ocr-model-download",
        "windows-chinese-ocr-language-capability",
        "synthetic-first-run-verification",
        "xlsx-viewer-for-independent-output-inspection",
        "core-workflow-needs-no-adb-win32-lan-or-developer-tools",
        "privacy-reviewed-diagnostics",
        "application-mediated-recovery",
    }
    if (
        amendment.get("rootMappings") != expected_root_mappings
        or declared_manual_paths != required_manual_paths
        or prerequisite_ids != expected_prerequisite_ids
        or len(amendment.get("nonDeveloperPrerequisites", [])) != 14
        or any(
            not item.get("stages")
            or not item.get("applicability")
            or not item.get("documentationPaths")
            or not item.get("requirement")
            for item in amendment.get("nonDeveloperPrerequisites", [])
        )
    ):
        raise AssertionError("P3.1 complete documentation/prerequisite inventory drifted")
    packaging = consumer.get("upstreamPackagingResult", {})
    expected_assets = [
        {
            "name": "Birdsgone_0.1.0_windows-x64-portable.zip",
            "sizeBytes": 344467332,
            "sha256": (
                "4f1028a6ce1dd15b13cc1583dbac1f7c"
                "b0ff0b4da6993eeb9f8c1ab0016b4f66"
            ),
        },
        {
            "name": "portable-manifest.json",
            "sizeBytes": 141840,
            "sha256": (
                "0f141d12bcfe92a9017a3e19e905214c"
                "0e4d9f9c19e0ae485909984fb654f886"
            ),
        },
        {
            "name": "SBOM.cdx.json",
            "sizeBytes": 445475,
            "sha256": (
                "aee22775cf2e5bd7902222e4cf3ed6c4"
                "7b6c3673d88e378e176ea7cb82848e71"
            ),
        },
        {
            "name": "SHA256SUMS",
            "sizeBytes": 276,
            "sha256": (
                "91dd656b357488f55c33c0e6952f04dd"
                "3267a1c62eb747b320d527b9019d3561"
            ),
        },
    ]
    if (
        packaging.get("gate") != "G6.2"
        or packaging.get("pullRequest") != 22
        or packaging.get("candidateCommit")
        != "1b616aab0c996ae643a254df352ae9216d919c25"
        or packaging.get("protectedCommit")
        != "5eba3c60e4b95fa461a39adb9d9c1dfb066ce15c"
        or packaging.get("protectedTree")
        != "dbe98a0b0621353ed09cebff79d7cde64145881d"
        or packaging.get("assetCount") != 4
        or packaging.get("assets") != expected_assets
        or packaging.get("verifierLaunches") != 2
        or packaging.get("systemUnchanged") is not True
        or packaging.get("installSideEffects") != 0
        or packaging.get("residualOwnedProcesses") != 0
        or packaging.get("hyperVOrGuestEvidence") != "notPerformed"
    ):
        raise AssertionError("P3.1 upstream G6.2 result drifted")
    boundary = consumer.get("p3_1Boundary", {})
    if set(boundary.values()) != {"notPerformed"} or set(boundary) != {
        "runtimeImplementation",
        "package",
        "release",
        "installation",
        "hyperVMutation",
        "guestOperation",
    }:
        raise AssertionError("P3.1 claims work outside its schema/fixture boundary")

    positive = {
        "portable-manifest.external-neutral.valid.json": (
            "portable-manifest.schema.json"
        ),
        "portable-manifest.external-birdsgone-shape.valid.json": (
            "portable-manifest.schema.json"
        ),
        "portable-manifest.external-test2-provenance.valid.json": (
            "portable-manifest.schema.json"
        ),
        "portable-manifest.external-legacy-historical.valid.json": (
            "portable-manifest.schema.json"
        ),
        "test-profile.external-neutral.valid.json": "test-profile.schema.json",
        "test-profile.external-ui.valid.json": "test-profile.schema.json",
        "evidence.external-neutral.valid.json": "evidence.schema.json",
    }
    negative = {
        "portable-manifest.external-unknown-field.invalid.json": (
            "portable-manifest.schema.json"
        ),
        "portable-manifest.external-end-user-missing-docs.invalid.json": (
            "portable-manifest.schema.json"
        ),
        "test-profile.external-both-branches.invalid.json": (
            "test-profile.schema.json"
        ),
        "test-profile.external-ui-missing-driver.invalid.json": (
            "test-profile.schema.json"
        ),
        "test-profile.external-legacy-boundary.invalid.json": (
            "test-profile.schema.json"
        ),
    }
    for name, schema_name in positive.items():
        instance = load_json(P3_1_FIXTURE_ROOT / name)
        errors = list(validator_for(schema_name, schemas, registry).iter_errors(instance))
        if errors:
            raise AssertionError(
                f"P3.1 positive fixture rejected: {name}: {errors[0].message}"
            )
        semantic = semantic_errors(name.split(".", 1)[0], instance)
        if semantic:
            raise AssertionError(
                f"P3.1 positive fixture failed semantics: {name}: {semantic[0]}"
            )
    for name, schema_name in negative.items():
        instance = load_json(P3_1_FIXTURE_ROOT / name)
        if not list(validator_for(schema_name, schemas, registry).iter_errors(instance)):
            raise AssertionError(f"P3.1 negative fixture accepted: {name}")

    neutral_manifest = load_json(
        P3_1_FIXTURE_ROOT / "portable-manifest.external-neutral.valid.json"
    )
    neutral_profile = load_json(
        P3_1_FIXTURE_ROOT / "test-profile.external-neutral.valid.json"
    )
    neutral_profile_sha256 = sha256_file(
        P3_1_FIXTURE_ROOT / "test-profile.external-neutral.valid.json"
    )
    neutral_evidence = load_json(
        P3_1_FIXTURE_ROOT / "evidence.external-neutral.valid.json"
    )
    ui_manifest = load_json(
        P3_1_FIXTURE_ROOT / "portable-manifest.external-birdsgone-shape.valid.json"
    )
    ui_profile = load_json(
        P3_1_FIXTURE_ROOT / "test-profile.external-ui.valid.json"
    )
    ui_profile_sha256 = sha256_file(
        P3_1_FIXTURE_ROOT / "test-profile.external-ui.valid.json"
    )
    test2_manifest = load_json(
        P3_1_FIXTURE_ROOT / "portable-manifest.external-test2-provenance.valid.json"
    )
    portable_validator = validator_for(
        "portable-manifest.schema.json", schemas, registry
    )
    if validate_portable_manifest_semantics(test2_manifest):
        raise AssertionError("exact Test2 provenance fixture failed semantic validation")
    test2_schema_probes = {}
    partial_source = deepcopy(test2_manifest)
    del partial_source["sourceManifestSha256"]
    test2_schema_probes["partial selected-source binding"] = partial_source
    wrong_source_mode = deepcopy(test2_manifest)
    wrong_source_mode["sourceMode"] = "frozen-g4.2-baseline"
    test2_schema_probes["unsupported selected-source mode"] = wrong_source_mode
    wrong_case_source_mode = deepcopy(test2_manifest)
    wrong_case_source_mode["SourceMode"] = wrong_case_source_mode.pop("sourceMode")
    test2_schema_probes["incorrectly cased selected-source field"] = (
        wrong_case_source_mode
    )
    mixed_source_inventory = deepcopy(test2_manifest)
    mixed_source_inventory["sourceInputs"]["preparedAgentFiles"].append(
        {"path": "extra.exe", "size": 1, "sha256": "a" * 64}
    )
    test2_schema_probes["mixed source-input inventory"] = mixed_source_inventory
    partial_agent_size = deepcopy(test2_manifest)
    del partial_agent_size["maa"]["agent"]["executableSize"]
    test2_schema_probes["partial Agent size binding"] = partial_agent_size
    for label, probe in test2_schema_probes.items():
        if not list(portable_validator.iter_errors(probe)):
            raise AssertionError(f"portable schema accepted {label}")
    removed_source_mismatch = deepcopy(test2_manifest)
    removed_source_mismatch["removedFiles"][0]["size"] += 1
    if not validate_portable_manifest_semantics(removed_source_mismatch):
        raise AssertionError("selected-source removed-file mismatch was accepted")
    source_input_mismatch = deepcopy(test2_manifest)
    source_input_mismatch["sourceInputs"]["birdsgoneTrackedFiles"][0] = (
        "missing.json"
    )
    if not validate_portable_manifest_semantics(source_input_mismatch):
        raise AssertionError("unbound source-input path was accepted")
    source_input_separator_collision = deepcopy(test2_manifest)
    source_input_separator_collision["sourceInputs"]["birdsgoneTrackedFiles"] = [
        "resource/interface.json",
        "resource\\interface.json",
    ]
    if not validate_portable_manifest_semantics(source_input_separator_collision):
        raise AssertionError("separator-alias source-input collision was accepted")
    agent_size_mismatch = deepcopy(test2_manifest)
    agent_size_mismatch["maa"]["agent"]["inventorySize"] += 1
    if not validate_portable_manifest_semantics(agent_size_mismatch):
        raise AssertionError("Agent size drift from the archive inventory was accepted")
    embedded_manifest = load_json(FIXTURE_ROOT / "portable-manifest.valid.json")
    embedded_build_metadata = deepcopy(embedded_manifest)
    embedded_build_metadata["productVersion"] = "1.2.3+build"
    if not list(portable_validator.iter_errors(embedded_build_metadata)):
        raise AssertionError(
            "embedded portable manifest accepted newly introduced build metadata"
        )
    embedded_long_prerelease = deepcopy(embedded_manifest)
    embedded_long_prerelease["productVersion"] = f"1.2.3-{'a' * 200}"
    if list(portable_validator.iter_errors(embedded_long_prerelease)):
        raise AssertionError(
            "embedded portable manifest rejected a legacy-valid long prerelease"
        )
    external_build_metadata = deepcopy(neutral_manifest)
    external_build_metadata["version"] = "1.2.3+build"
    if list(portable_validator.iter_errors(external_build_metadata)):
        raise AssertionError(
            "external portable manifest rejected bounded build metadata"
        )
    ordinal_inventory_probe = {
        "files": [
            {"path": "\ue000.txt", "size": 1, "sha256": "1" * 64},
            {"path": "\U00010000.txt", "size": 2, "sha256": "2" * 64},
        ]
    }
    if external_manifest_inventory_identity(ordinal_inventory_probe) != (
        2,
        3,
        "46608303bc9106c730e7b35e65aa99a35b387894724cc5fd940d9c60b1aeb603",
    ):
        raise AssertionError("external inventory did not use Windows ordinal order")
    manifest_fixture_collision = deepcopy(ui_profile)
    manifest_fixture_collision["artifact"][
        "portableManifestRelativePath"
    ] = "FIXTURES\\SYNTHETIC-INPUT.JSON"
    collision_errors = validate_external_portable_bindings(
        manifest_fixture_collision, ui_manifest
    )
    if "PORTABLE_MANIFEST_FIXTURE_PATH_COLLISION" not in collision_errors:
        raise AssertionError("external manifest sidecar was accepted as a fixture")
    expanding_fold_profile = deepcopy(ui_profile)
    expanding_fold_profile["artifact"][
        "portableManifestRelativePath"
    ] = "STRASSE.json"
    expanding_fold_profile["fixtures"][0][
        "sourceRelativePath"
    ] = "straße.json"
    expanding_fold_errors = validate_external_portable_bindings(
        expanding_fold_profile, ui_manifest
    )
    if "PORTABLE_MANIFEST_FIXTURE_PATH_COLLISION" in expanding_fold_errors:
        raise AssertionError(
            "Windows-distinct expanding Unicode case folds were treated as equal"
        )
    unicode_case_profile = deepcopy(ui_profile)
    unicode_case_profile["artifact"][
        "portableManifestRelativePath"
    ] = "FIXTURES/Å.JSON"
    unicode_case_profile["fixtures"][0][
        "sourceRelativePath"
    ] = "fixtures/å.json"
    unicode_case_errors = validate_external_portable_bindings(
        unicode_case_profile, ui_manifest
    )
    if "PORTABLE_MANIFEST_FIXTURE_PATH_COLLISION" not in unicode_case_errors:
        raise AssertionError(
            "Windows-equal non-ASCII fixture/manifest paths did not collide"
        )
    for schema_name in (
        "portable-manifest.schema.json",
        "test-profile.schema.json",
        "evidence.schema.json",
    ):
        scalar_fields, array_fields = schema_bound_relative_path_fields(
            schemas[schema_name]
        )
        if not scalar_fields.issubset(
            SAFE_RELATIVE_PATH_FIELDS
        ) or not array_fields.issubset(SAFE_RELATIVE_PATH_ARRAY_FIELDS):
            raise AssertionError(
                f"{schema_name} has safeRelativePath bindings outside semantic coverage"
            )
    composed_guard_probe = {
        "$defs": {
            "safeRelativePath": {"type": "string"},
            "safePathAlias": {
                "anyOf": [
                    {"$ref": "#/$defs/safeRelativePath"},
                    {"type": "null"},
                ]
            },
        },
        "properties": {
            "composedScalar": {
                "oneOf": [
                    {
                        "allOf": [
                            {"$ref": "#/$defs/safePathAlias"},
                        ]
                    },
                    {"type": "null"},
                ]
            },
            "composedArray": {
                "type": "array",
                "items": {
                    "anyOf": [
                        {"$ref": "#/$defs/safePathAlias"},
                        {"type": "null"},
                    ]
                },
            },
        },
    }
    guard_scalar_fields, guard_array_fields = schema_bound_relative_path_fields(
        composed_guard_probe
    )
    if guard_scalar_fields != {"composedScalar"} or guard_array_fields != {
        "composedArray"
    }:
        raise AssertionError("safeRelativePath coverage guard missed a composition")
    if (
        any(name in neutral_manifest for name in ("maa", "webView2"))
        or "webDriver" in neutral_profile
        or any(
            step.get("type") in UI_STEP_TYPES
            for step in neutral_profile.get("steps", [])
        )
    ):
        raise AssertionError("neutral external fixture is not component-portable")
    for console_device_path in ("CONIN$", "CONOUT$/payload.dll"):
        console_device_manifest = deepcopy(neutral_manifest)
        console_device_manifest["files"][1]["path"] = console_device_path
        if not list(
            validator_for(
                "portable-manifest.schema.json", schemas, registry
            ).iter_errors(console_device_manifest)
        ) or not validate_portable_manifest_semantics(console_device_manifest):
            raise AssertionError(
                "external inventory accepted a Windows console device path: "
                f"{console_device_path!r}"
            )
    control_path_manifest = deepcopy(neutral_manifest)
    control_path_manifest["sbom"]["path"] = "bad\u007f.cdx.json"
    if not list(
        validator_for(
            "portable-manifest.schema.json", schemas, registry
        ).iter_errors(control_path_manifest)
    ) or not validate_portable_manifest_semantics(control_path_manifest):
        raise AssertionError("external manifest accepted a control character path")
    decomposed_path_manifest = deepcopy(neutral_manifest)
    decomposed_path_manifest["sbom"]["derivedFromPath"] = "Cafe\u0301.cdx.json"
    if not validate_portable_manifest_semantics(decomposed_path_manifest):
        raise AssertionError("external manifest accepted a non-NFC bound path")
    signed_external_probe = deepcopy(neutral_manifest)
    signed_external_probe["unsigned"] = False
    if not list(
        validator_for(
            "portable-manifest.schema.json", schemas, registry
        ).iter_errors(signed_external_probe)
    ):
        raise AssertionError("executable external manifest accepted unsigned=false")
    for provenance_field in (
        "runtimeSourceCommit",
        "runtimeSourceTree",
        "packagingCommit",
        "packagingTree",
    ):
        missing_provenance_probe = deepcopy(neutral_manifest)
        del missing_provenance_probe[provenance_field]
        if not list(
            validator_for(
                "portable-manifest.schema.json", schemas, registry
            ).iter_errors(missing_provenance_probe)
        ):
            raise AssertionError(
                "executable external manifest omitted required provenance: "
                f"{provenance_field}"
            )
    uppercase_zip_manifest = deepcopy(neutral_manifest)
    uppercase_zip_profile = deepcopy(neutral_profile)
    uppercase_zip_evidence = deepcopy(neutral_evidence)
    uppercase_zip_manifest["fileName"] = "Package.ZIP"
    uppercase_zip_profile["artifact"]["fileNamePattern"] = "Package.ZIP"
    uppercase_zip_evidence["candidate"]["portableZipFileName"] = "Package.ZIP"
    if list(
        validator_for(
            "portable-manifest.schema.json", schemas, registry
        ).iter_errors(uppercase_zip_manifest)
    ) or list(
        validator_for(
            "test-profile.schema.json", schemas, registry
        ).iter_errors(uppercase_zip_profile)
    ) or list(
        validator_for(
            "evidence.schema.json", schemas, registry
        ).iter_errors(uppercase_zip_evidence)
    ):
        raise AssertionError("safe uppercase ZIP leaf was rejected")
    decomposed_zip_leaf = "Cafe\u0301.zip"
    decomposed_zip_manifest = deepcopy(neutral_manifest)
    decomposed_zip_profile = deepcopy(neutral_profile)
    decomposed_zip_evidence = deepcopy(neutral_evidence)
    decomposed_zip_manifest["fileName"] = decomposed_zip_leaf
    decomposed_zip_profile["artifact"]["fileNamePattern"] = decomposed_zip_leaf
    decomposed_zip_evidence["candidate"]["portableZipFileName"] = decomposed_zip_leaf
    next(
        artifact
        for artifact in decomposed_zip_evidence["artifacts"]
        if artifact["role"] == "portableZip"
    )["fileName"] = decomposed_zip_leaf
    if (
        not validate_portable_manifest_semantics(decomposed_zip_manifest)
        or not validate_profile_semantics(decomposed_zip_profile)
        or not validate_evidence_semantics(decomposed_zip_evidence)
    ):
        raise AssertionError("non-NFC external ZIP leaf passed semantic validation")
    for unsafe_zip_leaf in (
        "CON.zip",
        "com1.ZIP",
        "COM¹.zip",
        "LPT².ZIP",
        "bad\u0001.zip",
        "bad\u007f.zip",
    ):
        unsafe_zip_probe = deepcopy(neutral_manifest)
        unsafe_profile_probe = deepcopy(neutral_profile)
        unsafe_evidence_probe = deepcopy(neutral_evidence)
        unsafe_zip_probe["fileName"] = unsafe_zip_leaf
        unsafe_profile_probe["artifact"]["fileNamePattern"] = unsafe_zip_leaf
        unsafe_evidence_probe["candidate"]["portableZipFileName"] = unsafe_zip_leaf
        if not list(
            validator_for(
                "portable-manifest.schema.json", schemas, registry
            ).iter_errors(unsafe_zip_probe)
        ) or not list(
            validator_for(
                "test-profile.schema.json", schemas, registry
            ).iter_errors(unsafe_profile_probe)
        ) or not list(
            validator_for(
                "evidence.schema.json", schemas, registry
            ).iter_errors(unsafe_evidence_probe)
        ):
            raise AssertionError(
                "executable external manifest/profile/evidence accepted unsafe ZIP "
                "leaf: "
                f"{unsafe_zip_leaf!r}"
            )

    if validate_external_portable_bindings(neutral_profile, neutral_manifest):
        raise AssertionError(
            "valid neutral external cross-document bindings were rejected"
        )
    if validate_external_operation_bindings(
        neutral_profile,
        neutral_manifest,
        neutral_evidence,
        neutral_profile_sha256,
    ):
        raise AssertionError(
            "valid neutral external profile/manifest/evidence bindings were rejected"
        )
    expected_evidence_bindings = external_evidence_candidate_bindings(
        neutral_profile, neutral_manifest, neutral_profile_sha256
    )
    required_external_candidate_fields = set(
        schemas["evidence.schema.json"]["$defs"]["externalCandidateIdentity"][
            "required"
        ]
    )
    if set(expected_evidence_bindings) != required_external_candidate_fields:
        missing = sorted(
            required_external_candidate_fields - set(expected_evidence_bindings)
        )
        extra = sorted(set(expected_evidence_bindings) - required_external_candidate_fields)
        raise AssertionError(
            "external evidence binding coverage drifted from the closed candidate "
            f"schema: missing={missing}, extra={extra}"
        )
    for field, expected in expected_evidence_bindings.items():
        drifted_evidence = deepcopy(neutral_evidence)
        if isinstance(expected, int):
            drifted_evidence["candidate"][field] = expected + 1
        elif isinstance(expected, str) and len(expected) in {40, 64}:
            replacement = "0" if expected[0] != "0" else "1"
            drifted_evidence["candidate"][field] = replacement * len(expected)
        else:
            drifted_evidence["candidate"][field] = f"drifted-{expected}"
        if not validate_external_operation_bindings(
            neutral_profile,
            neutral_manifest,
            drifted_evidence,
            neutral_profile_sha256,
        ):
            raise AssertionError(
                f"external evidence candidate {field} drift was accepted"
            )
    evidence_entrypoint_drift = deepcopy(neutral_evidence)
    evidence_entrypoint_drift["automation"]["entrypoint"] = "Different.exe"
    if not validate_external_operation_bindings(
        neutral_profile,
        neutral_manifest,
        evidence_entrypoint_drift,
        neutral_profile_sha256,
    ):
        raise AssertionError("external evidence entrypoint drift was accepted")
    evidence_profile_id_drift = deepcopy(neutral_evidence)
    evidence_profile_id_drift["profile"]["id"] = "different-profile"
    if not validate_external_operation_bindings(
        neutral_profile,
        neutral_manifest,
        evidence_profile_id_drift,
        neutral_profile_sha256,
    ):
        raise AssertionError("external evidence profile ID drift was accepted")
    evidence_fixture_ids_drift = deepcopy(neutral_evidence)
    evidence_fixture_ids_drift["profile"]["fixtureIds"] = ["unexpected-fixture"]
    if not validate_external_operation_bindings(
        neutral_profile,
        neutral_manifest,
        evidence_fixture_ids_drift,
        neutral_profile_sha256,
    ):
        raise AssertionError("external evidence fixture-ID drift was accepted")
    evidence_ui_requirement_drift = deepcopy(neutral_evidence)
    evidence_ui_requirement_drift["automation"]["uiRequired"] = True
    if not validate_external_operation_bindings(
        neutral_profile,
        neutral_manifest,
        evidence_ui_requirement_drift,
        neutral_profile_sha256,
    ):
        raise AssertionError("external evidence UI requirement drift was accepted")
    fixture_profile = deepcopy(neutral_profile)
    fixture_profile["fixtures"] = [
        {
            "id": "synthetic-input",
            "sourceRelativePath": "fixtures/synthetic-input.json",
            "sizeBytes": 128,
            "sha256": "3" * 64,
            "mediaType": "application/json",
        }
    ]
    fixture_profile_sha256 = "8" * 64
    fixture_evidence = deepcopy(neutral_evidence)
    fixture_evidence["profile"]["sha256"] = fixture_profile_sha256
    fixture_evidence["profile"]["fixtureIds"] = ["synthetic-input"]
    fixture_evidence["candidate"]["profileSha256"] = fixture_profile_sha256
    expected_fixture_set_sha256 = (
        "5c9c2c92ad351fa1e7cfe6677c2240ca098f0c7ce126fd8d6bce1aa23f055a2b"
    )
    if (
        external_profile_fixture_set_sha256(fixture_profile)
        != expected_fixture_set_sha256
    ):
        raise AssertionError("non-empty fixture-set canonical digest drifted")
    fixture_evidence["candidate"][
        "fixtureSetSha256"
    ] = expected_fixture_set_sha256
    fixture_evidence["fixtureIdentities"] = [
        {
            "id": "synthetic-input",
            "sourceRelativePath": "fixtures/synthetic-input.json",
            "profileSizeBytes": 128,
            "sourceSizeBytes": 128,
            "guestSizeBytes": 128,
            "profileSha256": "3" * 64,
            "sourceSha256": "3" * 64,
            "guestSha256": "3" * 64,
            "status": "passed",
        }
    ]
    if validate_external_operation_bindings(
        fixture_profile,
        neutral_manifest,
        fixture_evidence,
        fixture_profile_sha256,
    ):
        raise AssertionError("valid external fixture identity bindings were rejected")
    for field in (
        "sourceRelativePath",
        "profileSizeBytes",
        "sourceSizeBytes",
        "guestSizeBytes",
        "profileSha256",
        "sourceSha256",
        "guestSha256",
        "status",
    ):
        fixture_drift = deepcopy(fixture_evidence)
        current = fixture_drift["fixtureIdentities"][0][field]
        if isinstance(current, int):
            fixture_drift["fixtureIdentities"][0][field] = current + 1
        elif field == "status":
            fixture_drift["fixtureIdentities"][0][field] = "failed"
        elif len(current) == 64:
            fixture_drift["fixtureIdentities"][0][field] = "4" * 64
        else:
            fixture_drift["fixtureIdentities"][0][field] = "fixtures/other.json"
        if not validate_external_operation_bindings(
            fixture_profile,
            neutral_manifest,
            fixture_drift,
            fixture_profile_sha256,
        ):
            raise AssertionError(
                f"external fixture identity {field} drift was accepted"
            )
    expected_webdriver_sha256 = (
        "a1103b5cb770cf0f0f09000d4dd2a71027354104888876308201b7dc2da5a2f8"
    )
    if (
        external_profile_webdriver_sha256(ui_profile)
        != expected_webdriver_sha256
    ):
        raise AssertionError("non-null WebDriver canonical digest drifted")
    ui_candidate = external_evidence_candidate_bindings(
        ui_profile, ui_manifest, ui_profile_sha256
    )
    if ui_candidate["webDriverManifestSha256"] != expected_webdriver_sha256:
        raise AssertionError("external UI candidate did not bind the WebDriver digest")
    ui_evidence = {
        "profile": {
            "id": ui_profile["id"],
            "schemaVersion": 2,
            "sha256": ui_profile_sha256,
            "fixtureIds": ["synthetic-input"],
        },
        "candidate": ui_candidate,
        "fixtureIdentities": [
            {
                "id": "synthetic-input",
                "sourceRelativePath": "fixtures/synthetic-input.json",
                "profileSizeBytes": 128,
                "sourceSizeBytes": 128,
                "guestSizeBytes": 128,
                "profileSha256": "3" * 64,
                "sourceSha256": "3" * 64,
                "guestSha256": "3" * 64,
                "status": "passed",
            }
        ],
        "automation": {
            "entrypoint": "SyntheticConsumer.exe",
            "uiRequired": True,
        },
    }
    if validate_external_operation_bindings(
        ui_profile, ui_manifest, ui_evidence, ui_profile_sha256
    ):
        raise AssertionError("valid external UI evidence bindings were rejected")
    webdriver_drift = deepcopy(ui_evidence)
    webdriver_drift["candidate"]["webDriverManifestSha256"] = "4" * 64
    if not validate_external_operation_bindings(
        ui_profile, ui_manifest, webdriver_drift, ui_profile_sha256
    ):
        raise AssertionError("external UI WebDriver digest drift was accepted")
    cross_document_probes: dict[str, dict[str, Any]] = {}
    name_drift_profile = deepcopy(neutral_profile)
    name_drift_profile["artifact"]["fileNamePattern"] = "Different.zip"
    cross_document_probes["ZIP name"] = name_drift_profile
    size_drift_profile = deepcopy(neutral_profile)
    size_drift_profile["artifact"]["sizeBytes"] += 1
    cross_document_probes["ZIP size"] = size_drift_profile
    hash_drift_profile = deepcopy(neutral_profile)
    hash_drift_profile["artifact"]["sha256"] = "f" * 64
    cross_document_probes["ZIP hash"] = hash_drift_profile
    entrypoint_drift_profile = deepcopy(neutral_profile)
    entrypoint_drift_profile["applications"][0][
        "executableRelativePath"
    ] = "Different.exe"
    cross_document_probes["application entrypoint"] = entrypoint_drift_profile
    profile_validator = validator_for("test-profile.schema.json", schemas, registry)
    for label, drifted_profile in cross_document_probes.items():
        if list(profile_validator.iter_errors(drifted_profile)) or (
            validate_profile_semantics(drifted_profile)
        ):
            raise AssertionError(
                f"{label} cross-document probe unexpectedly failed profile validation"
            )
        if not validate_external_portable_bindings(
            drifted_profile, neutral_manifest
        ):
            raise AssertionError(f"external cross-document {label} drift was accepted")

    synthetic_manifest = load_json(
        P3_1_FIXTURE_ROOT
        / "portable-manifest.external-birdsgone-shape.valid.json"
    )
    ui_profile = load_json(
        P3_1_FIXTURE_ROOT / "test-profile.external-ui.valid.json"
    )
    if validate_external_portable_bindings(ui_profile, synthetic_manifest):
        raise AssertionError("P3.1 external UI cross-document fixture bindings drifted")

    forbidden_real_identities = {
        "96647325bf36d590a388c17e9629cae7b4efb87630e8495fcd379fe67f8cce2f",
        "078fb99f72671b1d7a0dc5a61120276dbbb12924e86507250e50c4a3e3de341f",
        "aee22775cf2e5bd7902222e4cf3ed6c47b6c3673d88e378e176ea7cb82848e71",
        "130757909f151bf0b18a84f341aa8f4c07a1541be904e243250cf9f54d3672db",
        "4f1028a6ce1dd15b13cc1583dbac1f7cb0ff0b4da6993eeb9f8c1ab0016b4f66",
        "0f141d12bcfe92a9017a3e19e905214c0e4d9f9c19e0ae485909984fb654f886",
        "91dd656b357488f55c33c0e6952f04dd3267a1c62eb747b320d527b9019d3561",
    }
    if forbidden_real_identities & set(re.findall(r"[a-f0-9]{64}", canonical_json(
        synthetic_manifest
    ))):
        raise AssertionError("synthetic consumer fixture copied a real release identity")

    evidence = load_json(
        P3_1_FIXTURE_ROOT / "evidence.external-neutral.valid.json"
    )
    drift = load_json(
        P3_1_FIXTURE_ROOT
        / "evidence.external-manifest-hash-drift.semantic-invalid.json"
    )
    drifted_evidence = deepcopy(evidence)
    path_parts = drift["mutation"]["path"].strip("/").split("/")
    target = drifted_evidence
    for part in path_parts[:-1]:
        target = target[part]
    target[path_parts[-1]] = drift["mutation"]["value"]
    if not validate_evidence_semantics(drifted_evidence):
        raise AssertionError("external evidence manifest hash drift was accepted")

    matrix = load_json(P3_1_FIXTURE_ROOT / "negative-cases.json")
    case_ids = [case.get("id") for case in matrix.get("cases", [])]
    required_case_ids = {
        "manifest-missing",
        "manifest-reparse-point",
        "manifest-path-escape",
        "manifest-utf8-bom",
        "manifest-invalid-utf8",
        "manifest-duplicate-property",
        "manifest-oversize",
        "manifest-hash-drift",
        "manifest-size-drift",
        "manifest-inserted-in-zip",
        "manifest-in-portable-data",
        "zip-undeclared-entry",
        "zip-missing-entry",
        "zip-case-collision",
        "zip-nfc-collision",
        "zip-link",
        "zip-submodule",
        "zip-reparse-point",
        "zip-alternate-data-stream",
        "zip-non-nfc-path",
        "archive-forbidden-sbom-sidecar",
        "documentation-omission",
        "documentation-extra",
        "documentation-source-drift",
        "documentation-source-tree-drift",
        "documentation-mapping-drift",
        "documentation-root-mapping-missing",
        "prerequisite-omission",
        "legacy-boundary-release-ready",
        "distribution-boundary-missing",
        "distribution-boundary-unknown",
        "distribution-boundary-case-drift",
        "distribution-branches-ambiguous",
        "optional-component-omitted",
        "ui-without-webview2",
        "ui-without-webdriver",
        "webdriver-three-segment-mismatch",
        "illegal-selector",
        "illegal-url",
        "illegal-javascript",
        "illegal-argument",
    }
    if (
        matrix.get("contractVersion") != 3
        or len(case_ids) != len(required_case_ids)
        or set(case_ids) != required_case_ids
        or len(case_ids) != len(set(case_ids))
        or consumer.get("negativeCases") != case_ids
    ):
        raise AssertionError("P3.1 negative-case matrix is incomplete or duplicated")
    if any(
        not case.get("expectedError") and case.get("expectedResult") != "valid"
        for case in matrix["cases"]
    ):
        raise AssertionError("P3.1 negative-case matrix has no deterministic outcome")
    return len(positive), len(negative), len(case_ids), True


def main() -> int:
    required_contract_files = {
        CONTRACT_ROOT / "tool-catalog.json",
        CONTRACT_ROOT / "compatibility.json",
        CONTRACT_ROOT / "consumer-contract.json",
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
        if not contains_schema_version_2(schema):
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
    (
        p3_1_valid_count,
        p3_1_schema_invalid_count,
        p3_1_negative_case_count,
        p3_1_closable,
    ) = assert_p3_1_contract(schemas, registry)

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

    cleanup_only_ui_probe = load_json(
        P3_1_FIXTURE_ROOT / "test-profile.external-neutral.valid.json"
    )
    ui_profile_probe = load_json(
        P3_1_FIXTURE_ROOT / "test-profile.external-ui.valid.json"
    )
    ui_manifest_probe = load_json(
        P3_1_FIXTURE_ROOT
        / "portable-manifest.external-birdsgone-shape.valid.json"
    )
    neutral_manifest_probe = load_json(
        P3_1_FIXTURE_ROOT / "portable-manifest.external-neutral.valid.json"
    )
    cleanup_only_ui_probe["webDriver"] = deepcopy(ui_profile_probe["webDriver"])
    cleanup_only_ui_probe["artifact"]["fileNamePattern"] = ui_manifest_probe["fileName"]
    cleanup_only_ui_probe["artifact"]["sizeBytes"] = ui_manifest_probe["newZipSize"]
    cleanup_only_ui_probe["artifact"]["sha256"] = ui_manifest_probe["newZipSha256"]
    cleanup_only_ui_probe["cleanupSteps"] = [
        {
            "id": "cleanup-ui-capture",
            "type": "captureUiScreenshot",
            "timeoutSeconds": 30,
            "evidenceName": "cleanup-ui",
        }
    ]
    cleanup_only_ui_errors = list(
        validator_for("test-profile.schema.json", schemas, registry).iter_errors(
            cleanup_only_ui_probe
        )
    )
    if (
        cleanup_only_ui_errors
        or validate_profile_semantics(cleanup_only_ui_probe)
        or validate_external_ui_bindings(cleanup_only_ui_probe, ui_manifest_probe)
    ):
        raise AssertionError(
            "external cleanup-only UI profile with fixed WebView2/WebDriver was rejected"
        )
    if validate_external_ui_bindings(
        cleanup_only_ui_probe, neutral_manifest_probe
    ) != ["PORTABLE_UI_COMPONENT_REQUIRED"]:
        raise AssertionError(
            "cleanup-only UI profile without manifest WebView2 was accepted"
        )

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

    embedded_fixture_identity_probe = deepcopy(evidence_probe)
    embedded_fixture_identity_probe["fixtureIdentities"] = []
    if not list(evidence_validator.iter_errors(embedded_fixture_identity_probe)):
        raise AssertionError("embedded evidence accepted external fixture identities")

    external_evidence_probe = load_json(
        P3_1_FIXTURE_ROOT / "evidence.external-neutral.valid.json"
    )
    external_evidence_validator = validator_for(
        "evidence.schema.json", schemas, registry
    )
    historical_external_probe = deepcopy(external_evidence_probe)
    historical_external_probe["runtime"]["pluginBaseVersion"] = "0.3.0"
    historical_external_probe["runtime"][
        "pluginBuildVersion"
    ] = "0.3.0+codex.20260729122233"
    if list(external_evidence_validator.iter_errors(historical_external_probe)):
        raise AssertionError("schema rejected immutable v0.3.0 external evidence")
    v040_external_probe = deepcopy(external_evidence_probe)
    v040_external_probe["runtime"]["pluginBaseVersion"] = "0.4.0"
    v040_external_probe["runtime"][
        "pluginBuildVersion"
    ] = "0.4.0+codex.20260731141404"
    if list(external_evidence_validator.iter_errors(v040_external_probe)):
        raise AssertionError("schema rejected immutable v0.4.0 external evidence")
    v041_external_probe = deepcopy(external_evidence_probe)
    v041_external_probe["runtime"]["pluginBaseVersion"] = "0.4.1"
    v041_external_probe["runtime"][
        "pluginBuildVersion"
    ] = "0.4.1+codex.20260804090000"
    if list(external_evidence_validator.iter_errors(v041_external_probe)):
        raise AssertionError("schema rejected the current v0.4.1 external evidence")
    mismatched_external_probe = deepcopy(historical_external_probe)
    mismatched_external_probe["runtime"][
        "pluginBuildVersion"
    ] = "0.3.1+codex.20260729184240"
    if not list(external_evidence_validator.iter_errors(mismatched_external_probe)):
        raise AssertionError(
            "schema accepted mismatched external plugin base/build versions"
        )
    v040_base_v041_build = deepcopy(v040_external_probe)
    v040_base_v041_build["runtime"][
        "pluginBuildVersion"
    ] = "0.4.1+codex.20260804090000"
    if not list(external_evidence_validator.iter_errors(v040_base_v041_build)):
        raise AssertionError("schema accepted a v0.4.0 base with a v0.4.1 build")
    v041_base_v040_build = deepcopy(v041_external_probe)
    v041_base_v040_build["runtime"][
        "pluginBuildVersion"
    ] = "0.4.0+codex.20260731141404"
    if not list(external_evidence_validator.iter_errors(v041_base_v040_build)):
        raise AssertionError("schema accepted a v0.4.1 base with a v0.4.0 build")
    zip_name_drift_probe = deepcopy(external_evidence_probe)
    zip_name_drift_probe["candidate"][
        "portableZipFileName"
    ] = "Different_1.2.3_windows-x64-portable.zip"
    if list(external_evidence_validator.iter_errors(zip_name_drift_probe)):
        raise AssertionError("ZIP-name drift probe unexpectedly failed schema validation")
    if not validate_evidence_semantics(zip_name_drift_probe):
        raise AssertionError("external evidence accepted portable ZIP name drift")

    zip_size_drift_probe = deepcopy(external_evidence_probe)
    zip_size_drift_probe["candidate"]["portableZipSizeBytes"] += 1
    if list(external_evidence_validator.iter_errors(zip_size_drift_probe)):
        raise AssertionError("ZIP-size drift probe unexpectedly failed schema validation")
    if not validate_evidence_semantics(zip_size_drift_probe):
        raise AssertionError("external evidence accepted portable ZIP size drift")

    manifest_name_drift_probe = deepcopy(external_evidence_probe)
    next(
        artifact
        for artifact in manifest_name_drift_probe["artifacts"]
        if artifact["role"] == "portableManifest"
    )["fileName"] = "Different-manifest.json"
    if list(external_evidence_validator.iter_errors(manifest_name_drift_probe)):
        raise AssertionError(
            "manifest-name drift probe unexpectedly failed schema validation"
        )
    if not validate_evidence_semantics(manifest_name_drift_probe):
        raise AssertionError("external evidence accepted portable manifest name drift")

    fixture_status_probe = deepcopy(external_evidence_probe)
    fixture_identity = {
        "id": "seed-fixture",
        "sourceRelativePath": "fixtures/seed.json",
        "profileSizeBytes": 64,
        "sourceSizeBytes": 64,
        "guestSizeBytes": 64,
        "profileSha256": "f" * 64,
        "sourceSha256": "f" * 64,
        "guestSha256": "f" * 64,
        "status": "failed",
    }
    fixture_status_probe["profile"]["fixtureIds"] = ["seed-fixture"]
    fixture_status_probe["fixtureIdentities"] = [fixture_identity]
    fixture_status_probe["artifacts"].append(
        {
            "role": "fixture",
            "id": "seed-fixture",
            "fileName": "seed.json",
            "sizeBytes": 64,
            "sourceSha256": "f" * 64,
            "guestSha256": "f" * 64,
            "status": "passed",
        }
    )
    if not list(external_evidence_validator.iter_errors(fixture_status_probe)):
        raise AssertionError(
            "machine-passed external evidence schema accepted failed fixture identity"
        )
    if not validate_evidence_semantics(fixture_status_probe):
        raise AssertionError(
            "machine-passed external evidence semantics accepted failed fixture identity"
        )

    missing_fixture_probe = deepcopy(external_evidence_probe)
    missing_fixture_probe["profile"]["fixtureIds"] = ["seed-fixture"]
    if list(external_evidence_validator.iter_errors(missing_fixture_probe)):
        raise AssertionError(
            "missing-fixture evidence probe unexpectedly failed schema validation"
        )
    if not validate_evidence_semantics(missing_fixture_probe):
        raise AssertionError(
            "external evidence accepted omission of a candidate-declared fixture"
        )

    deployed_payload_drift_probe = deepcopy(external_evidence_probe)
    deployed_payload_artifact = next(
        artifact
        for artifact in deployed_payload_drift_probe["artifacts"]
        if artifact["role"] == "deployedPayload"
    )
    deployed_payload_artifact["sourceSha256"] = "e" * 64
    deployed_payload_artifact["guestSha256"] = "e" * 64
    if list(external_evidence_validator.iter_errors(deployed_payload_drift_probe)):
        raise AssertionError(
            "deployed-payload drift probe unexpectedly failed schema validation"
        )
    if not validate_evidence_semantics(deployed_payload_drift_probe):
        raise AssertionError(
            "external evidence accepted deployed payload inventory drift"
        )

    fixture_size_probe = deepcopy(fixture_status_probe)
    fixture_size_probe["fixtureIdentities"][0]["status"] = "passed"
    fixture_size_probe["artifacts"][-1]["sizeBytes"] += 1
    if list(external_evidence_validator.iter_errors(fixture_size_probe)):
        raise AssertionError(
            "fixture-size drift probe unexpectedly failed schema validation"
        )
    if not validate_evidence_semantics(fixture_size_probe):
        raise AssertionError("external evidence accepted fixture artifact size drift")

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
                "targetPluginVersion": "0.3.0",
                "currentRuntimeVersion": "0.4.1",
                "v1ToolsPreserved": v1_tool_count,
                "v2ToolsDeclared": len(EXPECTED_TOOL_NAMES),
                "v1SchemasPreserved": v1_schema_count,
                "v2Schemas": len(schemas),
                "validFixtures": valid_count,
                "schemaInvalidFixtures": schema_invalid_count,
                "semanticInvalidFixtures": semantic_invalid_count,
                "migrationFixtures": 2,
                "dynamicCompatibilityChecks": 19,
                "p3_1ValidFixtures": p3_1_valid_count,
                "p3_1SchemaInvalidFixtures": p3_1_schema_invalid_count,
                "p3_1NegativeCases": p3_1_negative_case_count,
                "p3_1Closable": p3_1_closable,
                "realHyperVMutations": 0,
                "realGuestOperations": 0,
            },
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

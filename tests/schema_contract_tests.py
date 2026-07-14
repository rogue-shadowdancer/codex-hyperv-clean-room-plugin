from __future__ import annotations

import json
import re
from collections import Counter
from copy import deepcopy
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator, FormatChecker


REPO_ROOT = Path(__file__).resolve().parents[1]
SCHEMA_ROOT = REPO_ROOT / "hyperv-clean-room" / "schemas"
FIXTURE_ROOT = Path(__file__).resolve().parent / "fixtures" / "schemas"
EXAMPLE_PROFILE_PATH = REPO_ROOT / "examples" / "minimal-test-profile.json"

SCHEMA_BY_PREFIX = {
    "vm-plan": "vm-plan.schema.json",
    "checkpoint-plan": "checkpoint-plan.schema.json",
    "evidence": "evidence.schema.json",
    "test-profile": "test-profile.schema.json",
}

CLEANUP_TYPES = {
    "stopApplication",
    "wait",
    "assertFile",
    "assertRegistry",
    "assertProcess",
    "assertModule",
    "assertShortcut",
    "assertPort",
    "assertSentinel",
}

ACTION_TYPES = {
    "stageArtifact",
    "installPackage",
    "launchApplication",
    "stopApplication",
    "uninstallPackage",
    "writeSentinel",
    "wait",
}

COMMON_STEP_FIELDS = {"id", "type", "timeoutSeconds", "required"}
TYPE_FIELDS = {
    "stageArtifact": set(),
    "installPackage": {"application"},
    "launchApplication": {"application"},
    "stopApplication": {"application"},
    "uninstallPackage": {"application"},
    "assertFile": {"path", "expected"},
    "assertRegistry": {"registryPath", "registryName", "expected"},
    "assertProcess": {"application", "processName", "expected"},
    "assertModule": {"application", "moduleRelativePath", "expected"},
    "assertShortcut": {"path", "expected"},
    "assertPort": {"port", "expected"},
    "writeSentinel": {"sentinelId"},
    "assertSentinel": {"sentinelId", "expected"},
    "wait": set(),
}

EXPECTED_CLEANUP_TRIGGER_BY_FIXTURE = {
    "evidence.cleanup-not-triggered.valid.json": False,
    "evidence.cleanup-untriggered-performed.semantic-invalid.json": False,
    "evidence.cleanup-forged-trigger.semantic-invalid.json": False,
    "evidence.cleanup-failed-overall-passed.valid.json": True,
    "evidence.cleanup-cannot-upgrade.semantic-invalid.json": True,
}


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def schema_for_fixture(path: Path) -> Path:
    prefix = path.name.split(".", 1)[0]
    try:
        schema_name = SCHEMA_BY_PREFIX[prefix]
    except KeyError as error:
        raise AssertionError(f"fixture has no schema mapping: {path.name}") from error
    return SCHEMA_ROOT / schema_name


def duplicate_values(values: list[str]) -> list[str]:
    return sorted(value for value, count in Counter(values).items() if count > 1)


def is_safe_relative_path(value: object) -> bool:
    if not isinstance(value, str) or not value or "\x00" in value:
        return False
    normalized = value.replace("/", "\\")
    if normalized.startswith("\\") or re.match(r"^[A-Za-z]:", normalized):
        return False
    if ":" in normalized or "%" in normalized:
        return False
    return all(part != ".." for part in normalized.split("\\"))


def validate_profile_semantics(profile: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    applications = profile.get("applications", [])
    steps = profile.get("steps", [])
    cleanup_steps = profile.get("cleanupSteps", [])
    manual_assertions = profile.get("manualAssertions", [])

    application_ids = [item.get("id") for item in applications if isinstance(item, dict)]
    duplicate_application_ids = duplicate_values(
        [item for item in application_ids if isinstance(item, str)]
    )
    if duplicate_application_ids:
        errors.append(f"duplicate application ids: {duplicate_application_ids}")
    declared_applications = {
        item for item in application_ids if isinstance(item, str)
    }

    execution_ids = [
        item.get("id")
        for item in [*steps, *cleanup_steps, *manual_assertions]
        if isinstance(item, dict)
    ]
    duplicate_execution_ids = duplicate_values(
        [item for item in execution_ids if isinstance(item, str)]
    )
    if duplicate_execution_ids:
        errors.append(
            "step, cleanup step, and manual assertion ids are not globally unique: "
            f"{duplicate_execution_ids}"
        )

    stage_indexes = [
        index for index, step in enumerate(steps) if step.get("type") == "stageArtifact"
    ]
    if stage_indexes != [0]:
        errors.append("steps must contain exactly one stageArtifact and it must be first")

    cleanup_timeout = sum(
        item.get("timeoutSeconds", 0)
        for item in cleanup_steps
        if isinstance(item.get("timeoutSeconds"), int)
    )
    if cleanup_timeout > 300:
        errors.append(f"cleanup timeout budget exceeds 300 seconds: {cleanup_timeout}")

    for application in applications:
        path = application.get("executableRelativePath")
        if not is_safe_relative_path(path):
            errors.append(
                f"application {application.get('id')!r} has an unsafe executableRelativePath"
            )

    for collection_name, collection in (
        ("steps", steps),
        ("cleanupSteps", cleanup_steps),
    ):
        for index, step in enumerate(collection):
            step_type = step.get("type")
            if collection_name == "cleanupSteps" and step_type not in CLEANUP_TYPES:
                errors.append(f"cleanupSteps[{index}] has forbidden type {step_type!r}")

            allowed_fields = COMMON_STEP_FIELDS | TYPE_FIELDS.get(step_type, set())
            irrelevant_fields = sorted(set(step) - allowed_fields)
            if irrelevant_fields:
                errors.append(
                    f"{collection_name}[{index}] has fields invalid for {step_type!r}: "
                    f"{irrelevant_fields}"
                )

            application = step.get("application")
            if application is not None and application not in declared_applications:
                errors.append(
                    f"{collection_name}[{index}] references unknown application "
                    f"{application!r}"
                )

            if step_type in ACTION_TYPES and step.get("required", True) is False:
                errors.append(f"{collection_name}[{index}] makes an action optional")

            for path_field in ("path", "registryPath", "moduleRelativePath"):
                if path_field in step and not is_safe_relative_path(step[path_field]):
                    errors.append(
                        f"{collection_name}[{index}] has unsafe {path_field}"
                    )

    return errors


def derive_overall_status(evidence: dict[str, Any]) -> str:
    required_results = [
        result
        for result in [
            *evidence.get("automaticAssertions", []),
            *evidence.get("manualAssertions", []),
        ]
        if result.get("required") is True
    ]
    if any(result.get("status") == "failed" for result in required_results):
        return "failed"
    if any(
        result.get("status") in {"notPerformed", "unsupported"}
        for result in required_results
    ):
        return "incomplete"
    return "passed"


def validate_evidence_semantics(
    evidence: dict[str, Any],
    profile: dict[str, Any] | None = None,
    expected_cleanup_triggered: bool | None = None,
) -> list[str]:
    errors: list[str] = []
    expected_overall = derive_overall_status(evidence)
    if evidence.get("overallStatus") != expected_overall:
        errors.append(
            "overallStatus does not match required automatic/manual assertions: "
            f"expected {expected_overall!r}"
        )

    artifact = evidence.get("artifact", {})
    source_hash = artifact.get("sourceSha256")
    guest_hash = artifact.get("guestSha256")
    hashes_verified = (
        isinstance(source_hash, str)
        and isinstance(guest_hash, str)
        and source_hash == guest_hash
    )
    stage_assertion: dict[str, Any] | None = None
    # Bind both directions whenever a profile is available: matching hashes
    # require a passed stage result, while null or mismatched guest facts
    # require a failed stage result. Legacy schema-only fixtures whose profile
    # is not present can still validate matching hashes without synthetic
    # operation state, but never unverified hashes.
    if profile is not None:
        stage_steps = [
            step for step in profile.get("steps", []) if step.get("type") == "stageArtifact"
        ]
        if len(stage_steps) == 1:
            stage_matches = [
                assertion
                for assertion in evidence.get("automaticAssertions", [])
                if assertion.get("id") == stage_steps[0].get("id")
            ]
            if len(stage_matches) == 1:
                stage_assertion = stage_matches[0]
            else:
                errors.append("stageArtifact assertion identity is not uniquely bound")
        else:
            errors.append("bound profile lacks one stageArtifact identity")
    elif not hashes_verified:
        errors.append("unverified artifact hashes lack a bound stageArtifact identity")
    if stage_assertion is not None:
        expected_stage_status = "passed" if hashes_verified else "failed"
        if stage_assertion.get("status") != expected_stage_status:
            errors.append(
                "artifact hashes require stageArtifact status "
                f"{expected_stage_status!r}"
            )

    operation_id = evidence.get("operationId")
    profile_id = evidence.get("profileId")
    cleanup_triggered = evidence.get("cleanupTriggered")
    cleanup_results = evidence.get("cleanupResults", [])
    if (
        expected_cleanup_triggered is not None
        and cleanup_triggered is not expected_cleanup_triggered
    ):
        errors.append("cleanupTriggered does not match immutable operation state")
    cleanup_ids: list[str] = []
    for index, result in enumerate(cleanup_results):
        cleanup_step_id = result.get("cleanupStepId")
        if isinstance(cleanup_step_id, str):
            cleanup_ids.append(cleanup_step_id)
        if result.get("operationId") != operation_id:
            errors.append(f"cleanupResults[{index}] operationId is not bound")
        if result.get("profileId") != profile_id:
            errors.append(f"cleanupResults[{index}] profileId is not bound")

    duplicate_cleanup_ids = duplicate_values(cleanup_ids)
    if duplicate_cleanup_ids:
        errors.append(f"duplicate cleanup result ids: {duplicate_cleanup_ids}")
    if cleanup_triggered is False and any(
        result.get("status") != "notPerformed" for result in cleanup_results
    ):
        errors.append(
            "cleanupResults must all be notPerformed when cleanupTriggered is false"
        )

    for index, assertion in enumerate(evidence.get("manualAssertions", [])):
        attestation = assertion.get("attestation")
        if not isinstance(attestation, dict):
            continue
        if attestation.get("operationId") != operation_id:
            errors.append(f"manualAssertions[{index}] operationId is not bound")
        if attestation.get("profileId") != profile_id:
            errors.append(f"manualAssertions[{index}] profileId is not bound")
        if attestation.get("assertionId") != assertion.get("id"):
            errors.append(f"manualAssertions[{index}] assertionId is not bound")

    if profile is not None:
        if profile.get("id") != profile_id:
            errors.append("evidence profileId does not match the bound profile")
        expected_cleanup = profile.get("cleanupSteps", [])
        if len(cleanup_results) != len(expected_cleanup):
            errors.append(
                "cleanupResults must contain one ordered result per cleanupSteps entry"
            )
        for index, (result, cleanup_step) in enumerate(
            zip(cleanup_results, expected_cleanup)
        ):
            if result.get("cleanupStepId") != cleanup_step.get("id"):
                errors.append(f"cleanupResults[{index}] cleanupStepId is not bound")
            if result.get("cleanupStepType") != cleanup_step.get("type"):
                errors.append(f"cleanupResults[{index}] cleanupStepType is not bound")

    return errors


def semantic_errors_for_fixture(
    fixture_path: Path,
    instance: dict[str, Any],
    example_profile: dict[str, Any],
) -> list[str]:
    prefix = fixture_path.name.split(".", 1)[0]
    if prefix == "test-profile":
        return validate_profile_semantics(instance)
    if prefix == "evidence":
        profile = (
            example_profile
            if instance.get("profileId") == example_profile.get("id")
            else None
        )
        return validate_evidence_semantics(
            instance,
            profile,
            EXPECTED_CLEANUP_TRIGGER_BY_FIXTURE.get(fixture_path.name),
        )
    return []


def main() -> int:
    schemas = sorted(SCHEMA_ROOT.glob("*.schema.json"))
    if len(schemas) != 5:
        raise AssertionError(f"expected 5 schemas, found {len(schemas)}")
    for schema_path in schemas:
        Draft202012Validator.check_schema(load_json(schema_path))

    example_profile = load_json(EXAMPLE_PROFILE_PATH)
    profile_schema = load_json(SCHEMA_ROOT / "test-profile.schema.json")
    profile_validator = Draft202012Validator(
        profile_schema,
        format_checker=FormatChecker(),
    )
    example_schema_errors = list(profile_validator.iter_errors(example_profile))
    if example_schema_errors:
        raise AssertionError(
            "minimal profile example failed schema validation: "
            + "; ".join(error.message for error in example_schema_errors[:5])
        )
    example_semantic_errors = validate_profile_semantics(example_profile)
    if example_semantic_errors:
        raise AssertionError(
            "minimal profile example failed semantic validation: "
            + "; ".join(example_semantic_errors)
        )

    unsafe_path_probes = (
        r"C:\\Temp\\escape.exe",
        r"AppData\\..\\escape.exe",
        r"%TEMP%\\escape.exe",
        r"%USERPROFILE%\\escape.exe",
    )
    for unsafe_path in unsafe_path_probes:
        if is_safe_relative_path(unsafe_path):
            raise AssertionError(
                f"semantic path validator accepted unsafe path: {unsafe_path!r}"
            )

    fixtures = sorted(FIXTURE_ROOT.glob("*.json"))
    if not fixtures:
        raise AssertionError("no schema fixtures found")

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

        instance = load_json(fixture_path)
        schema = load_json(schema_for_fixture(fixture_path))
        validator = Draft202012Validator(schema, format_checker=FormatChecker())
        schema_errors = sorted(
            validator.iter_errors(instance),
            key=lambda error: list(error.absolute_path),
        )

        if expects_schema_invalid:
            if not schema_errors:
                raise AssertionError(
                    f"schema-invalid fixture accepted: {fixture_path.name}"
                )
            schema_invalid_count += 1
            continue

        if schema_errors:
            messages = "; ".join(error.message for error in schema_errors[:5])
            raise AssertionError(
                f"schema-valid fixture rejected: {fixture_path.name}: {messages}"
            )

        semantic_errors = semantic_errors_for_fixture(
            fixture_path,
            instance,
            example_profile,
        )
        if expects_semantic_invalid:
            if not semantic_errors:
                raise AssertionError(
                    f"semantic-invalid fixture accepted: {fixture_path.name}"
                )
            semantic_invalid_count += 1
            continue

        if semantic_errors:
            raise AssertionError(
                f"valid fixture failed semantics: {fixture_path.name}: "
                + "; ".join(semantic_errors[:5])
            )
        valid_count += 1

    evidence_schema = load_json(SCHEMA_ROOT / "evidence.schema.json")
    evidence_validator = Draft202012Validator(
        evidence_schema,
        format_checker=FormatChecker(),
    )
    passed = load_json(FIXTURE_ROOT / "evidence.passed.valid.json")
    for path, value in (
        (("vm", "ownershipVerified"), False),
        (("guest", "isAdministrator"), True),
        (("guest", "isElevated"), True),
        (("guest", "tokenIntegrity"), "high"),
        (("guest", "tokenIntegrity"), "system"),
    ):
        candidate = deepcopy(passed)
        candidate[path[0]][path[1]] = value
        if not list(evidence_validator.iter_errors(candidate)):
            raise AssertionError(
                f"passed evidence accepted forbidden value {path[0]}.{path[1]}={value!r}"
            )

    manual = load_json(FIXTURE_ROOT / "evidence.manual-passed.valid.json")
    missing_hash = deepcopy(manual)
    del missing_hash["manualAssertions"][0]["attestation"]["evidenceReferences"][0][
        "sha256"
    ]
    if not list(evidence_validator.iter_errors(missing_hash)):
        raise AssertionError("manual evidence reference without SHA-256 was accepted")

    vm_plan_schema = load_json(SCHEMA_ROOT / "vm-plan.schema.json")
    vm_plan_validator = Draft202012Validator(
        vm_plan_schema,
        format_checker=FormatChecker(),
    )
    vm_plan = load_json(FIXTURE_ROOT / "vm-plan.complete.valid.json")
    vm_plan_checks = 0
    for field in ("vmPath", "vhdxPath", "targetVolume", "preconditions"):
        candidate = deepcopy(vm_plan)
        del candidate[field]
        if not list(vm_plan_validator.iter_errors(candidate)):
            raise AssertionError(f"VM plan without {field} was accepted")
        vm_plan_checks += 1
    candidate = deepcopy(vm_plan)
    del candidate["targetVolume"]["uniqueId"]
    if not list(vm_plan_validator.iter_errors(candidate)):
        raise AssertionError("VM plan without target volume identity was accepted")
    vm_plan_checks += 1
    for field in (
        "isoRegularFile",
        "switchPresent",
        "vmNameAbsent",
        "vmPathAbsent",
        "vhdxPathAbsent",
    ):
        candidate = deepcopy(vm_plan)
        candidate["preconditions"][field] = False
        if not list(vm_plan_validator.iter_errors(candidate)):
            raise AssertionError(f"VM plan with false precondition {field} was accepted")
        vm_plan_checks += 1

    checkpoint_schema = load_json(SCHEMA_ROOT / "checkpoint-plan.schema.json")
    checkpoint_validator = Draft202012Validator(
        checkpoint_schema,
        format_checker=FormatChecker(),
    )
    checkpoint_create = load_json(FIXTURE_ROOT / "checkpoint-plan.create.valid.json")
    checkpoint_without_owner = deepcopy(checkpoint_create)
    del checkpoint_without_owner["ownershipId"]
    if not list(checkpoint_validator.iter_errors(checkpoint_without_owner)):
        raise AssertionError("checkpoint plan without ownership identity was accepted")

    print(
        json.dumps(
            {
                "ok": True,
                "schemas": len(schemas),
                "validFixtures": valid_count,
                "schemaInvalidFixtures": schema_invalid_count,
                "semanticInvalidFixtures": semantic_invalid_count,
                "minimalProfileExample": True,
                "unsafePathProbes": len(unsafe_path_probes),
                "conditionalEvidenceChecks": 6,
                "vmPlanPreconditionChecks": vm_plan_checks,
                "checkpointOwnershipChecks": 1,
            },
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

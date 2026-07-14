from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker


REPO_ROOT = Path(__file__).resolve().parents[1]
SCHEMA_ROOT = REPO_ROOT / "hyperv-clean-room" / "schemas"
FIXTURE_ROOT = Path(__file__).resolve().parent / "fixtures" / "schemas"


def load_json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def schema_for_fixture(path: Path) -> Path:
    prefix = path.name.split(".", 1)[0]
    mapping = {
        "vm-plan": "vm-plan.schema.json",
        "checkpoint-plan": "checkpoint-plan.schema.json",
        "evidence": "evidence.schema.json",
    }
    return SCHEMA_ROOT / mapping[prefix]


def main() -> int:
    schemas = sorted(SCHEMA_ROOT.glob("*.schema.json"))
    if len(schemas) != 5:
        raise AssertionError(f"expected 5 schemas, found {len(schemas)}")
    for schema_path in schemas:
        Draft202012Validator.check_schema(load_json(schema_path))

    fixtures = sorted(FIXTURE_ROOT.glob("*.json"))
    if not fixtures:
        raise AssertionError("no schema fixtures found")

    valid_count = 0
    invalid_count = 0
    for fixture_path in fixtures:
        expected_valid = fixture_path.name.endswith(".valid.json")
        expected_invalid = fixture_path.name.endswith(".invalid.json")
        if expected_valid == expected_invalid:
            raise AssertionError(f"fixture name lacks one validity marker: {fixture_path.name}")

        schema = load_json(schema_for_fixture(fixture_path))
        validator = Draft202012Validator(schema, format_checker=FormatChecker())
        errors = sorted(
            validator.iter_errors(load_json(fixture_path)),
            key=lambda error: list(error.absolute_path),
        )
        if expected_valid and errors:
            messages = "; ".join(error.message for error in errors[:5])
            raise AssertionError(f"valid fixture rejected: {fixture_path.name}: {messages}")
        if expected_invalid and not errors:
            raise AssertionError(f"invalid fixture accepted: {fixture_path.name}")

        valid_count += int(expected_valid)
        invalid_count += int(expected_invalid)

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
                "invalidFixtures": invalid_count,
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

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator, FormatChecker

from schema_contract_tests import validate_evidence_semantics


REPO_ROOT = Path(__file__).resolve().parents[1]
SCHEMA_ROOT = REPO_ROOT / "hyperv-clean-room" / "schemas"
ARTIFACT_ROOT = REPO_ROOT / ".artifacts"
EXAMPLE_PROFILE_PATH = REPO_ROOT / "examples" / "minimal-test-profile.json"

SAMPLES = {
    "operation-envelope.json": "operation-envelope.schema.json",
    "vm-plan.json": "vm-plan.schema.json",
    "checkpoint-create-plan.json": "checkpoint-plan.schema.json",
    "checkpoint-restore-plan.json": "checkpoint-plan.schema.json",
    "evidence.json": "evidence.schema.json",
}


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def latest_sample_root() -> Path:
    candidates = [
        path / "runtime-schema-samples"
        for path in ARTIFACT_ROOT.glob("gate2-tests-*")
        if (path / "runtime-schema-samples").is_dir()
    ]
    if not candidates:
        raise AssertionError(
            "no Gate 2 runtime samples found; run tests/gate2-runtime.tests.ps1 first"
        )
    return max(candidates, key=lambda path: path.stat().st_mtime_ns)


def validate_sample(sample_path: Path, schema_path: Path) -> dict[str, Any]:
    instance = load_json(sample_path)
    schema = load_json(schema_path)
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    errors = sorted(validator.iter_errors(instance), key=lambda error: list(error.path))
    if errors:
        first = errors[0]
        location = "/".join(str(part) for part in first.absolute_path) or "<root>"
        raise AssertionError(
            f"{sample_path.name} violates {schema_path.name} at {location}: "
            f"{first.message}"
        )
    return instance


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate actual Gate 2 runtime outputs against frozen schemas."
    )
    parser.add_argument("--sample-root", type=Path)
    args = parser.parse_args()
    sample_root = (
        args.sample_root.resolve() if args.sample_root is not None else latest_sample_root()
    )

    instances: dict[str, dict[str, Any]] = {}
    for sample_name, schema_name in SAMPLES.items():
        sample_path = sample_root / sample_name
        if not sample_path.is_file():
            raise AssertionError(f"missing Gate 2 runtime sample: {sample_path}")
        instances[sample_name] = validate_sample(
            sample_path,
            SCHEMA_ROOT / schema_name,
        )

    if instances["checkpoint-create-plan.json"].get("planKind") != "checkpointCreate":
        raise AssertionError("checkpoint create runtime sample has the wrong planKind")
    restore_plan = instances["checkpoint-restore-plan.json"]
    if restore_plan.get("planKind") != "checkpointRestore":
        raise AssertionError("checkpoint restore runtime sample has the wrong planKind")
    if not restore_plan.get("confirmationToken"):
        raise AssertionError("checkpoint restore runtime response lacks its one-time token")

    evidence_errors = validate_evidence_semantics(
        instances["evidence.json"],
        profile=load_json(EXAMPLE_PROFILE_PATH),
        expected_cleanup_triggered=False,
    )
    if evidence_errors:
        raise AssertionError(
            "runtime evidence failed independent semantic validation: "
            + "; ".join(evidence_errors[:5])
        )

    print(
        json.dumps(
            {
                "ok": True,
                "runtimeSamples": len(SAMPLES),
                "schemas": len(set(SAMPLES.values())),
                "evidenceSemantics": True,
            },
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

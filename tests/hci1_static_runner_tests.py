from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker


ROOT = Path(__file__).resolve().parents[1]
RUNNER_PATH = ROOT / "scripts" / "run_hyperv_static_linux.py"
SPEC = importlib.util.spec_from_file_location("hci1_runner", RUNNER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("HCI1 runner module could not be loaded")
runner = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = runner
SPEC.loader.exec_module(runner)


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def run_git(repository: Path, *arguments: str) -> str:
    completed = subprocess.run(
        ["git", *arguments],
        cwd=repository,
        check=False,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
        env={
            **os.environ,
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_TERMINAL_PROMPT": "0",
        },
    )
    if completed.returncode != 0:
        raise AssertionError(
            completed.stderr.decode("utf-8", errors="replace")[-1000:]
        )
    return completed.stdout.decode("utf-8", errors="strict").strip()


def request_value(operation_id: str | None = None) -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "operationId": operation_id or str(uuid.uuid4()),
        "repositoryId": "hyperv-clean-room",
        "commitSha": "1" * 40,
        "treeSha": "2" * 40,
        "suiteId": "hyperv-static-linux",
        "suiteContractVersion": 1,
        "sourceBundleSha256": "3" * 64,
        "runnerImageDigest": "sha256:" + "4" * 64,
    }


def content_reference(seed: str = "a", size: int = 16) -> dict[str, object]:
    sha = hashlib.sha256(seed.encode("utf-8")).hexdigest()
    return {
        "sha256": sha,
        "bytes": size,
        "contentPath": f"content/sha256/{sha[:2]}/{sha}",
    }


def summary_sample() -> dict[str, object]:
    checks: list[dict[str, object]] = []
    for index, suite_check in enumerate(runner.SUITE_CHECKS):
        checks.append(
            {
                "id": suite_check.check_id,
                "requiredForSuite": True,
                "status": "passed",
                "command": ["python", f"tests/check-{index}.py"],
                "exitCode": 0,
                "durationMilliseconds": 10,
                "commandAssertions": 1,
                "reportedTestCases": 1,
                "reportedMetrics": {"ok": True},
                "log": content_reference(chr(ord("a") + index)),
                "notPerformedReason": None,
            }
        )
    checks.append(
        {
            "id": "runtime-artifact-schema",
            "requiredForSuite": False,
            "status": "notPerformed",
            "command": None,
            "exitCode": None,
            "durationMilliseconds": 0,
            "commandAssertions": 0,
            "reportedTestCases": 0,
            "reportedMetrics": {},
            "log": None,
            "notPerformedReason": "Windows mock-runtime evidence belongs to HCI2.",
        }
    )
    packages = [
        {"name": name, "version": "1.0"}
        for name in (
            "attrs",
            "jsonschema",
            "jsonschema-specifications",
            "pyyaml",
            "referencing",
            "rpds-py",
            "typing-extensions",
        )
    ]
    wheel_objects = [
        {
            "filename": f"package_{index}-1.0-py3-none-any.whl",
            "bytes": 100 + index,
            "sha256": f"{index + 1:x}" * 64,
            "source": "prepared-input",
            "contentPath": (
                f"content/sha256/{index + 1:02x}/"
                + f"{index + 1:x}" * 64
            ),
        }
        for index in range(7)
    ]
    return {
        "schemaVersion": 1,
        "requestSchemaVersion": 1,
        "repositoryId": "hyperv-clean-room",
        "suiteId": "hyperv-static-linux",
        "suiteContractVersion": 1,
        "status": "passed",
        "operationId": "11111111-1111-4111-8111-111111111111",
        "idempotencyKey": "5" * 64,
        "requestSha256": "6" * 64,
        "sourceBundleSha256": "3" * 64,
        "runnerImageDigest": "sha256:" + "4" * 64,
        "startedAtUtc": "2026-07-24T00:00:00Z",
        "finishedAtUtc": "2026-07-24T00:01:00Z",
        "repository": {
            "identity": "rogue-shadowdancer/codex-hyperv-clean-room-plugin",
            "repositoryId": "hyperv-clean-room",
            "sourceBundleSha256": "3" * 64,
            "requestedCommitSha": "1" * 40,
            "requestedTreeSha": "2" * 40,
            "beforeCommitSha": "1" * 40,
            "beforeTreeSha": "2" * 40,
            "afterCommitSha": "1" * 40,
            "afterTreeSha": "2" * 40,
            "detachedHead": True,
            "fullHistory": True,
            "cleanBefore": True,
            "cleanAfter": True,
            "submodules": 0,
            "symlinks": 0,
            "lfsPointers": 0,
        },
        "infrastructure": {
            "visibleRoot": "/srv/codex-ci/hyperv-static-linux",
            "serviceAccount": "ci-hyperv-static",
            "serviceUnit": "codex-ci-hyperv-static@.service",
            "ownerUid": 1001,
            "ownerGid": 1001,
            "mount": {
                "target": "/srv/codex-ci/hyperv-static-linux",
                "source": "/dev/disk/by-uuid/example",
                "filesystemRoot": "/tianyi.zhang/codex-ci/hyperv-static-linux",
                "filesystemType": "ext4",
                "filesystemUuid": "dcebb074-2279-4a4d-bb21-e084cdda68b0",
                "options": ["nodev", "nosuid", "rw"],
                "propagation": "private",
            },
            "infrastructureRepository": (
                "rogue-shadowdancer/codex-ci-infrastructure"
            ),
            "infrastructureCommit": (
                "964c411ea0579b6adaca7a7bf7800d76f19028e2"
            ),
            "infrastructureTree": (
                "0bffd80a2b1f64ee3e091ff759c11110d988f2c6"
            ),
        },
        "runner": {
            "operatingSystem": "Linux",
            "architecture": "x86_64",
            "pythonImplementation": "CPython",
            "pythonVersion": "3.12.10",
            "pythonAbi": "cp312",
            "pythonExecutableSha256": "7" * 64,
            "gitVersion": "git version 2.43.0",
            "gitExecutableSha256": "8" * 64,
            "runnerSourceSha256": "9" * 64,
            "runnerImageIdentitySha256": "a" * 64,
            "isolation": "operation-scoped-venv",
        },
        "dependencyClosure": {
            "wheelLockSha256": "b" * 64,
            "requirementsSha256": "c" * 64,
            "inventorySha256": "d" * 64,
            "pipVersion": "25.0",
            "packages": packages,
            "wheelObjects": wheel_objects,
        },
        "checks": checks,
        "counts": {
            "checks": 9,
            "executed": 8,
            "passed": 8,
            "failed": 0,
            "incomplete": 0,
            "notPerformed": 1,
            "commandAssertions": 8,
            "reportedTestCases": 8,
        },
        "logManifest": content_reference("e", 100),
        "relatedSuites": {
            "hyperv-mock-windows": "notPerformed",
            "hyperv-validation": "notPerformed",
        },
        "operationCounters": dict(runner.ZERO_COUNTERS),
        "cleanup": {
            "workspace": "retained",
            "unknownEntries": 0,
            "symlinksFollowed": 0,
        },
        "ambiguity": {
            "status": "resolved",
            "statePath": (
                "ambiguity/11111111-1111-4111-8111-111111111111/state.json"
            ),
            "blindRetries": 0,
        },
        "diskUsage": {
            "workspacePeakBytes": 1024,
            "publishedContentBytes": 2048,
            "rootBytesBeforeSummaryPublish": 4096,
            "workspaceLimitBytes": 2147483648,
            "retentionLimitBytes": 10737418240,
        },
        "warnings": [
            "Linux static validation does not prove Windows or Hyper-V behavior."
        ],
    }


class RequestContractTests(unittest.TestCase):
    def test_closed_request_and_idempotency_bindings(self) -> None:
        first_raw = request_value(
            "11111111-1111-4111-8111-111111111111"
        )
        second_raw = request_value(
            "22222222-2222-4222-8222-222222222222"
        )
        first = runner.parse_request_json(runner.canonical_json(first_raw))
        second = runner.parse_request_json(runner.canonical_json(second_raw))
        self.assertEqual(
            runner.compute_idempotency_key(first),
            runner.compute_idempotency_key(second),
        )
        for field, replacement in (
            ("repositoryId", "birdsgone"),
            ("commitSha", "a" * 40),
            ("treeSha", "b" * 40),
            ("sourceBundleSha256", "c" * 64),
            ("suiteId", "kvm-ci-mirror"),
            ("suiteContractVersion", 2),
            ("runnerImageDigest", "sha256:" + "d" * 64),
        ):
            changed = dict(first_raw)
            changed[field] = replacement
            with self.subTest(field=field):
                if field in {
                    "repositoryId",
                    "suiteId",
                    "suiteContractVersion",
                }:
                    with self.assertRaises(runner.RunnerError):
                        runner.parse_request_json(runner.canonical_json(changed))
                else:
                    candidate = runner.Request(
                        **{
                            **first.__dict__,
                            {
                                "commitSha": "commit_sha",
                                "treeSha": "tree_sha",
                                "sourceBundleSha256": "source_bundle_sha256",
                                "runnerImageDigest": "runner_image_digest",
                            }[field]: replacement,
                        }
                    )
                    self.assertNotEqual(
                        runner.compute_idempotency_key(first),
                        runner.compute_idempotency_key(candidate),
                    )

    def test_request_rejects_unknown_duplicate_and_noncanonical_fields(self) -> None:
        unknown = request_value()
        unknown["path"] = "/tmp/not-accepted"
        with self.assertRaises(runner.RunnerError):
            runner.parse_request_json(runner.canonical_json(unknown))
        duplicate = (
            b'{"schemaVersion":1,"schemaVersion":1,'
            b'"operationId":"11111111-1111-4111-8111-111111111111"}'
        )
        with self.assertRaises(runner.RunnerError):
            runner.parse_request_json(duplicate)
        invalid = request_value()
        invalid["operationId"] = str(uuid.uuid4()).upper()
        with self.assertRaises(runner.RunnerError):
            runner.parse_request_json(runner.canonical_json(invalid))

    def test_aggregate_status_is_closed_and_zero_bound(self) -> None:
        binding = {
            "repositoryId": "hyperv-clean-room",
            "commitSha": "1" * 40,
            "treeSha": "2" * 40,
            "sourceBundleSha256": "3" * 64,
            "suiteContractVersion": 1,
            "runnerImageDigest": "sha256:" + "4" * 64,
            "status": "passed",
            "operationCounters": dict(runner.ZERO_COUNTERS),
        }
        self.assertEqual(
            runner.derive_hyperv_validation_status(binding, dict(binding)),
            "passed",
        )
        self.assertEqual(
            runner.derive_hyperv_validation_status(binding, None),
            "incomplete",
        )
        failed = dict(binding)
        failed["status"] = "failed"
        self.assertEqual(
            runner.derive_hyperv_validation_status(binding, failed),
            "failed",
        )
        drifted = dict(binding)
        drifted["treeSha"] = "f" * 40
        self.assertEqual(
            runner.derive_hyperv_validation_status(binding, drifted),
            "failed",
        )
        nonzero = dict(binding)
        nonzero["operationCounters"] = {
            **runner.ZERO_COUNTERS,
            "realHyperVMutations": 1,
        }
        self.assertEqual(
            runner.derive_hyperv_validation_status(binding, nonzero),
            "failed",
        )
        static_checks = summary_sample()["checks"]
        self.assertEqual(
            runner.derive_static_suite_status(static_checks),
            "passed",
        )
        static_checks[0]["status"] = "failed"
        self.assertEqual(
            runner.derive_static_suite_status(static_checks),
            "failed",
        )


class EvidenceContractTests(unittest.TestCase):
    def validate(self, relative: str, instance: dict[str, object]) -> None:
        schema = json.loads((ROOT / relative).read_text(encoding="utf-8"))
        Draft202012Validator.check_schema(schema)
        errors = list(
            Draft202012Validator(
                schema,
                format_checker=FormatChecker(),
            ).iter_errors(instance)
        )
        if errors:
            self.fail(errors[0].message)

    def test_summary_log_and_ambiguity_schemas(self) -> None:
        summary = summary_sample()
        self.validate(
            "contracts/ci/hyperv-static-linux-summary.schema.json",
            summary,
        )
        summary_schema = json.loads(
            (
                ROOT
                / "contracts/ci/hyperv-static-linux-summary.schema.json"
            ).read_text(encoding="utf-8")
        )
        contradictory_summary = summary_sample()
        contradictory_summary["ambiguity"]["status"] = "incomplete"
        self.assertTrue(
            list(
                Draft202012Validator(
                    summary_schema,
                    format_checker=FormatChecker(),
                ).iter_errors(contradictory_summary)
            )
        )
        failed_summary = summary_sample()
        failed_summary["status"] = "failed"
        failed_summary["checks"][0]["status"] = "failed"
        failed_summary["checks"][0]["exitCode"] = 1
        failed_summary["counts"]["passed"] = 7
        failed_summary["counts"]["failed"] = 1
        self.validate(
            "contracts/ci/hyperv-static-linux-summary.schema.json",
            failed_summary,
        )
        incomplete_summary = summary_sample()
        incomplete_summary["status"] = "incomplete"
        incomplete_summary["checks"][0]["status"] = "incomplete"
        incomplete_summary["checks"][0]["exitCode"] = -15
        incomplete_summary["counts"]["passed"] = 7
        incomplete_summary["counts"]["incomplete"] = 1
        self.validate(
            "contracts/ci/hyperv-static-linux-summary.schema.json",
            incomplete_summary,
        )
        entries = [
            {
                "id": identity,
                "category": category,
                **content_reference(f"{index + 1:x}"),
            }
            for index, (identity, category) in enumerate(
                runner.LOG_ENTRY_CONTRACT
            )
        ]
        log_manifest = {
            "schemaVersion": 1,
            "suiteId": "hyperv-static-linux",
            "operationId": summary["operationId"],
            "idempotencyKey": summary["idempotencyKey"],
            "entries": entries,
        }
        self.validate(
            "contracts/ci/hyperv-static-linux-log-manifest.schema.json",
            log_manifest,
        )
        log_schema = json.loads(
            (
                ROOT
                / "contracts/ci/hyperv-static-linux-log-manifest.schema.json"
            ).read_text(encoding="utf-8")
        )
        reordered = {**log_manifest, "entries": list(reversed(entries))}
        self.assertTrue(
            list(Draft202012Validator(log_schema).iter_errors(reordered))
        )
        ambiguity = {
            "schemaVersion": 1,
            "suiteId": "hyperv-static-linux",
            "operationId": summary["operationId"],
            "idempotencyKey": summary["idempotencyKey"],
            "repositoryId": "hyperv-clean-room",
            "commitSha": "1" * 40,
            "treeSha": "2" * 40,
            "sourceBundleSha256": "3" * 64,
            "suiteContractVersion": 1,
            "runnerImageDigest": "sha256:" + "4" * 64,
            "requestSha256": "6" * 64,
            "status": "resolved",
            "updatedAtUtc": "2026-07-24T00:01:00Z",
            "summaryPath": (
                f"results/{summary['idempotencyKey']}/summary.json"
            ),
            "summarySha256": "f" * 64,
            "message": "The immutable summary resolved this operation.",
        }
        self.validate(
            "contracts/ci/hyperv-static-linux-ambiguity.schema.json",
            ambiguity,
        )

    def test_summary_rejects_nonzero_counter_and_noexec(self) -> None:
        schema = json.loads(
            (
                ROOT
                / "contracts/ci/hyperv-static-linux-summary.schema.json"
            ).read_text(encoding="utf-8")
        )
        validator = Draft202012Validator(schema, format_checker=FormatChecker())
        nonzero = summary_sample()
        nonzero["operationCounters"]["realHyperVMutations"] = 1
        self.assertTrue(list(validator.iter_errors(nonzero)))
        noexec = summary_sample()
        noexec["infrastructure"]["mount"]["options"].append("noexec")
        self.assertTrue(list(validator.iter_errors(noexec)))
        reordered = summary_sample()
        reordered["checks"] = list(reversed(reordered["checks"]))
        self.assertTrue(list(validator.iter_errors(reordered)))
        contradictory = summary_sample()
        contradictory["checks"][0]["status"] = "failed"
        contradictory["checks"][0]["exitCode"] = 1
        contradictory["counts"]["passed"] = 7
        contradictory["counts"]["failed"] = 1
        self.assertTrue(list(validator.iter_errors(contradictory)))
        wrong_cleanup = summary_sample()
        wrong_cleanup["cleanup"]["workspace"] = "removed"
        self.assertTrue(list(validator.iter_errors(wrong_cleanup)))


class StorageAndSourceTests(unittest.TestCase):
    def private_root(self, base: Path) -> Path:
        root = base / "lane"
        root.mkdir(mode=0o700)
        if os.name == "posix":
            root.chmod(0o700)
        return root

    def test_layout_requires_existing_root_and_creates_only_fixed_children(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            missing = Path(temporary) / "missing"
            with self.assertRaises(runner.RunnerIncomplete):
                runner.initialize_layout(missing)
            root = self.private_root(Path(temporary))
            layout, facts = runner.initialize_layout(root)
            self.assertEqual(
                {path.name for path in root.iterdir()},
                {"ambiguity", "content", "locks", "results", "workspaces"},
            )
            self.assertEqual(layout.root, root.absolute())
            self.assertEqual(facts["serviceAccount"], "ci-hyperv-static")
            before = sorted(path.relative_to(root) for path in root.rglob("*"))
            with runner.LaneCapacityLock(root):
                pass
            after = sorted(path.relative_to(root) for path in root.rglob("*"))
            self.assertEqual(after, before)

    def test_content_publish_reuse_and_corruption_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = self.private_root(base)
            layout, _facts = runner.initialize_layout(root)
            workspace = layout.workspaces / str(uuid.uuid4())
            workspace.mkdir(mode=0o700)
            source = workspace / "source.bin"
            source.write_bytes(b"immutable-content")
            if os.name == "posix":
                source.chmod(0o600)
            store = runner.ContentStore(layout, workspace)
            first, created = store.publish_file(source)
            second, reused = store.publish_file(source)
            self.assertTrue(created)
            self.assertFalse(reused)
            self.assertEqual(first, second)
            target = layout.root / str(first["contentPath"])
            target.write_bytes(b"corrupt")
            if os.name == "posix":
                target.chmod(0o600)
            with self.assertRaises(runner.RunnerIncomplete):
                store.publish_file(source)

    def test_content_publish_fails_before_retention_overflow(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = self.private_root(base)
            layout, _facts = runner.initialize_layout(root)
            workspace = layout.workspaces / str(uuid.uuid4())
            workspace.mkdir(mode=0o700)
            source = workspace / "source.bin"
            source.write_bytes(b"bounded-content")
            if os.name == "posix":
                source.chmod(0o600)
            store = runner.ContentStore(layout, workspace)
            prior_limit = runner.RETENTION_LIMIT_BYTES
            prior_reserve = runner.RETENTION_METADATA_RESERVE_BYTES
            try:
                runner.RETENTION_METADATA_RESERVE_BYTES = 0
                runner.RETENTION_LIMIT_BYTES = runner.tree_size(root)
                with self.assertRaises(runner.RunnerIncomplete):
                    store.publish_file(source)
            finally:
                runner.RETENTION_LIMIT_BYTES = prior_limit
                runner.RETENTION_METADATA_RESERVE_BYTES = prior_reserve

    def test_exclusive_lock_has_one_writer(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            lock_path = Path(temporary) / "one.lock"
            with runner.ExclusiveFileLock(lock_path):
                with self.assertRaises(runner.RunnerBusy):
                    with runner.ExclusiveFileLock(lock_path):
                        pass
            reusable = runner.ExclusiveFileLock(lock_path)
            reusable.__enter__()
            with reusable:
                self.assertIsNotNone(reusable.stream)
            with runner.ExclusiveFileLock(lock_path):
                pass

    def test_same_operation_ambiguity_forbids_retry(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = self.private_root(Path(temporary))
            layout, _facts = runner.initialize_layout(root)
            request = runner.parse_request_json(
                runner.canonical_json(request_value())
            )
            key = runner.compute_idempotency_key(request)
            runner.write_ambiguity_state(
                layout,
                request,
                key,
                "incomplete",
                message="transport completion is uncertain",
            )
            with self.assertRaises(runner.RunnerIncomplete):
                runner.write_ambiguity_state(
                    layout,
                    request,
                    key,
                    "resolved",
                    summary_path=f"results/{key}/summary.json",
                    summary_sha256="f" * 64,
                    message="cannot resolve without summary readback",
                )
            unresolved = runner.find_unresolved_ambiguity(layout, key)
            self.assertIsNotNone(unresolved)
            self.assertEqual(unresolved["operationId"], request.operation_id)
            conflicting_value = request_value(request.operation_id)
            conflicting_value["commitSha"] = "a" * 40
            conflicting = runner.parse_request_json(
                runner.canonical_json(conflicting_value)
            )
            conflicting_key = runner.compute_idempotency_key(conflicting)
            with self.assertRaises(runner.RunnerIncomplete):
                runner.write_ambiguity_state(
                    layout,
                    conflicting,
                    conflicting_key,
                    "incomplete",
                    message="must not replace the original identity",
                )
            preserved = json.loads(
                runner.ambiguity_state_path(
                    layout,
                    request.operation_id,
                ).read_text(encoding="utf-8")
            )
            self.assertEqual(preserved["idempotencyKey"], key)
            self.assertEqual(preserved["commitSha"], request.commit_sha)

    def test_existing_summary_reuse_rehashes_all_content(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = self.private_root(Path(temporary))
            layout, _facts = runner.initialize_layout(root)
            original = runner.parse_request_json(
                runner.canonical_json(
                    request_value("11111111-1111-4111-8111-111111111111")
                )
            )
            key = runner.compute_idempotency_key(original)
            workspace = layout.workspaces / original.operation_id
            workspace.mkdir(mode=0o700)
            runner.atomic_write_json(
                workspace / ".hci-operation.json",
                {
                    "schemaVersion": 1,
                    "operationId": original.operation_id,
                    "idempotencyKey": key,
                },
            )
            store = runner.ContentStore(layout, workspace)
            summary = summary_sample()
            summary["idempotencyKey"] = key
            summary["requestSha256"] = digest(original.canonical_bytes())

            check_logs: list[dict[str, object]] = []
            for index, check in enumerate(summary["checks"][:8]):
                reference = store.publish_bytes(
                    f"check-{index}\n".encode("utf-8"),
                    f"check-{index}",
                )
                check["log"] = reference
                check_logs.append(
                    {
                        "id": check["id"],
                        "category": "check",
                        **reference,
                    }
                )

            wheel_objects: list[dict[str, object]] = []
            for index, wheel in enumerate(
                summary["dependencyClosure"]["wheelObjects"]
            ):
                payload = f"wheel-{index}".encode("utf-8")
                reference = store.publish_bytes(payload, f"wheel-{index}")
                wheel["bytes"] = reference["bytes"]
                wheel["sha256"] = reference["sha256"]
                wheel["contentPath"] = reference["contentPath"]
                wheel_objects.append(wheel)

            bootstrap_and_dependency: list[dict[str, object]] = []
            for identifier, category in (
                ("bundle-verify", "bootstrap"),
                ("bundle-fetch", "bootstrap"),
                ("venv-create", "dependency"),
                ("venv-install", "dependency"),
            ):
                reference = store.publish_bytes(
                    f"{identifier}\n".encode("utf-8"),
                    identifier,
                )
                bootstrap_and_dependency.append(
                    {"id": identifier, "category": category, **reference}
                )
            manifest = {
                "schemaVersion": 1,
                "suiteId": "hyperv-static-linux",
                "operationId": original.operation_id,
                "idempotencyKey": key,
                "entries": bootstrap_and_dependency + check_logs,
            }
            summary["logManifest"] = store.publish_bytes(
                runner.canonical_json(manifest),
                "log-manifest",
            )
            result_path, summary_sha = runner.publish_summary(
                layout,
                key,
                original.operation_id,
                summary,
            )
            reused = runner.read_existing_summary(
                layout,
                result_path,
                original,
                key,
            )
            self.assertEqual(reused["status"], "passed")
            relative_summary = f"results/{key}/summary.json"
            runner.write_ambiguity_state(
                layout,
                original,
                key,
                "incomplete",
                message="transport completion was uncertain",
            )
            runner.write_ambiguity_state(
                layout,
                original,
                key,
                "resolved",
                summary_path=relative_summary,
                summary_sha256=summary_sha,
                message="initial terminal identity",
            )
            state_path = runner.ambiguity_state_path(
                layout,
                original.operation_id,
            )
            terminal_bytes = state_path.read_bytes()
            runner.write_ambiguity_state(
                layout,
                original,
                key,
                "resolved",
                summary_path=relative_summary,
                summary_sha256=summary_sha,
                message="must not replace the terminal bytes",
            )
            self.assertEqual(state_path.read_bytes(), terminal_bytes)
            with self.assertRaises(runner.RunnerIncomplete):
                runner.cleanup_workspace_after_readback(
                    layout,
                    original.operation_id,
                    key,
                    "0" * 64,
                )
            self.assertTrue(workspace.is_dir())
            cleanup = runner.cleanup_workspace_after_readback(
                layout,
                original.operation_id,
                key,
                summary_sha,
            )
            self.assertEqual(cleanup["workspace"], "removed")
            self.assertFalse(workspace.exists())

            first_log = layout.root / str(check_logs[0]["contentPath"])
            first_log.write_bytes(b"corrupt")
            if os.name == "posix":
                first_log.chmod(0o600)
            with self.assertRaises(runner.RunnerIncomplete):
                runner.read_existing_summary(
                    layout,
                    result_path,
                    original,
                    key,
                )

    def test_command_log_is_bounded_after_metadata(self) -> None:
        prior_limit = runner.MAX_LOG_BYTES
        runner.MAX_LOG_BYTES = 256
        try:
            result = runner.run_command(
                (
                    sys.executable,
                    "-c",
                    "import sys;sys.stdout.write('x'*1024)",
                ),
                cwd=ROOT,
                environment=dict(os.environ),
                timeout_seconds=30,
            )
        finally:
            runner.MAX_LOG_BYTES = prior_limit
        self.assertTrue(result.output_overflow)
        self.assertLessEqual(len(result.output), 256)

    def test_local_bundle_checkout_binds_commit_tree_and_runner(self) -> None:
        git = Path(shutil.which("git") or "")
        if not git.is_file():
            self.skipTest("git is unavailable")
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            source = base / "source"
            source.mkdir()
            run_git(source, "init", "--quiet")
            candidate = source / "scripts" / RUNNER_PATH.name
            candidate.parent.mkdir()
            shutil.copyfile(RUNNER_PATH, candidate)
            run_git(source, "add", "scripts/run_hyperv_static_linux.py")
            run_git(
                source,
                "-c",
                "user.name=runner-test",
                "-c",
                "user.email=78423508+rogue-shadowdancer@users.noreply.github.com",
                "commit",
                "--quiet",
                "-m",
                "runner fixture",
            )
            commit = run_git(source, "rev-parse", "HEAD")
            tree = run_git(source, "rev-parse", "HEAD^{tree}")
            bundle = base / "source.bundle"
            run_git(source, "bundle", "create", str(bundle), "HEAD")
            request = runner.Request(
                schema_version=1,
                operation_id=str(uuid.uuid4()),
                repository_id="hyperv-clean-room",
                commit_sha=commit,
                tree_sha=tree,
                source_bundle_sha256=runner.sha256_file(bundle),
                suite_id="hyperv-static-linux",
                suite_contract_version=1,
                runner_image_digest="sha256:" + "4" * 64,
            )
            root = self.private_root(base)
            layout, _facts = runner.initialize_layout(root)
            workspace = layout.workspaces / request.operation_id
            workspace.mkdir(mode=0o700)
            store = runner.ContentStore(layout, workspace)
            log_entries: list[dict[str, object]] = []
            repository, facts = runner.checkout_candidate(
                request,
                bundle,
                workspace,
                git.resolve(),
                runner.sanitized_environment(git_path=git.resolve()),
                store,
                log_entries,
            )
            self.assertEqual(facts["beforeCommitSha"], commit)
            self.assertEqual(facts["beforeTreeSha"], tree)
            self.assertTrue(facts["fullHistory"])
            self.assertEqual(len(log_entries), 2)
            self.assertTrue((repository / ".git").is_dir())


class BoundaryTests(unittest.TestCase):
    def test_wheel_lock_matches_requirements_and_has_no_home_path(self) -> None:
        lock, _path = runner.load_wheel_lock(ROOT)
        self.assertEqual(len(lock["packages"]), 7)
        self.assertNotIn("interpreterRelativeToHome", lock["python"])
        source = RUNNER_PATH.read_text(encoding="utf-8")
        self.assertNotIn("urllib.request", source)
        self.assertNotIn("git clone", source)
        self.assertEqual(
            runner.default_ci_root().as_posix(),
            "/srv/codex-ci/hyperv-static-linux",
        )

    def test_direct_entrypoint_is_explicitly_not_integrated(self) -> None:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            exit_code = runner.main([])
        receipt = json.loads(output.getvalue())
        self.assertEqual(exit_code, 2)
        self.assertEqual(receipt["status"], "incomplete")
        self.assertEqual(receipt["controllerAdapter"], "notPerformed")
        self.assertEqual(receipt["remoteProof"], "notPerformed")

    def test_linux_suite_is_static_and_windows_runtime_is_not_synthesized(self) -> None:
        self.assertEqual(len(runner.SUITE_CHECKS), 8)
        self.assertIn(
            ("--static-only",),
            [check.arguments for check in runner.SUITE_CHECKS],
        )
        self.assertNotIn(
            "runtime_artifact_schema_tests.py",
            [check.relative_script for check in runner.SUITE_CHECKS],
        )


if __name__ == "__main__":
    result = unittest.main(verbosity=2, exit=False)
    if not result.result.wasSuccessful():
        raise SystemExit(1)
    print(
        json.dumps(
            {
                "ok": True,
                "assertions": result.result.testsRun,
                "realHostOperations": 0,
                "realHyperVMutations": 0,
                "realGuestOperations": 0,
                "portableDeployments": 0,
                "webDriverLaunches": 0,
                "uiOperations": 0,
                "controllerAdapter": "notPerformed",
                "remoteProof": "notPerformed",
            },
            separators=(",", ":"),
        )
    )

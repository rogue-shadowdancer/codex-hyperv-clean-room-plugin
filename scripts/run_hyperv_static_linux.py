from __future__ import annotations

import contextlib
import dataclasses
import datetime as dt
import hashlib
import json
import os
import platform
import re
import shutil
import stat
import subprocess
import sys
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence
from urllib.parse import urlsplit


REQUEST_SCHEMA_VERSION = 1
REPOSITORY_ID = "hyperv-clean-room"
REPOSITORY_IDENTITY = "rogue-shadowdancer/codex-hyperv-clean-room-plugin"
SUITE_ID = "hyperv-static-linux"
SUITE_CONTRACT_VERSION = 1
SUMMARY_SCHEMA_VERSION = 1
C2_INFRASTRUCTURE_REPOSITORY = "rogue-shadowdancer/codex-ci-infrastructure"
C2_INFRASTRUCTURE_COMMIT = "964c411ea0579b6adaca7a7bf7800d76f19028e2"
C2_INFRASTRUCTURE_TREE = "0bffd80a2b1f64ee3e091ff759c11110d988f2c6"
VISIBLE_LANE_ROOT = Path("/srv/codex-ci/hyperv-static-linux")
SERVICE_ACCOUNT = "ci-hyperv-static"
SERVICE_UNIT = "codex-ci-hyperv-static@.service"
EXPECTED_FILESYSTEM_UUID = "dcebb074-2279-4a4d-bb21-e084cdda68b0"
EXPECTED_FILESYSTEM_TYPE = "ext4"
EXPECTED_FILESYSTEM_ROOT = (
    "/tianyi.zhang/codex-ci/hyperv-static-linux"
)
GIT_SHA = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
RUNNER_IMAGE_DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")
OPERATION_ID = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-"
    r"[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
)
WORKSPACE_LIMIT_BYTES = 2 * 1024 * 1024 * 1024
RETENTION_LIMIT_BYTES = 10 * 1024 * 1024 * 1024
MAX_LOG_BYTES = 16 * 1024 * 1024
MAX_WHEEL_BYTES = 32 * 1024 * 1024
SUMMARY_LIMIT_BYTES = 1024 * 1024
RETENTION_METADATA_RESERVE_BYTES = 1024 * 1024
OPERATION_RETENTION_RESERVE_BYTES = (
    WORKSPACE_LIMIT_BYTES
    + (12 * MAX_LOG_BYTES)
    + (7 * MAX_WHEEL_BYTES)
    + SUMMARY_LIMIT_BYTES
    + RETENTION_METADATA_RESERVE_BYTES
)
BUNDLE_TIMEOUT_SECONDS = 300
VENV_TIMEOUT_SECONDS = 300
TEST_TIMEOUT_SECONDS = 900
ZERO_COUNTERS = {
    "realHostOperations": 0,
    "realHyperVMutations": 0,
    "realGuestOperations": 0,
    "portableDeployments": 0,
    "webDriverLaunches": 0,
    "uiOperations": 0,
}

TEST_LAUNCHER = (
    "import pathlib,runpy,sys;"
    "p=pathlib.Path(sys.argv[1]).resolve();"
    "sys.path.insert(0,str(p.parent));"
    "sys.argv=sys.argv[1:];"
    "runpy.run_path(str(p),run_name='__main__')"
)
INVENTORY_LAUNCHER = (
    "import importlib.metadata as m,json;"
    "rows=sorted((d.metadata['Name'],d.version) for d in m.distributions());"
    "print(json.dumps(rows,separators=(',',':')))"
)


@dataclasses.dataclass(frozen=True)
class Request:
    schema_version: int
    repository_id: str
    commit_sha: str
    tree_sha: str
    source_bundle_sha256: str
    suite_id: str
    suite_contract_version: int
    runner_image_digest: str
    operation_id: str

    def canonical_dict(self) -> dict[str, object]:
        return {
            "schemaVersion": self.schema_version,
            "operationId": self.operation_id,
            "repositoryId": self.repository_id,
            "commitSha": self.commit_sha,
            "treeSha": self.tree_sha,
            "suiteId": self.suite_id,
            "suiteContractVersion": self.suite_contract_version,
            "sourceBundleSha256": self.source_bundle_sha256,
            "runnerImageDigest": self.runner_image_digest,
        }

    def canonical_bytes(self) -> bytes:
        return canonical_json(self.canonical_dict())


@dataclasses.dataclass(frozen=True)
class PreparedInputs:
    """Path-independent core inputs resolved by a future trusted adapter.

    These paths are not accepted by the command line or serialized request.
    The future infrastructure runner-integration gate owns their fixed remote
    locations, ownership checks, and dispatch wiring.
    """

    source_bundle: Path
    wheels_by_sha256: Mapping[str, Path]


@dataclasses.dataclass(frozen=True)
class Check:
    check_id: str
    relative_script: str
    arguments: tuple[str, ...] = ()


@dataclasses.dataclass
class CommandResult:
    arguments: list[str]
    exit_code: int | None
    duration_milliseconds: int
    output: bytes
    timed_out: bool
    output_overflow: bool


@dataclasses.dataclass(frozen=True)
class Layout:
    root: Path
    workspaces: Path
    locks: Path
    results: Path
    content: Path
    ambiguity: Path

    @classmethod
    def under(cls, root: Path) -> "Layout":
        return cls(
            root=root,
            workspaces=root / "workspaces",
            locks=root / "locks",
            results=root / "results",
            content=root / "content" / "sha256",
            ambiguity=root / "ambiguity",
        )


SUITE_CHECKS = (
    Check("repository-formats", "tests/repository_format_tests.py"),
    Check(
        "publication-hygiene-policy",
        "tests/publication_hygiene_policy_tests.py",
    ),
    Check("publication-hygiene", "tests/publication_hygiene_tests.py"),
    Check("public-release-contract", "tests/public_release_contract_tests.py"),
    Check("schema-contract", "tests/schema_contract_tests.py"),
    Check("static-quality", "tests/static_quality_tests.py"),
    Check(
        "gate7-static-integration",
        "tests/gate7_implementation_tests.py",
        ("--static-only",),
    ),
    Check("hci1-runner-contract", "tests/hci1_static_runner_tests.py"),
)
LOG_ENTRY_CONTRACT = (
    ("bundle-verify", "bootstrap"),
    ("bundle-fetch", "bootstrap"),
    ("venv-create", "dependency"),
    ("venv-install", "dependency"),
    *((check.check_id, "check") for check in SUITE_CHECKS),
)


class RunnerError(RuntimeError):
    pass


class RunnerIncomplete(RunnerError):
    pass


class RunnerBusy(RunnerIncomplete):
    pass


class RunnerInterrupted(RunnerIncomplete):
    pass


def canonical_json(value: object) -> bytes:
    return (
        json.dumps(
            value,
            ensure_ascii=True,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
        + b"\n"
    )


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def canonical_package_name(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).casefold()


def validate_request(request: Request) -> None:
    if request.schema_version != REQUEST_SCHEMA_VERSION:
        raise RunnerError("unsupported request schema version")
    if request.repository_id != REPOSITORY_ID:
        raise RunnerError("request repository is not the fixed Hyper-V repository")
    if request.suite_id != SUITE_ID:
        raise RunnerError("request suite is not hyperv-static-linux")
    if not GIT_SHA.fullmatch(request.commit_sha):
        raise RunnerError("commit SHA must be exactly 40 lowercase hexadecimal characters")
    if not GIT_SHA.fullmatch(request.tree_sha):
        raise RunnerError("tree SHA must be exactly 40 lowercase hexadecimal characters")
    if not SHA256.fullmatch(request.source_bundle_sha256):
        raise RunnerError("source bundle SHA-256 is invalid")
    if not RUNNER_IMAGE_DIGEST.fullmatch(request.runner_image_digest):
        raise RunnerError("runner image digest is invalid")
    if request.suite_contract_version != SUITE_CONTRACT_VERSION:
        raise RunnerError("unsupported suite contract version")
    try:
        parsed_operation = uuid.UUID(request.operation_id)
    except ValueError as error:
        raise RunnerError("operation ID must be a canonical UUID") from error
    if (
        str(parsed_operation) != request.operation_id
        or not OPERATION_ID.fullmatch(request.operation_id)
    ):
        raise RunnerError("operation ID must be a canonical lowercase UUID")


def compute_idempotency_key(request: Request) -> str:
    validate_request(request)
    material = "|".join(
        (
            request.repository_id,
            request.commit_sha,
            request.tree_sha,
            request.source_bundle_sha256,
            SUITE_ID,
            str(request.suite_contract_version),
            request.runner_image_digest,
        )
    )
    return sha256_bytes(material.encode("utf-8"))


def derive_hyperv_validation_status(
    static_input: dict[str, object] | None,
    windows_input: dict[str, object] | None,
) -> str:
    inputs = (static_input, windows_input)
    if any(item is None for item in inputs):
        return "incomplete"
    assert static_input is not None and windows_input is not None
    bindings = (
        "repositoryId",
        "commitSha",
        "treeSha",
        "sourceBundleSha256",
        "suiteContractVersion",
        "runnerImageDigest",
    )
    if any(static_input.get(field) != windows_input.get(field) for field in bindings):
        return "failed"
    statuses = (static_input.get("status"), windows_input.get("status"))
    if "failed" in statuses:
        return "failed"
    for item in inputs:
        counters = item.get("operationCounters")
        if not isinstance(counters, dict) or counters != ZERO_COUNTERS:
            return "failed"
    if statuses == ("passed", "passed"):
        return "passed"
    return "incomplete"


def default_ci_root() -> Path:
    return VISIBLE_LANE_ROOT


def lstat_kind(path: Path) -> str:
    mode = path.lstat().st_mode
    if stat.S_ISLNK(mode):
        return "symlink"
    if stat.S_ISDIR(mode):
        return "directory"
    if stat.S_ISREG(mode):
        return "file"
    return "special"


def require_no_symlink_chain(path: Path, stop_at: Path) -> None:
    path = path.absolute()
    stop_at = stop_at.absolute()
    try:
        path.relative_to(stop_at)
    except ValueError as error:
        raise RunnerIncomplete("CI path escapes its fixed root") from error
    current = stop_at
    if current.exists() and lstat_kind(current) == "symlink":
        raise RunnerIncomplete("CI root anchor is a symlink")
    for part in path.relative_to(stop_at).parts:
        current = current / part
        if current.exists() or current.is_symlink():
            if lstat_kind(current) == "symlink":
                raise RunnerIncomplete("CI path contains a symlink")


def ensure_private_directory(path: Path, *, create: bool = True) -> None:
    if path.exists() or path.is_symlink():
        if lstat_kind(path) != "directory":
            raise RunnerIncomplete("required CI directory is not an ordinary directory")
        if os.name == "posix" and stat.S_IMODE(path.stat().st_mode) != 0o700:
            raise RunnerIncomplete("required CI directory mode is not 0700")
        return
    if not create:
        raise RunnerIncomplete("required CI directory is absent")
    path.mkdir(mode=0o700)
    if os.name == "posix" and stat.S_IMODE(path.stat().st_mode) != 0o700:
        raise RunnerIncomplete("new CI directory mode is not 0700")


def parse_findmnt_observation(payload: bytes) -> dict[str, object]:
    try:
        value = json.loads(payload.decode("utf-8", errors="strict"))
        rows = value["filesystems"]
        if not isinstance(rows, list) or len(rows) != 1:
            raise RunnerIncomplete("findmnt returned an ambiguous lane")
        row = rows[0]
        options = frozenset(str(row["options"]).split(","))
        observation = {
            "target": str(row["target"]),
            "source": str(row["source"]),
            "filesystemRoot": str(row["fsroot"]),
            "filesystemType": str(row["fstype"]),
            "filesystemUuid": str(row["uuid"]),
            "options": sorted(options),
            "propagation": str(row["propagation"]),
        }
    except (
        KeyError,
        TypeError,
        ValueError,
        UnicodeDecodeError,
        json.JSONDecodeError,
    ) as error:
        raise RunnerIncomplete("findmnt returned an invalid observation") from error
    required_options = {"rw", "nosuid", "nodev"}
    if observation["target"] != str(VISIBLE_LANE_ROOT):
        raise RunnerIncomplete("lane mount target differs from the fixed contract")
    if observation["filesystemRoot"] != EXPECTED_FILESYSTEM_ROOT:
        raise RunnerIncomplete("lane bind source differs from the fixed contract")
    if observation["filesystemType"] != EXPECTED_FILESYSTEM_TYPE:
        raise RunnerIncomplete("lane filesystem is not ext4")
    if observation["filesystemUuid"] != EXPECTED_FILESYSTEM_UUID:
        raise RunnerIncomplete("lane filesystem UUID differs from the fixed contract")
    if not required_options.issubset(options):
        raise RunnerIncomplete("lane mount lacks rw,nosuid,nodev")
    if "noexec" in options:
        raise RunnerIncomplete("lane mount unexpectedly has noexec")
    if observation["propagation"] not in {"private", "unbindable"}:
        raise RunnerIncomplete("lane mount propagation is not isolated")
    return observation


def observe_production_lane() -> dict[str, object]:
    completed = subprocess.run(
        (
            "/usr/bin/findmnt",
            "--json",
            "--target",
            str(VISIBLE_LANE_ROOT),
            "--output",
            "SOURCE,TARGET,FSTYPE,FSROOT,OPTIONS,PROPAGATION,UUID",
        ),
        check=False,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        env={
            "PATH": "/usr/bin:/bin",
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
        },
    )
    if completed.returncode != 0:
        raise RunnerIncomplete("findmnt could not resolve the fixed lane")
    return parse_findmnt_observation(completed.stdout)


def require_production_principal(root: Path) -> tuple[int, int]:
    if os.name != "posix":
        raise RunnerIncomplete("production lane requires a POSIX runner")
    import pwd

    principal = pwd.getpwnam(SERVICE_ACCOUNT)
    if (
        os.geteuid() != principal.pw_uid
        or os.getegid() != principal.pw_gid
        or any(group != principal.pw_gid for group in os.getgroups())
    ):
        raise RunnerIncomplete("runner principal is not the fixed service account")
    metadata = root.stat(follow_symlinks=False)
    if (
        lstat_kind(root) != "directory"
        or metadata.st_uid != principal.pw_uid
        or metadata.st_gid != principal.pw_gid
        or stat.S_IMODE(metadata.st_mode) != 0o700
    ):
        raise RunnerIncomplete("lane root ownership or mode differs")
    return principal.pw_uid, principal.pw_gid


def require_no_nested_mounts(root: Path) -> None:
    mount_info = Path("/proc/self/mountinfo")
    if not mount_info.is_file():
        raise RunnerIncomplete("mountinfo is unavailable")
    root_text = str(root)
    for line in mount_info.read_text(encoding="utf-8").splitlines():
        fields = line.split()
        if len(fields) < 5:
            raise RunnerIncomplete("mountinfo contains a malformed row")
        mount_point = (
            fields[4]
            .replace("\\040", " ")
            .replace("\\011", "\t")
            .replace("\\012", "\n")
            .replace("\\134", "\\")
        )
        if mount_point == root_text:
            continue
        try:
            Path(mount_point).relative_to(root)
        except ValueError:
            continue
        raise RunnerIncomplete("lane contains a nested mount")


def require_owned_lane_tree(root: Path, uid: int, gid: int) -> None:
    root_device = root.stat(follow_symlinks=False).st_dev
    stack = [root]
    while stack:
        current = stack.pop()
        metadata = current.lstat()
        if metadata.st_dev != root_device:
            raise RunnerIncomplete("lane tree crosses a device or nested mount")
        if metadata.st_uid != uid or metadata.st_gid != gid:
            raise RunnerIncomplete("lane descendant ownership differs")
        mode = stat.S_IMODE(metadata.st_mode)
        if stat.S_ISDIR(metadata.st_mode):
            if mode != 0o700:
                raise RunnerIncomplete("lane directory mode is not 0700")
            with os.scandir(current) as entries:
                stack.extend(Path(entry.path) for entry in entries)
        elif stat.S_ISREG(metadata.st_mode):
            if metadata.st_nlink != 1:
                raise RunnerIncomplete(
                    "lane file has an unexpected hard-link count"
                )
            if mode not in {0o600, 0o700}:
                raise RunnerIncomplete("lane file mode is not private")
        elif stat.S_ISLNK(metadata.st_mode):
            raise RunnerIncomplete("lane tree contains a symlink")
        else:
            raise RunnerIncomplete("lane tree contains a special entry")


def initialize_layout(
    root: Path | None = None,
) -> tuple[Layout, dict[str, object]]:
    production = root is None
    chosen_root = (default_ci_root() if production else root).absolute()
    assert chosen_root is not None
    if production:
        expected = default_ci_root().absolute()
        if chosen_root != expected:
            raise RunnerIncomplete("CI root does not equal the fixed lane root")
        if not chosen_root.exists() or chosen_root.is_symlink():
            raise RunnerIncomplete("fixed lane root is absent or is a symlink")
        require_no_symlink_chain(chosen_root, Path("/srv/codex-ci"))
        uid, gid = require_production_principal(chosen_root)
        mount = observe_production_lane()
        require_no_nested_mounts(chosen_root)
        require_owned_lane_tree(chosen_root, uid, gid)
    else:
        if not chosen_root.exists() or chosen_root.is_symlink():
            raise RunnerIncomplete("injected test lane root is absent or unsafe")
        require_no_symlink_chain(chosen_root, chosen_root)
        ensure_private_directory(chosen_root, create=False)
        metadata = chosen_root.stat(follow_symlinks=False)
        uid, gid = metadata.st_uid, metadata.st_gid
        mount = {
            "target": str(chosen_root),
            "source": "test-injected",
            "filesystemRoot": "test-injected",
            "filesystemType": "test",
            "filesystemUuid": "test",
            "options": ["nodev", "nosuid", "rw"],
            "propagation": "private",
        }

    if (
        tree_size(chosen_root) + RETENTION_METADATA_RESERVE_BYTES
        > RETENTION_LIMIT_BYTES
    ):
        raise RunnerIncomplete("CI root cannot admit fixed layout metadata")
    layout = Layout.under(chosen_root)
    for path in (
        layout.workspaces,
        layout.locks,
        layout.results,
        layout.content.parent,
        layout.content,
        layout.ambiguity,
    ):
        ensure_private_directory(path)
    if production:
        require_owned_lane_tree(chosen_root, uid, gid)
    return (
        layout,
        {
            "visibleRoot": str(chosen_root),
            "serviceAccount": SERVICE_ACCOUNT,
            "serviceUnit": SERVICE_UNIT,
            "ownerUid": uid,
            "ownerGid": gid,
            "mount": mount,
            "infrastructureRepository": C2_INFRASTRUCTURE_REPOSITORY,
            "infrastructureCommit": C2_INFRASTRUCTURE_COMMIT,
            "infrastructureTree": C2_INFRASTRUCTURE_TREE,
        },
    )


def tree_size(path: Path) -> int:
    if not path.exists() and not path.is_symlink():
        return 0
    total = 0
    stack = [path]
    root_device = path.stat(follow_symlinks=False).st_dev
    while stack:
        current = stack.pop()
        metadata = current.lstat()
        if metadata.st_dev != root_device:
            raise RunnerIncomplete("CI tree crosses a device or nested mount")
        if stat.S_ISLNK(metadata.st_mode):
            raise RunnerIncomplete("CI tree contains a symlink")
        if not (
            stat.S_ISDIR(metadata.st_mode)
            or stat.S_ISREG(metadata.st_mode)
        ):
            raise RunnerIncomplete("CI tree contains a special entry")
        if stat.S_ISREG(metadata.st_mode) and metadata.st_nlink != 1:
            raise RunnerIncomplete("CI tree file has an unexpected hard-link count")
        total += metadata.st_size
        if stat.S_ISDIR(metadata.st_mode):
            with os.scandir(current) as entries:
                for entry in entries:
                    stack.append(Path(entry.path))
    return total


def require_limits(layout: Layout, workspace: Path | None = None) -> tuple[int, int]:
    workspace_bytes = tree_size(workspace) if workspace is not None else 0
    root_bytes = tree_size(layout.root)
    if workspace_bytes > WORKSPACE_LIMIT_BYTES:
        raise RunnerIncomplete("operation workspace exceeds the 2 GiB limit")
    if root_bytes > RETENTION_LIMIT_BYTES:
        raise RunnerIncomplete("CI retention root exceeds the 10 GiB limit")
    return workspace_bytes, root_bytes


def normalize_private_tree(path: Path) -> None:
    """Normalize an operation subtree to the lane's private mode contract."""

    root_metadata = path.stat(follow_symlinks=False)
    root_device = root_metadata.st_dev
    stack = [path]
    while stack:
        current = stack.pop()
        metadata = current.lstat()
        if metadata.st_dev != root_device:
            raise RunnerIncomplete("operation tree crosses a device")
        if stat.S_ISLNK(metadata.st_mode):
            raise RunnerIncomplete("operation tree contains a symlink")
        if stat.S_ISDIR(metadata.st_mode):
            if os.name == "posix":
                os.chmod(current, 0o700)
            with os.scandir(current) as entries:
                stack.extend(Path(entry.path) for entry in entries)
            continue
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            raise RunnerIncomplete(
                "operation tree contains a special or multi-link file"
            )
        if os.name == "posix":
            executable = bool(
                metadata.st_mode
                & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
            )
            os.chmod(current, 0o700 if executable else 0o600)


def atomic_write_json(path: Path, value: object, mode: int = 0o600) -> str:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if path.exists() and lstat_kind(path) != "file":
        raise RunnerIncomplete("JSON destination is not an ordinary file")
    payload = canonical_json(value)
    temporary = path.parent / f".{path.name}.tmp-{uuid.uuid4()}"
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    try:
        with os.fdopen(descriptor, "wb", closefd=True) as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        if os.name == "posix":
            os.chmod(path, mode)
    finally:
        with contextlib.suppress(FileNotFoundError):
            temporary.unlink()
    return sha256_bytes(payload)


class ExclusiveFileLock:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.stream: Any = None

    def __enter__(self) -> "ExclusiveFileLock":
        if self.stream is not None:
            return self
        self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.stream = self.path.open("a+b")
        if os.name == "posix":
            os.chmod(self.path, 0o600)
            import fcntl

            try:
                fcntl.flock(self.stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                self.stream.close()
                self.stream = None
                raise RunnerBusy("another writer holds the idempotency lock") from error
        elif os.name == "nt":
            import msvcrt

            try:
                self.stream.seek(0)
                if self.stream.read(1) == b"":
                    self.stream.write(b"\0")
                    self.stream.flush()
                self.stream.seek(0)
                msvcrt.locking(self.stream.fileno(), msvcrt.LK_NBLCK, 1)
            except OSError as error:
                self.stream.close()
                self.stream = None
                raise RunnerBusy("another writer holds the idempotency lock") from error
        else:
            self.stream.close()
            self.stream = None
            raise RunnerIncomplete("unsupported file-lock platform")
        return self

    def __exit__(self, exc_type: object, exc: object, traceback: object) -> None:
        if self.stream is None:
            return
        if os.name == "posix":
            import fcntl

            fcntl.flock(self.stream.fileno(), fcntl.LOCK_UN)
        elif os.name == "nt":
            import msvcrt

            self.stream.seek(0)
            with contextlib.suppress(OSError):
                msvcrt.locking(self.stream.fileno(), msvcrt.LK_UNLCK, 1)
        self.stream.close()
        self.stream = None


_LOCAL_CAPACITY_LOCK = threading.RLock()


class LaneCapacityLock:
    """Serialize lane writes without creating a sixth persistent path class."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self.descriptor: int | None = None
        self.local_held = False

    def __enter__(self) -> "LaneCapacityLock":
        if self.descriptor is not None or self.local_held:
            return self
        if os.name == "posix":
            import fcntl

            flags = os.O_RDONLY
            if hasattr(os, "O_DIRECTORY"):
                flags |= os.O_DIRECTORY
            if hasattr(os, "O_NOFOLLOW"):
                flags |= os.O_NOFOLLOW
            self.descriptor = os.open(self.root, flags)
            try:
                fcntl.flock(self.descriptor, fcntl.LOCK_EX)
            except Exception:
                os.close(self.descriptor)
                self.descriptor = None
                raise
        else:
            _LOCAL_CAPACITY_LOCK.acquire()
            self.local_held = True
        return self

    def __exit__(self, exc_type: object, exc: object, traceback: object) -> None:
        if os.name == "posix":
            import fcntl

            assert self.descriptor is not None
            fcntl.flock(self.descriptor, fcntl.LOCK_UN)
            os.close(self.descriptor)
            self.descriptor = None
        else:
            _LOCAL_CAPACITY_LOCK.release()
            self.local_held = False


class ContentStore:
    def __init__(self, layout: Layout, temporary_root: Path) -> None:
        self.layout = layout
        self.temporary_root = temporary_root
        self.published_bytes = 0

    def path_for(self, digest: str) -> Path:
        if not SHA256.fullmatch(digest):
            raise RunnerError("invalid content digest")
        return self.layout.content / digest[:2] / digest

    def relative_path(self, digest: str) -> str:
        return f"content/sha256/{digest[:2]}/{digest}"

    def verify_existing(self, path: Path, digest: str, size: int) -> None:
        if lstat_kind(path) != "file":
            raise RunnerIncomplete("content object is not an ordinary file")
        metadata = path.stat(follow_symlinks=False)
        if (
            metadata.st_nlink != 1
            or metadata.st_size != size
            or sha256_file(path) != digest
        ):
            raise RunnerIncomplete("content-addressed object is corrupt")
        if os.name == "posix" and stat.S_IMODE(metadata.st_mode) != 0o600:
            raise RunnerIncomplete("content-addressed object mode is not 0600")

    def publish_file(self, source: Path) -> tuple[dict[str, object], bool]:
        if lstat_kind(source) != "file":
            raise RunnerIncomplete("content source is not an ordinary file")
        if source.stat(follow_symlinks=False).st_nlink != 1:
            raise RunnerIncomplete("content source has an unexpected hard-link count")
        size = source.stat().st_size
        digest = sha256_file(source)
        target = self.path_for(digest)
        if target.exists() or target.is_symlink():
            self.verify_existing(target, digest, size)
            return (
                {
                    "sha256": digest,
                    "bytes": size,
                    "contentPath": self.relative_path(digest),
                },
                False,
            )
        root_bytes = tree_size(self.layout.root)
        if (
            root_bytes + size + RETENTION_METADATA_RESERVE_BYTES
            > RETENTION_LIMIT_BYTES
        ):
            raise RunnerIncomplete(
                "content publication would exceed the retention limit"
            )
        ensure_private_directory(target.parent)
        temporary = target.parent / f".publish-{uuid.uuid4()}.tmp"
        try:
            descriptor = os.open(
                temporary,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                0o600,
            )
            with os.fdopen(descriptor, "wb", closefd=True) as output:
                with source.open("rb") as input_stream:
                    shutil.copyfileobj(input_stream, output, 1024 * 1024)
                output.flush()
                os.fsync(output.fileno())
            if temporary.stat().st_size != size or sha256_file(temporary) != digest:
                raise RunnerIncomplete("content staging copy changed")
            try:
                os.link(temporary, target)
            except FileExistsError:
                self.verify_existing(target, digest, size)
                return (
                    {
                        "sha256": digest,
                        "bytes": size,
                        "contentPath": self.relative_path(digest),
                    },
                    False,
                )
            finally:
                with contextlib.suppress(FileNotFoundError):
                    temporary.unlink()
            if os.name == "posix":
                os.chmod(target, 0o600)
            self.verify_existing(target, digest, size)
            if target.stat(follow_symlinks=False).st_nlink != 1:
                raise RunnerIncomplete("published content has an unexpected link count")
        finally:
            with contextlib.suppress(FileNotFoundError):
                temporary.unlink()
        self.published_bytes += size
        return (
            {
                "sha256": digest,
                "bytes": size,
                "contentPath": self.relative_path(digest),
            },
            True,
        )

    def publish_bytes(self, value: bytes, label: str) -> dict[str, object]:
        if not value or len(value) > MAX_LOG_BYTES:
            raise RunnerIncomplete("content log is empty or exceeds 16 MiB")
        staging = self.temporary_root / "content-staging"
        staging.mkdir(mode=0o700, exist_ok=True)
        temporary = staging / f"{label}-{uuid.uuid4()}.tmp"
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            with os.fdopen(descriptor, "wb", closefd=True) as stream:
                stream.write(value)
                stream.flush()
                os.fsync(stream.fileno())
            reference, _created = self.publish_file(temporary)
            return reference
        finally:
            with contextlib.suppress(FileNotFoundError):
                temporary.unlink()


def sanitized_environment(venv_bin: Path | None = None, git_path: Path | None = None) -> dict[str, str]:
    path_entries: list[str] = []
    if venv_bin is not None:
        path_entries.append(str(venv_bin))
    if git_path is not None:
        path_entries.append(str(git_path.parent))
    path_entries.extend(("/usr/bin", "/bin"))
    return {
        "PATH": os.pathsep.join(dict.fromkeys(path_entries)),
        "HOME": "/nonexistent",
        "LANG": "C.UTF-8",
        "LC_ALL": "C.UTF-8",
        "PYTHONDONTWRITEBYTECODE": "1",
        "PYTHONNOUSERSITE": "1",
        "PIP_CONFIG_FILE": "/dev/null",
        "PIP_DISABLE_PIP_VERSION_CHECK": "1",
        "PIP_NO_INPUT": "1",
        "PIP_REQUIRE_VIRTUALENV": "1",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_ASKPASS": "",
        "GITHUB_EVENT_NAME": "push",
        "GITHUB_BASE_REF": "",
    }


def run_command(
    arguments: Sequence[str],
    *,
    cwd: Path,
    environment: dict[str, str],
    timeout_seconds: int,
) -> CommandResult:
    started = time.monotonic()
    process = subprocess.Popen(
        list(arguments),
        cwd=cwd,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    chunks: list[bytes] = []
    size = 0
    overflow = False

    def read_output() -> None:
        nonlocal size, overflow
        assert process.stdout is not None
        while True:
            try:
                chunk = process.stdout.read(64 * 1024)
            except (OSError, ValueError):
                return
            if not chunk:
                return
            if size + len(chunk) > MAX_LOG_BYTES:
                remaining = max(0, MAX_LOG_BYTES - size)
                if remaining:
                    chunks.append(chunk[:remaining])
                    size += remaining
                overflow = True
                with contextlib.suppress(ProcessLookupError):
                    process.terminate()
                return
            chunks.append(chunk)
            size += len(chunk)

    reader = threading.Thread(target=read_output, daemon=True)
    reader.start()
    timed_out = False
    try:
        process.wait(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        timed_out = True
        with contextlib.suppress(ProcessLookupError):
            process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            with contextlib.suppress(ProcessLookupError):
                process.kill()
            process.wait(timeout=5)
    prefix = canonical_json({"command": list(arguments)})
    suffix = b""
    if timed_out:
        suffix += b"\nrunner: command timed out\n"
    if overflow:
        suffix += b"\nrunner: command output exceeded the fixed limit\n"
    reader.join(timeout=5)
    if reader.is_alive():
        overflow = True
        suffix += b"\nrunner: output reader did not stop cleanly\n"
    if process.stdout is not None:
        process.stdout.close()
    reader.join(timeout=1)
    body = b"".join(chunks)
    body_limit = MAX_LOG_BYTES - len(prefix) - len(suffix)
    if body_limit < 0:
        raise RunnerIncomplete("command metadata exceeds the log limit")
    if len(body) > body_limit:
        body = body[:body_limit]
        overflow = True
        if b"output exceeded" not in suffix:
            suffix += b"\nrunner: command output exceeded the fixed limit\n"
            body_limit = MAX_LOG_BYTES - len(prefix) - len(suffix)
            body = body[: max(0, body_limit)]
    output = prefix + body + suffix
    return CommandResult(
        arguments=list(arguments),
        exit_code=process.returncode,
        duration_milliseconds=int((time.monotonic() - started) * 1000),
        output=output,
        timed_out=timed_out,
        output_overflow=overflow,
    )


def run_small(
    arguments: Sequence[str],
    *,
    cwd: Path,
    environment: dict[str, str],
    timeout_seconds: int = 60,
    text: bool = True,
) -> str | bytes:
    completed = subprocess.run(
        list(arguments),
        cwd=cwd,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout_seconds,
        check=False,
    )
    if completed.returncode != 0:
        error = completed.stderr.decode("utf-8", errors="replace")[-512:]
        raise RunnerIncomplete(f"closed command failed: {error}")
    if len(completed.stdout) > 4 * 1024 * 1024:
        raise RunnerIncomplete("closed command returned oversized output")
    if text:
        return completed.stdout.decode("utf-8", errors="strict").strip()
    return completed.stdout


def locate_git() -> Path:
    candidate = shutil.which("git", path=os.environ.get("PATH"))
    if not candidate:
        raise RunnerIncomplete("git is unavailable")
    path = Path(candidate).resolve()
    if not path.is_file() or path.is_symlink():
        raise RunnerIncomplete("git executable is not an ordinary file")
    return path


def validate_runner_host(wheel_lock: dict[str, object]) -> dict[str, str]:
    python = wheel_lock["python"]
    assert isinstance(python, dict)
    actual_path = Path(sys.executable).resolve()
    if not actual_path.is_file() or actual_path.is_symlink():
        raise RunnerIncomplete("runner Python is not an ordinary executable")
    if platform.system() != python["operatingSystem"]:
        raise RunnerIncomplete("runner operating system does not match the wheel lock")
    if platform.machine() != python["architecture"]:
        raise RunnerIncomplete("runner architecture does not match the wheel lock")
    if platform.python_implementation() != python["implementation"]:
        raise RunnerIncomplete("runner Python implementation does not match the wheel lock")
    if platform.python_version() != python["version"]:
        raise RunnerIncomplete("runner Python version does not match the wheel lock")
    return {
        "operatingSystem": platform.system(),
        "architecture": platform.machine(),
        "pythonImplementation": platform.python_implementation(),
        "pythonVersion": platform.python_version(),
        "pythonAbi": str(python["abi"]),
        "pythonExecutableSha256": sha256_file(actual_path),
    }


def git_snapshot(
    git: Path,
    repository: Path,
    environment: dict[str, str],
) -> tuple[str, str, bool]:
    commit = str(
        run_small(
            (str(git), "rev-parse", "HEAD"),
            cwd=repository,
            environment=environment,
        )
    )
    tree = str(
        run_small(
            (str(git), "rev-parse", "HEAD^{tree}"),
            cwd=repository,
            environment=environment,
        )
    )
    status = str(
        run_small(
            (str(git), "status", "--porcelain=v1", "--untracked-files=all"),
            cwd=repository,
            environment=environment,
        )
    )
    return commit, tree, status == ""


def inspect_tree_entries(
    git: Path,
    repository: Path,
    commit_sha: str,
    environment: dict[str, str],
) -> None:
    raw = run_small(
        (str(git), "ls-tree", "-r", "-z", "--full-tree", commit_sha),
        cwd=repository,
        environment=environment,
        text=False,
    )
    assert isinstance(raw, bytes)
    for entry in raw.split(b"\0"):
        if not entry:
            continue
        metadata, raw_path = entry.split(b"\t", 1)
        mode, object_type, _object_id = metadata.decode("ascii").split(" ")
        path_text = raw_path.decode("utf-8", errors="strict")
        if mode == "160000" or object_type == "commit":
            raise RunnerIncomplete("candidate contains a submodule")
        if mode == "120000":
            raise RunnerIncomplete("candidate contains a tracked symlink")
        if path_text == ".gitmodules":
            raise RunnerIncomplete("candidate contains submodule configuration")


def verify_no_lfs_pointers(
    git: Path,
    repository: Path,
    environment: dict[str, str],
) -> None:
    raw = run_small(
        (str(git), "ls-files", "-z"),
        cwd=repository,
        environment=environment,
        text=False,
    )
    assert isinstance(raw, bytes)
    for item in raw.split(b"\0"):
        if not item:
            continue
        relative = item.decode("utf-8", errors="strict")
        path = repository / relative
        if lstat_kind(path) != "file":
            raise RunnerIncomplete("tracked candidate path is not an ordinary file")
        with path.open("rb") as stream:
            prefix = stream.read(256)
        if prefix.startswith(b"version https://git-lfs.github.com/spec/v1"):
            raise RunnerIncomplete("candidate contains a Git LFS pointer")


def checkout_candidate(
    request: Request,
    source_bundle: Path,
    workspace: Path,
    git: Path,
    environment: dict[str, str],
    store: ContentStore,
    log_entries: list[dict[str, object]],
) -> tuple[Path, dict[str, object]]:
    repository = workspace / "repository"
    if repository.exists() or repository.is_symlink():
        raise RunnerIncomplete("operation repository path already exists")
    if lstat_kind(source_bundle) != "file":
        raise RunnerIncomplete("source bundle is not an ordinary file")
    bundle_metadata = source_bundle.stat(follow_symlinks=False)
    if bundle_metadata.st_nlink != 1:
        raise RunnerIncomplete("source bundle has an unexpected hard-link count")
    if sha256_file(source_bundle) != request.source_bundle_sha256:
        raise RunnerIncomplete("source bundle SHA-256 differs from the request")
    repository.mkdir(mode=0o700)
    run_small(
        (str(git), "init", "--quiet"),
        cwd=repository,
        environment=environment,
    )
    verify = run_command(
        (
            str(git),
            "bundle",
            "verify",
            str(source_bundle),
        ),
        cwd=repository,
        environment=environment,
        timeout_seconds=BUNDLE_TIMEOUT_SECONDS,
    )
    verify_ref = store.publish_bytes(verify.output, "bundle-verify")
    log_entries.append(
        {"id": "bundle-verify", "category": "bootstrap", **verify_ref}
    )
    if verify.timed_out or verify.output_overflow or verify.exit_code != 0:
        raise RunnerIncomplete("source bundle verification did not complete")
    advertised = str(
        run_small(
            (str(git), "bundle", "list-heads", str(source_bundle)),
            cwd=workspace,
            environment=environment,
        )
    ).splitlines()
    advertised_commits = [
        row.split(maxsplit=1)[0]
        for row in advertised
        if row and not row.startswith("-")
    ]
    if advertised_commits != [request.commit_sha]:
        raise RunnerIncomplete(
            "source bundle does not advertise exactly the requested commit"
        )
    fetch = run_command(
        (
            str(git),
            "-c",
            "protocol.file.allow=always",
            "fetch",
            "--quiet",
            "--no-tags",
            str(source_bundle),
            request.commit_sha,
        ),
        cwd=repository,
        environment=environment,
        timeout_seconds=BUNDLE_TIMEOUT_SECONDS,
    )
    fetch_ref = store.publish_bytes(fetch.output, "bundle-fetch")
    log_entries.append(
        {"id": "bundle-fetch", "category": "bootstrap", **fetch_ref}
    )
    if fetch.timed_out or fetch.output_overflow or fetch.exit_code != 0:
        raise RunnerIncomplete("source bundle fetch did not complete")
    require_limits(store.layout, workspace)
    missing = str(
        run_small(
            (
                str(git),
                "rev-list",
                "--objects",
                request.commit_sha,
                "--missing=print",
            ),
            cwd=repository,
            environment=environment,
        )
    )
    if any(row.startswith("?") for row in missing.splitlines()):
        raise RunnerIncomplete("source bundle lacks complete reachable history")
    run_small(
        (str(git), "cat-file", "-e", f"{request.commit_sha}^{{commit}}"),
        cwd=repository,
        environment=environment,
    )
    requested_tree = str(
        run_small(
            (str(git), "rev-parse", f"{request.commit_sha}^{{tree}}"),
            cwd=repository,
            environment=environment,
        )
    )
    if requested_tree != request.tree_sha:
        raise RunnerIncomplete("requested commit does not have the requested tree")
    inspect_tree_entries(git, repository, request.commit_sha, environment)
    run_small(
        (str(git), "config", "core.filemode", "false"),
        cwd=repository,
        environment=environment,
    )
    run_small(
        (str(git), "checkout", "--detach", "--force", request.commit_sha),
        cwd=repository,
        environment=environment,
        timeout_seconds=120,
    )
    verify_no_lfs_pointers(git, repository, environment)
    normalize_private_tree(repository)
    before_commit, before_tree, clean_before = git_snapshot(
        git, repository, environment
    )
    if (
        before_commit != request.commit_sha
        or before_tree != request.tree_sha
        or not clean_before
    ):
        raise RunnerIncomplete("detached candidate identity is not exact and clean")
    candidate_runner = repository / "scripts" / "run_hyperv_static_linux.py"
    if sha256_file(candidate_runner) != sha256_file(Path(__file__).resolve()):
        raise RunnerIncomplete("bootstrap runner bytes differ from the requested commit")
    return (
        repository,
        {
            "identity": REPOSITORY_IDENTITY,
            "repositoryId": request.repository_id,
            "sourceBundleSha256": request.source_bundle_sha256,
            "requestedCommitSha": request.commit_sha,
            "requestedTreeSha": request.tree_sha,
            "beforeCommitSha": before_commit,
            "beforeTreeSha": before_tree,
            "afterCommitSha": before_commit,
            "afterTreeSha": before_tree,
            "detachedHead": True,
            "fullHistory": True,
            "cleanBefore": True,
            "cleanAfter": True,
            "submodules": 0,
            "symlinks": 0,
            "lfsPointers": 0,
        },
    )


def load_wheel_lock(repository: Path) -> tuple[dict[str, Any], Path]:
    path = (
        repository
        / "contracts"
        / "ci"
        / "hyperv-static-linux-wheel-lock.v1.json"
    )
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RunnerIncomplete("wheel lock is not an object")
    if (
        value.get("schemaVersion") != 1
        or value.get("suiteId") != SUITE_ID
        or value.get("suiteContractVersion") != SUITE_CONTRACT_VERSION
    ):
        raise RunnerIncomplete("wheel lock identity is invalid")
    if value.get("python") != {
        "implementation": "CPython",
        "version": "3.12.10",
        "abi": "cp312",
        "operatingSystem": "Linux",
        "architecture": "x86_64",
    }:
        raise RunnerIncomplete("wheel lock Python identity is not frozen")
    requirements_path = repository / str(value.get("requirementsFile"))
    requirements_sha = sha256_file(requirements_path)
    if requirements_sha != value.get("requirementsSha256"):
        raise RunnerIncomplete("requirements-dev.txt does not match the wheel lock")
    requirement_rows: dict[str, str] = {}
    for line in requirements_path.read_text(encoding="utf-8").splitlines():
        if not re.fullmatch(r"[A-Za-z0-9_.-]+==[A-Za-z0-9_.+-]+", line):
            raise RunnerIncomplete("requirements-dev.txt contains a non-exact pin")
        name, version = line.split("==", 1)
        normalized = canonical_package_name(name)
        if normalized in requirement_rows:
            raise RunnerIncomplete("requirements-dev.txt has a duplicate package")
        requirement_rows[normalized] = version
    packages = value.get("packages")
    if not isinstance(packages, list) or len(packages) != 7:
        raise RunnerIncomplete("wheel lock must contain exactly seven packages")
    locked_rows: dict[str, str] = {}
    filenames: set[str] = set()
    for package in packages:
        if not isinstance(package, dict):
            raise RunnerIncomplete("wheel lock package is not an object")
        name = str(package.get("name", ""))
        version = str(package.get("version", ""))
        filename = str(package.get("filename", ""))
        size = package.get("bytes")
        digest = str(package.get("sha256", ""))
        url = str(package.get("url", ""))
        normalized = canonical_package_name(name)
        if normalized in locked_rows or filename in filenames:
            raise RunnerIncomplete("wheel lock contains a duplicate")
        locked_rows[normalized] = version
        filenames.add(filename)
        if (
            not filename.endswith(".whl")
            or not isinstance(size, int)
            or not 0 < size <= MAX_WHEEL_BYTES
            or not SHA256.fullmatch(digest)
        ):
            raise RunnerIncomplete("wheel lock contains invalid file identity")
        if not (
            filename.endswith("-py3-none-any.whl")
            or (
                "cp312-cp312" in filename
                and (
                    "manylinux_2_17_x86_64" in filename
                    or "manylinux2014_x86_64" in filename
                )
            )
        ):
            raise RunnerIncomplete("wheel lock contains an incompatible wheel tag")
        parsed = urlsplit(url)
        if (
            parsed.scheme != "https"
            or parsed.hostname != "files.pythonhosted.org"
            or Path(parsed.path).name != filename
            or parsed.query
            or parsed.fragment
        ):
            raise RunnerIncomplete("wheel URL is outside the fixed origin policy")
    if requirement_rows != locked_rows:
        raise RunnerIncomplete("wheel lock does not equal requirements-dev.txt")
    origin_policy = value.get("originPolicy")
    if not isinstance(origin_policy, dict) or origin_policy != {
        "metadataOrigin": "https://pypi.org",
        "wheelOrigin": "https://files.pythonhosted.org",
        "allowRedirects": False,
        "allowSourceDistributions": False,
        "allowDependencyResolution": False,
    }:
        raise RunnerIncomplete("wheel origin policy is not closed")
    return value, path


def materialize_wheels(
    wheel_lock: dict[str, Any],
    prepared_wheels: Mapping[str, Path],
    workspace: Path,
    store: ContentStore,
) -> list[dict[str, object]]:
    wheels = workspace / "wheels"
    wheels.mkdir(mode=0o700)
    expected_digests = {
        str(package["sha256"]) for package in wheel_lock["packages"]
    }
    if not set(prepared_wheels).issubset(expected_digests):
        raise RunnerIncomplete("prepared wheel inputs contain an unknown digest")
    records: list[dict[str, object]] = []
    for package in wheel_lock["packages"]:
        filename = str(package["filename"])
        expected_size = int(package["bytes"])
        expected_digest = str(package["sha256"])
        destination = wheels / filename
        content_path = store.path_for(expected_digest)
        source = "prepared-input"
        if content_path.exists() or content_path.is_symlink():
            store.verify_existing(content_path, expected_digest, expected_size)
            with content_path.open("rb") as input_stream:
                descriptor = os.open(
                    destination,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                    0o600,
                )
                with os.fdopen(descriptor, "wb", closefd=True) as output:
                    shutil.copyfileobj(input_stream, output, 1024 * 1024)
                    output.flush()
                    os.fsync(output.fileno())
            source = "content-cache"
        else:
            prepared = prepared_wheels.get(expected_digest)
            if prepared is None:
                raise RunnerIncomplete(
                    "verified wheel bytes are absent from the prepared inputs"
                )
            if lstat_kind(prepared) != "file":
                raise RunnerIncomplete("prepared wheel is not an ordinary file")
            prepared_metadata = prepared.stat(follow_symlinks=False)
            if (
                prepared_metadata.st_nlink != 1
                or prepared_metadata.st_size != expected_size
                or sha256_file(prepared) != expected_digest
            ):
                raise RunnerIncomplete(
                    "prepared wheel bytes differ from the committed lock"
                )
            descriptor = os.open(
                destination,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                0o600,
            )
            with os.fdopen(descriptor, "wb", closefd=True) as output:
                with prepared.open("rb") as input_stream:
                    shutil.copyfileobj(input_stream, output, 1024 * 1024)
                output.flush()
                os.fsync(output.fileno())
            reference, _created = store.publish_file(destination)
            if reference["sha256"] != expected_digest:
                raise RunnerIncomplete("published wheel digest differs")
        destination_metadata = destination.stat(follow_symlinks=False)
        if (
            destination_metadata.st_nlink != 1
            or destination_metadata.st_size != expected_size
            or sha256_file(destination) != expected_digest
        ):
            raise RunnerIncomplete("materialized wheel digest differs")
        records.append(
            {
                "filename": filename,
                "bytes": expected_size,
                "sha256": expected_digest,
                "source": source,
                "contentPath": store.relative_path(expected_digest),
            }
        )
        require_limits(store.layout, workspace)
    return records


def venv_executable(venv: Path) -> Path:
    if os.name == "nt":
        return venv / "Scripts" / "python.exe"
    return venv / "bin" / "python"


def remove_known_venv_aliases(venv: Path) -> None:
    """Remove only CPython's known internal lib64 alias.

    The lane contract forbids symlink descendants. CPython may create
    ``venv/lib64 -> lib`` even when executable copies were requested. The
    alias is not needed by this suite and is removed only after its exact
    in-venv target is verified. Any other symlink remains a hard failure.
    """

    alias = venv / "lib64"
    if not alias.is_symlink():
        return
    target = os.readlink(alias)
    if target != "lib":
        raise RunnerIncomplete("operation venv has an unexpected lib64 alias")
    alias.unlink()


def create_dependency_environment(
    repository: Path,
    workspace: Path,
    git: Path,
    wheel_lock: dict[str, Any],
    wheel_lock_path: Path,
    prepared_wheels: Mapping[str, Path],
    store: ContentStore,
    log_entries: list[dict[str, object]],
) -> tuple[Path, dict[str, object]]:
    wheel_objects = materialize_wheels(
        wheel_lock,
        prepared_wheels,
        workspace,
        store,
    )
    venv = workspace / "venv"
    if venv.exists() or venv.is_symlink():
        raise RunnerIncomplete("operation venv path already exists")
    environment = sanitized_environment(git_path=git)
    create = run_command(
        (sys.executable, "-I", "-m", "venv", "--copies", str(venv)),
        cwd=workspace,
        environment=environment,
        timeout_seconds=VENV_TIMEOUT_SECONDS,
    )
    create_ref = store.publish_bytes(create.output, "venv-create")
    log_entries.append(
        {"id": "venv-create", "category": "dependency", **create_ref}
    )
    if create.timed_out or create.output_overflow or create.exit_code != 0:
        raise RunnerIncomplete("operation venv creation failed")
    remove_known_venv_aliases(venv)
    normalize_private_tree(venv)
    require_limits(store.layout, workspace)
    python = venv_executable(venv)
    if lstat_kind(python) != "file":
        raise RunnerIncomplete("operation venv Python is not an ordinary file")
    requirements = workspace / "wheel-requirements.txt"
    lines = [
        f"./wheels/{package['filename']} --hash=sha256:{package['sha256']}"
        for package in wheel_lock["packages"]
    ]
    requirement_payload = ("\n".join(lines) + "\n").encode("utf-8")
    descriptor = os.open(
        requirements,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL,
        0o600,
    )
    with os.fdopen(descriptor, "wb", closefd=True) as stream:
        stream.write(requirement_payload)
        stream.flush()
        os.fsync(stream.fileno())
    pip_environment = sanitized_environment(venv_bin=python.parent, git_path=git)
    install = run_command(
        (
            str(python),
            "-I",
            "-m",
            "pip",
            "install",
            "--no-index",
            "--only-binary=:all:",
            "--require-hashes",
            "--no-deps",
            "--no-compile",
            "--no-input",
            "--disable-pip-version-check",
            "--requirement",
            requirements.name,
        ),
        cwd=workspace,
        environment=pip_environment,
        timeout_seconds=VENV_TIMEOUT_SECONDS,
    )
    install_ref = store.publish_bytes(install.output, "venv-install")
    log_entries.append(
        {"id": "venv-install", "category": "dependency", **install_ref}
    )
    if install.timed_out or install.output_overflow or install.exit_code != 0:
        raise RunnerIncomplete("hash-locked wheel installation failed")
    normalize_private_tree(venv)
    require_limits(store.layout, workspace)
    raw_inventory = str(
        run_small(
            (str(python), "-I", "-c", INVENTORY_LAUNCHER),
            cwd=workspace,
            environment=pip_environment,
        )
    )
    installed_rows = json.loads(raw_inventory)
    if not isinstance(installed_rows, list):
        raise RunnerIncomplete("installed dependency inventory is invalid")
    normalized_installed = {
        canonical_package_name(str(name)): str(version)
        for name, version in installed_rows
    }
    expected = {
        canonical_package_name(str(item["name"])): str(item["version"])
        for item in wheel_lock["packages"]
    }
    pip_version = normalized_installed.pop("pip", None)
    if not pip_version or normalized_installed != expected:
        raise RunnerIncomplete("installed dependency inventory differs from the lock")
    packages = [
        {"name": name, "version": expected[name]}
        for name in sorted(expected)
    ]
    inventory_sha = sha256_bytes(canonical_json(packages))
    return (
        python,
        {
            "wheelLockSha256": sha256_file(wheel_lock_path),
            "requirementsSha256": str(wheel_lock["requirementsSha256"]),
            "inventorySha256": inventory_sha,
            "pipVersion": pip_version,
            "packages": packages,
            "wheelObjects": wheel_objects,
        },
    )


def parse_reported_metrics(output: bytes) -> tuple[dict[str, object], int]:
    text = output.decode("utf-8", errors="replace")
    metrics: dict[str, object] = {}
    for line in reversed(text.splitlines()):
        try:
            candidate = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(candidate, dict):
            metrics = candidate
            break
    match = re.search(r"\bRan ([0-9]+) tests?\b", text)
    reported = int(match.group(1)) if match else 1
    if isinstance(metrics.get("assertions"), int):
        reported = max(reported, int(metrics["assertions"]))
    return metrics, reported


def execute_suite_checks(
    repository: Path,
    python: Path,
    git: Path,
    store: ContentStore,
    log_entries: list[dict[str, object]],
) -> list[dict[str, object]]:
    environment = sanitized_environment(venv_bin=python.parent, git_path=git)
    results: list[dict[str, object]] = []
    for check in SUITE_CHECKS:
        script = repository / check.relative_script
        command = (
            str(python),
            "-I",
            "-B",
            "-c",
            TEST_LAUNCHER,
            str(script),
            *check.arguments,
        )
        result = run_command(
            command,
            cwd=repository,
            environment=environment,
            timeout_seconds=TEST_TIMEOUT_SECONDS,
        )
        log_ref = store.publish_bytes(result.output, check.check_id)
        log_entries.append(
            {"id": check.check_id, "category": "check", **log_ref}
        )
        metrics, reported = parse_reported_metrics(result.output)
        if result.timed_out or result.output_overflow:
            status_value = "incomplete"
        elif result.exit_code == 0:
            status_value = "passed"
        else:
            status_value = "failed"
        results.append(
            {
                "id": check.check_id,
                "requiredForSuite": True,
                "status": status_value,
                "command": [
                    "python",
                    "-I",
                    "-B",
                    check.relative_script,
                    *check.arguments,
                ],
                "exitCode": result.exit_code,
                "durationMilliseconds": result.duration_milliseconds,
                "commandAssertions": 1 if status_value != "incomplete" else 0,
                "reportedTestCases": reported,
                "reportedMetrics": metrics,
                "log": log_ref,
                "notPerformedReason": None,
            }
        )
        require_limits(store.layout, store.temporary_root)
    results.append(
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
            "notPerformedReason": (
                "Requires Windows mock-runtime samples and belongs to "
                "hyperv-mock-windows; the Linux static lane does not synthesize them."
            ),
        }
    )
    return results


def calculate_counts(checks: list[dict[str, object]]) -> dict[str, int]:
    statuses = [str(check["status"]) for check in checks]
    return {
        "checks": len(checks),
        "executed": sum(status != "notPerformed" for status in statuses),
        "passed": statuses.count("passed"),
        "failed": statuses.count("failed"),
        "incomplete": statuses.count("incomplete"),
        "notPerformed": statuses.count("notPerformed"),
        "commandAssertions": sum(int(check["commandAssertions"]) for check in checks),
        "reportedTestCases": sum(int(check["reportedTestCases"]) for check in checks),
    }


def derive_static_suite_status(checks: list[dict[str, object]]) -> str:
    required_statuses = [
        str(check["status"])
        for check in checks
        if check.get("requiredForSuite") is True
    ]
    if "failed" in required_statuses:
        return "failed"
    if "incomplete" in required_statuses:
        return "incomplete"
    if len(required_statuses) == len(SUITE_CHECKS) and all(
        status == "passed" for status in required_statuses
    ):
        return "passed"
    raise RunnerIncomplete("required check statuses cannot derive a result")


def safe_remove_tree(path: Path, required_root: Path) -> None:
    path = path.absolute()
    required_root = required_root.absolute()
    try:
        path.relative_to(required_root)
    except ValueError as error:
        raise RunnerIncomplete("cleanup target escapes the operation workspace root") from error
    metadata = path.lstat()
    if not stat.S_ISDIR(metadata.st_mode):
        raise RunnerIncomplete("cleanup target is not an ordinary directory")

    def remove(current: Path) -> None:
        with os.scandir(current) as entries:
            children = [Path(entry.path) for entry in entries]
        for child in children:
            child_metadata = child.lstat()
            if stat.S_ISDIR(child_metadata.st_mode):
                remove(child)
                child.rmdir()
            elif stat.S_ISREG(child_metadata.st_mode) or stat.S_ISLNK(
                child_metadata.st_mode
            ):
                child.unlink()
            else:
                raise RunnerIncomplete("cleanup found an unknown special entry")

    remove(path)
    path.rmdir()


def _cleanup_workspace_after_readback_unlocked(
    layout: Layout,
    operation_id: str,
    idempotency_key: str,
    summary_sha256: str,
) -> dict[str, object]:
    """Remove one exact workspace only after immutable-summary readback."""

    if not OPERATION_ID.fullmatch(operation_id):
        raise RunnerIncomplete("cleanup operation ID is invalid")
    if not SHA256.fullmatch(idempotency_key) or not SHA256.fullmatch(
        summary_sha256
    ):
        raise RunnerIncomplete("cleanup summary identity is invalid")
    summary = layout.results / idempotency_key / "summary.json"
    if (
        not summary.exists()
        or summary.is_symlink()
        or lstat_kind(summary) != "file"
        or sha256_file(summary) != summary_sha256
    ):
        raise RunnerIncomplete("cleanup summary readback differs")
    workspace = layout.workspaces / operation_id
    if (
        not workspace.exists()
        or workspace.is_symlink()
        or lstat_kind(workspace) != "directory"
    ):
        raise RunnerIncomplete("cleanup workspace is not an ordinary directory")
    marker = workspace / ".hci-operation.json"
    if (
        not marker.exists()
        or marker.is_symlink()
        or lstat_kind(marker) != "file"
    ):
        raise RunnerIncomplete("cleanup workspace marker is absent")
    marker_payload = marker.read_bytes()
    marker_value = json.loads(marker_payload.decode("utf-8", errors="strict"))
    if (
        canonical_json(marker_value) != marker_payload
        or marker_value
        != {
            "schemaVersion": 1,
            "operationId": operation_id,
            "idempotencyKey": idempotency_key,
        }
    ):
        raise RunnerIncomplete("cleanup workspace marker differs")
    safe_remove_tree(workspace, layout.workspaces)
    return {
        "workspace": "removed",
        "unknownEntries": 0,
        "symlinksFollowed": 0,
    }


def cleanup_workspace_after_readback(
    layout: Layout,
    operation_id: str,
    idempotency_key: str,
    summary_sha256: str,
) -> dict[str, object]:
    with LaneCapacityLock(layout.root):
        return _cleanup_workspace_after_readback_unlocked(
            layout,
            operation_id,
            idempotency_key,
            summary_sha256,
        )


def verify_content_reference(
    layout: Layout,
    value: object,
    *,
    max_size: int = MAX_LOG_BYTES,
) -> Path:
    if not isinstance(value, dict) or set(value) != {
        "sha256",
        "bytes",
        "contentPath",
    }:
        raise RunnerIncomplete("content reference shape differs")
    digest = value.get("sha256")
    size = value.get("bytes")
    relative = value.get("contentPath")
    if (
        not isinstance(digest, str)
        or not SHA256.fullmatch(digest)
        or type(size) is not int
        or not 0 < size <= max_size
        or relative != f"content/sha256/{digest[:2]}/{digest}"
    ):
        raise RunnerIncomplete("content reference identity differs")
    path = layout.root / str(relative)
    ContentStore(layout, layout.root).verify_existing(path, digest, size)
    return path


def read_existing_summary(
    layout: Layout,
    path: Path,
    request: Request,
    idempotency_key: str,
) -> dict[str, object]:
    if lstat_kind(path) != "file":
        raise RunnerIncomplete("completed summary is not an ordinary file")
    metadata = path.stat(follow_symlinks=False)
    if metadata.st_nlink != 1:
        raise RunnerIncomplete("completed summary has an unexpected link count")
    if os.name == "posix" and stat.S_IMODE(metadata.st_mode) != 0o600:
        raise RunnerIncomplete("completed summary mode is not 0600")
    payload = path.read_bytes()
    value = json.loads(payload.decode("utf-8", errors="strict"))
    if not isinstance(value, dict):
        raise RunnerIncomplete("completed summary is not an object")
    if canonical_json(value) != payload:
        raise RunnerIncomplete("completed summary is not canonical JSON")
    expected_fields = {
        "schemaVersion",
        "requestSchemaVersion",
        "repositoryId",
        "suiteId",
        "suiteContractVersion",
        "status",
        "operationId",
        "idempotencyKey",
        "requestSha256",
        "sourceBundleSha256",
        "runnerImageDigest",
        "startedAtUtc",
        "finishedAtUtc",
        "repository",
        "infrastructure",
        "runner",
        "dependencyClosure",
        "checks",
        "counts",
        "logManifest",
        "relatedSuites",
        "operationCounters",
        "cleanup",
        "ambiguity",
        "diskUsage",
        "warnings",
    }
    if set(value) != expected_fields:
        raise RunnerIncomplete("completed summary fields differ")
    expected = {
        "schemaVersion": SUMMARY_SCHEMA_VERSION,
        "requestSchemaVersion": request.schema_version,
        "repositoryId": request.repository_id,
        "suiteId": SUITE_ID,
        "suiteContractVersion": request.suite_contract_version,
        "idempotencyKey": idempotency_key,
        "sourceBundleSha256": request.source_bundle_sha256,
        "runnerImageDigest": request.runner_image_digest,
    }
    for field, expected_value in expected.items():
        if value.get(field) != expected_value:
            raise RunnerIncomplete("completed summary binding differs")
    if value.get("status") not in {"passed", "failed", "incomplete"}:
        raise RunnerIncomplete("completed summary status is invalid")
    summary_operation = value.get("operationId")
    if not isinstance(summary_operation, str):
        raise RunnerIncomplete("completed summary operation ID is invalid")
    original_request = dataclasses.replace(request, operation_id=summary_operation)
    validate_request(original_request)
    if value.get("requestSha256") != sha256_bytes(
        original_request.canonical_bytes()
    ):
        raise RunnerIncomplete("completed summary request hash differs")
    repository = value.get("repository")
    if not isinstance(repository, dict) or (
        repository.get("requestedCommitSha") != request.commit_sha
        or repository.get("requestedTreeSha") != request.tree_sha
        or repository.get("sourceBundleSha256") != request.source_bundle_sha256
        or repository.get("beforeCommitSha") != request.commit_sha
        or repository.get("beforeTreeSha") != request.tree_sha
        or repository.get("afterCommitSha") != request.commit_sha
        or repository.get("afterTreeSha") != request.tree_sha
        or repository.get("cleanBefore") is not True
        or repository.get("cleanAfter") is not True
    ):
        raise RunnerIncomplete("completed summary source binding differs")
    if value.get("operationCounters") != ZERO_COUNTERS:
        raise RunnerIncomplete("completed summary operation counters are not zero")
    if value.get("relatedSuites") != {
        "hyperv-mock-windows": "notPerformed",
        "hyperv-validation": "notPerformed",
    }:
        raise RunnerIncomplete("completed summary related-suite status differs")
    checks = value.get("checks")
    if not isinstance(checks, list) or len(checks) != len(SUITE_CHECKS) + 1:
        raise RunnerIncomplete("completed summary check inventory differs")
    expected_check_ids = [
        *(check.check_id for check in SUITE_CHECKS),
        "runtime-artifact-schema",
    ]
    if [check.get("id") for check in checks if isinstance(check, dict)] != (
        expected_check_ids
    ):
        raise RunnerIncomplete("completed summary check order differs")
    check_logs: dict[str, dict[str, object]] = {}
    for index, check in enumerate(checks):
        if not isinstance(check, dict):
            raise RunnerIncomplete("completed summary check is invalid")
        if index < len(SUITE_CHECKS):
            if (
                check.get("requiredForSuite") is not True
                or check.get("status") not in {"passed", "failed", "incomplete"}
                or not isinstance(check.get("command"), list)
                or type(check.get("exitCode")) is not int
                or check.get("notPerformedReason") is not None
            ):
                raise RunnerIncomplete(
                    "completed required-check semantics differ"
                )
        elif (
            check.get("requiredForSuite") is not False
            or check.get("status") != "notPerformed"
            or check.get("command") is not None
            or check.get("exitCode") is not None
            or check.get("durationMilliseconds") != 0
            or check.get("commandAssertions") != 0
            or check.get("reportedTestCases") != 0
            or check.get("reportedMetrics") != {}
            or check.get("log") is not None
            or not isinstance(check.get("notPerformedReason"), str)
        ):
            raise RunnerIncomplete(
                "completed Windows-runtime placeholder semantics differ"
            )
        log = check.get("log")
        if log is not None:
            verify_content_reference(layout, log)
            assert isinstance(log, dict)
            check_logs[str(check["id"])] = log
    if value.get("counts") != calculate_counts(checks):
        raise RunnerIncomplete("completed summary counts differ")
    if value.get("status") != derive_static_suite_status(checks):
        raise RunnerIncomplete("completed summary derived status differs")
    dependency = value.get("dependencyClosure")
    if not isinstance(dependency, dict):
        raise RunnerIncomplete("completed summary dependency closure is invalid")
    wheel_objects = dependency.get("wheelObjects")
    if not isinstance(wheel_objects, list) or len(wheel_objects) != 7:
        raise RunnerIncomplete("completed summary wheel inventory differs")
    for wheel in wheel_objects:
        if not isinstance(wheel, dict):
            raise RunnerIncomplete("completed summary wheel record is invalid")
        verify_content_reference(
            layout,
            {
                "sha256": wheel.get("sha256"),
                "bytes": wheel.get("bytes"),
                "contentPath": wheel.get("contentPath"),
            },
            max_size=MAX_WHEEL_BYTES,
        )
    manifest_path = verify_content_reference(layout, value.get("logManifest"))
    manifest_payload = manifest_path.read_bytes()
    manifest = json.loads(manifest_payload.decode("utf-8", errors="strict"))
    if (
        not isinstance(manifest, dict)
        or canonical_json(manifest) != manifest_payload
        or manifest.get("schemaVersion") != 1
        or manifest.get("suiteId") != SUITE_ID
        or manifest.get("operationId") != summary_operation
        or manifest.get("idempotencyKey") != idempotency_key
    ):
        raise RunnerIncomplete("completed log manifest binding differs")
    entries = manifest.get("entries")
    if not isinstance(entries, list) or len(entries) != len(SUITE_CHECKS) + 4:
        raise RunnerIncomplete("completed log manifest inventory differs")
    if [
        (entry.get("id"), entry.get("category"))
        for entry in entries
        if isinstance(entry, dict)
    ] != list(LOG_ENTRY_CONTRACT):
        raise RunnerIncomplete("completed log manifest order differs")
    identifiers: set[str] = set()
    for entry in entries:
        if (
            not isinstance(entry, dict)
            or set(entry)
            != {"id", "category", "sha256", "bytes", "contentPath"}
            or entry.get("category") not in {"bootstrap", "dependency", "check"}
            or not isinstance(entry.get("id"), str)
            or entry["id"] in identifiers
        ):
            raise RunnerIncomplete("completed log manifest entry is invalid")
        identifiers.add(entry["id"])
        verify_content_reference(
            layout,
            {
                "sha256": entry.get("sha256"),
                "bytes": entry.get("bytes"),
                "contentPath": entry.get("contentPath"),
            },
        )
        if entry["category"] == "check":
            expected_log = check_logs.get(str(entry["id"]))
            manifest_log = {
                "sha256": entry.get("sha256"),
                "bytes": entry.get("bytes"),
                "contentPath": entry.get("contentPath"),
            }
            if expected_log != manifest_log:
                raise RunnerIncomplete(
                    "completed check and manifest log references differ"
                )
    return value


def publish_summary(
    layout: Layout,
    idempotency_key: str,
    operation_id: str,
    summary: dict[str, object],
) -> tuple[Path, str]:
    root_bytes = tree_size(layout.root)
    disk_usage = summary.get("diskUsage")
    if not isinstance(disk_usage, dict):
        raise RunnerIncomplete("summary disk usage is absent")
    disk_usage["rootBytesBeforeSummaryPublish"] = root_bytes
    payload = canonical_json(summary)
    if len(payload) > SUMMARY_LIMIT_BYTES:
        raise RunnerIncomplete("summary exceeds the 1 MiB limit")
    if (
        root_bytes + len(payload) + RETENTION_METADATA_RESERVE_BYTES
        > RETENTION_LIMIT_BYTES
    ):
        raise RunnerIncomplete(
            "summary publication would exceed the retention limit"
        )
    final_directory = layout.results / idempotency_key
    final_path = final_directory / "summary.json"
    if final_directory.exists() or final_directory.is_symlink():
        raise RunnerIncomplete("terminal result already exists")
    temporary_directory = layout.results / f".tmp-{operation_id}"
    if temporary_directory.exists() or temporary_directory.is_symlink():
        raise RunnerIncomplete("operation result temporary directory already exists")
    temporary_directory.mkdir(mode=0o700)
    temporary_summary = temporary_directory / "summary.json"
    descriptor = os.open(
        temporary_summary,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL,
        0o600,
    )
    with os.fdopen(descriptor, "wb", closefd=True) as stream:
        stream.write(payload)
        stream.flush()
        os.fsync(stream.fileno())
    if os.name == "posix":
        os.chmod(temporary_summary, 0o600)
        os.chmod(temporary_directory, 0o700)
    try:
        os.rename(temporary_directory, final_directory)
    except FileExistsError:
        raise RunnerIncomplete("completed result appeared during atomic publication")
    return final_path, sha256_bytes(payload)


def ambiguity_state_path(layout: Layout, operation_id: str) -> Path:
    return layout.ambiguity / operation_id / "state.json"


def find_unresolved_ambiguity(
    layout: Layout,
    idempotency_key: str,
) -> dict[str, object] | None:
    for operation_directory in layout.ambiguity.iterdir():
        if lstat_kind(operation_directory) != "directory":
            raise RunnerIncomplete("ambiguity root contains an unknown entry")
        state_path = operation_directory / "state.json"
        if not state_path.exists():
            continue
        if lstat_kind(state_path) != "file":
            raise RunnerIncomplete("ambiguity record is not an ordinary file")
        value = json.loads(state_path.read_text(encoding="utf-8"))
        if (
            isinstance(value, dict)
            and value.get("idempotencyKey") == idempotency_key
            and value.get("status") in {"running", "incomplete"}
        ):
            return value
    return None


def write_ambiguity_state(
    layout: Layout,
    request: Request,
    idempotency_key: str,
    status_value: str,
    *,
    summary_path: str | None = None,
    summary_sha256: str | None = None,
    message: str | None = None,
) -> None:
    directory = layout.ambiguity / request.operation_id
    directory_exists = directory.exists() or directory.is_symlink()
    if directory_exists:
        ensure_private_directory(directory, create=False)
    immutable_identity = {
        "schemaVersion": 1,
        "suiteId": SUITE_ID,
        "operationId": request.operation_id,
        "idempotencyKey": idempotency_key,
        "repositoryId": request.repository_id,
        "commitSha": request.commit_sha,
        "treeSha": request.tree_sha,
        "sourceBundleSha256": request.source_bundle_sha256,
        "suiteContractVersion": request.suite_contract_version,
        "runnerImageDigest": request.runner_image_digest,
        "requestSha256": sha256_bytes(request.canonical_bytes()),
    }
    if status_value == "resolved":
        expected_summary_path = f"results/{idempotency_key}/summary.json"
        summary_file = layout.results / idempotency_key / "summary.json"
        if (
            summary_path != expected_summary_path
            or not isinstance(summary_sha256, str)
            or not SHA256.fullmatch(summary_sha256)
            or not summary_file.exists()
            or summary_file.is_symlink()
            or lstat_kind(summary_file) != "file"
            or sha256_file(summary_file) != summary_sha256
        ):
            raise RunnerIncomplete(
                "resolved ambiguity requires exact summary readback"
            )
    state_path = ambiguity_state_path(layout, request.operation_id)
    if state_path.exists() or state_path.is_symlink():
        if lstat_kind(state_path) != "file":
            raise RunnerIncomplete("existing ambiguity state is not an ordinary file")
        state_metadata = state_path.stat(follow_symlinks=False)
        if state_metadata.st_nlink != 1 or (
            os.name == "posix"
            and stat.S_IMODE(state_metadata.st_mode) != 0o600
        ):
            raise RunnerIncomplete("existing ambiguity state is not private")
        existing_payload = state_path.read_bytes()
        existing = json.loads(existing_payload.decode("utf-8", errors="strict"))
        if (
            not isinstance(existing, dict)
            or canonical_json(existing) != existing_payload
            or any(
                existing.get(field) != expected
                for field, expected in immutable_identity.items()
            )
        ):
            raise RunnerIncomplete("ambiguity identity cannot be overwritten")
        prior_status = existing.get("status")
        allowed_transitions = {
            "running": {"running", "incomplete", "resolved"},
            "incomplete": {"incomplete", "resolved"},
            "resolved": {"resolved"},
        }
        if status_value not in allowed_transitions.get(str(prior_status), set()):
            raise RunnerIncomplete("ambiguity status transition is invalid")
        if prior_status == "resolved" and (
            existing.get("summaryPath") != summary_path
            or existing.get("summarySha256") != summary_sha256
        ):
            raise RunnerIncomplete("resolved ambiguity evidence is immutable")
        if prior_status == "resolved":
            return
    state = {
        **immutable_identity,
        "status": status_value,
        "updatedAtUtc": utc_now(),
        "summaryPath": summary_path,
        "summarySha256": summary_sha256,
        "message": message,
    }
    state_payload = canonical_json(state)
    existing_size = (
        state_path.stat(follow_symlinks=False).st_size
        if state_path.exists()
        else 0
    )
    additional_bytes = max(0, len(state_payload) - existing_size)
    if (
        tree_size(layout.root)
        + additional_bytes
        + RETENTION_METADATA_RESERVE_BYTES
        > RETENTION_LIMIT_BYTES
    ):
        raise RunnerIncomplete(
            "ambiguity publication would exceed the retention limit"
        )
    if not directory_exists:
        ensure_private_directory(directory)
    atomic_write_json(state_path, state)


def initialize_workspace(
    layout: Layout,
    request: Request,
    idempotency_key: str,
) -> Path:
    workspace = layout.workspaces / request.operation_id
    if workspace.exists() or workspace.is_symlink():
        raise RunnerIncomplete("operation workspace already exists")
    workspace.mkdir(mode=0o700)
    marker = workspace / ".hci-operation.json"
    marker_value = {
        "schemaVersion": 1,
        "operationId": request.operation_id,
        "idempotencyKey": idempotency_key,
    }
    if marker.exists():
        raise RunnerIncomplete("operation workspace marker already exists")
    atomic_write_json(marker, marker_value)
    return workspace


def bounded_message(error: BaseException) -> str:
    message = str(error).replace("\r", " ").replace("\n", " ").strip()
    return message[:512] or error.__class__.__name__


def exit_code_for_status(status_value: object) -> int:
    if status_value == "passed":
        return 0
    if status_value == "failed":
        return 1
    return 2


def run_once(
    request: Request,
    prepared_inputs: PreparedInputs,
    *,
    root: Path | None = None,
) -> tuple[dict[str, object], int]:
    validate_request(request)
    idempotency_key = compute_idempotency_key(request)
    layout, infrastructure = initialize_layout(root)
    result_path = layout.results / idempotency_key / "summary.json"
    lock_path = layout.locks / f"{idempotency_key}.lock"
    capacity_context = LaneCapacityLock(layout.root)
    capacity_context.__enter__()
    if (
        not result_path.exists()
        and tree_size(layout.root) + OPERATION_RETENTION_RESERVE_BYTES
        > RETENTION_LIMIT_BYTES
    ):
        capacity_context.__exit__(None, None, None)
        return (
            {
                "suiteId": SUITE_ID,
                "operationId": request.operation_id,
                "idempotencyKey": idempotency_key,
                "status": "incomplete",
                "reused": False,
                "summaryPath": None,
                "summarySha256": None,
                "message": (
                    "retention capacity cannot admit one bounded operation"
                ),
            },
            2,
        )
    try:
        lock_context = ExclusiveFileLock(lock_path)
        lock_context.__enter__()
    except RunnerBusy:
        capacity_context.__exit__(None, None, None)
        if result_path.exists():
            try:
                summary = read_existing_summary(
                    layout,
                    result_path,
                    request,
                    idempotency_key,
                )
            except Exception as error:
                return (
                    {
                        "suiteId": SUITE_ID,
                        "operationId": request.operation_id,
                        "idempotencyKey": idempotency_key,
                        "status": "incomplete",
                        "reused": False,
                        "summaryPath": None,
                        "summarySha256": None,
                        "message": (
                            "completed result validation failed: "
                            f"{bounded_message(error)}"
                        )[:512],
                    },
                    2,
                )
            return (
                {
                    "suiteId": SUITE_ID,
                    "operationId": request.operation_id,
                    "idempotencyKey": idempotency_key,
                    "status": summary["status"],
                    "reused": True,
                    "summaryPath": (
                        f"results/{idempotency_key}/summary.json"
                    ),
                    "summarySha256": sha256_file(result_path),
                },
                exit_code_for_status(summary["status"]),
            )
        return (
            {
                "suiteId": SUITE_ID,
                "operationId": request.operation_id,
                "idempotencyKey": idempotency_key,
                "status": "incomplete",
                "reused": False,
                "summaryPath": None,
                "summarySha256": None,
                "message": "another writer holds the idempotency lock",
            },
            2,
        )
    except Exception:
        capacity_context.__exit__(*sys.exc_info())
        raise

    with capacity_context, lock_context:
        if result_path.exists():
            try:
                summary = read_existing_summary(
                    layout,
                    result_path,
                    request,
                    idempotency_key,
                )
            except Exception as error:
                message = (
                    "completed result validation failed: "
                    f"{bounded_message(error)}"
                )[:512]
                with contextlib.suppress(Exception):
                    write_ambiguity_state(
                        layout,
                        request,
                        idempotency_key,
                        "incomplete",
                        message=message,
                    )
                return (
                    {
                        "suiteId": SUITE_ID,
                        "operationId": request.operation_id,
                        "idempotencyKey": idempotency_key,
                        "status": "incomplete",
                        "reused": False,
                        "summaryPath": None,
                        "summarySha256": None,
                        "message": message,
                    },
                    2,
                )
            return (
                {
                    "suiteId": SUITE_ID,
                    "operationId": request.operation_id,
                    "idempotencyKey": idempotency_key,
                    "status": summary["status"],
                    "reused": True,
                    "summaryPath": f"results/{idempotency_key}/summary.json",
                    "summarySha256": sha256_file(result_path),
                },
                exit_code_for_status(summary["status"]),
            )
        unresolved = find_unresolved_ambiguity(
            layout,
            idempotency_key,
        )
        if unresolved is not None:
            return (
                {
                    "suiteId": SUITE_ID,
                    "operationId": request.operation_id,
                    "idempotencyKey": idempotency_key,
                    "status": "incomplete",
                    "reused": False,
                    "summaryPath": None,
                    "summarySha256": None,
                    "message": "an unresolved earlier operation forbids blind retry",
                },
                2,
            )

        workspace: Path | None = None
        try:
            workspace = initialize_workspace(layout, request, idempotency_key)
            write_ambiguity_state(
                layout,
                request,
                idempotency_key,
                "running",
                message="The exclusive writer is executing.",
            )
            started_at = utc_now()
            log_entries: list[dict[str, object]] = []
            store = ContentStore(layout, workspace)
            git = locate_git()
            base_environment = sanitized_environment(git_path=git)
            git_version = str(
                run_small(
                    (str(git), "--version"),
                    cwd=workspace,
                    environment=base_environment,
                )
            )
            repository, repository_facts = checkout_candidate(
                request,
                prepared_inputs.source_bundle,
                workspace,
                git,
                base_environment,
                store,
                log_entries,
            )
            wheel_lock, wheel_lock_path = load_wheel_lock(repository)
            host_facts = validate_runner_host(wheel_lock)
            python, dependency_closure = create_dependency_environment(
                repository,
                workspace,
                git,
                wheel_lock,
                wheel_lock_path,
                prepared_inputs.wheels_by_sha256,
                store,
                log_entries,
            )
            checks = execute_suite_checks(
                repository,
                python,
                git,
                store,
                log_entries,
            )
            after_commit, after_tree, clean_after = git_snapshot(
                git,
                repository,
                sanitized_environment(venv_bin=python.parent, git_path=git),
            )
            if (
                after_commit != request.commit_sha
                or after_tree != request.tree_sha
                or not clean_after
            ):
                raise RunnerIncomplete("candidate identity or cleanliness changed")
            repository_facts["afterCommitSha"] = after_commit
            repository_facts["afterTreeSha"] = after_tree
            repository_facts["cleanAfter"] = clean_after
            counts = calculate_counts(checks)
            status_value = derive_static_suite_status(checks)

            log_manifest_value = {
                "schemaVersion": 1,
                "suiteId": SUITE_ID,
                "operationId": request.operation_id,
                "idempotencyKey": idempotency_key,
                "entries": log_entries,
            }
            log_manifest = store.publish_bytes(
                canonical_json(log_manifest_value),
                "log-manifest",
            )
            workspace_peak, _root_before_cleanup = require_limits(layout, workspace)
            runner_source_sha = sha256_file(Path(__file__).resolve())
            image_identity = {
                **host_facts,
                "gitVersion": git_version,
                "gitExecutableSha256": sha256_file(git),
                "runnerSourceSha256": runner_source_sha,
                "wheelLockSha256": dependency_closure["wheelLockSha256"],
                "inventorySha256": dependency_closure["inventorySha256"],
            }
            runner_facts = {
                **host_facts,
                "gitVersion": git_version,
                "gitExecutableSha256": sha256_file(git),
                "runnerSourceSha256": runner_source_sha,
                "runnerImageIdentitySha256": sha256_bytes(
                    canonical_json(image_identity)
                ),
                "isolation": "operation-scoped-venv",
            }
            cleanup = {
                "workspace": "retained",
                "unknownEntries": 0,
                "symlinksFollowed": 0,
            }
            normalize_private_tree(workspace)
            root_before_summary = tree_size(layout.root)
            if root_before_summary > RETENTION_LIMIT_BYTES:
                raise RunnerIncomplete("retention limit exceeded before summary publish")
            summary = {
                "schemaVersion": SUMMARY_SCHEMA_VERSION,
                "requestSchemaVersion": request.schema_version,
                "repositoryId": request.repository_id,
                "suiteId": SUITE_ID,
                "suiteContractVersion": SUITE_CONTRACT_VERSION,
                "status": status_value,
                "operationId": request.operation_id,
                "idempotencyKey": idempotency_key,
                "requestSha256": sha256_bytes(request.canonical_bytes()),
                "sourceBundleSha256": request.source_bundle_sha256,
                "runnerImageDigest": request.runner_image_digest,
                "startedAtUtc": started_at,
                "finishedAtUtc": utc_now(),
                "repository": repository_facts,
                "infrastructure": infrastructure,
                "runner": runner_facts,
                "dependencyClosure": dependency_closure,
                "checks": checks,
                "counts": counts,
                "logManifest": log_manifest,
                "relatedSuites": {
                    "hyperv-mock-windows": "notPerformed",
                    "hyperv-validation": "notPerformed",
                },
                "operationCounters": dict(ZERO_COUNTERS),
                "cleanup": cleanup,
                "ambiguity": {
                    "status": "resolved",
                    "statePath": (
                        f"ambiguity/{request.operation_id}/state.json"
                    ),
                    "blindRetries": 0,
                },
                "diskUsage": {
                    "workspacePeakBytes": workspace_peak,
                    "publishedContentBytes": store.published_bytes,
                    "rootBytesBeforeSummaryPublish": root_before_summary,
                    "workspaceLimitBytes": WORKSPACE_LIMIT_BYTES,
                    "retentionLimitBytes": RETENTION_LIMIT_BYTES,
                },
                "warnings": [
                    (
                        "Linux static validation does not execute Windows "
                        "PowerShell, mock runtime, real Hyper-V, guest, "
                        "portable, WebDriver, or UI operations."
                    )
                ],
            }
            summary_path, summary_sha = publish_summary(
                layout,
                idempotency_key,
                request.operation_id,
                summary,
            )
            relative_summary = f"results/{idempotency_key}/summary.json"
            write_ambiguity_state(
                layout,
                request,
                idempotency_key,
                "resolved",
                summary_path=relative_summary,
                summary_sha256=summary_sha,
                message="The immutable summary resolved this operation.",
            )
            return (
                {
                    "suiteId": SUITE_ID,
                    "operationId": request.operation_id,
                    "idempotencyKey": idempotency_key,
                    "status": status_value,
                    "reused": False,
                    "summaryPath": relative_summary,
                    "summarySha256": summary_sha,
                },
                exit_code_for_status(status_value),
            )
        except Exception as error:
            message = bounded_message(error)
            with contextlib.suppress(Exception):
                write_ambiguity_state(
                    layout,
                    request,
                    idempotency_key,
                    "incomplete",
                    message=message,
                )
            return (
                {
                    "suiteId": SUITE_ID,
                    "operationId": request.operation_id,
                    "idempotencyKey": idempotency_key,
                    "status": "incomplete",
                    "reused": False,
                    "summaryPath": None,
                    "summarySha256": None,
                    "message": message,
                },
                2,
            )


REQUEST_FIELDS = frozenset(
    {
        "schemaVersion",
        "operationId",
        "repositoryId",
        "commitSha",
        "treeSha",
        "suiteId",
        "suiteContractVersion",
        "sourceBundleSha256",
        "runnerImageDigest",
    }
)


def closed_json_object(
    pairs: Iterable[tuple[str, object]],
) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise RunnerError(f"duplicate request key: {key}")
        result[key] = value
    return result


def parse_request_json(payload: bytes) -> Request:
    if not 0 < len(payload) <= 16 * 1024:
        raise RunnerError("request size is outside the fixed bound")
    try:
        value = json.loads(
            payload.decode("utf-8", errors="strict"),
            object_pairs_hook=closed_json_object,
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RunnerError("request is not strict UTF-8 JSON") from error
    if not isinstance(value, dict) or frozenset(value) != REQUEST_FIELDS:
        raise RunnerError("request fields do not match the closed contract")
    if type(value["schemaVersion"]) is not int:
        raise RunnerError("request schema version must be an integer")
    if type(value["suiteContractVersion"]) is not int:
        raise RunnerError("suite contract version must be an integer")
    for field in (
        "operationId",
        "repositoryId",
        "commitSha",
        "treeSha",
        "suiteId",
        "sourceBundleSha256",
        "runnerImageDigest",
    ):
        if type(value[field]) is not str:
            raise RunnerError("request identity fields must be strings")
    request = Request(
        schema_version=value["schemaVersion"],
        operation_id=value["operationId"],
        repository_id=value["repositoryId"],
        commit_sha=value["commitSha"],
        tree_sha=value["treeSha"],
        suite_id=value["suiteId"],
        suite_contract_version=value["suiteContractVersion"],
        source_bundle_sha256=value["sourceBundleSha256"],
        runner_image_digest=value["runnerImageDigest"],
    )
    validate_request(request)
    if request.canonical_bytes() != canonical_json(value):
        raise RunnerError("request is not canonically representable")
    return request


def main(argv: Sequence[str] | None = None) -> int:
    del argv
    receipt = {
        "schemaVersion": 1,
        "suiteId": SUITE_ID,
        "status": "incomplete",
        "controllerAdapter": "notPerformed",
        "remoteProof": "notPerformed",
        "message": (
            "The path-independent HCI1 core is not a remote entrypoint. "
            "A future infrastructure runner-integration gate must supply "
            "the fixed request, source, dependency, dispatch, timeout, and "
            "publication adapter."
        ),
    }
    print(canonical_json(receipt).decode("utf-8"), end="")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())

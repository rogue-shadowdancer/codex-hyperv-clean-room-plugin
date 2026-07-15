from __future__ import annotations

import json
import hashlib
import re
import os
import subprocess
from pathlib import Path, PurePosixPath


REPO_ROOT = Path(__file__).resolve().parents[1]
MAX_SCANNED_BLOB_BYTES = 2 * 1024 * 1024
ACCEPTED_LEGACY_COMMIT_SHA256 = {
    "45193ddc75ba108b468a9bab180cfab9ae31620224817906420578cf6a3db0e1",
    "5f9aeac3283df11ffe1918c33d16434d8e6a834f63a9b64e70dd7083f8a5ea3a",
    "69bcfba21b8fcb68d1e4d8914631190eb3195c52bc160789c940f685dcd4795e",
    "8194ee43dea44e54e32776669d29928548e9b3de99291eb847a5a285dd363f31",
    "adb05c896fd6b201ca2c08b26abe89f3e5a4677ea507c4543c81b3c0814981c5",
    "d323ea912a0bf3805b875262206e7ef9c8141adfb554954a70339da2c7dc48bc",
    "b592529dc22c8b52289899035d1658d67fbc8eec5b57f0d50b0e13a5b7f3e55d",
    "3ffce4f4af707fc3fc3ad137962571fe19d14b28d3c394356fab3fec1e582f07",
}
PUBLIC_COMMIT_NAME = "rogue-shadowdancer"
PUBLIC_COMMIT_EMAIL = "78423508+rogue-shadowdancer@users.noreply.github.com"
GITHUB_WEB_FLOW_COMMITTER = ("GitHub", "noreply" + "@github.com")
GITHUB_MERGE_MESSAGE = re.compile(
    rb"Merge pull request #[1-9][0-9]* from "
    rb"rogue-shadowdancer/codex/(?P<branch>[A-Za-z0-9][A-Za-z0-9._/-]{0,199})"
    rb"\n\n[^\r\n]{1,256}\n?"
)
PARENT_HEADER = re.compile(rb"^parent ([0-9a-f]{40})$", re.MULTILINE)
FORBIDDEN_SUFFIXES = {
    ".avhd",
    ".avhdx",
    ".clixml",
    ".iso",
    ".log",
    ".vhd",
    ".vhdx",
    ".vmcx",
    ".vmgs",
    ".vmrs",
    ".vsv",
}
FORBIDDEN_PARTS = {
    ".artifacts",
    ".cache",
    ".state",
    "artifacts",
    "cache",
    "caches",
    "checkpoint",
    "checkpoints",
    "credentials",
    "evidence",
    "install-state",
    "installed-copy",
    "installed-state",
    "log",
    "logs",
    "plans",
    "vm",
    "vm-state",
    "vms",
}
FORBIDDEN_FILENAMES = {"evidence.json", "inventory.json"}
FORBIDDEN_CONTROL_FILES = {
    ".codex-plugin/install-manifest.json",
    ".codex-plugin/install-ownership.json",
}
SECRET_KEYS = {"password", "passwd", "secret"}
SAFE_SECRET_LITERALS = {
    "",
    "null",
    "none",
    "~",
    "redacted",
    "<redacted>",
    "[redacted]",
    "***redacted***",
}
KNOWN_SAFE_TEST_LITERALS = {
    ("tests/gate2-runtime.tests.ps1", "password", "must-not-be-accepted"),
}
SECRET_REFERENCE_PATTERNS = (
    re.compile(r"\$\{[A-Za-z_][A-Za-z0-9_]*\}"),
    re.compile(r"\$env:[A-Za-z_][A-Za-z0-9_]*", re.IGNORECASE),
    re.compile(r"\$[A-Za-z_][A-Za-z0-9_]*"),
    re.compile(r"%[A-Za-z_][A-Za-z0-9_]*%"),
    re.compile(r"\{\{[^{}]+\}\}"),
    re.compile(r"(?:env|secret|vault):(?://)?[A-Za-z_][A-Za-z0-9_./-]*", re.IGNORECASE),
    re.compile(r"!env\s+.+", re.IGNORECASE),
    re.compile(r"process\.env\.[A-Za-z_][A-Za-z0-9_]*", re.IGNORECASE),
    re.compile(r"os\.environ\[['\"][A-Za-z_][A-Za-z0-9_]*['\"]\]", re.IGNORECASE),
    re.compile(r"(?:read-host|get-credential)", re.IGNORECASE),
)
ASSIGNMENT_PATTERN = re.compile(
    r"^\s*\$?(?P<key>password|passwd|secret)\s*=\s*(?P<value>.*?)\s*$",
    re.IGNORECASE,
)
YAML_SECRET_PATTERN = re.compile(
    r"^\s*(?P<quote>['\"]?)(?P<key>password|passwd|secret)(?P=quote)"
    r"\s*:\s*(?P<value>.*?)\s*$",
    re.IGNORECASE,
)
UNIVERSAL_PATTERNS = (
    (re.compile(rb"-----BEGIN [A-Z ]+ PRIVATE KEY-----"), "private key"),
    (re.compile(rb"\bgh[pousr]_[A-Za-z0-9]{20,}\b"), "GitHub token"),
    (re.compile(rb"\bgithub_pat_[A-Za-z0-9_]{20,}\b"), "GitHub token"),
    (re.compile(rb"\bAKIA[0-9A-Z]{16}\b"), "AWS access key"),
    (re.compile(rb"\bsk-[A-Za-z0-9_-]{20,}\b"), "API key"),
    (re.compile(rb"(?i)\b[A-Z]:\\Users\\[^\\\s]+"), "absolute user path"),
    (re.compile(rb"(?i)\b[A-Z]:\\study\\"), "workspace-specific path"),
    (re.compile(rb"(?i)/(?:Users|home)/[^/\s]+"), "absolute user path"),
    (
        re.compile(rb"(?i)https?://[^/:\s]+:[^@\s/]+@"),
        "credentialed URL",
    ),
)
EMAIL_PATTERN = re.compile(
    rb"(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"
)
MOJIBAKE_MARKERS = ("\ufffd", "\u00c3", "\u00c2", "\u9225", "\u951b", "\u9286")
OTHER_LITERAL_PATTERNS = (
    (re.compile(rb"(?i)\bBearer\s+[A-Za-z0-9._~-]{12,}"), "bearer token"),
    (
        re.compile(
            rb"(?i)\bconfirmationToken\s*[:=]\s*['\"][^'\"\r\n]{8,}['\"]"
        ),
        "restore confirmation token",
    ),
)
HANDOFF_PROJECT_PATH = re.compile(
    rb"^`projectPath: [A-Za-z]:\\[^`\r\n]+`$", re.MULTILINE
)


def git_bytes(*arguments: str) -> bytes:
    completed = subprocess.run(
        ["git", "-C", str(REPO_ROOT), *arguments],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return completed.stdout


def decode_path(raw: bytes) -> str:
    return raw.decode("utf-8", errors="strict").replace("\\", "/")


def assert_publishable_path(path_text: str, context: str) -> None:
    normalized = path_text.replace("\\", "/")
    path = PurePosixPath(normalized)
    folded_parts = {part.casefold() for part in path.parts}
    if "birdsgone" in folded_parts:
        raise AssertionError(f"Birdsgone path is publishable in {context}: {normalized}")
    if folded_parts.intersection(FORBIDDEN_PARTS):
        raise AssertionError(f"machine-state path is publishable in {context}: {normalized}")
    if path.suffix.casefold() in FORBIDDEN_SUFFIXES:
        raise AssertionError(f"forbidden artifact is publishable in {context}: {normalized}")
    if path.name.casefold() in FORBIDDEN_FILENAMES:
        raise AssertionError(f"evidence state is publishable in {context}: {normalized}")
    folded = normalized.casefold()
    if any(folded.endswith(name) for name in FORBIDDEN_CONTROL_FILES):
        raise AssertionError(f"installed control file is publishable in {context}: {normalized}")


def is_safe_secret_literal(value: str) -> bool:
    normalized = value.strip()
    folded = normalized.casefold()
    if folded in SAFE_SECRET_LITERALS or re.fullmatch(r"\*{3,}", normalized):
        return True
    return any(pattern.fullmatch(normalized) for pattern in SECRET_REFERENCE_PATTERNS)


def quoted_literal(expression: str) -> str | None:
    candidate = expression.strip()
    if len(candidate) < 2 or candidate[0] not in {'"', "'"}:
        return None
    quote = candidate[0]
    escaped = False
    for index in range(1, len(candidate)):
        character = candidate[index]
        if escaped:
            escaped = False
            continue
        if character == "\\":
            escaped = True
            continue
        if character != quote:
            continue
        remainder = candidate[index + 1 :].strip()
        if remainder and not re.fullmatch(r"[,;]?(?:\s*(?:#|//).*)?", remainder):
            return None
        return candidate[1:index]
    return None


def assignment_literal(expression: str) -> str | None:
    quoted = quoted_literal(expression)
    if quoted is not None:
        return quoted
    candidate = re.split(r"\s+(?:#|//)", expression.strip(), maxsplit=1)[0]
    candidate = candidate.rstrip(";, ")
    if not candidate or not re.fullmatch(r"[^\s,;#]+", candidate):
        return None
    return candidate


def yaml_literal(expression: str) -> str | None:
    quoted = quoted_literal(expression)
    if quoted is not None:
        return quoted
    candidate = re.split(r"\s+#", expression.strip(), maxsplit=1)[0].strip()
    return candidate or None


def assert_secret_literal_safe(
    path_text: str, key: str, literal: str, context: str
) -> None:
    known_safe = (
        path_text.replace("\\", "/").casefold(),
        key.casefold(),
        literal.casefold(),
    ) in KNOWN_SAFE_TEST_LITERALS
    if not known_safe and not is_safe_secret_literal(literal):
        raise AssertionError(
            f"plaintext {key} literal found in {context}: {path_text}"
        )


def scan_json_secret_literals(path_text: str, text: str, context: str) -> None:
    try:
        value = json.loads(text)
    except json.JSONDecodeError as error:
        raise AssertionError(f"invalid JSON in {context}: {path_text}") from error

    def visit(item: object) -> None:
        if isinstance(item, dict):
            for key, child in item.items():
                if isinstance(key, str) and key.casefold() in SECRET_KEYS:
                    if isinstance(child, (str, int, float, bool)):
                        assert_secret_literal_safe(
                            path_text, key, str(child), context
                        )
                visit(child)
        elif isinstance(item, list):
            for child in item:
                visit(child)

    visit(value)


def scan_structured_secret_literals(path_text: str, text: str, context: str) -> None:
    suffix = PurePosixPath(path_text).suffix.casefold()
    if suffix == ".json":
        scan_json_secret_literals(path_text, text, context)

    for line in text.splitlines():
        assignment = ASSIGNMENT_PATTERN.fullmatch(line)
        if assignment:
            literal = assignment_literal(assignment.group("value"))
            if literal is not None:
                assert_secret_literal_safe(
                    path_text, assignment.group("key"), literal, context
                )
        if suffix in {".yaml", ".yml"}:
            yaml_match = YAML_SECRET_PATTERN.fullmatch(line)
            if yaml_match:
                literal = yaml_literal(yaml_match.group("value"))
                if literal is not None:
                    assert_secret_literal_safe(
                        path_text, yaml_match.group("key"), literal, context
                    )


def mask_handoff_project_path(path_text: str, content: bytes) -> bytes:
    if PurePosixPath(path_text).as_posix() != "TASK_HANDOFF.md":
        return content
    matches = list(HANDOFF_PROJECT_PATH.finditer(content))
    if len(matches) > 1:
        raise AssertionError(
            f"multiple projectPath contract fields found in publication content: {path_text}"
        )
    return HANDOFF_PROJECT_PATH.sub(b"`projectPath: <workspace-root>`", content)


def scan_content(path_text: str, content: bytes, context: str) -> None:
    if len(content) > MAX_SCANNED_BLOB_BYTES:
        raise AssertionError(
            f"oversized repository blob cannot be publication-scanned in {context}: "
            f"{path_text} ({len(content)} bytes)"
        )
    if b"\x00" in content:
        raise AssertionError(f"unexpected binary repository blob in {context}: {path_text}")
    try:
        text = content.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise AssertionError(
            f"repository blob is not strict UTF-8 in {context}: {path_text}"
        ) from error
    if content.startswith(b"\xef\xbb\xbf"):
        raise AssertionError(f"UTF-8 BOM found in {context}: {path_text}")
    for marker in MOJIBAKE_MARKERS:
        if marker in text:
            raise AssertionError(
                f"mojibake marker found in {context}: {path_text}"
            )

    policy_content = mask_handoff_project_path(path_text, content)
    for pattern, label in UNIVERSAL_PATTERNS:
        candidate_content = (
            policy_content
            if label in {"absolute user path", "workspace-specific path"}
            else content
        )
        if pattern.search(candidate_content):
            raise AssertionError(f"{label} found in {context}: {path_text}")
    for pattern, label in OTHER_LITERAL_PATTERNS:
        if pattern.search(content):
            raise AssertionError(f"{label} found in {context}: {path_text}")
    for match in EMAIL_PATTERN.finditer(content):
        email = match.group(0).decode("ascii")
        if email.casefold() != PUBLIC_COMMIT_EMAIL.casefold():
            raise AssertionError(
                f"non-public email found in {context}: {path_text}"
            )
    scan_structured_secret_literals(path_text, text, context)


def current_files() -> list[str]:
    raw = git_bytes("ls-files", "-z", "--cached", "--others", "--exclude-standard")
    return sorted(decode_path(item) for item in raw.split(b"\0") if item)


def select_history_revision(event_name: str, base_ref: str) -> str:
    if event_name == "pull_request":
        if (
            not base_ref
            or not re.fullmatch(r"[A-Za-z0-9._/-]+", base_ref)
            or base_ref.startswith(("/", "-"))
            or ".." in base_ref
        ):
            raise AssertionError("pull_request history scan has an unsafe base ref")
        return f"origin/{base_ref}"
    return "HEAD"


def history_commits(revision: str) -> list[str]:
    return [
        line
        for line in git_bytes("rev-list", revision).decode("ascii").splitlines()
        if line
    ]


def history_tree(commit: str) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    raw = git_bytes("ls-tree", "-r", "-z", "--full-tree", commit)
    for item in raw.split(b"\0"):
        if not item:
            continue
        metadata, raw_path = item.split(b"\t", 1)
        _mode, object_type, object_id = metadata.decode("ascii").split(" ")
        if object_type == "blob":
            rows.append((object_id, decode_path(raw_path)))
    return rows


def commit_identity(header: bytes, field: bytes) -> tuple[str, str]:
    prefix = field + b" "
    rows = [line for line in header.splitlines() if line.startswith(prefix)]
    if len(rows) != 1:
        raise AssertionError(f"commit has an invalid {field.decode()} header")
    match = re.fullmatch(
        rb"[^ ]+ (?P<name>.+) <(?P<email>[^<>\s]+)> (?P<time>[0-9]+) [+-][0-9]{4}",
        rows[0],
    )
    if not match:
        raise AssertionError(f"commit has an unparsable {field.decode()} header")
    return (
        match.group("name").decode("utf-8", errors="strict"),
        match.group("email").decode("ascii", errors="strict"),
    )


def is_safe_github_web_flow_merge(
    header: bytes,
    message: bytes,
    author: tuple[str, str],
    committer: tuple[str, str],
) -> bool:
    if author[1].casefold() != PUBLIC_COMMIT_EMAIL.casefold():
        return False
    if committer != GITHUB_WEB_FLOW_COMMITTER:
        return False
    parents = PARENT_HEADER.findall(header)
    if len(parents) != 2 or parents[0] == parents[1]:
        return False
    if b"gpgsig -----BEGIN PGP SIGNATURE-----\n" not in header:
        return False
    if b"\n -----END PGP SIGNATURE-----" not in header:
        return False
    match = GITHUB_MERGE_MESSAGE.fullmatch(message)
    if not match:
        return False
    branch = match.group("branch").decode("ascii")
    if ".." in branch or "//" in branch or branch.endswith(("/", ".")):
        return False
    return True


def assert_commit_metadata_safe(commit: str, raw: bytes) -> str:
    try:
        header, message = raw.split(b"\n\n", 1)
    except ValueError as error:
        raise AssertionError(f"commit object is malformed: {commit}") from error
    author = commit_identity(header, b"author")
    committer = commit_identity(header, b"committer")
    raw_sha256 = hashlib.sha256(raw).hexdigest()
    if raw_sha256 in ACCEPTED_LEGACY_COMMIT_SHA256:
        identity_class = "accepted-legacy-sha256"
    else:
        expected = (PUBLIC_COMMIT_NAME, PUBLIC_COMMIT_EMAIL)
        if author == expected and committer == expected:
            identity_class = "public-noreply"
        elif is_safe_github_web_flow_merge(header, message, author, committer):
            identity_class = "github-web-flow-merge"
        else:
            raise AssertionError(
                f"unexpected author/committer identity in history commit {commit}"
            )
    scan_content(
        f"commit-message-{commit}.txt",
        message,
        f"history commit message {commit}",
    )
    return identity_class


def main() -> int:
    current = current_files()
    for path_text in current:
        assert_publishable_path(path_text, "prospective working tree")
        scan_content(
            path_text,
            (REPO_ROOT / Path(path_text)).read_bytes(),
            "prospective working tree",
        )

    history_revision = select_history_revision(
        os.environ.get("GITHUB_EVENT_NAME", ""),
        os.environ.get("GITHUB_BASE_REF", ""),
    )
    git_bytes("rev-parse", "--verify", f"{history_revision}^{{commit}}")
    commits = history_commits(history_revision)
    accepted_legacy_digests: set[str] = set()
    public_identity_commits = 0
    github_web_flow_merge_commits = 0
    seen_blob_paths: set[tuple[str, str]] = set()
    blob_cache: dict[str, bytes] = {}
    for commit in commits:
        raw_commit = git_bytes("cat-file", "commit", commit)
        identity_class = assert_commit_metadata_safe(commit, raw_commit)
        if identity_class == "accepted-legacy-sha256":
            accepted_legacy_digests.add(hashlib.sha256(raw_commit).hexdigest())
        elif identity_class == "github-web-flow-merge":
            github_web_flow_merge_commits += 1
        else:
            public_identity_commits += 1
        for object_id, path_text in history_tree(commit):
            assert_publishable_path(path_text, f"history commit {commit}")
            key = (object_id, path_text)
            if key in seen_blob_paths:
                continue
            seen_blob_paths.add(key)
            if object_id not in blob_cache:
                blob_cache[object_id] = git_bytes("cat-file", "blob", object_id)
            content = blob_cache[object_id]
            scan_content(path_text, content, f"history blob {object_id}")

    if accepted_legacy_digests != ACCEPTED_LEGACY_COMMIT_SHA256:
        missing = ACCEPTED_LEGACY_COMMIT_SHA256 - accepted_legacy_digests
        unexpected = accepted_legacy_digests - ACCEPTED_LEGACY_COMMIT_SHA256
        raise AssertionError(
            "retained legacy commit SHA-256 allowlist mismatch: "
            f"missing={len(missing)}, unexpected={len(unexpected)}"
        )

    print(
        json.dumps(
            {
                "ok": True,
                "currentFiles": len(current),
                "historyCommits": len(commits),
                "historyRevision": history_revision,
                "historyBlobPaths": len(seen_blob_paths),
                "commitMessagesScanned": len(commits),
                "acceptedLegacyCommits": len(accepted_legacy_digests),
                "publicNoreplyCommits": public_identity_commits,
                "githubWebFlowMergeCommits": github_web_flow_merge_commits,
                "forbiddenArtifacts": 0,
                "sensitiveFindings": 0,
                "strictUtf8": True,
                "bomFiles": 0,
            },
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

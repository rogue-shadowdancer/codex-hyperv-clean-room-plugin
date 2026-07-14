from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path, PurePosixPath


REPO_ROOT = Path(__file__).resolve().parents[1]
MAX_SCANNED_BLOB_BYTES = 2 * 1024 * 1024
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
    "cache",
    "caches",
    "credentials",
    "evidence",
    "plans",
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
)
OTHER_LITERAL_PATTERNS = (
    (re.compile(rb"(?i)\bBearer\s+[A-Za-z0-9._~-]{12,}"), "bearer token"),
    (
        re.compile(
            rb"(?i)\bconfirmationToken\s*[:=]\s*['\"][^'\"\r\n]{8,}['\"]"
        ),
        "restore confirmation token",
    ),
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

    for pattern, label in UNIVERSAL_PATTERNS:
        if pattern.search(content):
            raise AssertionError(f"{label} found in {context}: {path_text}")
    for pattern, label in OTHER_LITERAL_PATTERNS:
        if pattern.search(content):
            raise AssertionError(f"{label} found in {context}: {path_text}")
    scan_structured_secret_literals(path_text, text, context)


def current_files() -> list[str]:
    raw = git_bytes("ls-files", "-z", "--cached", "--others", "--exclude-standard")
    return sorted(decode_path(item) for item in raw.split(b"\0") if item)


def history_commits() -> list[str]:
    return [line for line in git_bytes("rev-list", "--all").decode("ascii").splitlines() if line]


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


def main() -> int:
    current = current_files()
    for path_text in current:
        assert_publishable_path(path_text, "prospective working tree")
        scan_content(
            path_text,
            (REPO_ROOT / Path(path_text)).read_bytes(),
            "prospective working tree",
        )

    commits = history_commits()
    seen_blob_paths: set[tuple[str, str]] = set()
    blob_cache: dict[str, bytes] = {}
    for commit in commits:
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

    print(
        json.dumps(
            {
                "ok": True,
                "currentFiles": len(current),
                "historyCommits": len(commits),
                "historyBlobPaths": len(seen_blob_paths),
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

from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import unquote

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
TEXT_EXTENSIONS = {".json", ".md", ".ps1", ".py", ".yaml", ".yml"}
SKIPPED_PARTS = {".git", ".artifacts", "__pycache__"}
MARKDOWN_LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")


def source_files() -> list[Path]:
    return sorted(
        path
        for path in REPO_ROOT.rglob("*")
        if path.is_file()
        and path.suffix.lower() in TEXT_EXTENSIONS
        and not SKIPPED_PARTS.intersection(path.relative_to(REPO_ROOT).parts)
    )


def read_utf8(path: Path) -> str:
    data = path.read_bytes()
    if data.startswith(b"\xef\xbb\xbf"):
        raise AssertionError(f"UTF-8 BOM is not allowed: {path.relative_to(REPO_ROOT)}")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise AssertionError(
            f"file is not strict UTF-8: {path.relative_to(REPO_ROOT)}: {error}"
        ) from error


def check_markdown(path: Path, text: str) -> int:
    relative = path.relative_to(REPO_ROOT)
    mojibake_markers = (
        chr(0xFFFD),
        chr(0x00C2),
        chr(0x00C3),
        chr(0x9225),
    )
    for marker in mojibake_markers:
        if marker in text:
            raise AssertionError(f"possible mojibake in {relative}")

    for pattern, label in (
        (r"(?i)\bTODO\b", "TODO placeholder"),
        (r"(?i)\bTBD\b", "TBD placeholder"),
        (r"(?i)<(?:sha|commit|hash)>", "placeholder SHA or commit"),
        (r"\b0{40}\b|\b0{64}\b", "all-zero placeholder hash"),
        (r"(?i)(?<![A-Za-z0-9])[A-Z]:[\\/]", "absolute Windows path"),
        (r"(?i)/(?:Users|home)/[^/\s]+", "absolute user path"),
        (r"(?i)\bshado\b", "local username"),
        (r"-----BEGIN [A-Z ]*PRIVATE KEY-----", "private key material"),
        (r"(?i)\bpassword\s*[:=]\s*['\"][^'\"]+", "password value"),
        (
            r"(?i)\bconfirmationToken\s*[:=]\s*['\"][^'\"]+",
            "restore token value",
        ),
        (r"(?i)\bBearer\s+[A-Za-z0-9._~-]+", "bearer token"),
    ):
        if re.search(pattern, text):
            raise AssertionError(f"{label} found in {relative}")

    checked_links = 0
    for match in MARKDOWN_LINK.finditer(text):
        raw_target = match.group(1).strip()
        if raw_target.startswith("<") and raw_target.endswith(">"):
            raw_target = raw_target[1:-1]
        target = raw_target.split(maxsplit=1)[0]
        if not target or target.startswith(("#", "http://", "https://", "mailto:")):
            continue
        target_path_text = unquote(target.split("#", 1)[0])
        target_path = (path.parent / target_path_text).resolve()
        try:
            target_path.relative_to(REPO_ROOT.resolve())
        except ValueError as error:
            raise AssertionError(
                f"local Markdown link escapes repository in {relative}: {target}"
            ) from error
        if not target_path.exists():
            raise AssertionError(
                f"broken local Markdown link in {relative}: {target}"
            )
        checked_links += 1
    return checked_links


def check_sensitive_repository_state(decoded: dict[Path, str]) -> int:
    forbidden_suffixes = {".clixml", ".iso", ".log", ".vhd", ".vhdx"}
    forbidden_artifacts = [
        path.relative_to(REPO_ROOT)
        for path in REPO_ROOT.rglob("*")
        if path.is_file()
        and path.suffix.lower() in forbidden_suffixes
        and not SKIPPED_PARTS.intersection(path.relative_to(REPO_ROOT).parts)
    ]
    if forbidden_artifacts:
        raise AssertionError(
            f"forbidden VM, credential, ISO, or log artifacts found: {forbidden_artifacts}"
        )

    checked = 0
    for path, text in decoded.items():
        relative = path.relative_to(REPO_ROOT)
        if "tests" in relative.parts:
            continue
        for pattern, label in (
            (r"(?i)\b[A-Z]:\\Users\\[^\\\s]+", "absolute user path"),
            (r"(?i)\b[A-Z]:\\study\\", "workspace-specific path"),
            (r"(?i)\bpassword\s*[:=]\s*['\"][^'\"]+", "password value"),
            (
                r"(?i)\bconfirmationToken\s*[:=]\s*['\"][^'\"]+",
                "restore token value",
            ),
            (r"-----BEGIN [A-Z ]*PRIVATE KEY-----", "private key material"),
        ):
            if re.search(pattern, text):
                raise AssertionError(f"{label} found in {relative}")
        checked += 1
    return checked


def main() -> int:
    files = source_files()
    decoded = {path: read_utf8(path) for path in files}

    json_count = 0
    yaml_count = 0
    markdown_count = 0
    link_count = 0
    for path, text in decoded.items():
        suffix = path.suffix.lower()
        if suffix == ".json":
            json.loads(text)
            json_count += 1
        elif suffix in {".yaml", ".yml"}:
            yaml.safe_load(text)
            yaml_count += 1
        elif suffix == ".md":
            link_count += check_markdown(path, text)
            markdown_count += 1

    sensitive_file_count = check_sensitive_repository_state(decoded)

    examples = sorted((REPO_ROOT / "examples").glob("*.json"))
    expected_example = REPO_ROOT / "examples" / "minimal-test-profile.json"
    if examples != [expected_example]:
        raise AssertionError(
            "examples must contain only the canonical minimal-test-profile.json"
        )

    print(
        json.dumps(
            {
                "ok": True,
                "utf8Files": len(decoded),
                "jsonFiles": json_count,
                "yamlFiles": yaml_count,
                "markdownFiles": markdown_count,
                "localLinks": link_count,
                "documentationExamples": len(examples),
                "sensitiveFilesChecked": sensitive_file_count,
            },
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

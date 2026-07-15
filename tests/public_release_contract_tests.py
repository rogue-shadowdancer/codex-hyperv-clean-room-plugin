from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PLUGIN_ROOT = REPO_ROOT / "hyperv-clean-room"
EXPECTED_LICENSE_SHA256 = (
    "3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986"
)
EXPECTED_ACTION_PINS = {
    "actions/checkout": "df4cb1c069e1874edd31b4311f1884172cec0e10",
    "actions/setup-python": "ece7cb06caefa5fff74198d8649806c4678c61a1",
}
EXPECTED_DESCRIPTION = (
    "Guarded Windows Hyper-V clean-room and package lifecycle testing for "
    "Codex via typed MCP tools."
)
EXPECTED_TOPICS = (
    "clean-room",
    "codex-plugin",
    "hyper-v",
    "mcp-server",
    "package-testing",
    "powershell",
    "test-automation",
    "virtualization",
    "windows",
)
REQUIRED_COMMUNITY_FILES = (
    "LICENSE",
    "CONTRIBUTING.md",
    "CODE_OF_CONDUCT.md",
    ".github/ISSUE_TEMPLATE/bug_report.yml",
    ".github/ISSUE_TEMPLATE/feature_request.yml",
    ".github/ISSUE_TEMPLATE/config.yml",
    ".github/pull_request_template.md",
    ".github/dependabot.yml",
)


def read_text(relative: str) -> str:
    content = (REPO_ROOT / relative).read_bytes()
    if content.startswith(b"\xef\xbb\xbf"):
        raise AssertionError(f"UTF-8 BOM found: {relative}")
    return content.decode("utf-8", errors="strict")


def main() -> int:
    license_bytes = (REPO_ROOT / "LICENSE").read_bytes()
    if hashlib.sha256(license_bytes).hexdigest() != EXPECTED_LICENSE_SHA256:
        raise AssertionError("LICENSE is not the canonical GNU GPL v3 text")
    license_text = license_bytes.decode("utf-8", errors="strict")
    for marker in (
        "GNU GENERAL PUBLIC LICENSE",
        "Version 3, 29 June 2007",
        "END OF TERMS AND CONDITIONS",
        "How to Apply These Terms to Your New Programs",
    ):
        if marker not in license_text:
            raise AssertionError(f"LICENSE is missing canonical marker: {marker}")

    manifest = json.loads(
        read_text("hyperv-clean-room/.codex-plugin/plugin.json")
    )
    if manifest.get("license") != "GPL-3.0-only":
        raise AssertionError("manifest SPDX identifier must be GPL-3.0-only")
    version = str(manifest.get("version", ""))
    if not re.fullmatch(r"0\.1\.1\+codex\.[0-9]{14}", version):
        raise AssertionError(f"release cachebuster version is invalid: {version}")

    server = read_text("hyperv-clean-room/mcp/server.ps1")
    if "version = '0.1.1'" not in server:
        raise AssertionError("MCP serverInfo version is not 0.1.1")
    schemas = sorted((PLUGIN_ROOT / "schemas").glob("*.json"))
    if len(schemas) != 5:
        raise AssertionError("public schema count must remain exactly five")

    for relative in REQUIRED_COMMUNITY_FILES:
        if not (REPO_ROOT / relative).is_file():
            raise AssertionError(f"missing public community file: {relative}")
    code_of_conduct = read_text("CODE_OF_CONDUCT.md")
    if "Contributor Covenant Code of Conduct" not in code_of_conduct:
        raise AssertionError("Contributor Covenant heading is missing")
    if "version 2.1" not in code_of_conduct.casefold():
        raise AssertionError("Contributor Covenant version 2.1 is missing")
    if "INSERT CONTACT METHOD" in code_of_conduct:
        raise AssertionError("Contributor Covenant contact placeholder remains")

    workflow = read_text(".github/workflows/ci.yml")
    required_workflow_fragments = (
        "name: public-release-validation",
        "contents: read",
        "fetch-depth: 0",
        "name: public-release-validation",
        "Validate GPL and public-release contract",
        "validate-gate4-ci.ps1",
    )
    for fragment in required_workflow_fragments:
        if fragment not in workflow:
            raise AssertionError(f"workflow is missing: {fragment}")
    for action, sha in EXPECTED_ACTION_PINS.items():
        pattern = rf"uses:\s*{re.escape(action)}@{sha}\s+#\s*v6\b"
        if not re.search(pattern, workflow):
            raise AssertionError(f"workflow pin is missing or not commented: {action}")
    for match in re.finditer(r"uses:\s*([^\s@]+)@([^\s#]+)", workflow):
        if not re.fullmatch(r"[0-9a-f]{40}", match.group(2)):
            raise AssertionError(f"workflow action is not pinned: {match.group(1)}")

    hygiene_source = read_text("tests/publication_hygiene_tests.py")
    for fragment in (
        'os.environ.get("GITHUB_EVENT_NAME"',
        'os.environ.get("GITHUB_BASE_REF"',
        'return f"origin/{base_ref}"',
        'return "HEAD"',
    ):
        if fragment not in hygiene_source:
            raise AssertionError(f"PR-safe history scope is missing: {fragment}")

    settings_source = read_text("scripts/validate-public-github-settings.ps1")
    release_process = read_text("docs/release-process.md")
    for value in (EXPECTED_DESCRIPTION, *EXPECTED_TOPICS):
        if value not in settings_source or value not in release_process:
            raise AssertionError(f"public repository metadata is not frozen: {value}")
    for fragment in (
        "public-release-validation",
        "required_status_checks",
        "strict",
        "required_pull_request_reviews",
        "required_approving_review_count",
        "required_conversation_resolution",
        "allow_force_pushes",
        "allow_deletions",
        "enforce_admins",
        "restrictions",
        "required_signatures",
    ):
        if fragment not in settings_source or fragment not in release_process:
            raise AssertionError(f"public protection contract is missing: {fragment}")

    docs = "\n".join(
        read_text(relative)
        for relative in (
            "README.md",
            "CHANGELOG.md",
            "SECURITY.md",
            "docs/README.md",
            "docs/specification.md",
            "docs/release-process.md",
            "TASK_HANDOFF.md",
        )
    )
    for phrase in (
        "GPL-3.0-only",
        "16 MCP tools",
        "five public",
        "schemaVersion: 1",
        "notPerformed",
        "Birdsgone",
        "public-release-validation",
    ):
        if phrase.casefold() not in docs.casefold():
            raise AssertionError(f"public documentation is missing: {phrase}")

    print(
        json.dumps(
            {
                "ok": True,
                "license": "GPL-3.0-only",
                "licenseSha256": EXPECTED_LICENSE_SHA256,
                "version": version,
                "tools": 16,
                "schemas": len(schemas),
                "schemaVersion": 1,
                "protocolVersions": 4,
                "communityFiles": len(REQUIRED_COMMUNITY_FILES),
                "workflowPins": len(EXPECTED_ACTION_PINS),
                "repositoryTopics": len(EXPECTED_TOPICS),
                "protectedBranch": "master",
            },
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

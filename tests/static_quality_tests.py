from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import unquote

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
TEXT_EXTENSIONS = {".json", ".md", ".ps1", ".py", ".txt", ".yaml", ".yml"}
SKIPPED_PARTS = {".git", ".artifacts", "__pycache__"}
MARKDOWN_LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
MARKDOWN_HEADING = re.compile(r"^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$", re.MULTILINE)
EXPLICIT_ANCHOR = re.compile(
    r"<a\s+[^>]*(?:id|name)\s*=\s*['\"]([^'\"]+)['\"][^>]*>", re.IGNORECASE
)
HANDOFF_PROJECT_PATH = re.compile(
    r"^`projectPath: [A-Za-z]:\\[^`\r\n]+`$", re.MULTILINE
)


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


def markdown_anchors(text: str) -> set[str]:
    anchors: set[str] = set()
    counts: dict[str, int] = {}
    for match in MARKDOWN_HEADING.finditer(text):
        heading = re.sub(r"<[^>]+>", "", match.group(1)).replace("`", "").lower()
        slug = re.sub(r"[^\w\- ]", "", heading, flags=re.UNICODE).strip()
        slug = re.sub(r"\s", "-", slug)
        if not slug:
            continue
        count = counts.get(slug, 0)
        anchors.add(slug if count == 0 else f"{slug}-{count}")
        counts[slug] = count + 1
    anchors.update(match.group(1) for match in EXPLICIT_ANCHOR.finditer(text))
    return anchors


def mask_handoff_project_path(relative: Path, text: str) -> str:
    if relative.as_posix() != "TASK_HANDOFF.md":
        return text
    matches = list(HANDOFF_PROJECT_PATH.finditer(text))
    if len(matches) != 1:
        raise AssertionError(
            "TASK_HANDOFF.md must contain exactly one absolute projectPath contract field"
        )
    return HANDOFF_PROJECT_PATH.sub("`projectPath: <workspace-root>`", text)


def check_markdown(path: Path, text: str) -> int:
    relative = path.relative_to(REPO_ROOT)
    policy_text = mask_handoff_project_path(relative, text)
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
        scan_text = policy_text if label == "absolute Windows path" else text
        if re.search(pattern, scan_text):
            raise AssertionError(f"{label} found in {relative}")

    checked_links = 0
    for match in MARKDOWN_LINK.finditer(text):
        raw_target = match.group(1).strip()
        if raw_target.startswith("<") and raw_target.endswith(">"):
            raw_target = raw_target[1:-1]
        target = raw_target.split(maxsplit=1)[0]
        if not target or target.startswith(("http://", "https://", "mailto:")):
            continue
        target_parts = target.split("#", 1)
        target_path_text = unquote(target_parts[0])
        fragment = unquote(target_parts[1]) if len(target_parts) > 1 else ""
        target_path = (
            path.resolve()
            if not target_path_text
            else (path.parent / target_path_text).resolve()
        )
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
        if fragment:
            if target_path.suffix.lower() != ".md":
                raise AssertionError(
                    f"fragment does not target Markdown in {relative}: {target}"
                )
            if fragment not in markdown_anchors(read_utf8(target_path)):
                raise AssertionError(
                    f"broken local Markdown fragment in {relative}: {target}"
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
        policy_text = mask_handoff_project_path(relative, text)
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
            scan_text = (
                policy_text
                if label in {"absolute user path", "workspace-specific path"}
                else text
            )
            if re.search(pattern, scan_text):
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

    required_documents = {
        REPO_ROOT / "CHANGELOG.md",
        REPO_ROOT / "SECURITY.md",
        REPO_ROOT / "docs" / "architecture.md",
        REPO_ROOT / "docs" / "installation.md",
        REPO_ROOT / "docs" / "maintenance.md",
        REPO_ROOT / "docs" / "operations.md",
        REPO_ROOT / "docs" / "release-process.md",
        REPO_ROOT / "docs" / "evidence.md",
        REPO_ROOT / "docs" / "security.md",
        REPO_ROOT / "docs" / "troubleshooting.md",
    }
    missing_documents = sorted(
        str(path.relative_to(REPO_ROOT))
        for path in required_documents
        if not path.is_file()
    )
    if missing_documents:
        raise AssertionError(f"required Gate documents are missing: {missing_documents}")

    ci_source = decoded[REPO_ROOT / ".github" / "workflows" / "ci.yml"]
    for required_ci_seam in (
        "fetch-depth: 0",
        "validate-docs.ps1",
        "publication_hygiene_policy_tests.py",
        "publication_hygiene_tests.py",
        "validate-gate4-ci.ps1",
    ):
        if required_ci_seam not in ci_source:
            raise AssertionError(
                f"CI publication validation is missing: {required_ci_seam}"
            )

    gate4_ci_source = decoded[REPO_ROOT / "scripts" / "validate-gate4-ci.ps1"]
    for required_gate4_ci_seam in (
        "-SkipRealHostSmoke",
        "validate-install-source.ps1",
        "gate4-installation.tests.ps1",
        "personalInstallOperations = 0",
        "marketplaceMutations = 0",
        "realHostOperations = 0",
        "realHyperVMutations = 0",
    ):
        if required_gate4_ci_seam not in gate4_ci_source:
            raise AssertionError(
                f"CI-safe Gate 4 validation is missing: {required_gate4_ci_seam}"
            )

    requirements = read_utf8(REPO_ROOT / "requirements-dev.txt").splitlines()
    expected_requirements = {
        "attrs==26.1.0",
        "jsonschema==4.26.0",
        "jsonschema-specifications==2025.9.1",
        "PyYAML==6.0.3",
        "referencing==0.37.0",
        "rpds-py==0.30.0",
        "typing-extensions==4.16.0",
    }
    if set(requirements) != expected_requirements or len(requirements) != len(
        expected_requirements
    ):
        raise AssertionError("requirements-dev.txt must contain only exact reviewed pins")

    prepare_source = decoded[REPO_ROOT / "scripts" / "prepare-test-python.ps1"]
    validate_source = decoded[REPO_ROOT / "scripts" / "validate-gate2.ps1"]
    if "requirementsSha256" not in prepare_source or "abiLabel" not in prepare_source:
        raise AssertionError("test Python preparation is not requirements/ABI isolated")
    if ".artifacts\\test-python\\runtime.json" not in validate_source:
        raise AssertionError("no-argument Gate 2 validation does not use prepared metadata")

    adapter_source = decoded[
        REPO_ROOT / "hyperv-clean-room" / "mcp" / "lib" / "Adapters.ps1"
    ]
    worker_source = decoded[
        REPO_ROOT / "hyperv-clean-room" / "mcp" / "lib" / "GuestWorker.ps1"
    ]
    if "GUEST_ADAPTER_UNVALIDATED" in adapter_source:
        raise AssertionError("the former production guest fail-closed stub remains")
    for required_symbol in (
        "Invoke-HcrRealInspectGuest",
        "Invoke-HcrRealStageArtifact",
        "Invoke-HcrRealGuestStep",
        "Invoke-HcrFixedGuestWorker",
    ):
        if required_symbol not in adapter_source:
            raise AssertionError(f"production guest adapter is missing {required_symbol}")
    for forbidden_surface in (
        "Invoke-Expression",
        "ScriptBlock]::Create",
        "Invoke-WebRequest",
        "DownloadString",
        "cmd.exe",
        "ssh.exe",
    ):
        if forbidden_surface in worker_source:
            raise AssertionError(
                f"fixed guest worker contains forbidden surface: {forbidden_surface}"
            )
    if not re.search(r"S-1-16-8448'[\s\S]{0,80}'mediumPlus'", worker_source):
        raise AssertionError("medium-plus integrity is not distinguished from exact medium")
    for required_security_seam in (
        "Initialize-WorkerDirectoryTree",
        "[Console]::OpenStandardOutput",
    ):
        if required_security_seam not in worker_source:
            raise AssertionError(
                f"fixed guest worker is missing security seam: {required_security_seam}"
            )
    if "[IO.FileMode]::CreateNew" not in adapter_source:
        raise AssertionError("guest control files are not created atomically")
    initializer_source = decoded[
        REPO_ROOT / "hyperv-clean-room" / "mcp" / "Initialize-GuestCredential.ps1"
    ]
    if "$acl.SetOwner($currentSid)" not in initializer_source:
        raise AssertionError(
            "credential ACL publication does not set current-user ownership explicitly"
        )
    for result_channel_seam in (
        "CreateProcessWithLogonW",
        "CreateSuspended",
        "AssignProcessToJobObject",
        "ResumeThread",
        "TerminateAndVerify",
        "ActiveProcessCount",
        "ReleaseVerifiedSingleProcess",
        "NtSuspendProcess",
        "Synchronize",
        "WaitFailed",
        "GetProcessCreationTicks",
        "GetProcessImagePath",
        "inputSha256",
        "invocationId",
    ):
        if result_channel_seam not in adapter_source:
            raise AssertionError(
                f"process-bound worker result seam is missing: {result_channel_seam}"
            )
    if "outputRoot; rights = [Security.AccessControl.FileSystemRights]::Modify" in adapter_source:
        raise AssertionError("standard user can modify the whole guest output directory")
    if "SetAccessRuleProtection($true, $false)" not in adapter_source:
        raise AssertionError("guest workspace ACLs still inherit parent grants")
    for acl_seam in (
        "$acl.SetOwner($administratorSid)",
        "[IO.Directory]::CreateDirectory(",
        "New-ProtectedWorkspaceAcl $TestSid $AllowTestRead $true",
        "A privileged workspace ACL is missing or duplicated.",
        "ReadAndExecute",
    ):
        if acl_seam not in adapter_source:
            raise AssertionError(f"guest workspace ACL readback seam is missing: {acl_seam}")
    deadline_guard = adapter_source.find(
        "if ([DateTimeOffset]::UtcNow -ge $deadline)"
    )
    suspended_create = adapter_source.find(
        "$supervised = [Hcr.SupervisedProcess]::CreateSuspendedInJob("
    )
    if deadline_guard < 0 or suspended_create <= deadline_guard:
        raise AssertionError("expired worker deadline can reach process creation")
    for restore_identity_seam in (
        "RequireOfflineDiskIdentity",
        "RESTORE_DISK_IDENTITY_UNAVAILABLE",
        "RESTORE_CHECKPOINT_INVENTORY_UNAVAILABLE",
        "Get-VMHardDiskDrive -VM $Vm -ErrorAction Stop",
        "Get-VHD -Path $path -ErrorAction Stop",
        "-CheckpointInventory $boundaryCheckpoints",
        "$snapshots = @($boundaryCheckpoints | Where-Object",
    ):
        if restore_identity_seam not in adapter_source:
            raise AssertionError(
                "restore offline disk identity seam is missing: "
                + restore_identity_seam
            )
    if "ProcessQueryLimitedInformation | ProcessSuspendResume | Synchronize" not in adapter_source:
        raise AssertionError("sole-child release handle lacks SYNCHRONIZE")
    if "candidateWait == WaitFailed" not in adapter_source:
        raise AssertionError("sole-child release does not fail closed on WAIT_FAILED")
    if "if (suspended) { NtResumeProcess(candidate); }" in adapter_source:
        raise AssertionError("rejected launch child is resumed before job termination")
    restore_binding = re.search(
        r"Assert-HcrRestoreAdapterBindings \$liveSnapshot \$Arguments"
        r"[\s\S]*?\$snapshots = @\(\$boundaryCheckpoints \| Where-Object"
        r"[\s\S]*?Restore-VMSnapshot -VMSnapshot \$snapshots\[0\]",
        adapter_source,
    )
    if restore_binding is None:
        raise AssertionError(
            "restore does not use the exact object from its validated boundary inventory"
        )
    restore_binding_start = adapter_source.find("function Assert-HcrRestoreAdapterBindings")
    restore_binding_end = adapter_source.find(
        "function Get-HcrRealGuestRemainingSeconds", restore_binding_start
    )
    restore_binding_source = adapter_source[restore_binding_start:restore_binding_end]
    for expected_field in (
        "expectedVmId",
        "expectedVmName",
        "expectedOwnershipId",
        "expectedVmPath",
        "expectedVhdxPath",
    ):
        if expected_field not in restore_binding_source:
            raise AssertionError(
                "restore boundary omits VM ownership identity field: " + expected_field
            )
    if "WorkerProcessHandle]::TerminateAndWait" not in worker_source:
        raise AssertionError("stopApplication does not use the retained process handle")
    if re.search(r"Stop-Process\s+-Id", worker_source):
        raise AssertionError("stopApplication still performs a PID-only stop lookup")

    server_source = (
        REPO_ROOT / "hyperv-clean-room" / "mcp" / "server.ps1"
    ).read_text(encoding="utf-8")
    for stream_boundary in (
        "$WarningPreference = 'SilentlyContinue'",
        "$InformationPreference = 'SilentlyContinue'",
        "$ProgressPreference = 'SilentlyContinue'",
        "3>$null 4>$null 5>$null 6>$null",
    ):
        if stream_boundary not in server_source:
            raise AssertionError(
                f"MCP non-protocol stream boundary is missing: {stream_boundary}"
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
                "requiredDocuments": len(required_documents),
                "pinnedRequirements": len(requirements),
                "sensitiveFilesChecked": sensitive_file_count,
            },
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

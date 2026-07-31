#!/usr/bin/env python3
"""Validate selected-plugin MCP catalog injection through Codex app-server."""

from __future__ import annotations

import argparse
import json
import os
import queue
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from typing import Any, TextIO


EXPECTED_TOOLS = {
    "inspect_host",
    "list_vms",
    "inspect_vm",
    "validate_test_profile",
    "validate_evidence",
    "plan_vm_create",
    "apply_vm_create",
    "plan_checkpoint_create",
    "apply_checkpoint_create",
    "plan_checkpoint_restore",
    "apply_checkpoint_restore",
    "inspect_guest",
    "stage_artifact",
    "run_test_profile",
    "collect_evidence",
    "record_manual_attestation",
    "plan_vm_power",
    "apply_vm_power",
    "plan_vm_network",
    "apply_vm_network",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plugin-root", type=Path, required=True)
    parser.add_argument("--expected-version", default="0.3.2")
    parser.add_argument("--environment-id", default="local")
    parser.add_argument("--timeout-seconds", type=int, default=45)
    parser.add_argument("--mock-tool-call-smoke", action="store_true")
    return parser.parse_args()


def read_lines(stream: TextIO, output: queue.Queue[str | None]) -> None:
    try:
        for line in iter(stream.readline, ""):
            output.put(line)
    finally:
        output.put(None)


def send(process: subprocess.Popen[str], message: dict[str, Any]) -> None:
    assert process.stdin is not None
    process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    process.stdin.flush()


def powershell_single_quote(value: Path) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def receive_response(
    process: subprocess.Popen[str],
    stdout_lines: queue.Queue[str | None],
    stderr_lines: queue.Queue[str | None],
    request_id: int,
    notifications: list[dict[str, Any]],
    deadline: float,
) -> Any:
    while time.monotonic() < deadline:
        try:
            line = stdout_lines.get(
                timeout=max(0.01, min(0.2, deadline - time.monotonic()))
            )
        except queue.Empty:
            if process.poll() is not None:
                break
            continue
        if line is None:
            break
        if not line.strip():
            continue
        message = json.loads(line)
        if message.get("id") == request_id:
            if "error" in message:
                raise RuntimeError(
                    f"Codex app-server request {request_id} failed: "
                    f"{json.dumps(message['error'], separators=(',', ':'))}"
                )
            return message["result"]
        notifications.append(message)

    stderr: list[str] = []
    while True:
        try:
            line = stderr_lines.get_nowait()
        except queue.Empty:
            break
        if line:
            stderr.append(line.rstrip())
    detail = "\n".join(stderr[-20:])
    raise RuntimeError(
        f"Timed out waiting for Codex app-server response id {request_id}."
        + (f"\napp-server stderr:\n{detail}" if detail else "")
    )


def app_server_command() -> list[str]:
    codex = shutil.which("codex.cmd") or shutil.which("codex")
    if not codex:
        raise RuntimeError("codex executable is not available on PATH.")
    if os.name == "nt" and Path(codex).suffix.casefold() in {".cmd", ".bat"}:
        wrapper_root = Path(codex).parent
        node = wrapper_root / "node.exe"
        codex_js = wrapper_root / "node_modules" / "@openai" / "codex" / "bin" / "codex.js"
        if not node.is_file() or not codex_js.is_file():
            raise RuntimeError(
                "The Codex command wrapper does not have its expected Node entrypoint."
            )
        return [str(node), str(codex_js), "app-server", "--stdio"]
    return [codex, "app-server", "--stdio"]


def remove_readonly(
    function: Any, path: str, _error_info: tuple[type[BaseException], BaseException, Any]
) -> None:
    os.chmod(path, stat.S_IWRITE)
    function(path)


def remove_tree_with_retries(path: Path) -> None:
    cleanup_error: BaseException | None = None
    for _ in range(20):
        try:
            shutil.rmtree(path, onerror=remove_readonly)
            return
        except FileNotFoundError:
            return
        except (OSError, RecursionError) as exc:
            cleanup_error = exc
            time.sleep(0.1)
    raise RuntimeError(f"Could not remove isolated Codex home {path}: {cleanup_error}")


def main() -> int:
    args = parse_args()
    plugin_root = args.plugin_root.resolve(strict=True)
    plugin_manifest_path = plugin_root / ".codex-plugin" / "plugin.json"
    mcp_manifest_path = plugin_root / ".mcp.json"
    for required_path in (plugin_manifest_path, mcp_manifest_path):
        if not required_path.is_file():
            raise RuntimeError(f"Selected plugin root is missing {required_path}.")

    plugin_manifest = json.loads(plugin_manifest_path.read_text(encoding="utf-8"))
    if plugin_manifest.get("name") != "hyperv-clean-room":
        raise RuntimeError(
            f"Unexpected selected plugin name: {plugin_manifest.get('name')!r}."
        )

    creation_flags = (
        subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0  # type: ignore[attr-defined]
    )
    isolated_codex_home = Path(
        tempfile.mkdtemp(prefix="hyperv-clean-room-codex-home-")
    )
    process_environment = dict(os.environ)
    process_environment["CODEX_HOME"] = str(isolated_codex_home)
    selected_plugin_root = plugin_root
    if args.mock_tool_call_smoke:
        selected_plugin_root = isolated_codex_home / "selected-plugin"
        shutil.copytree(plugin_root, selected_plugin_root)
        mock_adapter_path = isolated_codex_home / "mock-adapter.json"
        mock_adapter_path.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "host": {
                        "computerName": "MOCK-HOST",
                        "windowsEdition": "Windows 11 Pro",
                        "windowsBuild": "26100",
                        "architecture": "AMD64",
                        "hyperVCommandsAvailable": True,
                        "hypervisorPresent": True,
                        "elevated": True,
                        "processorCount": 8,
                        "memoryBytes": 17179869184,
                        "switches": [],
                        "targetVolumes": [],
                    },
                    "vms": [],
                    "credentialProfiles": [],
                    "guest": {},
                    "stepResults": {},
                    "cleanupResults": {},
                },
                separators=(",", ":"),
            ),
            encoding="utf-8",
        )
        mock_server_path = selected_plugin_root / "mock-server.ps1"
        mock_server_path.write_text(
            "\n".join(
                (
                    "$ErrorActionPreference = 'Stop'",
                    "$env:HCR_TEST_MODE = '1'",
                    "$env:HCR_ADAPTER_MODE = 'mock'",
                    (
                        "$env:HCR_MOCK_ADAPTER_PATH = "
                        f"{powershell_single_quote(mock_adapter_path)}"
                    ),
                    (
                        "$env:HCR_STATE_ROOT = "
                        f"{powershell_single_quote(isolated_codex_home / 'state')}"
                    ),
                    (
                        "$env:HCR_CREDENTIAL_ROOT = "
                        f"{powershell_single_quote(isolated_codex_home / 'credentials')}"
                    ),
                    "& (Join-Path $PSScriptRoot 'mcp\\server.ps1')",
                    "exit $LASTEXITCODE",
                    "",
                )
            ),
            encoding="utf-8",
        )
        isolated_mcp_manifest_path = selected_plugin_root / ".mcp.json"
        isolated_mcp_manifest = json.loads(
            isolated_mcp_manifest_path.read_text(encoding="utf-8")
        )
        isolated_mcp_manifest["mcpServers"]["hyperv-clean-room"]["args"] = [
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            "./mock-server.ps1",
        ]
        isolated_mcp_manifest_path.write_text(
            json.dumps(isolated_mcp_manifest, indent=2) + "\n",
            encoding="utf-8",
        )
    try:
        process = subprocess.Popen(
            app_server_command(),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            creationflags=creation_flags,
            env=process_environment,
        )
    except BaseException:
        remove_tree_with_retries(isolated_codex_home)
        raise
    assert process.stdout is not None
    assert process.stderr is not None
    stdout_lines: queue.Queue[str | None] = queue.Queue()
    stderr_lines: queue.Queue[str | None] = queue.Queue()
    threading.Thread(
        target=read_lines, args=(process.stdout, stdout_lines), daemon=True
    ).start()
    threading.Thread(
        target=read_lines, args=(process.stderr, stderr_lines), daemon=True
    ).start()
    notifications: list[dict[str, Any]] = []
    deadline = time.monotonic() + args.timeout_seconds

    try:
        send(
            process,
            {
                "method": "initialize",
                "id": 1,
                "params": {
                    "clientInfo": {
                        "name": "hyperv_clean_room_catalog_validator",
                        "title": "Hyper-V Clean Room catalog validator",
                        "version": "1.0.0",
                    },
                    "capabilities": {"experimentalApi": True},
                },
            },
        )
        receive_response(
            process, stdout_lines, stderr_lines, 1, notifications, deadline
        )
        send(process, {"method": "initialized", "params": {}})
        send(
            process,
            {
                "method": "thread/start",
                "id": 2,
                "params": {
                    "cwd": str(plugin_root),
                    "approvalPolicy": "never",
                    "sandbox": "read-only",
                    "ephemeral": True,
                },
            },
        )
        unselected_thread_result = receive_response(
            process, stdout_lines, stderr_lines, 2, notifications, deadline
        )
        unselected_thread_id = unselected_thread_result["thread"]["id"]
        send(
            process,
            {
                "method": "mcpServerStatus/list",
                "id": 3,
                "params": {
                    "threadId": unselected_thread_id,
                    "detail": "toolsAndAuthOnly",
                },
            },
        )
        unselected_status = receive_response(
            process, stdout_lines, stderr_lines, 3, notifications, deadline
        )
        unselected_servers = [
            item
            for item in unselected_status["data"]
            if item["name"] == "hyperv-clean-room"
        ]
        if unselected_servers:
            raise RuntimeError(
                "An unselected fresh thread unexpectedly exposed "
                "hyperv-clean-room; plain prompt text is not valid selection."
            )

        send(
            process,
            {
                "method": "thread/start",
                "id": 4,
                "params": {
                    "cwd": str(selected_plugin_root),
                    "approvalPolicy": "never",
                    "sandbox": "read-only",
                    "ephemeral": True,
                    "selectedCapabilityRoots": [
                        {
                            "id": "hyperv-clean-room@personal",
                            "location": {
                                "type": "environment",
                                "environmentId": args.environment_id,
                                "path": str(selected_plugin_root),
                            },
                        }
                    ],
                },
            },
        )
        thread_result = receive_response(
            process, stdout_lines, stderr_lines, 4, notifications, deadline
        )
        thread_id = thread_result["thread"]["id"]
        request_id = 5
        server: dict[str, Any] | None = None
        while time.monotonic() < deadline:
            send(
                process,
                {
                    "method": "mcpServerStatus/list",
                    "id": request_id,
                    "params": {
                        "threadId": thread_id,
                        "detail": "toolsAndAuthOnly",
                    },
                },
            )
            status_result = receive_response(
                process,
                stdout_lines,
                stderr_lines,
                request_id,
                notifications,
                deadline,
            )
            servers = [
                item
                for item in status_result["data"]
                if item["name"] == "hyperv-clean-room"
            ]
            if len(servers) != 1:
                observed = [item["name"] for item in status_result["data"]]
                raise RuntimeError(
                    f"Expected one selected hyperv-clean-room server; "
                    f"observed {len(servers)} in {observed}. "
                    f"Thread={json.dumps(thread_result['thread'], separators=(',', ':'))}"
                )
            server = servers[0]
            if server.get("serverInfo") is not None:
                break
            failures = [
                item
                for item in notifications
                if item.get("method") == "mcpServer/startupStatus/updated"
                and item.get("params", {}).get("name") == "hyperv-clean-room"
                and item.get("params", {}).get("status") == "failed"
            ]
            if failures:
                raise RuntimeError(
                    "Selected server startup failed: "
                    + json.dumps(failures[-1]["params"], separators=(",", ":"))
                )
            request_id += 1
            time.sleep(0.2)

        if server is None or server.get("serverInfo") is None:
            startup = [
                item
                for item in notifications
                if "mcpServer" in str(item.get("method", ""))
            ]
            raise RuntimeError(
                "Selected server returned no serverInfo before the deadline. "
                f"Last status={json.dumps(server, separators=(',', ':'))}; "
                f"startup notifications={json.dumps(startup[-10:], separators=(',', ':'))}"
            )
        server_info = server["serverInfo"]
        if server_info.get("name") != "hyperv-clean-room":
            raise RuntimeError(f"Unexpected server identity: {server_info!r}.")
        if server_info.get("version") != args.expected_version:
            raise RuntimeError(
                f"Unexpected server version {server_info.get('version')!r}; "
                f"expected {args.expected_version!r}."
            )

        observed_tools = list(server["tools"].keys())
        unique_tools = set(observed_tools)
        if (
            len(observed_tools) != 20
            or len(unique_tools) != 20
            or unique_tools != EXPECTED_TOOLS
        ):
            raise RuntimeError(
                "Unexpected tool catalog: "
                f"observed={len(observed_tools)}, unique={len(unique_tools)}, "
                f"missing={sorted(EXPECTED_TOOLS - unique_tools)}, "
                f"extra={sorted(unique_tools - EXPECTED_TOOLS)}."
            )

        tool_call_count = 0
        mock_tool_calls: list[dict[str, Any]] = []
        if args.mock_tool_call_smoke:
            for tool_name, arguments in (
                ("inspect_host", {}),
                ("list_vms", {"managedOnly": False}),
            ):
                request_id += 1
                send(
                    process,
                    {
                        "method": "mcpServer/tool/call",
                        "id": request_id,
                        "params": {
                            "threadId": thread_id,
                            "server": "hyperv-clean-room",
                            "tool": tool_name,
                            "arguments": arguments,
                            "_meta": {
                                "progressToken": f"metadata-smoke-{tool_name}"
                            },
                        },
                    },
                )
                tool_result = receive_response(
                    process,
                    stdout_lines,
                    stderr_lines,
                    request_id,
                    notifications,
                    deadline,
                )
                tool_call_count += 1
                if tool_result.get("isError") is True:
                    raise RuntimeError(
                        f"Mock {tool_name} returned MCP isError=true: "
                        f"{json.dumps(tool_result, separators=(',', ':'))}"
                    )
                text_items = [
                    item
                    for item in tool_result.get("content", [])
                    if isinstance(item, dict)
                    and item.get("type") == "text"
                    and isinstance(item.get("text"), str)
                ]
                if len(text_items) != 1:
                    raise RuntimeError(
                        f"Mock {tool_name} did not return one text envelope."
                    )
                envelope = json.loads(text_items[0]["text"])
                if envelope.get("ok") is not True or envelope.get("changed") is not False:
                    raise RuntimeError(
                        f"Mock {tool_name} was not successful and read-only: "
                        f"{json.dumps(envelope, separators=(',', ':'))}"
                    )
                warnings = envelope.get("warnings")
                if (
                    not isinstance(warnings, list)
                    or not any(
                        isinstance(warning, str)
                        and warning.startswith("TEST_ONLY_MOCK_ADAPTER:")
                        for warning in warnings
                    )
                ):
                    raise RuntimeError(
                        f"Mock {tool_name} lacks the mandatory TEST_ONLY warning."
                    )
                if tool_name == "inspect_host":
                    if (
                        envelope.get("data", {})
                        .get("host", {})
                        .get("computerName")
                        != "MOCK-HOST"
                    ):
                        raise RuntimeError(
                            "Mock inspect_host did not return the isolated mock host."
                        )
                elif (
                    envelope.get("data", {}).get("managedOnly") is not False
                    or envelope.get("data", {}).get("vms") != []
                ):
                    raise RuntimeError(
                        "Mock list_vms did not preserve managedOnly=false "
                        "with the empty mock inventory."
                    )
                mock_tool_calls.append(
                    {
                        "tool": tool_name,
                        "ok": True,
                        "changed": False,
                        "testOnlyWarning": True,
                    }
                )

        if not args.mock_tool_call_smoke and any(
            notification.get("method")
            in {"mcpServer/tool/call", "mcp_tool_call"}
            for notification in notifications
        ):
            raise RuntimeError("Catalog-only validation observed an MCP tool call.")
        ready_deadline = min(deadline, time.monotonic() + 3)
        while time.monotonic() < ready_deadline:
            if any(
                notification.get("method")
                == "mcpServer/startupStatus/updated"
                and notification.get("params", {}).get("threadId") == thread_id
                and notification.get("params", {}).get("name")
                == "hyperv-clean-room"
                and notification.get("params", {}).get("status") == "ready"
                for notification in notifications
            ):
                break
            try:
                line = stdout_lines.get(timeout=0.1)
            except queue.Empty:
                continue
            if line is None:
                break
            if line.strip():
                notifications.append(json.loads(line))
        ready_notifications = [
            notification
            for notification in notifications
            if notification.get("method") == "mcpServer/startupStatus/updated"
            and notification.get("params", {}).get("threadId") == thread_id
            and notification.get("params", {}).get("name")
            == "hyperv-clean-room"
            and notification.get("params", {}).get("status") == "ready"
        ]
        if not ready_notifications:
            raise RuntimeError(
                "Selected server did not produce a thread-scoped ready "
                "startup notification."
            )

        print(
            json.dumps(
                {
                    "status": "passed",
                    "validation": "selected-plugin-codex-app-server-catalog",
                    "pluginRoot": str(plugin_root),
                    "isolatedMockPlugin": args.mock_tool_call_smoke,
                    "pluginVersion": plugin_manifest["version"],
                    "unselectedThreadId": unselected_thread_id,
                    "unselectedServerCount": len(unselected_servers),
                    "promptTextSelectionAccepted": False,
                    "threadId": thread_id,
                    "serverName": server_info["name"],
                    "serverVersion": server_info["version"],
                    "startupStatus": "ready",
                    "observedToolCount": len(observed_tools),
                    "uniqueToolCount": len(unique_tools),
                    "mockToolCallSmoke": args.mock_tool_call_smoke,
                    "toolCallCount": tool_call_count,
                    "mockAdapterOperationCount": tool_call_count,
                    "realAdapterOperationCount": 0,
                    "realOperationCount": 0,
                    "realHyperVMutationCount": 0,
                    "realGuestOperationCount": 0,
                    "mockToolCalls": mock_tool_calls,
                    "tools": sorted(unique_tools),
                },
                indent=2,
            )
        )
        return 0
    finally:
        if os.name == "nt" and process.poll() is None:
            subprocess.run(
                ["taskkill", "/PID", str(process.pid), "/T", "/F"],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            process.wait()
        else:
            if process.stdin is not None:
                process.stdin.close()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()

        remove_tree_with_retries(isolated_codex_home)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001 - CLI must report bounded diagnostics.
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)

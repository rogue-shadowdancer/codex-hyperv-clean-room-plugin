# Hyper-V Clean Room for Codex

`hyperv-clean-room` is a Windows-only Codex plugin for guarded Hyper-V virtual
machine provisioning, declarative package lifecycle tests, and structured
clean-room evidence.

## Current status

Gate 1 is complete: the plugin manifest, MCP launch configuration, companion
skill, public contracts, schemas, and validation scaffold are frozen and have
passed independent read-only review. The MCP server deliberately fails closed
until Gate 2 implements and tests the runtime. Do not install this commit as a
working automation tool.

The design keeps the automation API independent from the companion skill. MCP
clients can call the typed tools directly; the skill only supplies optional
workflow guidance.

## Safety model

- Inspect before mutation.
- Separate planning from applying.
- Modify only plugin-owned VMs.
- Require a one-time confirmation for checkpoint restores.
- Keep credentials outside MCP arguments, repositories, logs, and evidence.
- Reject arbitrary shell commands in test profiles.
- Preserve `notPerformed` for checks that were not actually run.
- Expose no VM, VHDX, checkpoint, or host-file deletion tools.

The frozen v1 contract is in [docs/specification.md](docs/specification.md).
Implementation progress and the next gate are recorded in
[TASK_HANDOFF.md](TASK_HANDOFF.md).

## Development validation

Run from a non-elevated Windows PowerShell session:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-gate1.ps1
```

Gate 1 validation is structural. It does not create a VM, download an ISO,
restore a checkpoint, install the plugin, or run a package lifecycle test.

---
name: manage-hyperv-clean-room
description: Safely plan, operate, audit, and troubleshoot Windows Hyper-V clean-room virtual machines and package lifecycle tests through the hyperv-clean-room MCP tools. Use for Hyper-V host readiness, VM creation plans, owned VM inspection, checkpoints and guarded restores, guest baseline inspection, artifact staging, declarative test profiles, or evidence validation.
---

# Manage Hyper-V Clean Room

Use the plugin's MCP tools as the authority. Do not reconstruct Hyper-V commands
from this skill when an equivalent tool is available.

## Required workflow

1. Call `inspect_host` before proposing any VM operation.
2. Validate a test profile before staging an artifact or starting a test.
3. Use `plan_vm_create` before `apply_vm_create`.
4. Use `plan_checkpoint_create` before `apply_checkpoint_create`. Use
   `plan_checkpoint_restore` before `apply_checkpoint_restore`; require the
   exact checkpoint name and confirmation token returned by the restore plan.
5. Inspect the guest baseline before claiming a clean environment.
6. Collect and validate evidence after a test run.
7. Record a manual result only through `record_manual_attestation`; never infer
   a visual or interactive result from process state.
8. Report automatic assertions, manual assertions, unsupported checks, and
   unperformed checks separately.

## Safety rules

- Treat VM creation, checkpoint creation, restore, guest file transfer,
  installation, launch, uninstall, and reinstall as state-changing actions.
- Never submit a password or serialized credential through an MCP tool. Use the
  interactive credential initializer for its separate orchestration-admin and
  standard-test-user roles, then refer only to the profile name.
- Require package lifecycle evidence to identify the standard test user and a
  non-elevated token; an administrator PowerShell Direct session is not proof
  of an ordinary-user install.
- Do not modify a VM unless the plugin reports it as plugin-managed.
- Do not turn `notPerformed` or `unsupported` into `passed`.
- Keep a stock Windows baseline separate from a derived WebView2-absent
  checkpoint.
- Do not delete VMs, VHDX files, checkpoints, or host files. This plugin does
  not expose deletion tools.
- Stop when a plan expires, its host fingerprint changes, or an artifact hash
  differs; create a new plan instead of bypassing the guard.

## Evidence handoff

Include the operation ID, VM and checkpoint identity, Windows build, guest user
privilege, artifact SHA-256, automatic assertion results, manual checklist,
warnings, and evidence path. State plainly when no real VM or package lifecycle
test was executed.

---
name: manage-hyperv-clean-room
description: Safely plan, operate, audit, and troubleshoot Windows Hyper-V clean-room virtual machines and package lifecycle tests through the hyperv-clean-room MCP tools. Use for Hyper-V host readiness, VM creation plans, owned VM inspection, checkpoints and guarded restores, guest baseline inspection, artifact staging, declarative test profiles, or evidence validation.
---

# Manage Hyper-V Clean Room

Use the plugin's MCP tools as the authority. Do not reconstruct Hyper-V commands
from this skill when an equivalent tool is available.

Gate 1.1 freezes this guidance and the schemas, but the MCP entry point still
fails closed. Do not present this repository revision as a working Hyper-V
automation tool.

## Required workflow

1. Call `inspect_host` before proposing any VM operation.
2. Validate a test profile before staging an artifact or starting a test.
   Require one first-position `stageArtifact`, explicit `cleanupSteps` (use
   `[]` when empty), globally unique execution/assertion IDs, declared
   applications, safe relative paths, and the bounded cleanup budget.
3. Use `plan_vm_create` before `apply_vm_create`.
4. Use `plan_checkpoint_create` before `apply_checkpoint_create`. Use
   `plan_checkpoint_restore` before `apply_checkpoint_restore`; require the
   exact checkpoint name and confirmation token returned by the restore plan.
   Never repeat or record that token: plaintext is returned once, only by a
   successful restore plan, and the first well-formed apply attempt consumes
   the plan even when a supplied value or drift check is wrong.
5. Inspect the guest baseline before claiming a clean environment.
6. Let `run_test_profile` stage its host-local regular-file artifact for its own
   operation and verify both hashes. Use `stage_artifact` only for low-level
   preflight, troubleshooting, or an explicitly manual workflow; never assume
   it stages input for a later test operation.
7. Collect and validate evidence after a test run. Keep manual references
   relative to the server-controlled staging root for that operation.
8. Record a manual result only through `record_manual_attestation`; never infer
   a visual or interactive result from process state.
9. Report automatic assertions, manual assertions, cleanup results, unsupported
   checks, and unperformed checks separately. Cleanup never changes the
   required-assertion derivation of `overallStatus`.

## Safety rules

- Treat VM creation, checkpoint creation, restore, guest file transfer,
  installation, launch, uninstall, and reinstall as state-changing actions.
- Never submit a password or serialized credential through an MCP tool. Use the
  future interactive credential initializer with only `-ProfileName` and
  `-VmName`. Its two `Get-Credential` prompts and PowerShell Direct checks must
  prove different SIDs, an administrator orchestration role, and a standard
  non-administrator test role before DPAPI persistence. Then refer only to the
  profile name.
- Require package lifecycle evidence to identify the standard test user and a
  non-elevated token; an administrator PowerShell Direct session is not proof
  of an ordinary-user install.
- Do not modify a VM unless the plugin reports it as plugin-managed.
- Do not turn `notPerformed` or `unsupported` into `passed`.
- Cleanup begins only after execution starts and a required assertion, action,
  timeout, or guest-adapter failure occurs. An optional assertion failure is
  recorded and execution continues; actions cannot be optional.
- Cleanup may use only the nine declared cleanup types: one guarded
  `stopApplication` action, `wait`, and seven read-only assertion types. The
  stop action targets only a current-operation PID after rechecking identity.
  Continue later cleanup steps within budget after a cleanup failure; do not
  recursively clean up.
- Keep a stock Windows baseline separate from a derived WebView2-absent
  checkpoint.
- Do not delete VMs, VHDX files, checkpoints, or host files. This plugin does
  not expose deletion tools.
- Never use cleanup to uninstall a package, delete guest state, restore a
  checkpoint, or roll back a VM.
- Stop when a plan expires, its host fingerprint changes, or an artifact hash
  differs; create a new plan instead of bypassing the guard.

## Evidence handoff

Include the operation ID, VM and checkpoint identity, Windows build, guest user
privilege, both artifact SHA-256 values, automatic assertion results, manual
checklist, immutable `cleanupTriggered` state, cleanup results with bound
identities, warnings, and evidence path. State plainly when no real VM or
package lifecycle test was executed.

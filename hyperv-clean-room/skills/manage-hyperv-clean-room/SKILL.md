---
name: manage-hyperv-clean-room
description: Safely plan, operate, audit, and troubleshoot Windows Hyper-V clean-room virtual machines and package lifecycle tests through the hyperv-clean-room MCP tools. Use for Hyper-V host readiness, VM creation plans, owned VM inspection, checkpoints and guarded restores, guest baseline inspection, artifact staging, declarative test profiles, or evidence validation.
---

# Manage Hyper-V Clean Room

Use the plugin's MCP tools as the authority. Do not reconstruct Hyper-V commands
from this skill when an equivalent tool is available.

Gate 2 implements the MCP surface and the fixed production guest adapter, then
validates them with mock adapters, parsers, and static closed-dispatch seams.
It does not validate a real guest, credential profile, transfer, package, VM,
or checkpoint mutation. Do not turn implementation or mock results into claims
about a real Hyper-V host.

Gate 6/H1 freezes a plugin `0.2.0`, schema-v2 target contract for guarded power
and network planning, portable ZIP deployment, fixed WebDriver automation, a
closed `data-testid` UI DSL, and evidence v2. Gate 7/H2 integrates the contract
as exactly 20 tools while preserving the first 16 schema-v1 tools and five
schema-v1 files. H2 validation is mock/parser/static only: do not treat the
implementation, fixtures, or generated mock evidence as proof of a real
clean-room, guest, portable, driver, network, or UI run.

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
   The managed VM must be `Off` at planning and remain `Off` at apply; the
   plugin does not stop it automatically.
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
10. Before any production guest transfer or lifecycle call, require explicit
    authorization naming the VM, credential profile, artifact, profile, and
    intended mutation. Gate 2 validation itself authorizes no such call.

After H2 exposes schema v2, extend the same workflow as follows:

1. Validate the exact schema version; never downgrade an unknown version or
   migrate evidence. Migrate a v1 profile only through the explicit lossless
   path, and stop for authoring when package kind is ambiguous.
2. Use `plan_vm_power` then `apply_vm_power` only for `start` or
   `gracefulShutdown`. Apply accepts only the returned `planId` and consumes
   the plan before expiry/drift checks.
3. Use `plan_vm_network` then `apply_vm_network` only for the recorded
   `baseline` or `disconnected` primary-NIC target. Before disconnect, require
   the paired baseline recovery plan; if the change may have occurred, recovery
   is required evidence.
4. Require the candidate ZIP, root portable manifest, profile, fixture set,
   and fixed Microsoft EdgeDriver manifest hashes to match. Let the server own
   extraction, deployment slot, data preservation, driver acquisition,
   loopback endpoint, and process identities.
5. Use only declared UI step types and non-empty `data-testid` targets. Upload
   only a declared fixture ID. Never provide a selector, URL, JavaScript,
   WebDriver payload, executable argument, credential/secret, or file path
   through the UI DSL.
6. Report `machineStatus`, `overallStatus`, manual assertions, cleanup, and
   network recovery separately. A required manual `notPerformed` result keeps
   an otherwise machine-passed run `incomplete`.

## Safety rules

- Treat VM creation, checkpoint creation, restore, guest file transfer,
  installation, launch, uninstall, and reinstall as state-changing actions.
- Never submit a password or serialized credential through an MCP tool. Use the
  interactive credential initializer with only `-ProfileName` and
  `-VmName`. Its two `Get-Credential` prompts and PowerShell Direct checks must
  prove different SIDs, a high/system administrator orchestration role, and an
  exact-medium non-administrator test role before DPAPI persistence. The two
  DPAPI files and metadata are read-validated and atomically published as one
  new profile. Then refer only to the profile name.
- Require package lifecycle evidence to identify the standard test user and a
  non-elevated token; an administrator PowerShell Direct session is not proof
  of an ordinary-user install.
- The production adapter may execute only the plugin-owned fixed worker. It
  hash-verifies that worker, revalidates both credential roles, binds results to
  redirected stdout and the invocation/input hash, protects guest workspaces
  with explicit non-inheriting ACLs, creates the worker suspended and assigns
  it to a Windows job before resume, and uses operation-scoped staging and
  retained-handle process identities. Timeout containment must verify zero
  active processes; a surviving launch child is suspended and accepted only
  when its full identity is rebound as the job's sole active process before the
  deadline, using a synchronizable retained handle and failing closed on a
  liveness-query error. The adapter maps the declared
  NSIS/MSI/application/assertion/cleanup types to fixed behavior.
  Never substitute an arbitrary command, script, shell, URL, download, raw
  uninstall string, or caller-selected argument list.
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
- For schema-v2 portable work, reject an archive with traversal, absolute or
  drive paths, alternate data streams, links/reparse points, undeclared files,
  size/hash drift, or case-insensitive path collisions. Do not publish a
  partially verified slot or delete the previous slot/data.
- Require exact fixed WebView2/EdgeDriver version, archive and executable
  SHA-256, x64 PE identity, Microsoft publisher, full inventory, and loopback
  policy. Never substitute a caller URL, driver, endpoint, port, or arguments.

## Evidence handoff

Include the operation ID, VM and checkpoint identity, Windows build, guest user
privilege, both artifact SHA-256 values, automatic assertion results, manual
checklist, immutable `cleanupTriggered` state, cleanup results with bound
identities, warnings, and evidence path. State plainly when no real VM or
package lifecycle test was executed.

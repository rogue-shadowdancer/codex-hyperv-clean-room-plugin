# Task handoff: v0.4.0 least-privilege Hyper-V authorization

`relayProtocolVersion: 1`

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

## Objective

Publish and install one protected v0.4.0 runtime that supports normal,
non-elevated Codex operation through enabled local `Hyper-V Administrators`
membership while retaining elevated Administrator compatibility with an
explicit broader-privilege warning. This source/release gate performs no
production Hyper-V tool call or mutation.

## Frozen compatibility boundary

- Capability target remains `0.3.0`.
- Exactly 20 public typed tools and their closed inputs remain unchanged.
- SchemaVersion 1/2 routing, Plan/Apply consumption, expiry, drift, ownership,
  fingerprint, and network-recovery ordering remain unchanged.
- V1 host fingerprints retain the historical `elevated` component. V2 host
  fingerprints continue excluding transient privilege state. New
  authorization fields enter neither fingerprint.
- Matching v0.3.0, v0.3.1, and v0.3.2 external evidence remains readable;
  current generated provenance is v0.4.0.

## Authorization contract

The production MCP server reads only its current process token. Local built-in
SID `S-1-5-32-578` is `Hyper-V Administrators`.

- `hyperVAuthorized` is true when the token is an elevated Administrator or
  has the Hyper-V Administrators SID enabled.
- `authorizationMode` precedence is `elevatedAdministrator`,
  `hyperVAdministrators`, then `none`.
- `inspect_host` remains diagnostic and returns `elevated`,
  `hyperVAdministratorsTokenEnabled`, `hyperVAuthorized`, and
  `authorizationMode`; it returns no user name or user SID.
- `list_vms`, `inspect_vm`, and every host Plan/Apply path require
  authorization. Missing authorization returns
  `HYPERV_AUTHORIZATION_REQUIRED`.
- Successful elevated results include exactly:
  `BROADER_PRIVILEGE_CONTEXT: MCP server is elevated; Hyper-V Administrators is the preferred least-privilege authorization mode.`
- Production VM create, checkpoint create/restore, power, and network adapters
  independently recompute live token authorization before mutation entry.

ISO read, existing VM-root enumeration, and state-root initialization/access
fail respectively with `ISO_ACCESS_DENIED`, `VM_ROOT_ACCESS_DENIED`, and
`STATE_ROOT_ACCESS_DENIED`. The runtime never changes ACLs, adds group
membership, creates a caller VM root, or elevates itself.

## Version and release invariant

Runtime and manifest base version are `0.4.0`. After the source candidate is
stable, invoke the plugin-creator cachebuster helper exactly once and freeze
the only `0.4.0+codex.20260731141404` personal build. Do not rerun the helper after any
later correction.

The gate closes only when:

`protected master SHA = annotated v0.4.0 peeled SHA = Release tag target = install-manifest sourceCommit`

Publish one non-draft, non-prerelease, source-only v0.4.0 Release with zero
uploaded assets. Preserve immutable v0.1.1 through v0.3.2 tag objects, peeled
commits, Release identities, flags, timestamps, and zero-asset state.

## Required verification

Before commit and again on the exact final candidate as applicable:

```powershell
.\scripts\prepare-test-python.ps1
.\scripts\validate-docs.ps1
python -S .\tests\publication_hygiene_policy_tests.py
python -S .\tests\publication_hygiene_tests.py
python -S .\tests\public_release_contract_tests.py
.\scripts\validate-gate4-ci.ps1
.\scripts\validate-gate7.ps1 -SkipInheritedBaseline
.\scripts\validate-install-source.ps1 -RequireCachebuster
.\scripts\validate-codex-app-server-catalog.ps1 `
  -PluginRoot .\hyperv-clean-room -ExpectedVersion 0.4.0
.\scripts\validate-codex-app-server-catalog.ps1 `
  -PluginRoot .\hyperv-clean-room -ExpectedVersion 0.4.0 `
  -MockToolCallSmoke
```

Mock runtime coverage must prove the unauthorised/least-privilege/elevated
matrix, exact warnings and errors, role-authorized Plan/Apply, path-access
errors, unchanged fingerprints, and zero real-operation counters. Static
validation must prove all five real host mutation boundaries perform their own
live-token check.

The exact staged candidate requires substantive source/diff/test/scope review
with ZERO ACTIONABLE FINDINGS. Candidate changes reset affected validation and
review. Push only the reviewed branch, open a protected PR, resolve every
actionable thread, and merge normally. If hosted CI capacity is unavailable,
use the repository-authorized exact-head local fallback and report hosted CI
as `notPerformed`; never represent it as success.

## Safety boundary

- Do not call a production Hyper-V adapter or typed Hyper-V tool in this
  source/release task.
- The historical H4/G9 production-adapter `validate-gate4.ps1` smoke remains
  outside this gate and is not a substitute for the fresh post-install typed
  acceptance task.
- Do not mutate a VM, VHDX, checkpoint, switch, host setting, credential,
  guest, package, portable deployment, network attachment, UI, evidence, or
  manual attestation.
- Mock/parser/schema/static/install validation is allowed and is not real-host
  evidence.
- Do not edit the existing installed v0.3.2 cache. Install v0.4.0 only after
  protected merge, tag, and Release exist.
- Do not force-push, rewrite protected history, move old tags, bypass review,
  or upload Release assets.

## Current checkpoint

- Worktree: isolated task-owned checkout for this gate (local absolute path is
  intentionally not published).
- Branch: `codex/v0.4.0-hyperv-role-auth`
- Base: protected `origin/master`
  `d4598c4c49b8fc8500aea321190870288bcaa4ee`
- User session preflight: `Elevated=false`, current token has enabled
  Hyper-V Administrators SID.
- Current personal installation remains v0.3.2 build
  `0.3.2+codex.20260731014242` from source commit
  `d4598c4c49b8fc8500aea321190870288bcaa4ee`.
- Exactly 20 typed tools were loaded in the coordinating task. No typed tool
  was called during this source gate.

## Next gate

After exact protected publication, installation, and readback, create a fresh
non-elevated Codex task and actually select
`plugin://hyperv-clean-room@personal`. Its production smoke calls only typed
`inspect_host({})`, typed `list_vms({managedOnly:false})`, and typed
`inspect_vm({vmName})` for one returned VM. It must prove
`authorizationMode=hyperVAdministrators`, no broader-privilege or mock warning,
and consistent real VM identity/state/configuration. That smoke grants no
mutation authority.

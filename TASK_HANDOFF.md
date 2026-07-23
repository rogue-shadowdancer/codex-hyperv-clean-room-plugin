# TaskHandoff - H5A automatic-checkpoint ownership repair

`relayProtocolVersion: 1`

## Objective and outcome

H5A repairs the fail-closed ownership deadlock caused when Hyper-V attaches an
automatic-checkpoint `.avhdx` leaf to a managed VM whose schema-v1 ownership
record remains bound to its original base `.vhdx`.

The backward-compatible repair has two parts:

- new VM creation disables `AutomaticCheckpointsEnabled` immediately after
  `New-VM`, before publishing the Notes ownership marker, and fails closed
  unless a fresh Hyper-V readback returns the Boolean value `false`;
- an existing differencing leaf is ownership verified only through a complete,
  bounded, acyclic, identity-bearing chain whose exact parent links terminate
  at the unchanged recorded base VHDX and whose canonical SHA-256 fingerprint
  agrees with the inspected chain.

Recognition is read-only. It never adopts the active leaf, rewrites ownership
state, changes Notes, or modifies checkpoints or disks. While automatic
checkpoints remain true or unavailable, both guarded power actions are
rejected because starting or stopping can change the differencing-disk
lifecycle.

## Release-source and compatibility boundary

- Candidate branch: `codex/h5a-checkpoint-ownership`.
- Candidate base: accepted `origin/master`
  `b1e68d32ff8d29fb475ba3f43b59353086060f33`.
- Candidate cachebuster: `0.2.0+codex.20260723113253`.
- The immutable public version, annotated `v0.2.0` tag, and source-only GitHub
  Release are unchanged.
- The 20 MCP tool names, five schema-v1 files, seven schema-v2 files, plan
  consumption rules, and existing schema fields remain backward compatible.
  New inspection fields are additive.
- The previous accepted H4/G9 installed build
  `0.2.0+codex.20260722114845` remains the baseline until this exact candidate
  passes protected publication acceptance and is then installed.

## Changed areas

- `hyperv-clean-room/mcp/lib/Adapters.ps1`
  - disables automatic checkpoints before ownership publication;
  - reads the setting back from Hyper-V;
  - builds a bounded VHD/AVHDX identity chain from `Get-VHD`;
  - re-verifies ownership at ordinary and restore adapter mutation boundaries.
- `hyperv-clean-room/mcp/lib/Tools.Host.ps1`
  - canonicalizes and hashes VHD-chain identities;
  - accepts only a verified chain ending at the recorded base;
  - reports the storage-binding mode and recovery state from `inspect_vm`.
- `hyperv-clean-room/mcp/lib/Tools.Host.V2.ps1`
  - includes the chain and automatic-checkpoint setting in mutation invariants;
  - blocks both guarded power actions until automatic checkpoints are disabled.
- `tests/gate2-runtime.tests.ps1`
  - covers future creation, valid automatic-checkpoint chains, broken links,
    unrelated bases, forged fingerprints, cycles, missing identities,
    oversized chains, adapter-dispatch ownership drift, and power blocking.
- The specification, operations, security, troubleshooting, user README,
  repository skill, changelog, plugin cachebuster, and this handoff describe
  the same guarded behavior.

No MCP input accepts a chain, leaf, or replacement ownership identity. The
real adapter derives all chain evidence from the currently attached Hyper-V
disk and local ordinary non-reparse files.

## Repository state

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

- This isolated worktree started clean at the exact candidate base.
- All listed changes belong to H5A; no pre-existing user changes were present.
- Runtime fixtures and prepared test dependencies are ignored under
  `.artifacts` and are not publication candidates.
- No VM, VHDX, checkpoint, ISO, credential, evidence, installed-state, or
  machine-specific state file is tracked.

## Verification

Completed during implementation:

- Windows PowerShell 5.1 parsing passed for the modified runtime and test files.
- `tests/gate2-runtime.tests.ps1` passed 1,298 assertions with 20 tools and
  `realHyperVMutations: 0`.
- `tests/gate7-runtime.tests.ps1` passed 216 assertions with all real host,
  Hyper-V, guest, portable, WebDriver, and UI operation counters at zero.
- `scripts/validate-docs.ps1` passed 17 documents, 98 local links, strict UTF-8,
  and zero mojibake markers.
- Two independent reviews identified missing behavioral coverage for
  cycle/missing-identity rejection and adapter-dispatch ownership drift. Those
  cases were added and the affected suites passed afterward.

The exact candidate also passed:

```powershell
.\scripts\validate-gate4-ci.ps1
.\scripts\validate-gate7.ps1 -SkipInheritedBaseline
.\scripts\validate-public-release.ps1
git diff --check
```

Gate 4 CI-safe reported 31 source files, 20 tools, five v1 schemas, seven v2
schemas, 33 installer assertions, and zero install, marketplace, installed-copy,
host, guest, or Hyper-V mutation operations. Gate 7 reported 216 runtime
assertions and zero real host, Hyper-V, guest, portable, WebDriver, or UI
operations. The aggregate public-release gate passed 13 checks with
`realGuestOperations: 0` and `realHyperVMutations: 0`.

The substantive staged review must still reach `ZERO ACTIONABLE FINDINGS`.
Remote acceptance requires exact-head protected CI, zero unresolved actionable
review threads, normal merge without bypass, and exact accepted-source
installation. After installation, `validate-gate4.ps1` and installed
manifest/source readback must pass before the installed plugin is used for
read-only inspection.

## Existing pre-fix VM recovery boundary

H5A performs no recovery mutation. For the already running pre-fix managed VM:

1. Install and verify only the exact protected, accepted H5A source candidate.
2. Use installed `inspect_host` and `inspect_vm` read-only.
3. Require the same VM ID, ownership ID, recorded base path, active leaf,
   verified chain fingerprint, checkpoint inventory, and current power state
   expected by the separately retained operational evidence.
4. Preserve the current power state. Do not plan or apply start or graceful
   shutdown while `AutomaticCheckpointsEnabled` remains true or unavailable.
5. Separately review one setting-only host change whose only effect is setting
   `AutomaticCheckpointsEnabled` to false in the current power state. It must
   not change disks, checkpoints, power, Notes, ownership state, or any other
   VM setting.
6. If that future change is explicitly authorized and succeeds, inspect again
   and require the same chain fingerprint and checkpoint inventory, verified
   ownership, the setting `false`, and
   `automaticCheckpointRecoveryRequired: false` before any power plan.

Any incomplete, cyclic, identity-missing, forged, unrelated, or changed chain
is `OWNERSHIP_UNVERIFIED`; stop without mutation.

## Safety boundary, unresolved work, and next gate

`blockers[]`: none for completing and publishing H5A.

H5A does not delete, remove, apply, rename, merge, restore, or adopt a
checkpoint. It does not delete, reset, force-off, recreate, or reconfigure the
existing VM or its disks. It does not edit ownership state by hand, use
credentials, run arbitrary PowerShell Direct, or change permanent host access.

Windows installation/OOBE, credential enrollment, `inspect_guest`, graceful
shutdown, stock-Windows checkpoint creation, package/profile/WebDriver/UI
testing, guest evidence, and clean-machine acceptance all remain
`notPerformed`.

The next gate is recovery-plan evidence review only. It begins after exact H5A
installation and read-only inspection. It may propose the single setting-only
change above, but must not execute it without separate explicit authorization
after the exact old-to-new setting diff and preserved invariants are reviewed.

`ownership.previousTask: read-only-after-relay`

`ownership.successorTask: owns-next-gate`

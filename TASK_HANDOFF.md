# Task handoff: Windows token-integrity repair before Birdsgone Test2

`relayProtocolVersion: 1`

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

## Objective and authorization

Repair the Hyper-V Clean Room Windows access-token integrity defect across the
interactive credential initializer, production PowerShell Direct adapter, and
standalone `GuestWorker.ps1`; complete tests, exact-candidate review, ordinary
protected publication, exact protected installation, and only then resume the
already authorized Birdsgone `v0.1.0-test.2` production sequence.

The token source Gate performs no production MCP call, Hyper-V mutation, VM
start, guest operation, credential prompt or persistence, package execution,
evidence collection, installation, tag, or Release. The later production
authority remains limited to the owned VM and exact inputs below. It does not
authorize checkpoint, network, VM-create, deletion, forced power-off,
arbitrary guest command, UI/manual attestation, ACL/group/login-policy change,
alternate transport, direct Hyper-V cmdlet/WMI/JSON-RPC, force/direct push,
branch deletion, tag, or GitHub Release.

## Repository and build state

- Protected base and live `origin/master` at Gate start:
  `22ea38620277ea9ad6312b1210b68c5d2158cadc`.
- Task branch: `codex/fix-windows-token-integrity`.
- The active Codex worktree is the unique writable repository checkout.
- The permanent original workspace at `projectPath` remains on unrelated
  user-owned work and must not be switched, cleaned, synchronized, or edited.
- Frozen repaired build: `0.4.1+codex.20260814082037`. The plugin-creator
  cachebuster helper ran exactly once for this repair and must not be rerun.
- Installed predecessor: `0.4.1+codex.20260813075830` from protected commit
  `22ea38620277ea9ad6312b1210b68c5d2158cadc`; it does not contain this repair.
- Task Mail status is `credential_state_missing`; no prior identity is reused
  or impersonated. Agent Mail remains advisory.

## Exact production inputs retained

- VM: `Birdsgone-W11-HV-20260723`.
- New credential profile: `birdsgone-w11-test2`.
- ZIP `Birdsgone_0.1.0_windows-x64-portable.zip`: 344,485,947 bytes, SHA-256
  `1a7cd75229c785b0724ea9552439504a8a4721242246ed53c2251594b36f8f6a`.
- Sidecar `portable-manifest.json`: 142,013 bytes, SHA-256
  `f9267d70ca9b412bc54170489e38d211bd528a28e64a1fe15fa2cf987471650c`.
- Non-UI profile SHA-256
  `37c4c8a49cef9a7b982c842a197f47f54a7cb02c10c3ff1c9043ccf803b31021`.
- The profile contains stage, deploy, launch, running assertion, stop, stopped
  assertion, and bounded cleanup; it contains no UI or manual assertion.

## Reproduced defect and repair

The installed build inferred integrity by enumerating
`WindowsIdentity.Groups` for `S-1-16-*`. On the valid guest role probes this
produced `tokenIntegrity=unknown` even when SID, administrator role, session,
and credential transport were otherwise valid. The adapter also hardcoded
administrator elevation, and the worker inferred elevation from integrity.
Those facts cannot safely authorize credential enrollment or a lifecycle.

The repair is deliberately fail closed:

- `Common.ps1` provides one self-contained PowerShell 5.1 probe used unchanged
  by the initializer and production adapter through PowerShell Direct.
- Both the shared probe and standalone worker call native
  `GetTokenInformation` for `TokenIntegrityLevel`, `TokenElevation`, and
  `TokenElevationType` using the borrowed `WindowsIdentity.Token` handle and
  dispose only the identity.
- The first sizing call must fail specifically with
  `ERROR_INSUFFICIENT_BUFFER=122`; allocation is bounded; returned sizes,
  mandatory-label structure, in-buffer SID bounds, `SE_GROUP_INTEGRITY`,
  `IsValidSid`, exact `S-1-16` authority, one-subauthority shape, and RID are
  validated while the buffer is alive and freed in `finally`.
- Only exact RIDs `0x1000`, `0x2000`, `0x2100`, `0x3000`, and `0x4000` map to
  low, medium, medium-plus, high, and system. Numeric ranges and unknown values
  are rejected.
- Elevation must be Boolean; Full with non-elevated and Limited with elevated
  are rejected. Elevation type is internal and is not published.
- Administrator acceptance now requires observed elevation and exact
  high/system integrity. Test-user acceptance requires no elevation and exact
  medium integrity. All `S-1-16-*` group inference and hardcoded/inferred
  elevation are removed.

Public tool names, tool inputs, public evidence fields, five schema-v1 files,
seven schema-v2 paths/IDs, Plan/Apply semantics, credential file shape, and the
31-payload topology remain unchanged.

## Changed areas

- Runtime: `Common.ps1`, `Initialize-GuestCredential.ps1`, `Adapters.ps1`, and
  `GuestWorker.ps1`.
- Tests: PowerShell 5.1 current-token smoke, shared/worker parity, exact
  RID/elevation truth tables, invalid-handle and static native-safety checks,
  and removal of obsolete group/hardcoded assertions.
- Documentation: README, architecture, specification, operations, security,
  troubleshooting, installation, maintenance, release process, and this
  handoff.
- Build identity: `.codex-plugin/plugin.json` only; no marketplace or Codex
  configuration was edited.

## Verification completed on the dirty candidate

- PowerShell 5.1 parser: initializer, Common, adapter, worker, and runtime test
  parse with zero errors.
- Native local smoke: current SID present, exact medium integrity,
  `isElevated=false`, and no public elevation-type property in the current
  non-elevated process.
- Gate 2 runtime: 1,805 assertions, 20 tools, zero real Hyper-V mutations.
- Impact-scoped `validate-gate2.ps1 -SkipRealHostSmoke`: passed schema,
  semantic, runtime, documentation, and isolated static checks with zero real
  host operations and zero real Hyper-V mutations.
- `validate-gate7.ps1 -SkipInheritedBaseline`: 452 runtime assertions, 20
  tools, five v1 and seven v2 schemas, ten generated mock evidence documents,
  and zero real host, Hyper-V, guest, portable, WebDriver, or UI operations.
- Plugin-creator manifest validation: passed.
- `validate-install-source.ps1 -RequireCachebuster`: build
  `0.4.1+codex.20260814082037`, cachebuster `20260814082037`, 31 payloads, five
  v1 schemas, seven v2 schemas, zero reparse points, and zero untracked payload.
- `validate-docs.ps1`: 17 documents, 101 local links, strict UTF-8, zero
  reported mojibake markers.
- No real VM, guest, credential, evidence, install, marketplace, or Codex
  operation occurred during this source repair.

Historical H4/G9 installed-copy acceptance through `validate-gate4.ps1` is not
source evidence and remains `notPerformed` for this candidate. Its inherited
production-host lane is not silently run or substituted into the exact Test2
authority.

## Next ordered gates

1. Review the final staged candidate against the defect and safety contract;
   require ZERO ACTIONABLE FINDINGS and rerun affected checks after any edit.
2. Commit and push the frozen build on `codex/fix-windows-token-integrity`,
   open one ordinary protected pull request to `master`, and read back exact
   branch/PR/check state. Do not regenerate the cachebuster.
3. In a successor protected-review Gate, reconcile all comments, reviews,
   inline threads, reactions, and checks; preserve the exact candidate through
   any required unchanged-head window and merge only through ordinary branch
   protection. Hosted infrastructure waiver is allowed only when affirmatively
   `waived_non_code` / `notPerformed` under repository policy.
4. From exact protected `master`, rerun source/install provenance checks,
   `check_install.ps1`, one `install_plugin.ps1`, and post-install readback.
   Require exact 31-file hashes, source/build/cachebuster, one marketplace
   entry, installed/enabled state, and a freshly selected exact 20-tool catalog.
5. Only from the freshly loaded repaired installed bytes, revalidate the exact
   Test2 profile; inspect the owned VM; guarded start only when Off; run the
   two-prompt interactive initializer without exposing secrets; inspect guest;
   run the exact non-UI smoke; collect and validate evidence to a new safe
   non-repository child; then guarded graceful shutdown and verify Off.

`blockers: []`

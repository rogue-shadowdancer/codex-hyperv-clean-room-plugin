# TaskHandoff - H5D-R2 conditional guarded power recovery

`relayProtocolVersion: 1`

`relayAttempt: 1`

## Objective and outcome

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

H5D-R2 completed the separately authorized guarded power recovery for the one
existing managed VM used by the H5 sequence.

After a fresh authoritative elevated readback proved that the VM was still
`Off`, every protected non-power structural invariant matched the accepted
H5D baseline, and no active plan existed, one bounded `start` plan was created.
The plan's sanitized exact `Off -> Running` delta, effects, and expiry were
shown to the user. A separate confirmation authorized one apply of that exact
plan.

The apply succeeded once with `changed=true` and confirmed `Off -> Running`.
The immediate elevated postflight observed `Running`, `changed=false`, zero
warnings, and every protected invariant unchanged. A separately authorized
read-only monitor then sampled at approximately 0, 5, 10, 15, 20, 25, and
30 minutes. All seven samples observed `Running`, matched the same host and
managed-VM identity, matched the same protected structure, reported
`changed=false`, and had zero warnings. H5D-R2 is therefore complete.

This result establishes the required bounded stability observation. It does
not identify the cause, timing, or authority of historical `Running -> Off`
transitions or the earlier 12 GiB-to-8 GiB maximum-memory difference. H5E,
guest inspection, credential publication, package lifecycle, portable, UI,
evidence, and `v0.3.0` implementation work remain `notPerformed`.

## Specification paths

`specificationPaths[]`:

- `AGENTS.md`
- `TASK_HANDOFF.md`
- `docs/specification.md`
- `docs/operations.md`
- `docs/security.md`
- `docs/troubleshooting.md`
- GitHub Issue #19
- the installed `hyperv-clean-room` skill and public MCP contract

## Completed work

`completedWork[]`:

- Re-read every listed repository authority, GitHub Issue #19, the installed
  clean-room skill, and the public MCP boundary before the guarded operation.
- Started from exact protected `origin/master` commit
  `0f9ba306dd3d607aa5fadb66211751451245d993`.
- Revalidated the installed plugin inventory: all 31 claimed payload files
  were present with zero missing, size-mismatched, hash-mismatched, unexpected,
  or reparse files.
- Confirmed that the installed public MCP catalog still contained exactly
  20 unique tools and that the credential root remained absent.
- Confirmed before planning that all historical plans were consumed and that
  zero unconsumed, live, live-power, or corrupt plans existed.
- Ran an authoritative elevated readback limited to `inspect_host`,
  `list_vms`, and `inspect_vm`. It found exactly one managed VM still `Off`;
  host, inventory, and VM calls all reported `changed=false`.
- Required and verified generation 2, verified ownership, a verified
  differencing-disk chain at depth 2, one checkpoint, automatic checkpoints
  disabled, no automatic-checkpoint recovery requirement, 4 processors,
  8 GiB startup memory, 8 GiB maximum dynamic memory, Secure Boot, vTPM, and
  one attached primary adapter on an internal virtual switch.
- Created one exact `start` plan only after every precondition passed and no
  active plan existed.
- Showed the sanitized `Off -> Running` delta, expected effects, and expiry,
  then stopped for a separate confirmation tied to that exact fresh plan.
- Applied the confirmed plan exactly once. The operation reported `ok=true`,
  `changed=true`, `effectState=confirmed`, and `Off -> Running`.
- Immediately re-inspected the host, managed inventory, and VM. The VM was
  `Running`; every protected invariant remained unchanged; all inspection
  envelopes reported `changed=false` and zero warnings.
- Preserved one failed-closed initial stability-monitor attempt. Its sample
  publication was blocked by an over-broad sanitized-output field-name check;
  it performed no mutation and was not retried without new authorization.
- After new explicit authorization, used a fresh create-only monitor whose
  exact full sample payload passed serialization self-tests and whose static
  closed dispatch contained only `inspect_host`, `list_vms`, and `inspect_vm`.
- Completed seven accepted read-only samples spanning at least 30 minutes.
  Every sample observed `Running`, the same host, the same managed VM, the same
  protected structure, zero warnings, and `changed=false`.
- Re-read the plan inventory after apply: four historical plans were consumed,
  with zero unconsumed, live, live-power, or corrupt plans.
- Performed no guest inspection, credential prompt or initialization,
  configuration change, account or policy change, network or checkpoint
  mutation, package operation, portable/UI/evidence work, tag, or Release.

## Changed files and repository state

`changedFiles[]`:

- `TASK_HANDOFF.md` - sanitized H5D-R2 guarded recovery, immediate postflight,
  30-minute stability result, verification boundary, and separately gated H5E
  route.

`repositoryState`:

- Branch: `codex/h5d-r2-guarded-power-recovery-closeout`.
- Base: protected `origin/master` commit
  `0f9ba306dd3d607aa5fadb66211751451245d993`.
- The tracked worktree was clean before this closeout edit.
- No pre-existing tracked user change was present.
- Fresh ignored operational helpers and local results remain untracked,
  unpublished, create-only, and untouched after their respective runs.
- Retained ignored evidence, saved checkouts, other worktrees, and remote
  branches remain untouched.
- Publication is limited to one protected pull request containing only this
  sanitized handoff.
- The user's standing merge authorization applies only after every required
  exact-head validation, review, wait-window, mergeability, conversation, and
  protection condition is satisfied. It does not authorize an automatic
  merge, direct protected-branch push, force-push, branch deletion, tag,
  Release, or protection change.
- H5E and every later machine gate require their own authorization and are
  outside this task.

## Verification

`verification[]`:

- Installed version: `0.2.0+codex.20260723113253`.
- Installed inventory: 31 claimed files, zero missing, zero size mismatches,
  zero hash mismatches, zero unexpected files, and zero reparse files.
- Public MCP catalog: exactly 20 tools and 20 unique names.
- Credential state: credential root absent and zero profiles.
- Pre-plan state: exactly one managed VM at `Off`; every protected structural
  invariant matched; zero active plans.
- Power apply: exactly one call, `ok=true`, `changed=true`,
  `effectState=confirmed`, and exact `Off -> Running`.
- Immediate postflight: `Running`; host, inventory, and VM calls all
  `changed=false`; zero warnings; every protected invariant unchanged.
- Stability schedule: approximately 0, 5, 10, 15, 20, 25, and 30 minutes.
- Stability result: seven of seven samples accepted over at least 30 minutes.
- Every stability sample: `Running`, one verified managed VM, generation 2,
  verified differencing chain at depth 2, one checkpoint, automatic
  checkpoints disabled, no recovery requirement, 4 processors, 8/8 GiB
  memory, Secure Boot, vTPM, one attached primary adapter on an internal
  switch, zero warnings, and `changed=false`.
- Continuity: the same host, same managed VM identity, and same protected
  structure across all seven samples.
- Final plan state: four historical consumed plans, zero unconsumed plans,
  zero live plans, zero live power plans, and zero corrupt plans.
- The historical H4/G9 installed-copy validator,
  `scripts/validate-gate4.ps1`, is not applicable to this sanitized handoff
  publication. `scripts/validate-public-release.ps1` supplies the applicable
  CI-safe aggregate coverage.

## Unresolved issues and blockers

`unresolvedIssues[]`:

- The cause, timing, and authority of the observed 12 GiB-to-8 GiB live
  maximum-memory difference remain unknown.
- The cause and authority of historical `Running -> Off` transitions remain
  unknown.
- The native administrator-token diagnostic, credential-profile publication,
  `inspect_guest`, package lifecycle, portable, UI, evidence, and
  manual-attestation lanes remain `notPerformed`.
- H5E, P3.1, P3.2, P3.3, and Birdsgone clean-room acceptance have not started.

`blockers[]`:

- No H5D-R2 machine blocker remains: guarded power recovery and the bounded
  30-minute stability observation completed successfully.
- This documentation candidate must not merge until its exact staged
  validation and substantive review reach zero actionable findings, its
  exact-head required checks pass, its complete fresh review window finishes,
  every actionable conversation is resolved, mergeability is clean, and
  protection is re-read unchanged.
- Any candidate change resets the affected validation, substantive review,
  hosted checks, and complete fresh review window.
- H5E remains separately gated and requires its own exact authorization.
  H5D-R2 completion does not authorize the diagnostic.

## Next gate and commands

`nextGate: H5E separately authorized one-shot native administrator-token
diagnostic, only after this H5D-R2 handoff is published, merged, verified, and
relayed to a new task`

`nextCommands[]`:

1. Stage only `TASK_HANDOFF.md`.
2. Run `scripts/validate-docs.ps1`,
   `scripts/validate-public-release.ps1`, exact staged
   `git diff --cached --check`, a sensitive-content/scope scan, and a
   substantive staged review to zero actionable findings.
3. Commit as `docs: record H5D-R2 guarded power recovery`, push the feature
   branch, and open a non-draft pull request against protected `master`.
4. Wait for exact-head required checks and the complete fresh review window.
   Re-read the exact head/base, checks, reviews, comments, threads,
   mergeability, and protection. Restart affected gates after any candidate
   change.
5. If and only if every merge condition is satisfied, use the user's standing
   authorization for one ordinary protected merge locked to the exact reviewed
   head SHA.
6. Verify the exact remote merge commit, parents, tree, signature, protection,
   and successful post-merge required check.
7. Update Issue #19 once and read it back: mark H5D-R2 complete with the
   sanitized guarded `Off -> Running` result and seven accepted samples over at
   least 30 minutes; retain H5E and all later gates as incomplete.
8. Relay H5E to a new task. Do not run the native token diagnostic in this
   task and do not infer its authorization from H5D-R2.

## Safety constraints

`safetyConstraints[]`:

- Do not perform another Hyper-V, guest, credential, account, policy, package,
  portable, UI, evidence, or machine operation in this task.
- Do not create or apply another VM creation, power, network, checkpoint, or
  restore plan.
- Do not start, stop, pause, save, checkpoint, restore, reset, or otherwise
  change a VM.
- Do not open another UAC or any interactive credential prompt in this task.
- Do not publish sensitive identities, machine paths, raw errors, plan
  capabilities, credential material, or ignored operational artifacts.
- Do not clean, reuse, overwrite, move, or delete ignored evidence.
- Do not push directly to the protected branch, enable automatic merge,
  force-push, delete branches, weaken protection, tag, or publish a Release.
- Repository merge authorization does not authorize H5E, guest work,
  credentials, account/policy change, or any later machine gate.

`ownership.previousTask: read-only-after-relay`

`ownership.successorTask: owns-next-gate`

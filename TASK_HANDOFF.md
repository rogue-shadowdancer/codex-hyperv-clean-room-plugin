# TaskHandoff - H5D existing-managed-VM memory baseline revision

`relayProtocolVersion: 1`

`relayAttempt: 1`

## Objective and outcome

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

This H5D gate implements the user's separate baseline-revision choice as a
documentation-only acceptance decision. For the one existing managed VM used
by the H5 operational sequence, the protected structural comparison baseline
is now:

- startup memory: 8 GiB;
- maximum dynamic memory: 8 GiB.

The revision is intentionally local to that existing VM. The public
`plan_vm_create` contract remains unchanged: omitted memory inputs still
default to 8 GiB startup memory and 12 GiB maximum dynamic memory.

The last authoritative elevated read-only preflight preceding H5D is the
recorded observation establishing the new baseline: startup memory was 8 GiB
and maximum dynamic memory was 8 GiB. The preceding H5C handoff's generic
statement that both memory values matched "the accepted baseline" omitted
those values and did not reconcile the observed maximum with the earlier
protected 12 GiB expectation. H5D supersedes that statement for the
maximum-memory field; it is not evidence that the VM still had a 12 GiB
maximum.

H5D changes no runtime, schema, tool catalog, compatibility fixture, test,
installed payload, or general VM-creation behavior. It performs and authorizes
no Hyper-V, guest, credential, plan/apply, H5E, or `0.3.0` work.

## Specification paths

`specificationPaths[]`:

- `AGENTS.md`
- `TASK_HANDOFF.md`
- `docs/specification.md`
- `docs/operations.md`
- `docs/security.md`
- `docs/troubleshooting.md`
- the installed `hyperv-clean-room` skill and public MCP contract

## Completed work

`completedWork[]`:

- Re-read every listed repository authority and the complete installed
  clean-room skill before editing.
- Started the required Task Mail session and found no pending coordination
  request.
- Fetched protected `origin/master` and confirmed the candidate started from
  exact commit `9f82e6a0cb2315720eb7548e3d7ce82660f92949` with no tracked
  change.
- Created `codex/h5d-existing-vm-memory-baseline` from that exact protected
  commit.
- Reconfirmed that the public `plan_vm_create` 12 GiB maximum default is
  present in the specification, tool schema, runtime default, compatibility
  snapshot, fixtures, and tests.
- Reconciled the preceding H5C handoff's unspecified "matched the accepted
  baseline" wording with the recorded authoritative 8 GiB startup and 8 GiB
  maximum-memory observation, and explicitly superseded that wording for the
  maximum-memory field.
- Added the narrow H5D acceptance boundary to `docs/specification.md`.
- Added a short operational-status note to `docs/operations.md` so operators
  do not conflate the one existing VM's 8 GiB accepted maximum with the
  product default.
- Preserved every runtime, schema, catalog, compatibility fixture, test,
  installed payload, and ignored operational artifact.
- Performed no host inspection, UAC elevation, live VM read, plan creation,
  apply, guest operation, credential operation, or machine mutation.
- Prepared a fresh ignored development-test dependency cache for this
  worktree only because the aggregate publication validator requires it. No
  cache or operational evidence from another worktree was copied or reused.

## Changed files and repository state

`changedFiles[]`:

- `docs/specification.md` - authoritative H5D existing-VM baseline boundary.
- `docs/operations.md` - operator-facing distinction between the local
  existing-VM baseline and the public creation default.
- `TASK_HANDOFF.md` - this sanitized gate record.

`repositoryState`:

- Branch: `codex/h5d-existing-vm-memory-baseline`.
- Base: protected `origin/master` commit
  `9f82e6a0cb2315720eb7548e3d7ce82660f92949`.
- The tracked worktree was clean before this gate.
- No pre-existing tracked user change was present.
- Fresh ignored validation dependencies and logs under `.artifacts` are local
  non-publication state and remain preserved.
- Existing ignored operational evidence, other worktrees, and remote gate
  branches remain untouched.
- Publication must use a pull request. Direct `master` push, automatic merge,
  force-push, branch deletion, tag creation, GitHub Release publication, and
  protection changes remain outside this gate.

## Verification

`verification[]`:

- Source occurrence review confirms that the public
  `maximumMemoryGb` default remains 12.
- Baseline evidence review confirms that the last authoritative elevated
  read-only preflight preceding H5D observed 8 GiB startup memory and 8 GiB
  maximum dynamic memory; H5D performs no new live readback.
- `scripts/validate-docs.ps1`: passed with 17 documents, 98 local links,
  strict UTF-8, and zero mojibake markers.
- `scripts/validate-public-release.ps1`: all 13 aggregate checks passed.
- Aggregate validation reported zero real guest operations and zero real
  Hyper-V mutations.
- The historical complete H4/G9 installed-copy validator,
  `scripts/validate-gate4.ps1`, was not run because its installed-host smoke
  would broaden this documentation-only gate into host inspection. The
  aggregate publication validator instead runs the applicable
  `validate-gate4-ci.ps1` lane.
- Exact candidate `git diff --check`: passed.
- Exact staged substantive review: zero actionable findings.
- Final staged scope contains only the three documentation files listed
  above.
- No runtime, schema, catalog, compatibility fixture, test, manifest, skill,
  installed payload, or machine-state file changed.

These checks establish only a documentation baseline decision. They do not
establish the cause or authority of prior live drift, a current VM state, an
operational recovery, a guest baseline, or any machine-backed result.

## Unresolved issues and blockers

`unresolvedIssues[]`:

- The cause, timing, and authority of the observed 12 GiB-to-8 GiB live
  maximum-memory difference remain unknown.
- The cause and authority of recurring `Running`-to-`Off` transitions remain
  unknown.
- H5D supplies no new live readback and makes no claim about the VM's current
  power state.
- The earlier native administrator-token diagnostic, guest baseline, package,
  portable, UI, evidence, and manual-attestation lanes remain `notPerformed`
  where previously recorded.

`blockers[]`:

- No documentation implementation blocker remains.
- Protected merge requires exact-head pull-request checks and review readback,
  followed by separate explicit user confirmation.
- This gate must not merge automatically or advance to power recovery, H5E,
  or `0.3.0`.

## Next gate and commands

`nextGate: protected merge of the H5D documentation-only candidate, conditional
on separate user confirmation; no post-merge operational gate is authorized`

`nextCommands[]`:

1. Commit and push only the three intended documentation files.
2. Open a pull request against protected `master`.
3. Wait for exact-head required checks and review readback.
4. Present the exact candidate SHA, PR state, checks, and review result to the
   user and request separate confirmation before merge.
5. If the user separately authorizes merge, merge only the protected
   documentation PR, then verify the exact remote merge commit and post-merge
   required check.
6. Stop after H5D publication. Do not infer authorization for live inspection,
   power recovery, H5E, or `0.3.0`.

## Safety constraints

`safetyConstraints[]`:

- Do not call `Set-VMMemory` or perform any live VM/configuration mutation.
- Do not inspect or mutate the host, VM, guest, credentials, registry, ACL,
  DPAPI data, disk, network, checkpoint, Notes, ownership, package, portable,
  UI, evidence, or manual-attestation state in this gate.
- Do not create or apply a VM creation, power, network, checkpoint, or restore
  plan.
- Do not open UAC or any interactive credential prompt.
- Do not record or publish a sensitive identity, machine path, raw error,
  screenshot, plan capability, credential material, or ignored operational
  artifact.
- Do not clean, reuse, overwrite, move, or delete ignored evidence.
- Do not push directly to `master`, force-push, delete branches, merge without
  separate confirmation, weaken protection, tag, or publish a Release.

`ownership.previousTask: read-only-after-relay`

`ownership.successorTask: owns-next-gate`

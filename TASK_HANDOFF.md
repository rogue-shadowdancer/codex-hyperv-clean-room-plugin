# TaskHandoff - H5D post-merge operational gate alignment

`relayProtocolVersion: 1`

`relayAttempt: 1`

## Objective and outcome

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

This documentation-only alignment gate records that H5D pull request
[#20](https://github.com/rogue-shadowdancer/codex-hyperv-clean-room-plugin/pull/20)
is merged on protected `master`. The accepted H5D outcome for the one existing
managed VM used by the H5 operational sequence remains:

- startup memory: 8 GiB;
- maximum dynamic memory: 8 GiB.

This baseline is intentionally local to that existing VM. The public
`plan_vm_create` contract remains unchanged: omitted memory inputs still
default to 8 GiB startup memory and 12 GiB maximum dynamic memory.

The H5D documentation change relied on the last authoritative elevated
read-only preflight preceding it, which observed 8 GiB startup memory and
8 GiB maximum dynamic memory. H5D itself performed no new live readback, so
this handoff makes no claim that the VM is currently `Off`, `Running`, or
stable. It does not establish when, why, or by whose authority the earlier
12 GiB-to-8 GiB maximum-memory difference occurred.

This alignment gate changes no runtime, schema, tool catalog, compatibility
fixture, test, installed payload, specification, operations guide, security
guide, troubleshooting guide, or general VM-creation behavior. It performs and
authorizes no Hyper-V, guest, credential, plan/apply, H5E, or `0.3.0` work.

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
- Re-read the complete GitHub collaboration skill and its relevant pull-
  request, review, Actions, and issue procedures.
- Started the required Task Mail session, reserved the single intended tracked
  file, and found no pending coordination request.
- Fetched protected `origin/master` and confirmed it is exact commit
  `df0203bbfeb76ff0a025e50cb8517b648232e0cb`.
- Re-read H5D PR #20 and confirmed its exact final head, protected base,
  successful exact-head checks, merge time, and merge commit.
- Re-read the exact merge commit, its two parents, candidate/merge trees,
  GitHub verification, protected-branch rules, and successful post-merge
  required check.
- Confirmed there is no open pull request and Issue #19 is the repository's
  only open issue.
- Confirmed Issue #19 still uses the superseded H5D operational-recovery label
  and therefore requires a post-publication tracker update.
- Created `codex/h5d-post-merge-alignment` from exact protected
  `origin/master`.
- Reconfirmed that `docs/specification.md` and `docs/operations.md` already
  state the correct H5D 8/8 GiB existing-VM baseline and the unchanged public
  8/12 GiB creation defaults.
- Reconfirmed that `docs/security.md` and `docs/troubleshooting.md` contain no
  conflicting H5D status statement requiring a change.
- Updated only this sanitized handoff. Preserved every runtime, schema,
  catalog, fixture, test, installed payload, other documentation file, old
  worktree, branch, and ignored artifact.
- Addressed two fail-closed validation findings without broadening scope:
  retained the required H4/G9 `validate-gate4.ps1` non-execution boundary and
  restored the single absolute `projectPath` field required by the handoff
  contract.
- Performed no host inspection, UAC elevation, live VM read, plan creation,
  apply, guest operation, credential operation, evidence operation, or machine
  mutation.

## Changed files and repository state

`changedFiles[]`:

- `TASK_HANDOFF.md` - post-merge H5D conclusion, publication evidence,
  unresolved boundaries, and the separately gated H5D-R1 route.

`repositoryState`:

- Branch: `codex/h5d-post-merge-alignment`.
- Base: protected `origin/master` commit
  `df0203bbfeb76ff0a025e50cb8517b648232e0cb`.
- The tracked worktree was clean before this gate.
- No pre-existing tracked user change was present.
- Existing ignored validation dependencies, operational evidence, saved
  checkouts, other worktrees, and remote gate branches remain untouched.
- Publication uses one protected pull request containing only this handoff.
- The user's standing merge authorization applies only after every required
  exact-head validation, review, wait-window, mergeability, conversation, and
  protection condition is satisfied. It does not authorize an automatic
  merge, direct `master` push, force-push, branch deletion, tag, Release, or
  protection change.
- Issue #19 may be updated only after this alignment pull request is merged and
  its exact merge commit plus post-merge required check are verified.

## Verification

`verification[]`:

- H5D PR #20 final head:
  `bf729739070de66a1c3f0923215921fca142ee22`.
- H5D PR #20 protected base:
  `9f82e6a0cb2315720eb7548e3d7ce82660f92949`.
- H5D PR #20 exact-head required-check runs `30212777693` and `30212776085`
  both completed successfully.
- H5D PR #20 merged at `2026-07-26T18:06:07Z` as exact commit
  `df0203bbfeb76ff0a025e50cb8517b648232e0cb`.
- The merge has exactly the protected base and PR head as parents, is a valid
  GitHub web-flow signed commit, and has the same tree
  `287e69008a12a77c58d37467c18b0f82ca6beef0` as the PR head.
- Post-merge `master` required-check run `30213996961` completed successfully
  on exact merge SHA `df0203bbfeb76ff0a025e50cb8517b648232e0cb`.
- Protected `master` remains strict, requires
  `public-release-validation`, requires conversation resolution, and
  disallows force-push and deletion.
- Source review confirms that the existing-VM H5D baseline remains 8 GiB
  startup and 8 GiB maximum dynamic memory, while the public omitted-input
  defaults remain 8 GiB startup and 12 GiB maximum dynamic memory.
- Current GitHub readback shows zero open pull requests and exactly one open
  repository issue, Issue #19.
- The historical complete H4/G9 installed-copy validator,
  `scripts/validate-gate4.ps1`, is not run because its installed-host smoke
  would broaden this documentation-only gate into host inspection. The
  aggregate publication validator instead runs the applicable CI-safe
  `validate-gate4-ci.ps1` lane.
- `scripts/validate-docs.ps1`: passed with 17 documents, 98 local links,
  strict UTF-8, and zero mojibake markers.
- `scripts/validate-public-release.ps1`: all 13 aggregate checks passed with
  zero real guest operations and zero real Hyper-V mutations.
- Exact staged `git diff --cached --check`: passed.
- Exact staged scope and sensitive-content scan: passed with only
  `TASK_HANDOFF.md` staged and only its required `projectPath` absolute path.
- Exact staged substantive review: zero actionable findings.

These local checks bind the exact staged alignment candidate. Hosted checks
and the fresh review window must still bind its exact pull-request head before
merge. Neither the prior H5D evidence nor this documentation gate establishes
current VM power state, operational stability, the cause of earlier live
differences, a guest baseline, or any new machine-backed result.

## Unresolved issues and blockers

`unresolvedIssues[]`:

- The cause, timing, and authority of the observed 12 GiB-to-8 GiB live
  maximum-memory difference remain unknown.
- The cause and authority of recurring `Running`-to-`Off` transitions remain
  unknown.
- H5D and this alignment gate supply no new live readback and make no claim
  about the VM's current power state or stability.
- The native administrator-token diagnostic, credential-profile publication,
  `inspect_guest`, package lifecycle, portable, UI, evidence, and
  manual-attestation lanes remain `notPerformed` where previously recorded.
- H5D-R1, conditional H5D-R2, H5E, P3.1, P3.2, P3.3, and Birdsgone G4.1 have
  not started.

`blockers[]`:

- No documentation implementation blocker is known.
- This alignment candidate must not merge until its exact staged validation
  and substantive review reach zero actionable findings, its exact-head
  required checks pass, its fresh 30-minute review window completes, every
  actionable conversation is resolved, mergeability is clean, and protection
  is re-read unchanged.
- Any candidate change resets affected validation, substantive review, hosted
  checks, and the complete fresh review window.
- Issue #19 must remain unchanged until the alignment pull request is merged
  and post-merge required CI passes.
- This gate must not advance into H5D-R1, power recovery, H5E, credentials,
  guest work, or `0.3.0`.

## Next gate and commands

`nextGate: protected publication and post-merge Issue #19 readback for this
alignment candidate; H5D-R1 remains a future named operational gate and may be
promoted only by a separately authorized post-merge task/handoff`

`nextCommands[]`:

1. Stage only `TASK_HANDOFF.md`.
2. Run `scripts/validate-docs.ps1`,
   `scripts/validate-public-release.ps1`, exact staged
   `git diff --cached --check`, a sensitive-content/scope scan, and a
   substantive staged review to zero actionable findings.
3. Commit as `docs: align post-H5D operational gates`, push the feature
   branch, and open a non-draft pull request against protected `master`.
4. Wait for exact-head required checks and a fresh 30-minute review window.
   Re-read the exact head/base, checks, reviews, comments, threads,
   mergeability, and protection. Restart the applicable gates after any
   candidate change.
5. If and only if every merge condition is satisfied, use the user's standing
   authorization to perform one ordinary protected merge locked to the exact
   reviewed head SHA.
6. Verify the exact remote merge commit, parents, tree, signature, protection,
   and successful post-merge required check.
7. Update Issue #19 once, then read it back: mark H5D complete as the existing
   managed-VM 8/8 GiB documentation baseline revision; add H5D-R1 read-only
   revalidation and conditional H5D-R2 guarded recovery before H5E; retain
   H5E and P3.1 through P3.3 as incomplete; and state that current VM power,
   recovery, credentials, guest work, H5E, and `0.3.0` were not performed.
8. Stop. H5D-R1 belongs to a new task and requires separate authorization.

## Safety constraints

`safetyConstraints[]`:

- Do not call `Set-VMMemory` or perform any live VM/configuration mutation.
- Do not inspect or mutate the host, VM, guest, credentials, registry, ACL,
  DPAPI data, disk, network, checkpoint, Notes, ownership, package, portable,
  UI, evidence, or manual-attestation state.
- Do not create or apply a VM creation, power, network, checkpoint, or restore
  plan.
- Do not open UAC or any interactive credential prompt.
- Do not record or publish a sensitive identity, machine path, raw error,
  screenshot, plan capability, credential material, or ignored operational
  artifact.
- Do not clean, reuse, overwrite, move, or delete ignored evidence.
- Do not push directly to `master`, enable automatic merge, force-push, delete
  branches, weaken protection, tag, or publish a Release.
- Repository merge authorization does not authorize Hyper-V apply, UAC,
  credentials, guest work, account/policy change, or any later gate.

`ownership.previousTask: read-only-after-relay`

`ownership.successorTask: owns-next-gate`

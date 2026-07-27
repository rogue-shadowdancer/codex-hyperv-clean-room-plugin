# TaskHandoff - H5D-R1 read-only operational revalidation

`relayProtocolVersion: 1`

`relayAttempt: 1`

## Objective and outcome

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

H5D-R1 completed the separately authorized, read-only operational
revalidation of the one existing managed VM used by the H5 sequence. At the
authoritative elevated readback, the VM was `Off` and every protected
non-power structural invariant matched the accepted H5D baseline:

- generation 2, verified ownership, and a verified differencing-disk chain;
- one checkpoint, automatic checkpoints disabled, and no automatic-checkpoint
  recovery requirement;
- 4 virtual processors;
- 8 GiB startup memory and 8 GiB maximum dynamic memory;
- Secure Boot and vTPM enabled; and
- one attached primary network adapter on an internal virtual switch.

The public `plan_vm_create` contract remains unchanged: omitted memory inputs
still default to 8 GiB startup memory and 12 GiB maximum dynamic memory. The
existing VM's accepted 8/8 GiB baseline is not a new product default.

This readback establishes only the observed state at the time of H5D-R1. It
does not establish power-state stability, when or why the earlier
12 GiB-to-8 GiB maximum-memory difference occurred, or what caused historical
`Running`-to-`Off` transitions. Bounded provenance sources could not be read
without broadening the approved elevated collector, so no actor or cause is
attributed.

Because the VM was `Off`, all non-power invariants matched, and no active plan
was present, a separate H5D-R2 guarded power-recovery gate is now eligible.
H5D-R1 did not create a power plan, start the VM, inspect the guest, initialize
credentials, or authorize H5D-R2.

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

- Re-read every listed repository authority, GitHub Issue #19, and the complete
  installed clean-room skill before the live readback.
- Started Task Mail sessions for the plugin and Birdsgone repositories and
  found no pending coordination request.
- Confirmed that another active task exclusively owns Birdsgone G5, so this
  gate did not write to or duplicate work in the Birdsgone repository.
- Created `codex/h5d-r1-read-only-revalidation` from exact protected
  `origin/master` commit
  `fc7c853503c21d76a81589da6be057a578e2f165`.
- Revalidated the installed plugin inventory: all 31 claimed payload files
  are present, each installed byte sequence matches its install-manifest hash,
  and there are zero missing, unexpected, or reparse files.
- Investigated the source-bound install check's negative aggregate result.
  The installed payload remains internally exact; the aggregate mismatch is
  limited to its older recorded source commit and raw source-worktree line
  endings in four payload files. The normalized file content is unchanged,
  and no runtime payload drift was found.
- Confirmed that the installed public MCP server still exposes exactly 20
  unique tools.
- Confirmed that the credential root is absent and no credential profile is
  configured.
- Parsed the current plan-state inventory and found three historical consumed
  plans, zero unconsumed plans, and zero live power plans.
- Ran non-elevated `inspect_host` successfully. Non-elevated VM enumeration
  failed closed because the process lacked the required host permissions and
  produced no VM conclusion.
- Attempted a bounded, read-only provenance scan. Protected event channels and
  scheduled-task data were not readable at that access level; the scan
  supplied no causal attribution.
- Prepared a fresh, ignored, create-only elevated collector whose public MCP
  calls were limited to `inspect_host`, `list_vms`, and `inspect_vm`. Static
  Node and PowerShell parsing passed, the result target was absent, and the
  tracked worktree remained clean before elevation.
- The first UAC attempt was cancelled and produced no result. After separate
  explicit user approval for one retry, the fresh collector completed once
  and returned only sanitized structural fields.
- Confirmed the elevated host readback was ready, the catalog still contained
  20 unique tools, exactly one managed VM was present, and the host, inventory,
  and VM inspection calls each reported `changed=false`.
- Confirmed the VM was `Off` at read time and that every protected structural
  invariant matched the accepted H5D 8/8 GiB baseline.
- Performed no plan creation, apply, VM start, guest inspection, credential
  prompt or initialization, account or policy change, package operation,
  evidence publication, tag, or Release.

## Changed files and repository state

`changedFiles[]`:

- `TASK_HANDOFF.md` - sanitized H5D-R1 result, verification boundary,
  unresolved causes, and the separately gated H5D-R2 route.

`repositoryState`:

- Branch: `codex/h5d-r1-read-only-revalidation`.
- Base: protected `origin/master` commit
  `fc7c853503c21d76a81589da6be057a578e2f165`.
- The tracked worktree was clean before this gate.
- No pre-existing tracked user change was present.
- Fresh ignored operational helpers and local results remain untracked and
  unpublished. Existing ignored evidence, saved checkouts, other worktrees,
  and remote branches remain untouched.
- Publication is limited to one protected pull request containing only this
  sanitized handoff.
- The user's standing merge authorization applies only after every required
  exact-head validation, review, wait-window, mergeability, conversation, and
  protection condition is satisfied. It does not authorize an automatic
  merge, direct protected-branch push, force-push, branch deletion, tag,
  Release, or protection change.
- H5D-R2 and every later machine gate require their own authorization and are
  outside this task.

## Verification

`verification[]`:

- Installed version: `0.2.0+codex.20260723113253`.
- Installed inventory: 31 claimed files, zero missing, zero installed-vs-
  manifest hash mismatches, zero unexpected files, and zero reparse files.
- Public MCP catalog: exactly 20 tools and 20 unique names.
- Credential state: root absent and zero profiles.
- Plan state: three historical consumed plans, zero unconsumed plans, and zero
  live power plans.
- Elevated host result: Hyper-V commands available, hypervisor present,
  elevated host access confirmed, host fingerprint present, no warnings or
  stderr, and `changed=false`.
- Managed inventory: exactly one VM, with both list and inspect calls reporting
  `changed=false`.
- Power state at authoritative readback: `Off`.
- Ownership and storage: ownership verified; storage binding is
  `verifiedDifferencingChain`; the disk chain is verified at depth 2.
- Checkpoints: one checkpoint; automatic checkpoints disabled; automatic-
  checkpoint recovery not required.
- Compute and memory: generation 2, 4 processors, 8 GiB startup memory, and
  8 GiB maximum dynamic memory.
- Platform security: Secure Boot and vTPM enabled.
- Network: one primary adapter, attached to an internal virtual switch.
- Inspector warnings: zero.
- The historical H4/G9 installed-copy validator,
  `scripts/validate-gate4.ps1`, is not run for this sanitized handoff
  publication. Its installed-host smoke belongs to the earlier installation
  gate; `scripts/validate-public-release.ps1` supplies the applicable CI-safe
  aggregate coverage here.

These results bind the single successful elevated H5D-R1 readback. They do not
claim that `Off` is a desired or stable state, identify who or what changed
power state, or authorize a transition to `Running`.

## Unresolved issues and blockers

`unresolvedIssues[]`:

- The cause, timing, and authority of the observed 12 GiB-to-8 GiB live
  maximum-memory difference remain unknown.
- The cause and authority of historical `Running`-to-`Off` transitions remain
  unknown.
- H5D-R1 observed `Off` once; it did not establish stability or a causal
  history.
- Protected provenance sources were not read by the approved collector, and
  no actor or scheduled action may be inferred from inaccessible data.
- The native administrator-token diagnostic, credential-profile publication,
  `inspect_guest`, package lifecycle, portable, UI, evidence, and
  manual-attestation lanes remain `notPerformed`.
- H5D-R2, H5E, P3.1, P3.2, P3.3, and Birdsgone clean-room VM acceptance have
  not started.

`blockers[]`:

- No H5D-R1 structural blocker remains: the read-only result is authoritative,
  internally unambiguous, and matches the accepted non-power baseline.
- This documentation candidate must not merge until its exact staged
  validation and substantive review reach zero actionable findings, its exact-
  head required checks pass, its full fresh review window completes, every
  actionable conversation is resolved, mergeability is clean, and protection
  is re-read unchanged.
- Any candidate change resets the affected validation, substantive review,
  hosted checks, and complete fresh review window.
- H5D-R2 remains blocked on its own gate and authorization. Repository merge
  authorization does not authorize creation or application of a power plan.

## Next gate and commands

`nextGate: H5D-R2 conditional guarded power recovery, only after this H5D-R1
handoff is published, merged, verified, and relayed to a new task`

`nextCommands[]`:

1. Stage only `TASK_HANDOFF.md`.
2. Run `scripts/validate-docs.ps1`,
   `scripts/validate-public-release.ps1`, exact staged
   `git diff --cached --check`, a sensitive-content/scope scan, and a
   substantive staged review to zero actionable findings.
3. Commit as `docs: record H5D-R1 read-only revalidation`, push the feature
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
7. Update Issue #19 once and read it back: mark H5D-R1 complete with the
   sanitized `Off` and matching-structure result; keep H5D-R2 conditional and
   unperformed; retain all later gates as incomplete.
8. Relay H5D-R2 to a new task. Do not create a power plan in this task.
9. In H5D-R2, first re-read current state and active-plan inventory. Only if
   the VM remains `Off`, every non-power invariant still matches, and no live
   plan exists may that task create one fresh `plan_vm_power(start)`.
10. Show the exact `Off`-to-`Running` diff, target, effects, and expiry to the
    user. Obtain separate confirmation for that exact plan before one
    `apply_vm_power`; do not infer this authorization from a PR merge.
11. After an authorized apply, immediately re-inspect every protected
    invariant and perform the required stability observation. Stop without
    retry on expiry, fingerprint drift, ambiguity, power regression, or any
    structural mismatch.

## Safety constraints

`safetyConstraints[]`:

- Do not call `Set-VMMemory` or perform any live VM/configuration mutation.
- Do not create or apply a VM creation, power, network, checkpoint, or restore
  plan in this task.
- Do not start, stop, pause, save, checkpoint, restore, reset, or otherwise
  change a VM.
- Do not inspect or mutate the guest, credentials, registry, ACL, DPAPI data,
  account, group, policy, disk, network, checkpoint, Notes, ownership, package,
  portable, UI, evidence, or manual-attestation state.
- Do not open another UAC or any interactive credential prompt in this task.
- Do not record or publish a sensitive identity, machine path, raw error,
  screenshot, plan capability, credential material, or ignored operational
  artifact.
- Do not clean, reuse, overwrite, move, or delete ignored evidence.
- Do not push directly to the protected branch, enable automatic merge,
  force-push, delete branches, weaken protection, tag, or publish a Release.
- Repository merge authorization does not authorize Hyper-V apply, UAC,
  credentials, guest work, account/policy change, or any later gate.

`ownership.previousTask: read-only-after-relay`

`ownership.successorTask: owns-next-gate`

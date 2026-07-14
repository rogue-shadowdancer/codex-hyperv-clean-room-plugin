# TaskHandoff - Gate 2 complete; Birdsgone Gate 3 next

`relayProtocolVersion: 1`

`relayAttempt: 1`

## Objective

Gate 2 implementation and acceptance are complete. Preserve the final plugin
snapshot, create the exact non-amended commit
`fix: close Gate 2 runtime and documentation gaps`, verify the clean local end
state, and relay only the Birdsgone profile/acceptance-documentation gate using
`gpt-5.6-terra` with high thinking.

## Specification paths

- `AGENTS.md`
- `docs/specification.md`
- `docs/README.md`
- `TASK_HANDOFF.md`
- sibling `birdsgone/AGENTS.md`

## Completed work

- Gate 1.1 remains `f98cf7a43f8e186fb2981e55fcdbe66081107d8e`.
- The original Gate 2 body remains
  `e40766c26c3bb112623315c670bc4290bd553dad`.
- The complete Gate 2 runtime implements the frozen 16-tool MCP surface,
  guarded state/ownership plans, the mock and production Hyper-V adapters, the
  fixed supervised PowerShell Direct guest worker, declarative profile
  execution, evidence validation/export, credential enrollment, documentation,
  reproducible validation, and CI checks.
- Earlier review repairs cover exact workspace ACLs and ownership, suspended
  job supervision, retained process handles, operation-bound worker/results,
  exact restore checkpoint rebinding, final evidence inventory reopen/rehash,
  atomic credential publication, and bidirectional artifact/stage semantics.
- The third-review findings are closed:
  1. VM create apply reopens the recorded root as the same normalized local
     non-reparse directory, recomputes the VM/VHDX paths, and repeats path and
     volume binding immediately before production `New-VM`. A plan-to-apply
     junction replacement fails with `PLAN_DRIFT` and `changed: false`.
  2. Production target-volume identity requires one non-empty
     `Get-Volume.UniqueId`; no drive-letter fallback remains. Missing identity
     and same-root/different-ID drift fail closed.
  3. VM creation, checkpoint creation, and checkpoint restore report bounded
     partial identities and recovery warnings. Pre-entry failures use
     `changed: false`; entered indeterminate or confirmed effects use
     `changed: true`. Mock fault injection covers before, entered, and after
     phases for all three mutations.
  4. JSON-RPC/MCP method params are object-shaped and closed. Initialize
     requires typed `protocolVersion`, `capabilities`, and `clientInfo`; ping,
     tools/list, tools/call, and initialized-notification shapes have
     adversarial transport coverage.
  5. The specification now separates mock execution, parser/static production
     source guarantees, and the bounded production-adapter read-only host
     smoke.

## Changed files

`changedFiles[]`:

- 46 intended Gate 2 paths: 28 modified and 18 added before commit.
- Modified areas: CI; root README and security/handoff documentation; docs hub,
  profile guide, and specification; credential initializer; MCP server and
  runtime libraries; evidence schema; companion skill; validation scripts;
  Gate 1/Gate 2/schema/static tests; and legacy evidence fixtures.
- Added areas: security/operator/architecture/evidence/troubleshooting docs;
  `GuestWorker.ps1`; pinned development requirements and isolated Python/docs
  helpers; the bounded real-host read-only test; and evidence semantic
  fixtures.
- No user-owned change overlaps the plugin repository.

## Repository state

`repositoryState`:

- Project path: this saved repository (`.`).
- Branch before the completion commit: `master`.
- Pre-commit HEAD: `e40766c26c3bb112623315c670bc4290bd553dad`.
- Pre-commit state: 46 intended Gate 2 paths, nothing staged, no remotes.
- Required commit: exactly
  `fix: close Gate 2 runtime and documentation gaps`, without amend.
- Installation and push state: no plugin install, remote, or push occurred.
- Birdsgone remained a separate unborn `main` repository with 31 top-level and
  369 total pre-existing untracked user-owned paths. Gate 2 made no Birdsgone
  write.

## Verification

`verification[]`:

- Windows PowerShell parser: 19 files, zero errors.
- Focused mock runtime: 1,179 assertions, exactly 16 tools, four protocol
  versions, one concurrent apply winner, and `realHyperVMutations=0`.
- Fault injection: before/entered/after coverage for VM create, checkpoint
  create, and checkpoint restore, including partial identity, effect state,
  recovery-warning projection, and changed semantics.
- Transport: malformed/scalar/null/array/unknown parameter probes plus valid
  omitted/empty forms for initialize, ping, tools/list, tools/call, and
  initialized state transitions.
- No-argument `scripts/validate-gate2.ps1`: green with isolated Python; five
  schemas; 11 valid, 13 schema-invalid, and 13 semantic-invalid fixtures; five
  runtime schema samples; 84 strict UTF-8 files; 46 JSON files; 57 links; 39
  sensitive-file checks; and `realHyperVMutations=0`.
- Documentation: 11 documents, 57 links, strict UTF-8, and zero mojibake.
- Production-adapter execution stayed bounded to `inspect_host` and the
  pre-mutation missing-ISO rejection. No production guest call, credential
  initialization, install, network dependency action, or real Hyper-V mutation
  ran.
- Three entirely fresh read-only Windows-security, state/protocol, and
  docs/reproducibility signers independently reproduced the 46-row candidate
  manifest `ebc1ebbac3202107bd80697a1f16db641bc74cebc02928cd8ebafedcb2cdd33d`
  and each returned `ZERO ACTIONABLE FINDINGS` with no file change.
- The finalized handoff snapshot must be revalidated and freshly signed before
  the exact commit; any later code or documentation change invalidates signoff.

## Unresolved issues

`unresolvedIssues[]`: none for Gate 2. Real VM/checkpoint mutation, production
PowerShell Direct behavior, live credential persistence, plugin installation,
marketplace/cache discovery, package execution, and clean-machine evidence are
deliberately outside this gate and remain unproved.

## Blockers

`blockers[]`: none.

## Next gate

`nextGate`:

- Name: Birdsgone Gate 3 profile and acceptance documentation only.
- Project path: sibling saved repository (`..\birdsgone`).
- Model: `gpt-5.6-terra` with high thinking.
- Boundary: author/validate the Birdsgone clean-room test profile and its
  acceptance documentation against this committed Gate 2 contract. This relay
  does not authorize plugin edits, plugin installation, dependency
  installation, production guest execution, credential enrollment, or any real
  Hyper-V mutation.

## Next commands

`nextCommands[]`:

1. Before relay, stage only the 46 intended plugin paths, create the exact
   non-amended commit, and verify clean branch/HEAD/no-remotes/no-install plus
   unchanged Birdsgone counts and content fingerprint.
2. Create a new task targeted at the saved Birdsgone project, using
   `gpt-5.6-terra` with high thinking, and pass a bounded TaskHandoff that names
   only the profile/acceptance-documentation gate.
3. In the successor, read `birdsgone/AGENTS.md` and its current requirements and
   handoff files before any edit; preserve all 369 pre-existing untracked
   user-owned paths and do not broaden the gate into application code or live
   Hyper-V work.

## Safety constraints

`safetyConstraints[]`:

- Preserve plugin version `0.1.0`, schema version 1, exactly 16 tools, and five
  public schemas.
- Do not add deletion/arbitrary-execution surfaces or accept plaintext
  credentials.
- Do not run production guest operations, credential initialization, plugin
  installation, real VM/VHDX/checkpoint mutation, remote creation, or push as
  part of Gate 2 completion.
- Treat every Birdsgone path as user-owned until the successor reads its
  governing files and explicitly establishes the Gate 3 edit set.

## Ownership

- `ownership.previousTask: read-only-after-relay`
- `ownership.successorTask: owns-next-gate`

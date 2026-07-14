# TaskHandoff - Gate 5 private publication candidate

`relayProtocolVersion: 1`

`relayAttempt: 1`

## Objective

Complete Gate 5 only: validate and review the final source candidate, preserve
the existing `master` history, create the exact private GitHub repository,
push normally, require Actions success and two fresh remote acceptance reviews,
record the final state, and stop at the Gate 5 boundary.

## Specification paths

`specificationPaths[]`:

- `AGENTS.md`
- `docs/specification.md`
- `docs/installation.md`
- `docs/maintenance.md`
- `docs/release-process.md`
- `CHANGELOG.md`
- `TASK_HANDOFF.md`

## Completed work

`completedWork[]`:

- Gate 2 is committed at `248a6808d4511d26b0014380778dd23601829824`
  with base version `0.1.0`, schema version 1, exactly 16 MCP tools, and five
  public schemas.
- Gate 3 produced the separate Birdsgone profile and acceptance documentation;
  Birdsgone is outside this repository and is not publishable in Gate 5.
- Gate 4 is committed at `a462199ae2b7b983cb430d93ce18e6c4d31f4575`.
  It implements the source-validated, ownership-marked personal install,
  helper-only marketplace workflow, commit-bound installed-copy acceptance,
  and one cachebuster `0.1.0+codex.20260714150737`.
- The Gate 5 candidate fixes Windows PowerShell 5.1 installed-copy redirected
  stdin so it emits UTF-8 without a BOM and restores the console encoding.
- The candidate adds the changelog, private publication runbook, full-history
  publication-hygiene scan, seven fail-closed policy regressions, explicit
  documentation/release validation, and a CI-safe Gate 4 path that skips all
  real-host and personal install state.
- Replacement review findings expanded the scanner to reject nested Birdsgone,
  cache, evidence, checkpoint-disk, and Hyper-V VM-state paths; exact-key
  JSON/YAML/assignment secret literals now cover tests too, with only one
  path/key/value-bound rejection sentinel exception. The publication runbook
  now requires one exact approved `origin` URL before push.
- The Actions workflow fetches full history and separately runs documentation,
  publication-sensitive, and CI-safe Gate 4 checks.

## Changed files

`changedFiles[]`:

- Release state and navigation: `CHANGELOG.md`, `README.md`,
  `docs/README.md`, `docs/release-process.md`, and this handoff.
- Validation and CI: `.github/workflows/ci.yml`,
  `scripts/validate-docs.ps1`, `scripts/validate-gate2.ps1`,
  `scripts/validate-gate4-ci.ps1`, `scripts/validate-install-source.ps1`,
  `tests/publication_hygiene_policy_tests.py`,
  `tests/publication_hygiene_tests.py`, and
  `tests/static_quality_tests.py`.
- Installed-copy harness: `tests/gate4-installed-copy.tests.ps1`.
- No plugin payload, public schema, MCP tool, schema-v1 semantic, guest worker,
  production adapter, cachebuster, version, or Birdsgone file changes.

## Repository state

`repositoryState`:

- Branch: `master`.
- Candidate parent: `a462199ae2b7b983cb430d93ce18e6c4d31f4575`.
- The six existing commits must remain unchanged. Gate 5 uses additive commits
  only; no amend, rebase, filter, force push, or history rewrite is permitted.
- Before the terminal Gate 5 commit, the dirty paths are the bounded candidate
  and no pre-existing change belongs to the user. The additive commit containing
  this handoff is the immutable terminal repository state; its working tree
  must be clean and no publishable repository edit may follow it.
- There is no configured remote or upstream at candidate-authoring time. The
  required destination is the private repository
  `rogue-shadowdancer/codex-hyperv-clean-room-plugin`.

## Verification

`verification[]`:

- PowerShell parsing and Python compilation pass for all affected scripts and
  tests. Documentation validation reports 15 required documents, 79 local
  links, strict UTF-8, no BOM, and zero mojibake markers.
- Seven publication-policy regressions cover sensitive JSON/YAML/assignment
  forms, safe references/redaction, exact test sentinels, and forbidden nested
  state paths.
- The publication-hygiene scan covers 100 prospective files, all six commits,
  and 169 unique historical blob/path versions with zero forbidden artifacts,
  sensitive findings, BOMs, or non-UTF-8 files.
- The CI-safe Gate 4 validator passes with 20 payload files, five public
  schemas, 33 installer-security assertions, and zero personal install,
  marketplace, installed-copy, real-host, guest, or Hyper-V mutation
  operations.
- The no-argument Gate 4 suite passes with all four install booleans true, one
  marketplace entry, 20 payload files, 16 tools, commit-bound source/install
  metadata, read-only `inspect_host`, missing-ISO `INVALID_ISO`, and zero real
  guest operations or Hyper-V mutations.
- Terminal acceptance requires three external pre-push zero-actionable-finding
  reviews on this content before its commit, followed by exact-commit install,
  publication, Actions, and two external remote reviews. Those reports and
  final command readbacks are external gate evidence and do not cause another
  repository edit.
- Remote visibility, Actions, remote UTF-8 readback, final SHA equality, branch
  tracking, and final installed-copy agreement remain deliberately unclaimed
  until they are read back after publication.

## Unresolved issues

`unresolvedIssues[]`:

- No known repository source or documentation issue remains. Gate 5 completion
  is conditional on the external terminal-acceptance protocol below.
- Three fresh pre-push review reports must have zero actionable findings on the
  terminal content before it is committed.
- The installed copy, private remote, Actions, local/remote SHA and tracking,
  UTF-8/no-BOM source, and two fresh remote reviews must all agree with the one
  immutable terminal commit. The completing task retains those final command
  readbacks and review reports externally and makes no later repository edit.

## Blockers

`blockers[]`: none.

## Next gate

`nextGate`:

- Name: Gate 6 clean-machine and real-guest validation, only after every Gate 5
  terminal acceptance condition succeeds.
- Project: this saved plugin repository.
- Scope: not started and not authorized by this handoff. Stop at the Gate 5
  boundary; do not begin credential, real guest, package lifecycle, VM, or
  checkpoint work.

## Next commands

`nextCommands[]`:

1. Require three external replacement pre-push reviews with zero actionable
   findings on this complete content.
2. Commit additively once; that commit is the terminal Gate 5 repository state.
   Reinstall from it without a new cachebuster and rerun full validation.
3. Create only the exact private repository, verify visibility plus the single
   approved fetch and effective push URL, push normally, and wait for Actions.
4. Require two external remote acceptance reviews on that immutable commit,
   report their evidence to the user, and make no post-commit repository edit.

## Safety constraints

`safetyConstraints[]`:

- Private GitHub publication only. Never make the repository public or
  internal, and do not create a tag or GitHub Release.
- Do not force push, amend, rebase, filter history, change old author metadata,
  or create a new cachebuster.
- Do not publish or modify Birdsgone, VM/VHDX/checkpoint/ISO state, credentials,
  DPAPI material, evidence, installed control files, caches, logs, or other
  machine-specific state.
- Do not run a real guest operation, credential initializer, package lifecycle,
  clean-machine workflow, or Hyper-V mutation. Do not claim those results from
  source, installation, CI, or remote readback.

## Ownership

- `ownership.previousTask: read-only-after-relay`
- `ownership.successorTask: owns-next-gate`

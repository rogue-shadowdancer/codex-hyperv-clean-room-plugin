# TaskHandoff - Gate 5.1 GPL public release candidate

`relayProtocolVersion: 1`

`relayAttempt: 1`

## Objective

Complete Gate 5.1 only: preserve the existing repository and eight historical
commits, add one reviewed GPL-3.0-only `v0.1.1` release commit, validate and
reinstall it, push it while private, require exact-commit CI, switch the same
repository public, configure public settings and protected `master`, verify
anonymous access, publish an annotated tag and source-only GitHub Release, and
stop before Gate 6.

## Specification paths

`specificationPaths[]`:

- `AGENTS.md`
- `docs/specification.md`
- `docs/README.md`
- `README.md`
- `CHANGELOG.md`
- `SECURITY.md`
- `docs/release-process.md`
- `docs/maintenance.md`
- `TASK_HANDOFF.md`

## Completed work

`completedWork[]`:

- Gates 1 through 5 produced the PowerShell 5.1 runtime, frozen schema-v1
  contract, guarded adapters, installation workflow, private repository, and
  accepted installed-copy/CI baseline at
  `8c0adabcf7308539f138b3564a220ab9a691d688`.
- Gate 5.1 source advances the plugin/server base to `0.1.1`, declares
  `GPL-3.0-only`, and includes the complete standard GNU GPL version 3 text.
- The plugin-creator cachebuster helper was invoked exactly once, producing
  `0.1.1+codex.20260715064728`; no marketplace/cache file was hand-edited.
- Public contribution guidance, Contributor Covenant 2.1, issue forms,
  pull-request template, Dependabot, public security reporting, and bilingual
  release documentation are included.
- `public-release-validation` uses full-history checkout, `contents: read`, and
  official v6 Actions pinned to full commit SHAs with version comments.
- Publication validation covers the prospective tree, retained history, raw
  commit-object SHA-256 allowlisting, author/committer/message policy, Actions
  logs, secrets, credentialed URLs, local paths, forbidden machine state,
  license/community contracts, parser/encoding/schema/docs quality, and the
  CI-safe Gate 4 boundary.
- The public contract remains exactly 16 tools, five schemas,
  `schemaVersion: 1`, and four supported MCP protocol versions.

## Changed areas

`changedFiles[]` includes:

- License/community: `LICENSE`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`,
  `.github/ISSUE_TEMPLATE/**`, `.github/pull_request_template.md`, and
  `.github/dependabot.yml`.
- Release state/docs: `README.md`, `CHANGELOG.md`, `SECURITY.md`,
  `docs/README.md`, `docs/specification.md`, `docs/architecture.md`,
  `docs/installation.md`, `docs/maintenance.md`,
  `docs/release-process.md`, `docs/troubleshooting.md`, and this handoff.
- Version/validation: the plugin manifest and server version, install/version
  contract checks, `.github/workflows/ci.yml`, public-release validators,
  hygiene regressions, Actions-log scanner, and anonymous readback script.
- No public MCP tool name, tool input schema, schema-v1 semantic, evidence
  derivation, guest dispatcher, production mutation path, or public schema is
  changed.

## Repository state

`repositoryState`:

- Branch: `master`.
- Candidate parent and private remote baseline:
  `8c0adabcf7308539f138b3564a220ab9a691d688`.
- The eight historical commits and all of their object IDs must remain
  unchanged. Their accepted legacy identity is represented in current source
  only by SHA-256 digests of the exact raw commit objects.
- Gate 5.1 permits one additive release commit with exact message
  `release: open source v0.1.1 under GPL-3.0-only` and the repository-local
  noreply identity. Amend, rebase, filter, force push, and clean export are
  forbidden.
- Candidate edits belong to Gate 5.1; no pre-existing user work was present.
- The remote remains private until all local reviews, commit/reinstall, private
  push, exact-commit CI, GPL detection, and Actions-log scan pass.

## Verification

`verification[]`:

- Candidate validation must pass PowerShell parsing, Python compilation,
  JSON/Draft 2020-12/YAML/Markdown/link validation, strict UTF-8/no-BOM/no
  mojibake, `git diff --check`, plugin validation, skill validation, Gate 1,
  no-argument Gate 2, docs, CI-safe Gate 4, public-release contracts, and
  publication-hygiene regressions/current-tree/history/identity scans.
- Before the release commit, three initial read-only reviews may find issues;
  all findings are fixed and affected checks rerun. Three entirely fresh final
  reviews must each report `actionableFindings: []` before commit.
- After commit, reinstall without a second cachebuster and run no-argument
  Gate 4. Source/install version, cachebuster, commit, file inventory, hashes,
  marketplace state, 16 tools, read-only `inspect_host`, `INVALID_ISO`, and
  zero real mutations must agree.
- Push while private and require `public-release-validation` success at the
  exact commit. Then rescan every Actions log before visibility changes.
- Public acceptance requires anonymous SHA/license/README/manifest/skill/
  Chinese-document readback, exact settings and branch protection, annotated
  unsigned `v0.1.1`, green tag CI, source-only non-prerelease GitHub Release,
  and two fresh zero-finding post-public reviews.
- Public-state readbacks and reviewer reports are external evidence. The source
  freezes at the public switch and is not edited merely to record those facts.

## Unresolved issues

`unresolvedIssues[]`:

- The additive release commit, final reinstall, private push/CI, visibility
  switch, GitHub settings/protection, anonymous readback, tag, Release, and
  post-public reviewers remain external acceptance steps until performed by
  the owning Gate 5.1 task.
- Any source issue found before public visibility requires an additive private
  fix commit and repeated affected validation/review/install/CI.
- Any source issue found after public visibility must use a public branch,
  pull request, required CI, review, and protected merge. Re-privating is not a
  rollback strategy.

## Blockers

`blockers[]`: none.

## Next gate

`nextGate`:

- Name: Gate 6 clean-machine and real-guest validation.
- State: `notPerformed` and not authorized.
- No credential initialization, live PowerShell Direct guest operation,
  package lifecycle run, VM/checkpoint mutation, clean-machine validation, or
  manual GUI attestation may be inferred from Gate 5.1.

## Next commands

`nextCommands[]`:

1. Run `scripts\validate-public-release.ps1`,
   `scripts\validate-github-actions-history.ps1`, and all affected regression
   checks after the initial-review repairs.
2. Obtain three entirely fresh final read-only reviews and require
   `actionableFindings: []` from each.
3. Verify the repository-local noreply identity, create the exact additive
   release commit, reinstall without a second cachebuster, and run the
   no-argument Gate 4 plus source/install hash and commit readback.
4. Fetch and push `master` normally while private; wait for exact-commit
   `public-release-validation`, require GitHub GPL detection, and rescan every
   Actions log.
5. Switch the same repository public with the authorized `gh repo edit`
   visibility command; configure the frozen metadata/features, vulnerability
   reporting, and exact branch-protection payload.
6. Run anonymous public readback and
   `scripts\validate-public-github-settings.ps1` against the release SHA.
7. Create and normally push the annotated unsigned `v0.1.1` tag, require green
   tag CI, and create the non-prerelease source-only GitHub Release with no
   assets.
8. Obtain the two fresh post-public read-only reviews, verify source/install/
   marketplace/remote/tag/Release/protection consistency and Birdsgone
   separation, then report Gate 6 as `notPerformed`.

## Safety constraints

`safetyConstraints[]`:

- Preserve the existing URL, branch, eight commits, and all historical SHAs.
- Never publish or modify Birdsgone; its name appears only to describe the
  separation boundary.
- Never commit VM/VHDX/checkpoint/ISO, credential/DPAPI, evidence, cache, log,
  installed-control, or machine-specific state.
- Tests use mock adapters. The installed smoke is limited to read-only host
  inspection and nonexistent-ISO rejection with zero real mutations.
- After the visibility switch, do not modify repository source in this release
  task.

## Ownership

- `ownership.previousTask: read-only-after-relay`
- `ownership.successorTask: owns-next-gate`

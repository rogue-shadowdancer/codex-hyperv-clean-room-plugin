# TaskHandoff - GitHub Actions v7 CI maintenance

`relayProtocolVersion: 1`

## Objective and outcome

This gate is a CI-only maintenance update based on accepted `master` commit
`5d60300f450ed2c57594d94c2065873f12f6bbce`. It replaces the two independently
opened Dependabot proposals with one human-owned candidate that updates:

- `actions/checkout` to v7.0.1 at full commit SHA
  `3d3c42e5aac5ba805825da76410c181273ba90b1`;
- `actions/setup-python` to v7.0.0 at full commit SHA
  `5fda3b95a4ea91299a34e894583c3862153e4b97`.

The public-release contract binds each Action to its exact SHA and exact
version comment. Its regression checks reject the previous SHA, an incorrect
version comment, and any non-40-character Action ref.

The candidate must be accepted only after its protected ready PR has both
exact-head `push` and `pull_request` `public-release-validation` runs pass, all
review threads are resolved, it is merged normally with a two-parent merge
commit, and the exact post-merge `master` run passes. PR #8 and PR #9 remain
open and unmerged until that complete remote acceptance succeeds; they may then
be commented as superseded and closed without merging.

## Release-source and change boundary

- The immutable annotated tag object
  `05ef3f5f61c78865e399eeb7e1673383dccc2db4` still peels exactly to release
  commit `642f20d1d74a54ecbb08115b1a921ca65ef01fb8`.
- The source-only, non-draft, non-prerelease `v0.2.0` GitHub Release remains
  unchanged with zero uploaded assets.
- The accepted H4/G9 installed-source commit is
  `65ff0b9cfc8c924156238295f33dfce7bb143920`. The single owned personal build
  remains `0.2.0+codex.20260722114845`, with 31 payload files and exactly 20
  MCP tools. H4/G9 acceptance through `scripts/validate-gate4.ps1` remains
  commit-bound; this gate neither reinstalls nor edits that copy.
- Advancing `master` for this CI-only change does not invalidate the H4
  commit-bound installed-source acceptance: the immutable release and the
  installed source commit remain fixed, while the maintenance commit changes
  no plugin payload file.
- No plugin runtime, MCP schema/tool, Windows PowerShell behavior, installation
  content, public version, tag, or Release changes in this gate.

## Repository state

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

- Candidate branch: `codex/ci-actions-v7`.
- Candidate base: accepted H4 `master` merge
  `5d60300f450ed2c57594d94c2065873f12f6bbce`.
- Gate-owned files are limited to `.github/workflows/ci.yml`,
  `tests/public_release_contract_tests.py`, `CHANGELOG.md`, and this handoff.
- No pre-existing user changes existed in the root checkout when ownership was
  taken. The installed plugin directory is outside this repository and remains
  read-only and untouched.
- At baseline, Dependabot PR #8 and PR #9 were open, unmerged, and limited to
  separate workflow-pin proposals. They are not ancestry inputs to this human
  candidate.

## Verification contract

Before committing and publishing the exact candidate:

- run `public_release_contract_tests.py`,
  `publication_hygiene_policy_tests.py`, and
  `publication_hygiene_tests.py` with the repository-prepared test Python;
- run `git diff --check`, `validate-docs.ps1`,
  `validate-gate4-ci.ps1`,
  `validate-gate7.ps1 -SkipInheritedBaseline`, and the complete
  `validate-public-release.ps1`;
- require all mock/real-operation counters to remain zero;
- stage only the four gate-owned files and review the exact staged candidate
  for correctness, supply-chain safety, compatibility, publication contract,
  and scope, reaching ZERO ACTIONABLE FINDINGS.

Remote acceptance additionally requires both exact-head PR event runs, branch
protection readback, zero unresolved review threads, normal protected merge,
and the exact post-merge `master` run. No force-push, rebase, squash, admin
bypass, protection change, tag, or Release operation is permitted.

## Safety boundary and unresolved work

`blockers[]`: none for preparing this CI-only candidate.

No real VM, VHDX, checkpoint, power/network transition, credential enrollment,
PowerShell Direct guest action, package lifecycle, portable deployment,
WebDriver, UI, evidence/manual, or clean-machine operation is performed. All
remain `notPerformed`.

This gate does not modify `.github/dependabot.yml`, add bot identities to a
publication-hygiene allowlist, skip bot CI, weaken full-SHA pinning, or change
branch protection. It does not change plugin `0.2.0`, the 20-tool catalog, five
public schema-v1 files, seven schema-v2 files, the `v0.2.0` tag/Release, or the
installed personal build.

## Next product gate

Carry forward H5/G10 unchanged: the separately authorized clean-machine and
real-operation gate may begin only from the accepted installed-source baseline
and only after explicit authorization names the host, VM, credential profile,
artifact, profile, and intended mutation. Without that authorization, limit
the successor to read-only planning and keep every real-operation lane
`notPerformed`.

1. Re-read `AGENTS.md`, this handoff, `docs/specification.md`, the operations
   and security authorities, and the installed manifest before any action.
2. Verify the H4 installed source OID, version, cachebuster, inventory,
   marketplace row, and 20-tool discovery without reinstalling or creating a
   second cachebuster.
3. Preserve `v0.2.0`, all Releases, branch protection, and repository history.
4. Do not reopen or merge superseded Dependabot PR #8/#9 after this CI gate is
   fully accepted and they have been closed.

`ownership.previousTask: read-only-after-relay`

`ownership.successorTask: owns-next-gate`

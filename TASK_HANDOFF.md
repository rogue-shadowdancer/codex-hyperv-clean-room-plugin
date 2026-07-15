# TaskHandoff - Gate 5.2 marketplace GitHub link

`relayProtocolVersion: 1`

`relayAttempt: 1`

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

## Objective

Complete Gate 5.2 only: add one canonical GitHub repository link to the Codex
plugin install surface, keep the existing OpenAI Platform listing aligned with
that URL, preserve base version `0.1.1` and every runtime/schema contract, and
stop before Gate 6.

## Specification paths

`specificationPaths[]`:

- `AGENTS.md`
- `docs/specification.md`
- `docs/README.md`
- `README.md`
- `CHANGELOG.md`
- `docs/maintenance.md`
- `docs/release-process.md`
- `TASK_HANDOFF.md`

## Completed work

`completedWork[]`:

- Gate 5.1 is complete at
  `4bed14c8a7df068fcd8e827418e7c20527a2f271`: the repository is public,
  `master` and annotated tag `v0.1.1` point at that release SHA, the source-only
  GitHub Release is published, and both the branch and tag
  `public-release-validation` runs succeeded.
- GitHub GPL detection, anonymous public readback, repository settings, and
  protected `master` were accepted by Gate 5.1. The protection requires strict
  `public-release-validation`, one approving review, resolved conversations,
  no force push, and no deletion. `validate-public-github-settings.ps1`
  remains the exact settings readback.
- Gate 5.2 adds
  `https://github.com/rogue-shadowdancer/codex-hyperv-clean-room-plugin` as
  `interface.websiteURL` and requires it to match the existing manifest
  `homepage` and `repository` fields exactly.
- The `plugin-creator` cachebuster helper was invoked exactly once for Gate
  5.2, replacing the release build with
  `0.1.1+codex.20260715084043`. No marketplace or Codex config file was
  hand-edited.
- The public-release contract now rejects a missing or divergent plugin URL.
  Documentation distinguishes the immutable `v0.1.1` Release build
  `0.1.1+codex.20260715064728` from the current `master` metadata build.
- Static quality and publication hygiene permit the mandatory absolute
  `projectPath` only in the single structured `TASK_HANDOFF.md` contract field;
  every other Markdown or repository absolute Windows/workspace path remains
  forbidden, with focused policy regressions covering the exception boundary.
- Source commit `c5f0bd8114de182642c9d39204afed995fa41d0f` was merged by PR
  #4 as the ordinary two-parent merge commit
  `ff5765c2b4626c43c5de8b6444553a2408785920`. The exact source SHA passed
  both push and pull-request CI with no unresolved review conversations.
- The first post-merge `master` run exposed a publication-policy gap: GitHub's
  signed web-flow merge uses the public user noreply email for the author and
  the GitHub web-flow committer identity. The fail-closed repair accepts only
  two-distinct-parent, GitHub-signature-envelope merges from this repository's
  `rogue-shadowdancer/codex/*` branches, while preserving message scanning,
  ordinary noreply identity checks, and the eight legacy raw-object digest
  allowlist.
- No MCP runtime file, tool name, tool input/output, schema-v1 semantic,
  production adapter, evidence derivation, or mutation path is changed.

## Changed areas

`changedFiles[]`:

- Plugin metadata: `hyperv-clean-room/.codex-plugin/plugin.json`.
- Contract regressions: `tests/public_release_contract_tests.py`,
  `tests/static_quality_tests.py`, `tests/publication_hygiene_tests.py`, and
  `tests/publication_hygiene_policy_tests.py`.
- Release/current-state documentation: `README.md`, `CHANGELOG.md`,
  `docs/README.md`, `docs/specification.md`, and this handoff.

## Repository state

`repositoryState`:

- Branch: `codex/fix-gate5-2-merge-validation`.
- Current pre-fix-commit HEAD and remote baseline:
  `ff5765c2b4626c43c5de8b6444553a2408785920` on `origin/master`.
- The fix candidate is limited to `TASK_HANDOFF.md`,
  `tests/publication_hygiene_tests.py`, and
  `tests/publication_hygiene_policy_tests.py`; there are no unrelated,
  untracked, or pre-existing user changes.
- The worktree was clean before Gate 5.2. There was no pre-existing user work,
  same-name local/remote branch, or same-head pull request; therefore no
  existing change in this worktree belongs to the user outside this gate.
- The required Gate 5.2 source commit is
  `feat: link plugin listing to GitHub repository`; the repair commit is
  `fix: validate GitHub web-flow merge commits`. Protected `master` changes
  only through pull requests and ordinary merge commits.
- The immutable `v0.1.1` tag and GitHub Release are not moved, replaced, or
  recreated. No `v0.1.2` release is part of this gate.

## Verification

`verification[]`:

- Before Gate 5.2 edits, `scripts/prepare-test-python.ps1` and
  `scripts/validate-public-release.ps1` passed all 13 checks with zero real
  guest operations and zero real Hyper-V mutations.
- The final Gate 5.2 candidate passed all 13 checks through
  `scripts/validate-public-release.ps1`: PowerShell parsing, repository
  formats, `git diff --check`, plugin validation, skill validation, Gate 1,
  Gate 2, documentation, publication-policy regressions, Actions-log
  regressions, full tree/history/identity hygiene, public-release contracts,
  and CI-safe Gate 4. It reported zero real guest operations and zero real
  Hyper-V mutations.
- `scripts/validate-github-actions-history.ps1` scanned 16 authoritative runs,
  3,728 log lines, and 597,833 log bytes with zero sensitive findings,
  credentialed URLs, private paths, or forbidden state files.
- Initial source push run `29403897567` and pull-request run `29403915224`
  succeeded on exact SHA `c5f0bd8114de182642c9d39204afed995fa41d0f`.
  Post-merge run `29404039585` failed only because the history policy rejected
  GitHub's web-flow author/committer combination for merge SHA
  `ff5765c2b4626c43c5de8b6444553a2408785920`; it was not bypassed or rerun.
- Focused repair validation passes 12 publication-hygiene policy regressions
  and the full local history scan, which recognizes one structurally bounded
  GitHub web-flow merge and reports zero sensitive findings.
- Pull-request and post-merge `master` Actions must pass
  `public-release-validation` on their exact SHAs, strict status checks must
  remain satisfied, and all conversations must be resolved. The user explicitly
  authorized administrator bypass only for the otherwise unattainable approving
  review because the repository's sole collaborator is also the PR author; the
  bypass must not replace, skip, or weaken CI or conversation resolution.
- After merge, reinstall from the final clean `master` without another
  cachebuster. `validate-install-source.ps1 -RequireCachebuster`,
  `install_plugin.ps1`, `check_install.ps1`, and `validate-gate4.ps1` must
  prove source/install version, commit, inventory, hashes, personal marketplace
  visibility, exactly 16 tools, read-only `inspect_host`, `INVALID_ISO`, and
  zero real mutations.
- Local UI acceptance requires the plugin details link to resolve to the exact
  canonical GitHub URL. Portal acceptance requires the existing listing's
  Website field to read back the same URL with no other listing-field drift.

## Unresolved issues

`unresolvedIssues[]`:

- The merge-policy repair still requires complete local validation, a protected
  fix PR, exact-SHA CI, approval-only administrator bypass, ordinary merge, and
  successful post-merge `master` CI before reinstall may begin.
- The OpenAI Platform portal requires the user to sign in. Only the existing
  plugin entry may be updated; if it is missing, Gate 5.2 stops rather than
  creating a new public submission or hosted MCP service.
- If a Website edit requires review, the public directory update remains
  externally pending until OpenAI approves it. External portal evidence does
  not trigger a source-only bookkeeping commit.

## Blockers

`blockers[]`: none.

## Next gate

`nextGate`:

- Name: Gate 6 clean-machine and real-guest validation.
- State: `notPerformed` and not authorized.
- No credential initialization, live PowerShell Direct guest operation,
  package lifecycle run, VM/checkpoint mutation, clean-machine validation, or
  manual GUI attestation may be inferred from Gate 5.2.

## Next commands

`nextCommands[]`:

1. Run the complete local validator and inspect the three-file repair diff for
   identity-policy, publication-hygiene, and safety-boundary drift.
2. Commit with `fix: validate GitHub web-flow merge commits`, push
   `codex/fix-gate5-2-merge-validation`, and open a protected fix PR.
3. Require exact-commit fix-PR CI and resolved conversations; use the
   user-authorized administrator bypass only for the unavailable independent
   approval, create a normal merge commit, and require green post-merge
   `master` CI.
4. Sync the final clean `master`, reinstall without another cachebuster, and
   run source/install/hash/runtime readback plus local plugin-details UI
   verification.
5. Sign in to the OpenAI Platform in the in-app browser, update only the
   existing entry's Website field after action-time confirmation, and read the
   result back. Stop if the existing entry is absent.
6. Report any externally pending portal review honestly and leave Gate 6 as
   `notPerformed`.

## Safety constraints

`safetyConstraints[]`:

- Preserve the repository URL, protected `master`, `v0.1.1` tag/Release, GPL
  license, existing history, and all historical object IDs.
- Never publish or modify Birdsgone; its name appears only as a separation
  boundary.
- Never commit VM/VHDX/checkpoint/ISO, credential/DPAPI, evidence, cache, log,
  installed-control, or machine-specific state.
- Tests use mock adapters. Installed smoke remains read-only host inspection
  plus nonexistent-ISO rejection with zero real guest operations and zero real
  Hyper-V mutations.
- Do not hand-edit the personal marketplace or `config.toml`, do not run the
  cachebuster helper again, and do not create a tag or GitHub Release.
- The administrator bypass is authorized only to replace the impossible
  independent approval. Never use it to bypass a failed or pending CI check,
  an unresolved conversation, force-push protection, or any other safety gate.

## Ownership

- `ownership.previousTask: read-only-after-relay`
- `ownership.successorTask: owns-next-gate`

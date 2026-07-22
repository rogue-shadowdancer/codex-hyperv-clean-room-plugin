# TaskHandoff - Gate 8/H3 plugin 0.2.0 source publication

`relayProtocolVersion: 1`

## Objective and outcome

Gate 8/H3 is complete. The reviewed Hyper-V Clean Room plugin `0.2.0` source
was merged through protected `master`, tagged with an annotated unsigned
`v0.2.0` tag, published as a source-only GitHub Release, and verified through
authenticated and anonymous readback.

The immutable release commit is
`642f20d1d74a54ecbb08115b1a921ca65ef01fb8`. Tag object
`05ef3f5f61c78865e399eeb7e1673383dccc2db4` peels exactly to that commit. The
Release is non-draft, non-prerelease, has zero uploaded assets, and offers only
GitHub's generated source archives:
<https://github.com/rogue-shadowdancer/codex-hyperv-clean-room-plugin/releases/tag/v0.2.0>.

## Publication and review record

- PR #7 final head `6824f95a4383d27da9f10a7b42e5a4dc5e6dc9e1` closed twenty
  technically actionable Codex findings and merged as
  `cf27311bd1414a605303da237cd6df4c3860bdb8`.
- Post-merge readback found the official anonymous validator still required a
  retired v0.1.1 README title. The minimal additive repair
  `cf67162fd65fcc047332e6fc4f3a04ceab4b9ad6` updated that marker and its
  contract regression in PR #10; protected merge
  `642f20d1d74a54ecbb08115b1a921ca65ef01fb8` is the accepted release commit.
- PR #10 review object `4753485327` raised one handoff-order comment. It was
  dispositioned non-actionable because the accepted plan requires this
  tracker-only update after the Release and outside the immutable tag; the
  rationale was recorded and the conversation resolved. Final technical
  triage was ZERO ACTIONABLE FINDINGS.
- `master` permanently retains a non-null pull-request-review protection object
  with zero required approvals. Strict `public-release-validation`, conversation
  resolution, no force-push/deletion, and all other prior controls remain.

## Verification

- Exact candidate validation: `scripts/validate-gate7.ps1` reports 20 tools,
  16 preserved v1 tools, five v1 schemas, seven v2 schemas, 216 runtime
  assertions, five valid v2 evidence documents, and zero real-operation
  counters. Public-release validation passes 13/13.
- Accepted master CI run `29914264199` and tag CI run `29914881338` both pass on
  `642f20d1d74a54ecbb08115b1a921ca65ef01fb8`.
- The final Actions-history scan covers 62 authoritative runs, 15,433 log lines
  and 2,388,490 bytes with zero sensitive findings, credentialed URLs, private
  paths, or forbidden state files.
- Anonymous readback confirms public `master`, GPL-3.0 detection, six strict
  UTF-8 files, zero BOM/mojibake, the annotated unsigned tag object and peeled
  commit, Release flags, zero assets, and both successful CI runs.
- `v0.1.1` remains unchanged: tag object
  `5edafb08c16a20d2994b4049367d481c67d56d57`, peeled commit
  `4bed14c8a7df068fcd8e827418e7c20527a2f271`.

## Repository and tracker state

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin-gate6`

This handoff is a tracker-only post-release change on branch
`codex/gate8-release-tracker`. It is later than the immutable release commit and
does not change or move `v0.2.0`. No pre-existing user changes existed in this
dedicated workspace. The saved root workspace remains read-only.

Relative to H2 commit `9205a23f1edb8b5b1199a206b97ea6725bb8736e`, H3 did not
change `.github/workflows/ci.yml` or `tests/publication_hygiene_tests.py`, and
did change `tests/public_release_contract_tests.py`. Dependabot PR #8/#9 were
not processed, merged, or closed; their separate dependency-upgrade task must
take a fresh baseline from the accepted release/master state.

Plugin issue #6 remains closed. Birdsgone issue #7 remains open and its G6-G7
checkbox remains unchecked because installed-source match belongs to H4/G9.

## Safety boundary and unresolved work

`blockers[]`: none for H3/G8 source publication.

No cachebuster/personal install or installed-source match was performed. No
real Hyper-V, VM/VHDX/checkpoint, power/network, credential, guest, package,
portable, WebDriver, UI, evidence/manual, or clean-machine operation was
performed. All remain `notPerformed`.

## Next gate

H4/G9 only: create an isolated workspace from immutable release commit
`642f20d1d74a54ecbb08115b1a921ca65ef01fb8`, perform exactly one authorized
cachebuster personal install, and prove installed-source/marketplace/runtime
match to that release. Do not perform clean-machine or real Hyper-V/guest work.

1. Re-read the authority files and this handoff from current tracker `master`,
   then create the H4 workspace from the immutable v0.2.0 commit, not the later
   tracker commit.
2. Preserve the v0.2.0 tag/Release, branch protection, and all repository
   history. Never change the release tag to include tracker or install state.
3. Limit validation to the personal cachebuster install and installed-source
   match; relay clean-machine/real-operation work to its later gate.

`ownership.previousTask: read-only-after-relay`

`ownership.successorTask: owns-next-gate`

# TaskHandoff - Gate 9/H4 personal cachebuster installation

`relayProtocolVersion: 1`

## Objective and outcome

Gate 9/H4 is complete. Starting from the immutable Hyper-V Clean Room plugin
`v0.2.0` source commit
`642f20d1d74a54ecbb08115b1a921ca65ef01fb8`, the documented
`plugin-creator` helper was invoked exactly once and produced the personal build
`0.2.0+codex.20260722114845`.

The owned installation at `%USERPROFILE%\plugins\hyperv-clean-room` matches the
accepted H4 source commit containing this handoff: 31 tracked payload files,
source and installed version, source commit, cachebuster, file sizes, and
SHA-256 values agree. The default personal marketplace contains exactly one
canonical `hyperv-clean-room` entry, and Codex reports it installed and enabled
at the same version.

Installed-copy acceptance starts the MCP server only from the personal plugin
directory, reads back server identity/version `hyperv-clean-room` / `0.2.0`,
discovers exactly 20 unique tools, executes read-only
`inspect_host`, and rejects a nonexistent ISO with `INVALID_ISO` before any
mutation. Real guest operations and real Hyper-V mutations are both zero.

## Release-source and change boundary

- Annotated tag object `05ef3f5f61c78865e399eeb7e1673383dccc2db4`
  still peels exactly to immutable release commit
  `642f20d1d74a54ecbb08115b1a921ca65ef01fb8`.
- The source-only, non-draft, non-prerelease `v0.2.0` GitHub Release remains
  unchanged and has zero uploaded assets.
- The H4 plugin payload differs from the immutable release plugin tree only in
  `.codex-plugin/plugin.json`, where the helper replaced version `0.2.0` with
  the single build suffix `0.2.0+codex.20260722114845`.
- `scripts/validate-gate4.ps1` now enforces the integrated 20-tool installed
  runtime instead of the historical 16-tool Gate 4 assertion.
- README, installation/maintenance/operations/specification documentation,
  changelog, and this handoff record the H4 acceptance without claiming any
  later machine-backed scope.

## Repository state

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

- Branch: `codex/gate9-cachebuster-install`.
- The exact H4 commit is the branch HEAD containing this handoff. Require
  `git rev-parse HEAD`, the pushed branch OID, and the installed manifest's
  `sourceCommit` to be identical before accepting the gate.
- The branch carries forward tracker-only master commit
  `48c911a52ecf066eb59ea548e12260bc5a702e12`; its plugin subtree was verified
  byte-identical to the immutable release tree before the helper ran.
- No pre-existing user changes existed in this assigned worktree. The saved
  root checkout and Dependabot PR #8/#9 were not modified.

## Verification

- `scripts/validate-install-source.ps1 -RequireCachebuster` accepts exactly 31
  ordinary tracked payload files, five schema-v1 files, seven schema-v2 files,
  no reparse points, and the single expected cachebuster.
- `scripts/install_plugin.ps1` performs the one authorized installation,
  preserves the existing ownership identity, updates the canonical personal
  entry only through `plugin-creator`, and runs
  `codex plugin add hyperv-clean-room@personal` exactly once.
- `scripts/check_install.ps1` reports `installed`, `owned`, `matches`, and
  `marketplaceVisible` true, one marketplace entry, matching source/installed
  commit, version, and cachebuster, and no payload or marketplace error.
- `scripts/validate-gate4.ps1` proves commit-bound installed-copy acceptance:
  server identity/version `hyperv-clean-room` / `0.2.0`, 20 tools,
  installed-path startup, read-only `inspect_host`, `INVALID_ISO` before
  mutation, zero real guest operations, and zero real Hyper-V mutations.
- The complete source, compatibility, documentation, publication, and exact
  candidate checks pass with ZERO ACTIONABLE FINDINGS before publication.

## Safety boundary and unresolved work

`blockers[]`: none for H4/G9 personal installation.

No real VM, VHDX, checkpoint, power/network transition, credential enrollment,
PowerShell Direct guest action, package lifecycle, portable deployment,
WebDriver, UI, evidence/manual, or clean-machine operation was performed. All
remain `notPerformed`. H4 does not establish clean-machine compatibility or
authorize any real mutation.

Birdsgone issue #7 G6-G7 was not edited in this repository task. Its consumer
tracking may use this installed-source-match result only after reading the
accepted H4 commit and installation evidence; it must not infer any
clean-machine or physical-machine result.

## Next gate

H5/G10 only: begin the separately authorized clean-machine/real-operation gate
from this accepted installed-source baseline. Before any real operation, read
the current authorities and obtain explicit authorization naming the host, VM,
credential profile, artifact, profile, and intended mutation. If that
authorization is absent, limit the successor to read-only planning and report
the real-operation lane as `notPerformed`.

1. Re-read `AGENTS.md`, this handoff, `docs/specification.md`, the operations
   and security authorities, and the installed manifest before any action.
2. Verify the H4 branch/installed source OID, version, cachebuster, inventory,
   marketplace row, and 20-tool discovery without reinstalling or creating a
   second cachebuster.
3. Preserve `v0.2.0`, all Releases, branch protection, and repository history.
4. Do not touch Dependabot PR #8/#9 or the saved root checkout.

`ownership.previousTask: read-only-after-relay`

`ownership.successorTask: owns-next-gate`

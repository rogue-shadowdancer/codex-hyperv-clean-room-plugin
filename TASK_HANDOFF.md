# TaskHandoff - Gate 4 closure; private publication next

`relayProtocolVersion: 1`

`relayAttempt: 1`

## Objective

Complete Gate 4 only: commit the source-validated, ownership-marked personal
installation/cachebuster workflow; reinstall from that clean commit without a
new cachebuster; require final commit-bound install and installed-copy
acceptance; then relay exactly Gate 5 private GitHub publication using
`gpt-5.6-sol` with `xhigh` thinking.

## Specification paths

`specificationPaths[]`:

- `AGENTS.md`
- `docs/specification.md`
- `docs/installation.md`
- `docs/maintenance.md`
- `TASK_HANDOFF.md`
- sibling `birdsgone/docs/gates/windows-clean-vm.md`
- sibling `birdsgone/test/clean-room/birdsgone-windows11.json`

## Completed work

`completedWork[]`:

- Gate 2 remains committed at
  `248a6808d4511d26b0014380778dd23601829824` with base version `0.1.0`,
  schema version 1, exactly 16 MCP tools, and five public schemas.
- Gate 3 produced the Birdsgone schema-v1 profile and acceptance documentation
  without installing the plugin or running a real guest lifecycle.
- Gate 4 implements pure PowerShell 5.1 source, ownership, containment, and
  install-manifest validation; `install_plugin.ps1`; `check_install.ps1`; the
  helper-only personal marketplace flow; installed-copy MCP acceptance; and
  operator installation/maintenance documentation.
- The personal copy lives at
  `%USERPROFILE%\plugins\hyperv-clean-room`. The marketplace contains exactly
  one canonical `hyperv-clean-room@personal` entry.
- The plugin-creator default cachebuster rehearsal changed only build metadata
  to `0.1.0+codex.20260714150737`; do not invent another token during final
  commit binding.
- First-pass reviewers found dirty-HEAD provenance, hard-link, ancestor-junction,
  alternate-data-stream, case-collision, and documentation/state gaps. The
  candidate now rejects those filesystem forms, requires a clean plugin payload
  in final validation, includes adversarial tests, and corrects the docs.

## Changed files

`changedFiles[]`:

- Plugin metadata: `.codex-plugin/plugin.json` cachebuster build metadata only.
- Installation scripts: shared bounded helper, source validator, installer,
  checker, and Gate 4 validator.
- Tests: installer adversarial coverage and installed-copy-only MCP smoke.
- Documentation: root/docs indexes, installation, maintenance, operations,
  troubleshooting, specification, validation topic lists, and this handoff.
- No public MCP tool, schema-v1 semantic, guest worker, Hyper-V adapter, or
  Birdsgone file changed in Gate 4.

## Repository state

`repositoryState`:

- Branch: `master`.
- Gate 4 parent: `248a6808d4511d26b0014380778dd23601829824`.
- Before the Gate 4 commit, all dirty paths are the bounded Gate 4 candidate;
  no pre-existing change belongs to the user.
- Required relay state: the commit containing this handoff is current `HEAD`,
  the working tree is clean, there is no remote yet, and the installed
  `sourceCommit` equals that `HEAD`.
- Birdsgone remains a separate user-owned unborn repository and is outside the
  Gate 4 and Gate 5 commit/push scope.

## Verification

`verification[]`:

- Source: exactly 20 tracked ordinary non-reparse, non-hard-linked files; no
  named ADS; safe case-insensitive relative paths; five public schemas.
- Installer security: 33 assertions cover ownership refusal, unexpected-file
  preservation, tamper repair, hard-link outside-write refusal, ancestor
  junction refusal, ADS refusal, and case-insensitive collision refusal.
- Pre-commit full candidate validation passes only with the explicit
  `-AllowDirtyPluginSource` development switch; no-argument final validation
  rejects a dirty `hyperv-clean-room/**`.
- Personal install currently reports all four booleans true, one marketplace
  entry, matching 20-file size/SHA-256 inventory, version, and cachebuster.
- Installed-copy MCP smoke starts only from the personal copy, discovers 16
  tools, passes read-only `inspect_host`, rejects a missing ISO with
  `INVALID_ISO`, and reports zero real guest operations and Hyper-V mutations.
- Final completion protocol after commit: rerun `install_plugin.ps1` without a
  new cachebuster, then no-argument `validate-gate4.ps1`; require
  `commitBound: true`, all four booleans true, exact metadata/hash matches, 16
  tools, missing-ISO rejection, zero mutations, and a clean tree.

## Unresolved issues

`unresolvedIssues[]`:

- Gate 4 is not relayable until fresh replacement installer-security,
  installed-copy, and documentation/state reviewers report zero actionable
  findings, the candidate is committed, and the final post-commit protocol
  above passes.
- Real VM/checkpoint mutation, credential enrollment, PowerShell Direct guest
  execution, Birdsgone package lifecycle, and clean-machine evidence remain
  deliberately unproved and are not part of Gate 5 publication.

## Blockers

`blockers[]`: none.

## Next gate

`nextGate`:

- Name: Gate 5 private GitHub publication and remote acceptance.
- Project: this saved plugin repository.
- Model: `gpt-5.6-sol`; thinking: `xhigh`.
- Scope: rerun full validation and sensitive-data scanning; obtain three
  pre-push read-only reviews; create a private GitHub repository and perform the
  first `master` push; monitor Actions; then obtain two remote acceptance
  reviews for UTF-8 readback, commit SHA, private visibility, branch tracking,
  and installed-copy consistency.

## Next commands

`nextCommands[]`:

1. Read every specification path and verify the committed, clean Gate 4 state.
2. Confirm no Birdsgone or machine-state path is tracked before publication.
3. Do not push unless full validation, sensitive scanning, and three fresh
   pre-push reviews are green.
4. Create only a private repository, push `master`, monitor Actions, and finish
   the two post-push remote reviews before declaring Gate 5 complete.

## Safety constraints

`safetyConstraints[]`:

- Do not publish Birdsgone, VM/VHDX/checkpoint/ISO, credentials, DPAPI,
  evidence, installed control files, caches, or machine-specific state.
- Do not run a real VM/checkpoint mutation, credential initializer, guest
  operation, package lifecycle, or clean-machine matrix during publication.
- Do not claim clean-machine or manual acceptance from installation, CI, or
  remote source readback.
- Do not force-push. Do not make the GitHub repository public without a new
  explicit user instruction.

## Ownership

- `ownership.previousTask: read-only-after-relay`
- `ownership.successorTask: owns-next-gate`

# TaskHandoff - Gate 6/H1 automation contract freeze

`relayProtocolVersion: 1`

## Objective

Freeze, review, and validate the plugin `0.2.0`, schema-v2 automation contract
needed by the Birdsgone private `v0.1.0-rc.1` route. H1 is contract, schema,
fixture, static-test, and documentation work only. It does not implement or run
any new mutation.

## Specification paths

`specificationPaths[]`:

- `AGENTS.md`
- `TASK_HANDOFF.md`
- `docs/specification.md`
- `docs/architecture.md`
- `docs/security.md`
- `docs/profile-authoring.md`
- `docs/evidence.md`
- `contracts/v2/README.md`
- `contracts/v2/tool-catalog.json`
- `contracts/v2/compatibility.json`
- `contracts/v2/schemas/*.schema.json`
- `tests/gate6_contract_tests.py`
- `tests/fixtures/v2/**`
- `scripts/validate-gate6.ps1`
- `hyperv-clean-room/skills/manage-hyperv-clean-room/SKILL.md`

## Completed work

`completedWork[]`:

- The target plugin version is `0.2.0`, public schema version is 2, and the
  target tool catalog contains exactly 20 tools.
- All 16 shipped schema-v1 tool names, input schemas, annotations, envelope
  behavior, profile/evidence behavior, and five public schema files are frozen
  without semantic change.
- Four additive tools are frozen: `plan_vm_power`, `apply_vm_power`,
  `plan_vm_network`, and `apply_vm_network`.
- Power transitions are limited to start and graceful shutdown. Network
  transitions are limited to the verified primary NIC's recorded baseline or
  disconnected state, with a pre-created paired recovery plan.
- Portable ZIP manifest/path/hash/limit/atomic-slot/data-preservation rules,
  exact Microsoft EdgeDriver provenance, the closed `data-testid` UI DSL,
  evidence-v2 derivation, and exact-version dispatch/migration are frozen.
- Seven stable Draft 2020-12 target schemas plus valid, invalid,
  semantic-invalid, compatibility, and deterministic migration fixtures are
  present outside the installable plugin payload.
- The current executable plugin remains `0.1.1`, schema v1, exactly 16 tools,
  and five public schemas. `ToolSchemas.ps1`, the runtime, production adapter,
  installer, manifest, tags, and Releases are unchanged.

## Changed areas

`changedFiles[]`:

- `contracts/v2/**`
- `tests/gate6_contract_tests.py`
- `tests/fixtures/v2/**`
- `scripts/validate-gate6.ps1`
- `.github/workflows/ci.yml`
- `docs/specification.md`
- `docs/architecture.md`
- `docs/security.md`
- `docs/profile-authoring.md`
- `docs/evidence.md`
- `docs/README.md`
- `README.md`
- `CHANGELOG.md`
- `hyperv-clean-room/skills/manage-hyperv-clean-room/SKILL.md`
- `TASK_HANDOFF.md`

## Repository state

`repositoryState`:

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin-gate6`

- Branch: `codex/gate6-automation-contract`.
- H1 started from public `origin/master` commit
  `3234daea726ebd6685b5dfef20f99aaab152b279` after a clean, ancestor-verified
  `--ff-only` update.
- The H1 commit is the branch HEAD containing this handoff; obtain its exact
  SHA with `git rev-parse HEAD` rather than copying a pre-commit placeholder.
- The saved root `master` workspace is read-only and remained outside H1.
- No pre-existing user changes were present in the dedicated H1 worktree.
- Ignored `.artifacts/test-python` contains only the prepared test runtime and
  logs; it is not committed.

## Verification

`verification[]`:

- `scripts/prepare-test-python.ps1` prepared the pinned ABI-isolated test
  runtime under ignored `.artifacts`.
- `tests/gate6_contract_tests.py` passed with 16 preserved v1 tools, 20 target
  tools, five preserved v1 schemas, seven v2 schemas, eight valid fixtures,
  five schema-invalid fixtures, three semantic-invalid fixtures, two migration
  fixtures, 15 dynamic compatibility/safety checks, and zero real operations.
- `scripts/validate-gate6.ps1` passed the complete H1 mock/static/docs gate and
  recorded target plugin `0.2.0`, current runtime `0.1.1`, 20/16 tool counts,
  seven/five schema counts, 16 contract fixtures, two migration fixtures, 15
  dynamic contract checks, and zero real operations.
- Strict documentation validation passed 17 documents and 97 local links with
  UTF-8/no-BOM and zero mojibake findings.
- The three publication policy/tree/release contract tests and
  `scripts/validate-gate4-ci.ps1` passed, matching the remaining CI-safe
  workflow checks affected by H1.
- `git diff --cached --check` passed. Substantive review of the exact 43-path
  staged candidate found zero production runtime/schema/manifest changes, zero
  added mutation primitives, zero unstaged drift, and ZERO ACTIONABLE FINDINGS.
- Clean-machine testing, credential enrollment, real PowerShell Direct work,
  VM/checkpoint/power/network mutation, package or portable deployment,
  WebDriver/UI execution, evidence collection, and manual attestation remain
  `notPerformed`.

## Unresolved issues

`unresolvedIssues[]`:

- Gate 7/H2 must implement the frozen target in production code and mock tests.
- H2 must decide internal file/module placement without changing any frozen
  public tool, schema, compatibility, expiry, recovery, path, hash, driver, UI,
  evidence, or migration semantic.
- Real clean-room acceptance is a later, separately authorized gate after H2;
  it is not implied by contract or mock success.

## Blockers

`blockers[]`: none for H1 contract completion. Any real mutation remains
authorization-blocked by design.

## Next gate

`nextGate`: Gate 7/H2 implementation only.

H2 owns executable integration of the already-frozen contract. It must not
perform clean-machine or real Hyper-V/guest/package automation.

## Next commands

`nextCommands[]`:

1. Read `AGENTS.md`, `TASK_HANDOFF.md`, `docs/specification.md`, and every file
   under `contracts/v2` before editing.
2. Verify the H1 branch/PR exact HEAD and checks, then use that exact candidate
   as the H2 baseline without rewriting H1 history.
3. Add v2 exact-version validation and the four tool registrations while
   preserving the 16-tool v1 snapshot.
4. Implement fixed adapter/worker seams only through mock-backed tests: plan
   consumption/drift/expiry/recovery, portable staging, driver provenance,
   closed UI dispatch, evidence derivation, and migration.
5. Run scoped tests while iterating, then the full exact-HEAD Gate 7 validation
   and staged review to ZERO ACTIONABLE FINDINGS.
6. Update this handoff, commit/push the H2 gate on the existing draft PR, sync
   GitHub trackers, and relay the next separately authorized gate.

## Safety constraints

`safetyConstraints[]`:

- Do not execute a real VM, VHDX, checkpoint, power, network, credential,
  guest, package, portable, WebDriver, UI, evidence, or manual-attestation
  operation in H2.
- Tests use the mock adapter. Do not add or expose deletion tools for a VM,
  VHDX, checkpoint, guest file, deployment data, or host path.
- Never accept plaintext credentials, arbitrary command/script/shell/URL,
  CSS/XPath selector, JavaScript, raw WebDriver payload, raw uninstall string,
  caller-selected executable argument, adapter, or switch.
- Dispatch profile/evidence by exact schema version and fail closed. Preserve
  v1 semantics; never synthesize v2 evidence from v1.
- Do not move or replace `v0.1.1`, publish `0.2.0`, install a cachebuster,
  force-push, rewrite history, or push `master` directly.

## Ownership

`ownership`:

- `previousTask: read-only-after-relay`
- `successorTask: owns-Gate-7-H2`

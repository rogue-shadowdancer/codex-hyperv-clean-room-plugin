# TaskHandoff - Gate 7/H2 schema-v2 production integration

`relayProtocolVersion: 1`

## Objective and outcome

Gate 7/H2 implements the frozen Hyper-V Clean Room plugin `0.2.0` / public
schema-v2 contract from `contracts/v2` in production source. The candidate
preserves the exact 16 schema-v1 tools and five schema-v1 file hashes, adds the
four frozen power/network tools for exactly 20 MCP tools, and installs exact
copies of all seven schema-v2 files.

H2 used only mock adapters, PowerShell parsers, JSON Schema validation, and
static production-seam checks. Real Hyper-V, VM/VHDX/checkpoint, power/network,
credential, guest, package, portable, WebDriver, UI, evidence/manual,
installation, release, and clean-machine operations remain `notPerformed`.

## Changed areas

- `hyperv-clean-room/mcp/lib/Common.ps1`, `Runtime.ps1`, `ToolSchemas.ps1`, and
  `server.ps1`: version `0.2.0`, exact 20-tool registry, and v1/v2 envelopes.
- `Tools.Host.V2.ps1` and `Adapters.ps1`: guarded one-shot VM power plans,
  paired network change/recovery plans, ownership/drift/expiry rebinding, exact
  primary-NIC transitions, and bounded partial-effect reporting.
- `Validation.V2.ps1`, `Tools.Guest.V2.ps1`, and `GuestWorker.ps1`: exact
  schema dispatch, closed portable/driver/UI workflows, atomic slot metadata,
  data-inventory preservation, evidence-v2 derivation, and fail-closed
  production seams.
- `Migrate-TestProfile.ps1`: additive, deterministic v1-to-v2 profile
  migration that refuses ambiguous input and existing destinations.
- `hyperv-clean-room/schemas/v2`: byte-identical copies of the seven frozen
  contracts; schema-v1 bytes remain unchanged.
- `tests/gate7-runtime.tests.ps1`, `tests/gate7_implementation_tests.py`, and
  `scripts/validate-gate7.ps1`: mock/parser/schema/static Gate 7 acceptance.
- Installer source validation, CI, authoritative documentation, changelog,
  skill guidance, and compatibility metadata now describe the integrated
  source candidate without claiming release or real validation.

## Repository state

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin-gate6`

- Writable workspace: the `projectPath` above.
- Branch: `codex/gate6-automation-contract`, tracking the same remote branch.
- The exact Gate 7 commit is the branch HEAD containing this handoff; obtain it
  with `git rev-parse HEAD` and require identical local/remote/PR head OIDs.
- Draft PR: <https://github.com/rogue-shadowdancer/codex-hyperv-clean-room-plugin/pull/7>.
- No pre-existing user changes existed in this dedicated workspace. All Gate 7
  changes belong to H2. The saved root `master` workspace remains read-only.

## Verification

- `scripts/validate-gate7.ps1` passes the inherited CI-safe runtime/schema
  baseline plus Gate 7 integration on mock/parser/static paths only.
- Gate 7 records exactly 20 tools, 16 preserved schema-v1 tools, five preserved
  schema-v1 files, seven installed schema-v2 files, 76 mock runtime assertions,
  one generated evidence-v2 document validated against Draft 2020-12, and zero
  real operations.
- Publication policy/tree/release-contract tests, strict UTF-8/link docs,
  install-source/CI-safe payload tests, and `git diff --check` pass.
- The exact staged candidate receives a substantive compatibility, security,
  recovery, data-integrity, and scope review with ZERO ACTIONABLE FINDINGS.
- Hosted `public-release-validation` must pass on the exact pushed Gate 7 SHA
  before the next task treats this handoff as publication-ready.

## Blockers and unresolved work

`blockers[]`: none for H2 source integration.

The candidate is not released, tagged, merged, cachebuster-installed, or
clean-machine validated. The immutable `v0.1.1` tag/Release and existing
`0.1.1+codex.20260715084043` personal installation are not moved or rewritten.
Birdsgone G6-G7 remains open until later publication and installed-source-match
work is separately completed.

## Next gate

H3/G8 only: publish the reviewed plugin `0.2.0` source candidate. Re-read the
authority files, verify the exact branch/PR head and successful required check,
resolve any review threads, make draft PR #7 ready, merge through protected
`master`, and create/read back the immutable `v0.2.0` tag and source-only
GitHub Release from the exact accepted commit. Do not perform a cachebuster
personal install or any real Hyper-V/guest/package/portable/WebDriver/UI or
clean-machine operation in H3; those belong to later gates.

## Successor commands and safety

1. Verify cwd, branch, clean state, local/upstream/PR OIDs, protected `master`,
   required checks, and unresolved review threads before any write.
2. Read `AGENTS.md`, this handoff, all authoritative docs, `contracts/v2`, and
   the release process before changing PR/release state.
3. Require exact-head validation and ZERO ACTIONABLE FINDINGS. A changed HEAD
   resets publication validation.
4. Preserve all v1 definitions/hashes, the frozen v2 contract, and every
   fail-closed boundary. Never force-push or rewrite history.
5. Do not move `v0.1.1`, install a cachebuster, claim an installed-source
   match, or perform real host/VM/credential/guest/package/portable/WebDriver/UI
   work in H3.

`ownership.previousTask: read-only-after-relay`

`ownership.successorTask: owns-next-gate`

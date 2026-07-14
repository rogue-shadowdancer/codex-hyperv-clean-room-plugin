# TaskHandoff — Gate 2 complete

## Outcome

Gate 2 replaces the fail-closed MCP stub with a Windows PowerShell 5.1
line-delimited JSON-RPC runtime while preserving plugin version `0.1.0`, schema
version 1, exactly 16 MCP tools, and exactly five public Draft 2020-12 schemas.
The complete tool surface is executable against a test-mode-only mock adapter.
No real VM, VHDX, checkpoint, ISO attachment, credential prompt, PowerShell
Direct session, package lifecycle, marketplace/cache, installation, remote, or
push mutation was performed.

The default Hyper-V adapter implements host, VM, VM-creation, checkpoint-create,
and checkpoint-restore boundaries, but Gate 2 did not execute them against a
real host. Real guest inspection, transfer, and declarative execution
deliberately return `GUEST_ADAPTER_UNVALIDATED` until a separately authorized
clean-machine gate. Gate 2 must not be cited as real Hyper-V validation.

## Implemented areas

- `mcp/server.ps1` now negotiates only the four frozen protocol versions,
  reserves stdout for one UTF-8 JSON response per line, exposes `tools/list`
  and `tools/call`, returns every tool result as JSON text, and maps failed
  envelopes to MCP `isError`.
- The runtime has closed input schemas for all 16 tools, bounded error
  projection without PowerShell records or stacks, operation envelopes, path
  checks, hash helpers, and test-mode gating for the mock adapter.
- State uses atomic UTF-8 JSON replacement, cross-process exclusive locks,
  separate plan/operation/ownership records, exact Notes markers, and
  VM-ID/name/path/VHDX agreement. Plans live for 15 minutes.
- The first well-formed apply atomically consumes an existing plan before kind,
  expiry, confirmation, or drift checks. VM apply rechecks host, ISO, switch,
  target-volume identity/capacity, name, and paths. Checkpoint apply rechecks
  VM, ownership, configuration, inventory, current state, and target identity.
- Restore-token plaintext is returned only in a successful restore-plan
  response. State persists only its SHA-256, and wrong name/token values consume
  the plan.
- Native PowerShell profile and evidence validators enforce the frozen schema
  and semantic contract without Python. Evidence results are bound in order to
  immutable operation, automatic, manual, and cleanup identities. Cleanup is
  armed only after execution starts, continues after a cleanup failure, and
  never changes `overallStatus`.
- Mock-backed guest execution stages and hashes the artifact for each test
  operation, enforces the standard-user token invariant, records launched
  process identity, runs only declared step types, preserves manual assertions,
  accepts bound attestations, and exports validated evidence plus a SHA-256
  inventory from a server-controlled root.
- `mcp/Initialize-GuestCredential.ps1` accepts exactly `-ProfileName` and
  `-VmName`, prompts separately for administrator and standard-user roles,
  validates distinct SIDs and role membership through PowerShell Direct, and
  persists two current-user/current-machine DPAPI `Export-Clixml` objects. Gate
  2 validates this boundary statically and does not collect credentials.

## Verification

- Gate 2 runtime/protocol/security tests pass under Windows PowerShell 5.1 with
  426 assertions, 16 tools, four protocol versions, one winner in a concurrent
  two-process apply race, happy evidence `passed`, failure evidence `failed`,
  and ordered cleanup continuation. All mutations in that suite are mock state
  writes below ignored `.artifacts`; reported real Hyper-V mutations: zero.
- Frozen contract tests pass with 16 declared tools, nine cleanup types, four
  MCP versions, and five schemas.
- Draft 2020-12 tests pass the canonical example plus 10 valid, 13
  schema-invalid, and 7 semantic-invalid fixtures. Five actual runtime outputs
  independently pass the four applicable frozen schemas and evidence semantic
  validation.
- Scaffold/manifest checks, JSON/YAML parsing, all PowerShell parsers, Markdown
  local links, strict UTF-8/mojibake checks, sensitive-file scans, and
  `git diff --check` pass.
- Plugin and companion-skill validators pass. No personal marketplace or Codex
  cache file is written by Gate 2 validation.

## Repository state and blockers

Gate 2 started from clean `master` at
`f98cf7a43f8e186fb2981e55fcdbe66081107d8e`, with no remote and no user-owned
uncommitted changes. The completed Gate 2 revision is the commit containing
this handoff; after that commit, the expected branch is `master` with a clean
tree and no remote. Gate 2 blockers: none.

Known next-gate boundary: real guest execution is intentionally fail-closed,
and the real host/VM/checkpoint adapter has not been exercised. That is not a
Gate 2 failure because this gate's acceptance surface is mock-only.

## Next gate exact entry

Gate 3 must run in a new independent Codex task. Before editing, read
`AGENTS.md`, `docs/specification.md`, `docs/README.md`, and this handoff; verify
that the commit containing this file is checked out on `master`, the tree is
clean, and no remote exists.

Gate 3 owns only real-adapter closure and clean-machine validation. Begin with
read-only host inspection and a written mutation plan. Do not perform a real
VM creation, checkpoint creation/restore, guest transfer, credential prompt, or
package lifecycle action without new explicit user authorization naming that
scope. After authorization, replace the `GUEST_ADAPTER_UNVALIDATED` path with
fixed declarative PowerShell Direct operations, validate the two-role DPAPI
initializer on dedicated accounts, exercise each guarded real mutation only on
an explicitly dedicated VM/root, collect and validate evidence, add
clean-machine regression coverage, update this handoff, validate, and commit.
Never add a deletion surface or weaken the schema-v1/16-tool contract to make
real-host testing pass.

# TaskHandoff — Gate 1.1 complete

## Outcome

Gate 1.1 refreezes the pre-first-release v1 cleanup, profile, evidence, plan,
artifact, credential, and protocol contracts. The plugin remains version
`0.1.0`, all public schemas remain `schemaVersion: 1`, the surface remains
exactly 16 MCP tools and five public schemas, and `mcp/server.ps1` remains a
fail-closed stub. No Gate 2 runtime was implemented.

## Frozen contract changes

- `test-profile.schema.json` now requires explicit `cleanupSteps`; the separate
  closed cleanup object permits nine non-destructive types, at most 16 entries,
  1–120 seconds each, and a semantic total of at most 300 seconds. Execution and
  manual IDs are globally unique. Actions cannot be optional.
- Cleanup triggers only after execution begins and a required assertion,
  action, timeout, or guest-adapter failure occurs. It runs in order within
  budget, only stops a current-operation PID after identity revalidation,
  continues after cleanup failure, and never uninstalls, deletes, restores, or
  rolls back.
- `evidence.schema.json` now requires immutable `cleanupTriggered` state and
  identity-bound `cleanupResults`. When untriggered, every declared cleanup is
  `notPerformed`. Cleanup state/results never change `overallStatus`, which is
  derived only from required automatic/manual assertions.
- Every profile has exactly one first-position `stageArtifact`.
  `run_test_profile.artifactPath` is a host-local ordinary file and the runner
  verifies host/guest hashes. Standalone `stage_artifact` never carries state
  into another operation.
- Each test operation has a server-controlled evidence staging root. Manual
  references stay relative to it until `collect_evidence` exports them.
- `Initialize-GuestCredential.ps1` is specified with only `-ProfileName` and
  `-VmName`, two interactive credential prompts, PowerShell Direct role/SID
  checks, then DPAPI persistence. The script is not implemented in this gate.
- Restore-token plaintext is returned once only by a successful plan response.
  Apply atomically consumes an existing plan before value or drift checks;
  wrong values consume it. VM volume revalidation requires stable identity and
  current capacity at least `requiredBytes`, not byte-for-byte free-space
  equality.
- Production remains Windows PowerShell 5.1 without Python. Supported MCP
  versions are exactly `2024-11-05`, `2025-03-26`, `2025-06-18`, and
  `2025-11-25`; protocol runtime is still unimplemented.

## Documentation and tests

`docs/README.md` is the documentation center. `docs/profile-authoring.md` is
the Simplified Chinese authoring guide. `examples/minimal-test-profile.json` is
the only complete documentation profile and participates in schema and semantic
tests. The root README is bilingual and explicitly says the plugin is not yet
a working installable tool.

Validation passed against both the repository marketplace fixture and the real
personal marketplace without writes. Contract tests report 16 tools, nine
cleanup types, four MCP versions, and five schemas. Draft 2020-12 tests pass the
canonical example plus 10 valid, 13 schema-invalid, and 7 semantic-invalid
fixtures. Plugin validation, companion-skill quick validation, YAML/JSON
parsing, all PowerShell parsers, Markdown local links, strict UTF-8/mojibake
checks, sensitive-document scans, and `git diff --check` pass. Development-only
Python packages are confined to ignored `.artifacts`.

The fresh read-only contract/docs review found four actionable issues; all were
repaired. Its final read-only re-review returned `No actionable findings.`

No VM, VHDX, checkpoint, ISO, credential, evidence, marketplace/cache,
installation, remote, or push mutation was performed.

## Repository state and blockers

The gate started from clean `master` at the required Gate 1 commit with no
remote and no user-owned uncommitted changes. Repository-state rule for this
handoff: the Gate 1.1 revision is the commit containing this file, not a
precommit working-tree snapshot. Before Gate 2 edits, the successor must verify
that containing commit is checked out on `master`, the tree is clean, and no
remote exists. Blockers: none.

## Gate 2 exact entry

Gate 2 must run in a new independent Codex task. Read `AGENTS.md`,
`docs/specification.md`, `docs/README.md`, and this handoff before editing.
Implement the MCP JSON-RPC runtime, common envelope, mock Hyper-V adapter,
state/ownership store, atomic plan/apply guards, profile/evidence validators,
interactive credential initializer, guest/tool surfaces, and protocol/security
tests. Use mock adapters only; do not create or restore a real VM. Preserve the
16-tool/schema-v1 compatibility surface and all Gate 1.1 cleanup semantics.

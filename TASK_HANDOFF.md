# TaskHandoff — Gate 1 complete

## Outcome

The independent repository and `hyperv-clean-room` plugin scaffold exist. The
v1 MCP, plan/apply, ownership, profile, evidence, dual-role credential, manual
attestation, and automatic/manual boundaries are frozen in
`docs/specification.md`. The MCP entry point fails closed because Gate 2 has not
implemented the runtime.

An independent read-only review originally found four contract defects. Gate 1
now resolves all four:

- Checkpoint creation uses `plan_checkpoint_create` and
  `apply_checkpoint_create`; restore remains plan/apply.
- VM creation plans expose normalized paths, ISO and switch identity, target
  volume identity/capacity, and every resource-absence precondition.
- Passed evidence requires verified ownership and a non-administrator,
  non-elevated, medium-integrity test identity.
- Manual results require `record_manual_attestation` with server-controlled
  observer/time provenance and verified relative evidence references.

A fresh ephemeral Codex session reviewed only the manifest, MCP configuration,
specification, and five schemas under a read-only sandbox and returned: `No
actionable findings.` Collaboration workers were attempted first but timed out;
the approved CLI fallback produced the completed review without modifying files.

## Verification completed

- `scripts/validate-gate1.ps1` passed against the real personal marketplace.
- `tests/gate1-contract.tests.ps1` passed with exactly 16 required tools, five
  public schemas, and forbidden direct/delete tools absent.
- Draft 2020-12 metaschema, positive fixtures, negative fixtures, passed-token
  conditions, VM preconditions, checkpoint ownership, and manual-attestation
  reference tests passed.
- Plugin-creator `validate_plugin.py` and skill-creator `quick_validate.py`
  passed.
- Both YAML files parsed, all PowerShell files parsed, and `git diff --check`
  passed.
- No VM, VHDX, checkpoint, ISO, credential, plugin installation, package test,
  Birdsgone edit, remote creation, or push was performed.

## Next gate

Implement Gate 2 only in a new Codex task: the MCP JSON-RPC server, common
envelope, mock Hyper-V adapter, state/ownership store, plan/apply guards,
profile and evidence validators, interactive credential initializer,
guest/tool surfaces, and protocol/security tests. Read `AGENTS.md`,
`docs/specification.md`, and this handoff before editing. Do not create or
restore a real VM.

## Blockers

None for Gate 1. Runtime behavior remains intentionally unimplemented and is
the subject of Gate 2.

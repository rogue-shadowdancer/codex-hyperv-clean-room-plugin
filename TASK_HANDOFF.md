# Task handoff: `list_vms` minimal production projection

`relayProtocolVersion: 1`

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

## Objective and authority

Implement one backward-compatible runtime Gate that removes deep
`inspect_vm`-level projection from production `list_vms`, layers ownership
enrichment behind keyed state and marker checks, and adds stable bounded stage
classification for unrecoverable list failures.

- Exact protected base: `f0da5cff3510d152e61bc9e3497adaed72d786a6`,
  the normal merge commit for documentation PR #33.
- Base tree: `bc0eff06cdd6f0bc8bf8344582c698cce204cba7`.
- Task branch: `codex/list-vms-minimal-projection`.
- This worktree is the Gate's only writer. The stopped PR #33 task, older H5C
  checkout, Birdsgone, and the preserved documentation-review source remain
  read-only.

## Preserved PR #33 review fixes

The reusable capability-discovery authority remains
[docs/troubleshooting.md](docs/troubleshooting.md#codex-desktop-capability-discovery).
This runtime candidate absorbs all four preserved review dispositions:

- use the established `list_vms(managedOnly=false)` signature;
- separate the reusable installation/current-skill/MCP-startup/selected-
  catalog/model-registry/production-typed-call workflow from dated incident
  evidence, with bounded repair, complete restart, and rollback;
- keep this handoff as a linked Gate summary instead of duplicating the
  troubleshooting matrix and repair narrative; and
- define an evidence lane and the current harness role of
  `selectedCapabilityRoots`, while identifying `deferred_tool_world_state` only
  as a separate unused feature key with no stability claim.

The standalone post-update selected-catalog recheck remains `notPerformed` and
fresh model inventory is not substituted for that lane. The documentation
continues to prohibit machine-specific cache paths and shell/WMI/direct-cmdlet,
handwritten JSON-RPC, alternate-registration, or mock/static substitution.

## Runtime design and compatibility

- Production `ListVms` enumerates with `Get-VM` once and uses a list-specific
  summary containing only ID, name, state, generation, Notes, and VM path.
  Notes/path are internal and are not returned publicly. The path does not call
  `ConvertTo-HcrRealVmSnapshot` or read NICs, switches, checkpoints, firmware,
  security, or complete VM configuration.
- Ownership first reads the keyed record by VM ID. No record means unmanaged
  and causes no disk/VHD projection. Only matching record ID/name and Notes
  marker candidates enter the new internal storage projection.
- The storage projection rebinds expected VM ID/name before reading the first
  attached-disk path and only the VHD-chain identity needed for the recorded
  base. Incomplete projection cannot establish ownership.
- `managedOnly=true` skips storage-unverified candidates.
  `managedOnly=false` retains their reduced summary as
  `OWNERSHIP_UNVERIFIED` and emits one bounded identity-free warning naming
  `ownershipProjection`.
- Provider inventory failures remain `HYPERV_UNAVAILABLE` with
  `error.details.stage: vmInventory`; required summary failures remain
  `INTERNAL_ERROR` with `stage: vmSummaryProjection`. State access/integrity
  errors remain `STATE_ROOT_ACCESS_DENIED` / `STATE_INTEGRITY_ERROR`. All list
  failures are `changed=false` and omit raw exceptions and sensitive identity.

The base/build version, exact 20-tool surface and inputs, public schemas and
version dispatch, Plan/Apply consumption/recovery, evidence contract,
`inspect_host`, full `inspect_vm`, guest paths, installation payload, and
release identities are unchanged. No public tool, field, or error code is
added.

## Changed areas

- `hyperv-clean-room/mcp/lib/Adapters.ps1`: shallow list projection, stable
  inventory/summary stages, and internal candidate-only ownership projection.
- `hyperv-clean-room/mcp/lib/Tools.Host.ps1`: keyed list ownership screen,
  candidate-only enrichment, safe filtering, and one bounded warning.
- `tests/gate2-runtime.tests.ps1`: zero/multi/Unicode, unmanaged deep-getter
  isolation, candidate-only projection, both filter modes, TOCTOU binding,
  staged failures, state failures, warning/privacy, catalog, inspect, and
  Plan/Apply regressions.
- `docs/specification.md`, `docs/architecture.md`, and
  `docs/troubleshooting.md`: synchronized contract, architecture, operator
  diagnosis, and preserved PR #33 review fixes.
- `TASK_HANDOFF.md`: this linked runtime-Gate status.

## Verification and review

The candidate passes the required local validation on 2026-08-03:

- `tests/gate2-runtime.tests.ps1`: `passed`, 1,682 assertions, exactly 20
  tools, four protocol versions, and `realHyperVMutations=0`.
- `prepare-test-python.ps1`: `passed`; Python 3.10.11 and the pinned isolated
  dependency set were prepared below ignored `.artifacts`.
- `validate-docs.ps1`: `passed`; 17 required documents, 102 local links,
  strict UTF-8, and zero mojibake markers.
- `validate-public-release.ps1`: `passed`; all 13 checks, including Gate 2 and
  the CI-safe Gate 4 path, with `realGuestOperations=0` and
  `realHyperVMutations=0`.

Commands:

```powershell
.\scripts\prepare-test-python.ps1
.\scripts\validate-docs.ps1
.\scripts\validate-public-release.ps1
```

The exact staged diff received substantive scope, compatibility, privacy,
error-boundary, test, documentation, and safety review with ZERO ACTIONABLE
FINDINGS. The final zero-VM assertions were also reviewed after they were added;
no candidate change remains outside this result.

The historical H4/G9 production-adapter `validate-gate4.ps1` smoke is not run
by this source Gate because it reads the real host. It is not a substitute for
the later separately authorized production typed acceptance.

## Evidence and safety result

The candidate removes the known structurally over-broad list path, but existing
logs still do not prove whether the prior first underlying exception came from
`Get-VM`, a VM projection getter, ownership state, or storage enrichment.
Mock/runtime/static success is not production Hyper-V evidence.

This Gate performs no production typed retry, plugin installation or cache
edit, tag, Release, merge, Hyper-V shell/WMI/direct-cmdlet substitute, VM/host/
guest mutation, Plan/Apply call, credential operation, package/portable/UI run,
evidence collection, or Birdsgone acceptance. Production
`list_vms(managedOnly=false)` and `inspect_vm` remain `notPerformed` for this
candidate and require a later separately authorized Gate.

## Blockers and next Gate

`blockers: []`

After complete local validation and ZERO ACTIONABLE FINDINGS, this Gate may
create one additive commit, push this `codex/` branch, and open a ready pull
request. It must not merge that PR. Any production typed retry remains a later
separately authorized Gate after candidate acceptance and installation.

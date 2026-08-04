# Task handoff: v0.4.1 minimal VM inventory repair candidate

`relayProtocolVersion: 1`

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

## Objective and authority

Package the merged production `list_vms` minimal-projection repair as a
backward-compatible v0.4.1 candidate, validate its exact source tree, and
publish a ready protected PR. This source Gate does not install the plugin,
call a production Hyper-V tool, merge, tag, or create a Release.

- PR [#34](https://github.com/rogue-shadowdancer/codex-hyperv-clean-room-plugin/pull/34)
  was normally merged at `2026-08-04T06:57:55Z`.
- Exact protected base:
  `4ba9cfbe2b75b514740e3e1467cba03b4f094417`.
- Base tree: `366bc98f02504f846291aa9b5fb81df1536f6cd0`.
- Task branch: `codex/v041-list-vms-release`.
- This worktree is the only writer. Older h5 checkouts, the preserved ccdc
  documentation worktree, and Birdsgone remain read-only.

## Merged runtime repair

Production `ListVms` enumerates once and projects only ID, name, state,
generation, Notes, and VM configuration path. Notes/path remain internal. The
list path does not call `ConvertTo-HcrRealVmSnapshot` or read NICs, switches,
checkpoints, firmware, security, or complete VM configuration.

Ownership reads keyed state by VM ID before enrichment. Missing state is
unmanaged and performs no disk/VHD read. Only matching ID/name/Notes candidates
enter the expected-identity storage seam, which revalidates the live Notes
marker. Incomplete storage stays `OWNERSHIP_UNVERIFIED`; it is skipped by
`managedOnly=true` and retained with one bounded identity-free warning by
`managedOnly=false`.

Inventory/provider failure is `HYPERV_UNAVAILABLE` at `vmInventory`; required
summary failure is `INTERNAL_ERROR` at `vmSummaryProjection`; recoverable
ownership projection is named only by its warning stage. State access and
integrity errors retain their existing stable codes. Every list failure is
`changed=false` and omits raw exceptions and sensitive resource identity.

## v0.4.1 candidate changes

- Advance runtime, manifest, catalog, and compatibility current identity to
  v0.4.1 while retaining exactly 20 public tools, every closed input, v1/v2
  dispatch, Plan/Apply/recovery semantics, and evidence fields.
- Add only the strict matching v0.4.1 evidence runtime-provenance pair; retain
  matching v0.3.0, v0.3.1, v0.3.2, and v0.4.0 pairs and reject cross-pairs.
- Keep authoritative and installable evidence schemas byte-identical and bind
  their updated SHA-256 in `contracts/v2/compatibility.json`.
- Recognize immutable installed v0.4.0 identities so read-only installation
  checks report stable drift instead of throwing, while the current source
  Gate requires v0.4.1 and rejects unknown or multiply suffixed versions.
- Keep that legacy recognition out of the source-install path: source inventory
  requires v0.4.1, and native evidence provenance uses case-sensitive build
  matching so it agrees with the authoritative JSON Schema.
- Add a v0.4.1 release-readback wrapper and freeze v0.4.0 as a historical
  baseline without modifying any historical tag, Release, or wrapper meaning.
- Freeze exactly one v0.4.1 cachebuster after the candidate is otherwise
  stable: `0.4.1+codex.20260804074002`. Do not regenerate it during review,
  merge, installation, or Release.

The reusable capability-discovery, selectedCapabilityRoots, catalog/model
registry, typed-call, restart, rollback, `deferred_tool_world_state`, and dated
incident boundaries remain in
[docs/troubleshooting.md](docs/troubleshooting.md#codex-desktop-capability-discovery).

## Installed-state boundary

At source-Gate start the owned/enabled personal plugin remained immutable
`0.4.0+codex.20260731141404` from
`52f947ce9a46f9a22a339a922042305e1e21a3ad`. Read-only
`check_install.ps1` reported `installed=true`, `owned=true`,
`marketplaceVisible=true`, `matches=false`, 31 source files, and a payload
inventory mismatch. That is expected source/install drift and is not v0.4.1
runtime evidence.

No manifest, marketplace, Codex cache, or installed payload is edited by this
Gate. Installation belongs only to the later exact protected merge Gate.

## Verification and review

The frozen source candidate passes the required local validation on
2026-08-04:

- `prepare-test-python.ps1`: passed with Python 3.10.11 and the pinned
  ABI-isolated dependency inventory.
- `tests/gate2-runtime.tests.ps1`: passed, 1,688 assertions, exactly 20 tools,
  four protocol versions, and `realHyperVMutations=0`.
- `tests/gate4-installation.tests.ps1`: passed, 45 assertions, 31 source
  payloads, stable stale-v0.4.0 mismatch reporting, and
  `realHyperVMutations=0`.
- `validate-gate6.ps1 -SkipInheritedBaseline`: passed with current runtime
  v0.4.1, 20 tools, seven v2 schemas, 19 dynamic compatibility checks, and
  zero real host/guest operations.
- `validate-gate7.ps1 -SkipInheritedBaseline`: passed with v0.4.1, 20 tools,
  386 runtime assertions, ten generated evidence validations, and zero real
  host/guest operations.
- `validate-install-source.ps1 -RequireCachebuster`: passed with frozen build
  `0.4.1+codex.20260804074002`, 31 payloads, five v1 schemas, and seven v2
  schemas.
- `validate-docs.ps1`: passed with 17 required documents, 102 local links,
  strict UTF-8, and zero mojibake markers.
- `validate-public-release.ps1`: passed all 13 checks, including Gate 2 and the
  CI-safe Gate 4 path, with `realGuestOperations=0` and
  `realHyperVMutations=0`.

Commands:

```powershell
.\scripts\prepare-test-python.ps1
.\scripts\validate-gate2.ps1 -SkipRealHostSmoke
.\tests\gate4-installation.tests.ps1
.\scripts\validate-docs.ps1
.\scripts\validate-public-release.ps1
```

The historical H4/G9 `validate-gate4.ps1` path includes bounded real-host
readback and is deliberately not run by this source Gate. The CI-safe aggregate
and `validate-gate2.ps1 -SkipRealHostSmoke` do not substitute for later
production typed acceptance.

The final staged candidate must pass `git diff --cached --check` and substantive
review with ZERO ACTIONABLE FINDINGS. After push, the exact PR head must also
complete required checks and one fresh `@codex review` 30-minute unchanged-head
window. Mock/runtime/schema/static success is not production Hyper-V evidence.

## Safety result and next Gate

This Gate performs no plugin installation, production typed call, Hyper-V
shell/WMI/direct-cmdlet or JSON-RPC substitute, VM/host/guest mutation,
Plan/Apply call, credential operation, package/portable/UI run, evidence
collection, Birdsgone acceptance, merge, tag, or Release. Production
`inspect_host`, `list_vms(managedOnly=false)`, and `inspect_vm` remain
`notPerformed` for v0.4.1.

`blockers: []`

After the ready PR is normally merged by the user, the next task must fetch and
bind to that exact protected merge commit, validate and install the one frozen
v0.4.1 build, require all 31 payload hashes and installed identity fields to
match, and then start a separate fresh non-elevated selected-plugin task. The
installation task itself must not call any production Hyper-V tool.

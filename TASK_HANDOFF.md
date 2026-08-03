# Task handoff: Desktop capability-discovery documentation closeout

`relayProtocolVersion: 1`

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

## Objective

Close only the documentation and GitHub gate for the Birdsgone Codex Desktop
capability-discovery repair. Document the diagnosis, minimal configuration
repair and rollback, and separate CLI/Desktop production read-only smoke
evidence without modifying the plugin runtime, installed cache, Codex
configuration, Hyper-V, or Birdsgone.

## Gate scope and authority

- Exact base and protected `origin/master` at task start:
  `52f947ce9a46f9a22a339a922042305e1e21a3ad`.
- Task branch: `codex/desktop-capability-discovery-docs`.
- Writable files: `docs/troubleshooting.md` and `TASK_HANDOFF.md` only.
- The older `codex/h5c-native-token-diagnostic` checkout and Birdsgone
  repository remain read-only; no user-owned change is absorbed.
- This gate creates an additive commit, branch push, and pull request only. It
  does not merge, tag, release, install, or change repository administration.

## Diagnosis and evidence boundaries

The affected environment had an installed and enabled
`hyperv-clean-room@personal` build at
`0.4.0+codex.20260731141404`. A stale task referenced the absent v0.3.2 skill
cache; resolving the current installed version located the v0.4.0 skill. The
installed manifest, `.mcp.json`, and PowerShell MCP launch path were internally
consistent. Those facts proved installation and launchability, not model-side
tool injection.

Before the Desktop update/restart, a selected app-server catalog-only check
reported ready state, exactly 20 unique tools, and `toolCallCount: 0`, while
affected task model registries contained no callable Hyper-V tools after the
older `tool_search` path was removed. This separated selected-child catalog
readiness from task-level capability discovery.

The minimal persistent repair was the following single line in the existing
`[features]` table of the user's Codex configuration:

```toml
executor_capability_discovery = true
```

A timestamped backup was preserved first under the user's `.codex\backups`
directory with leaf
`config.toml.executor-capability-discovery-20260801-023158.bak`. The key occurs
exactly once. No `deferred_tool_world_state` setting or duplicate MCP
registration was added. A complete Codex Desktop restart was required.

Rollback means preserving the current configuration, then preferably removing
only the single discovery line. Restore the whole timestamped backup only when
a diff proves that no later unrelated configuration change would be lost. In
either case, validate the remaining TOML and completely restart Desktop.
Rollback does not uninstall the plugin or alter Hyper-V.

After restart, a fresh Desktop task selected **Hyper-V Clean Room (personal)**
through the UI before its first message. Its model registry contained exactly
20 unique `mcp__hyperv_clean_room__*` tools, including `inspect_host`,
`list_vms`, and `inspect_vm`, and it resolved the current v0.4.0 skill path.

A separate post-update standalone `selectedCapabilityRoots` plus turn/start
catalog-only protocol recheck was `notPerformed`: the packaged Desktop
executable could not be safely invoked from the external shell, and the
repository had no equivalent Desktop harness. The fresh task's 20-tool model
inventory must not be substituted for that unperformed catalog-only lane.

## Production typed smoke evidence

CLI and Desktop results are separate evidence even though they matched. Both
smokes used only the selected plugin's typed surface, stopped at the first
`list_vms` failure, returned no mock marker, and made no mutation.

### Stable CLI 0.144.1

- Registry: `passed`, exactly 20 unique Hyper-V tools with the three required
  names present.
- `inspect_host({})`: `passed`; `ok=true`, `changed=false`, `elevated=false`,
  `hyperVAdministratorsTokenEnabled=true`, `hyperVAuthorized=true`, and
  `authorizationMode=hyperVAdministrators`.
- `list_vms({managedOnly:false})`: `failed`; `ok=false`, `changed=false`, and
  `INTERNAL_ERROR`.
- `inspect_vm`: `notPerformed` because enumeration returned no VM name.
- Typed tool calls: exactly 2.

### Fresh selected Desktop task

- Registry: `passed`, exactly 20 unique Hyper-V tools with the three required
  names and current v0.4.0 skill path.
- `inspect_host({})`: `passed`; the same least-privilege, non-elevated,
  `changed=false` authorization fields as the CLI result.
- `list_vms({managedOnly:false})`: `failed`; `ok=false`, `changed=false`, and
  `INTERNAL_ERROR`.
- `inspect_vm`: `notPerformed` because enumeration returned no VM name.
- Typed tool calls: exactly 2.

The model-side capability-discovery repair is proven. Production VM
enumeration and VM inspection are not proven, and the `INTERNAL_ERROR` cause
was not diagnosed in this gate. Do not infer successful real-VM access from
host authorization, catalog/model inventory, installation, mock, parser,
schema, or static evidence.

## Changed areas

- `docs/troubleshooting.md`: adds the layered diagnostic matrix, one-line
  repair and rollback, restart procedure, corrected pre/post catalog boundary,
  and separate CLI/Desktop smoke status.
- `TASK_HANDOFF.md`: replaces the completed v0.4.0 release handoff with this
  documentation-only closeout state and the remaining evidence gaps.
- Runtime, tests, schemas, manifests, version files, README, specification,
  installation cache, configuration, and Birdsgone are unchanged.

## Validation and review

The documentation candidate passed the required local checks on 2026-08-03:

- `prepare-test-python.ps1`: `passed`; Python 3.10.11 and the pinned isolated
  dependency set were prepared below ignored `.artifacts`.
- `validate-docs.ps1`: `passed`; 17 required documents, 100 local links,
  strict UTF-8, and zero mojibake markers.
- `validate-public-release.ps1`: `passed`; all 13 checks, including Gate 2 with
  real-host smoke skipped and the CI-safe Gate 4 path, with
  `realGuestOperations=0` and `realHyperVMutations=0`.

Commands:

```powershell
.\scripts\prepare-test-python.ps1
.\scripts\validate-docs.ps1
.\scripts\validate-public-release.ps1
```

Only CI-safe mock/parser/schema/static/publication checks are acceptance
evidence. The historical H4/G9 production-adapter `validate-gate4.ps1` smoke is
not run by this docs gate and is not a substitute for the typed CLI or Desktop
results above. The final staged two-file diff requires substantive scope,
truthfulness, privacy, link, and evidence-boundary review with ZERO ACTIONABLE
FINDINGS before commit.

## Safety result

- No Hyper-V typed call, shell/WMI/direct Hyper-V substitute, Plan/Apply call,
  VM/host/guest mutation, credential operation, package or portable run,
  WebDriver/UI action, evidence collection, or Birdsgone G8 operation was
  performed by this docs gate.
- The prior CLI/Desktop typed smokes were read-only and each stopped after
  `list_vms` returned `changed=false` with `INTERNAL_ERROR`.
- VM mutation, guest/package/portable/UI/evidence acceptance, successful real
  VM enumeration/inspection, and Birdsgone G8 remain `notPerformed`.

## Blockers and next gate

`blockers: []`

No subsequent implementation gate is authorized. A new, separately scoped
gate is required to diagnose the production `list_vms` `INTERNAL_ERROR` or to
perform any additional production typed call. This task ends after the two
documents pass validation and staged review, then are committed, pushed, and
opened as a pull request; it does not relay into implementation.

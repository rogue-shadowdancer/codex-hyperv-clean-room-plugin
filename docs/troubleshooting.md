# Troubleshooting

## Diagnose without broadening scope

Start with the exact stable error code, the requested tool, and whether the
adapter was mock or production. Do not respond to a failure by adding a shell
escape, weakening ownership or hash checks, deleting partial resources, or
putting credentials in arguments.

Gate 4 validation is allowed to read the real host only through `inspect_host`
and a `plan_vm_create` call that rejects a nonexistent ISO before mutation. It
must not enroll a credential, open a real guest session, transfer a file, start
a package, or mutate Hyper-V.

The v0.4.1 Windows MCP compatibility repair has a separately authorized
real-host diagnostic: it deliberately removes `COMPUTERNAME`, initializes the
production adapter, then calls only `inspect_host` and
`list_vms(managedOnly=false)`. Both must remain successful and read-only. This
is repository repair evidence, not installed-plugin or Gate C acceptance. The
publication aggregate still uses `-SkipRealHostSmoke` and the CI-safe Gate 4
path. Shell, WMI, local JSON-RPC, direct cmdlets, `inspect_vm`, and Plan/Apply
are not substitutes or follow-ups in this Gate.

## Development environment

### Prepared test Python is unavailable or stale

Run:

```powershell
.\scripts\prepare-test-python.ps1
.\scripts\validate-gate2.ps1
```

If the default `python` is older than 3.10, the preparation script tries the
Windows Python launcher. To select the interpreter explicitly:

```powershell
.\scripts\prepare-test-python.ps1 `
  -PythonCommand $env:LOCALAPPDATA\Programs\Python\Python310\python.exe
```

The ignored `.artifacts\test-python\runtime.json` records the selected
interpreter and ABI-isolated dependency path. Moving or uninstalling that
interpreter makes validation fail safely. Rerun preparation; do not copy a
binary extension directory between Python ABIs.

### Pinned dependency installation fails

Confirm that the selected interpreter has `pip`, network/package-index policy
allows the exact versions in `requirements-dev.txt`, and a compatible Windows
wheel exists. Preparation uses binary distributions only and writes below
ignored `.artifacts`. It does not modify the production plugin.

### Documentation validation fails

Run only the focused check:

```powershell
.\scripts\validate-docs.ps1
```

The bounded failure lists missing documents, required topics, strict UTF-8 or
mojibake problems, and broken repository-relative links. Save Markdown as
UTF-8 without BOM. Do not trust a terminal's mojibake display over a strict
file decode.

### `Get-VM` or `Get-VMSwitch` fails because the host name is null

On Windows, a filtered Codex MCP child can start without `COMPUTERNAME`; the
Hyper-V PowerShell module may then reject otherwise valid `Get-VM` or
`Get-VMSwitch` calls with a null `name` parameter. The plugin declares only
`env_vars: ["COMPUTERNAME"]` for its sole MCP server. At the earliest runtime
initialization stage it also repairs a missing or whitespace process value from
`[Environment]::MachineName` before loading the adapter or state store. A
non-empty explicit value is preserved.

This fallback changes only the current MCP child. Do not add other environment
variables or literal values, write user/system environment or registry state,
edit `config.toml` or the marketplace, or log the raw environment. Use the
contract, runtime-environment, missing-environment MCP protocol, and authorized
read-only host regressions to diagnose the source candidate. After merge, use a
separate exact-install Gate before any selected-plugin acceptance; a repository
diagnostic never proves that the installed copy was updated.

## Plugin installation

### Source validation fails

Run `scripts\validate-install-source.ps1` and use its bounded error. Do not
install a payload with untracked files, reparse points, forbidden machine-state
extensions, an unexpected folder/manifest name, or a version outside the
recognized v0.4.0/v0.4.1 patch identities plus one optional Codex cachebuster.
Gate 1 requires the current candidate to be v0.4.1; v0.4.0 parsing remains only
for stable old-install drift reporting. The earlier `COMPUTERNAME` repair build
was `0.4.1+codex.20260805101924`; the current exact-Test2 candidate freezes
exactly `0.4.1+codex.20260813075830` after the candidate is stable and performs
no install or Release during its source Gate.
The immutable historical `v0.1.1`, `v0.2.0`, `v0.3.0`, `v0.3.1`, and
`v0.3.2`, and `v0.4.0` Releases remain separate accepted artifacts.

### Exact Test2 sidecar returns `PORTABLE_MANIFEST_INVALID`

First verify the unchanged sidecar is 142,013 bytes with SHA-256
`f9267d70ca9b412bc54170489e38d211bd528a28e64a1fe15fa2cf987471650c`
and that the profile binds that same identity. The compatible runtime accepts
only a complete `fresh-exact-head` triple, homogeneous path or file-identity
source arrays, and a complete Maa Agent size pair. It then requires the source
manifest row and every path/size/SHA binding to agree with `removedFiles` and
the complete ZIP inventory. Field names are case-exact, and slash/backslash
aliases are normalized before Windows case-insensitive collision checks.

Do not delete the producer fields, convert strings to invented identity
objects, rewrite/re-hash the immutable sidecar, or weaken `additionalProperties`
or archive checks. If the exact source still reports unsupported root fields,
string items "must be an object", or unsupported Agent sizes, the selected
server is an older installed build. Stop before VM start or credential
enrollment, install the exact protected repair commit with the repository
installer, verify all 31 payload hashes and one catalog entry, and start a
fresh selected-plugin task before retrying validation.

### Source is v0.4.1 but the installed copy is v0.4.0

Before the protected v0.4.1 merge/install Gate, `check_install.ps1` should
report the owned and enabled v0.4.0 installation as `installed=true`,
`owned=true`, and `matches=false`, with the old installed version/source commit
preserved in the readback. This is expected source/install drift, not evidence
that the new runtime failed. Do not edit the install manifest, marketplace, or
Codex cache and do not run production tools from the old payload. After the
candidate is merged, use only the bounded installer and require all 31 payload
hashes, the exact protected commit, cachebuster, one marketplace entry, and
installed/enabled status to match before starting a fresh task.

### A portable launch reports `PORTABLE_DEPLOYMENT_DRIFT`

The shared active deployment changed after this operation published its own
slot. The runtime intentionally refuses to launch the replacement candidate
under the older operation's evidence identity. Do not bypass the binding or
edit `active.json`; start a new test operation from current state.

### A portable launch reports `PORTABLE_ENTRYPOINT_DRIFT`

The deployed entrypoint path, size, SHA-256, or ordinary-file identity changed
between validated deployment and the final pre-launch readback. The runtime
intentionally refuses to start those bytes under the older deployment
identity. The verified handle denies write/delete sharing until process
creation returns, while no-follow directory handles deny replacement of every
path component from the local volume root. Do not edit the slot or
suppress the check; discard the candidate state and begin a new authorized
test operation from known source bytes.

### Evidence reports `RUNTIME_PROVENANCE_INVALID`

The installed manifest, ownership record, plugin version, declared file
identity, or closed installed file set no longer matches the current ordinary
bytes. Do not edit the installed manifest or suppress the check. Treat the
installation as untrusted and use the P3.3 source-validation/install workflow
to replace it from the exact verified source candidate without creating a new
cachebuster.

### The target is not owned

`install_plugin.ps1` refuses an existing
`%USERPROFILE%\plugins\hyperv-clean-room` unless its exact
`.codex-plugin\install-ownership.json` marker owns that canonical path. Inspect
the directory's provenance. Do not fabricate a marker, overwrite a foreign
directory, or add automatic deletion to make the install pass.

### The owned target contains an unexpected file

The installer never deletes it. Review the reported relative path and determine
whether another process or a prior layout created it. Resolve provenance
outside the installer, then rerun source validation and installation.

### `matches` is false

Read `payloadError` from `scripts\check_install.ps1`. A payload path, size,
SHA-256, source commit, version, cachebuster, or install-manifest claim differs.
Return to the intended Git source and rerun the owned installer; do not weaken
hash checks. After committing Gate changes, reinstall once more so
`installedSourceCommit` matches the new HEAD.

### `marketplaceVisible` is false

The default personal marketplace is implicit. Run `codex plugin list` and
confirm one local `hyperv-clean-room@personal` row. Rerun
`scripts\install_plugin.ps1`, which updates the entry through `plugin-creator`
and executes `codex plugin add hyperv-clean-room@personal`. Do not hand-edit
`marketplace.json` or `config.toml`, and do not run
`codex plugin marketplace add` for the default personal path.

### Codex still loads an older local copy

Use the default `plugin-creator` cachebuster helper documented in
[maintenance.md](maintenance.md), reinstall, verify matching source/installed
cachebusters, and start a new Codex task. Do not append multiple suffixes or
increment the numeric version merely to bypass cache behavior.

## Codex Desktop capability discovery

### Reusable diagnostic workflow

An **evidence lane** is one independently verified boundary; success in one
lane cannot substitute for another. In this repository's acceptance harness,
`selectedCapabilityRoots` is the local-environment list whose plugin ID entry
binds the selected personal plugin to a fresh app-server thread; see
[installation.md](installation.md#proven-boundary). This describes
the current harness contract, not a promise that the app-server field is a
public stable API.

Diagnose a selected plugin that has no callable tools in this order:

| Lane | Reusable check | Stop condition and conclusion |
| --- | --- | --- |
| Installation | `codex plugin list` reports the intended personal plugin installed and enabled. | A missing or wrong build stops the workflow. A passing row proves installation only. |
| Current skill path | Resolve the installed version before reading `skills/manage-hyperv-clean-room/SKILL.md`. | An absent current path stops the workflow. A stale path in task context is not the installed authority. |
| MCP startup | Verify the installed manifest, `.mcp.json`, and declared `server.ps1` launch path; use bounded process diagnostics only when needed. | A launch failure stops catalog checks. A running child does not prove catalog or model injection. |
| Selected catalog | In a supported fresh app-server thread with the explicit selected-plugin binding, require ready status, exactly 20 unique tools, and `toolCallCount: 0`. | Failure stops catalog acceptance. Success proves only the selected child catalog. |
| Model registry | In a fresh Desktop task where **Hyper-V Clean Room (personal)** was selected before the first message, require exactly 20 unique `mcp__hyperv_clean_room__*` tools and the required `inspect_host`, `list_vms`, and `inspect_vm` names. | Missing tools stop production calls. Success proves model-callable injection only. |
| Production typed call | Use only separately authorized typed tools and preserve `ok`, `changed`, warnings, and error codes. | Stop at the first error, mock marker, or `changed=true`; only each successful call proves its own production read. |

Record any unavailable lane as `notPerformed`. Do not infer a selected catalog
from model inventory, or real-VM access from installation, catalog, registry,
mock, parser, schema, or static evidence.

### Minimal repair, restart, and rollback

When installation, current skill, MCP startup, and selected catalog pass but a
fresh task still lacks the callable registry, first preserve a timestamped copy
of `%USERPROFILE%\.codex\config.toml` below
`%USERPROFILE%\.codex\backups`. Add exactly one line inside the existing
`[features]` table:

```toml
executor_capability_discovery = true
```

Do not create a duplicate `[features]` table or MCP registration.
`deferred_tool_world_state` is a separate Codex feature key; this repair does
not enable, add, or depend on it, and this document makes no stability claim
about that key. Completely exit and restart Codex Desktop, then create a fresh
task and select the personal plugin before the first message. Existing tasks
are not acceptance evidence for a restart-sensitive discovery change.

To roll back, first preserve the current file, then prefer removing only the
single `executor_capability_discovery = true` line. Restore the whole
timestamped backup only after a diff proves that doing so will not discard any
later unrelated configuration change. Confirm the `[features]` table is still
valid TOML and restart Codex Desktop completely. Rollback removes this
environment's discovery repair; it does not uninstall the plugin, alter the
installed cache, or change Hyper-V.

### Incident evidence: 2026-08-03 closeout

- Installed/enabled build: `0.4.0+codex.20260731141404`. The stale task path
  named the absent `0.3.2+codex.20260731014242` skill cache; the current v0.4.0
  skill was present. Do not copy a machine-specific absolute cache path into
  evidence.
- Preserved backup leaf:
  `config.toml.executor-capability-discovery-20260801-023158.bak`.
- Before the Desktop update/restart, a selected catalog-only check reached
  ready state with exactly 20 unique tools and `toolCallCount: 0`, while task
  registries still had no callable Hyper-V tools after the older `tool_search`
  path was removed.
- After restart, a fresh Desktop task selected through the UI had exactly 20
  unique model-callable Hyper-V tools, the three required tools, and the current
  v0.4.0 skill path.
- A separate post-update standalone selected-catalog protocol recheck using
  `selectedCapabilityRoots` and turn/start was `notPerformed`. The packaged
  Desktop executable could not be safely invoked from the external shell and
  this repository had no equivalent Desktop harness. The fresh task's model
  inventory is not a substitute for that lane.

Keep CLI and Desktop evidence separate. In this incident, stable CLI `0.144.1`
and the fresh Desktop task each exposed the exact 20-tool registry. Their typed
production smokes then matched:

| Surface | `inspect_host` | `list_vms(managedOnly=false)` | `inspect_vm` |
| --- | --- | --- | --- |
| CLI | `passed`: `ok=true`, `changed=false`, non-elevated `hyperVAdministrators` authorization, no mock warning | `failed`: `ok=false`, `changed=false`, `INTERNAL_ERROR`, no mock warning | `notPerformed` because enumeration returned no VM name |
| Desktop | `passed`: `ok=true`, `changed=false`, non-elevated `hyperVAdministrators` authorization, no mock warning | `failed`: `ok=false`, `changed=false`, `INTERNAL_ERROR`, no mock warning | `notPerformed` because enumeration returned no VM name |

The discovery repair is therefore proven for model-side typed-tool injection,
but real VM enumeration and inspection are not proven. Stop on the typed
`list_vms` failure. Do not substitute shell, WMI, direct Hyper-V cmdlets,
hand-written JSON-RPC, another plugin registration, or mock/static evidence.
No VM or host mutation occurred, and guest, package, portable, UI, evidence,
and Birdsgone clean-room acceptance remain `notPerformed`.

## MCP transport

### `SERVER_NOT_INITIALIZED`

The client called a tool before sending the MCP initialized notification.
Complete `initialize`, use one of the four supported protocol versions, send
`notifications/initialized`, then call `tools/list` or `tools/call`.

### JSON parse, invalid request, or unknown method

The server accepts one JSON object per UTF-8 line. It rejects JSON-RPC batches.
Stdout must contain only protocol responses. Check the client framing rather
than adding terminal output to `server.ps1`.

### Unsupported protocol version

Supported versions are exactly `2024-11-05`, `2025-03-26`, `2025-06-18`, and
`2025-11-25`. A newer request negotiates the newest supported value; a request
older than the minimum is rejected.

## Host and VM planning

### `HYPERV_UNAVAILABLE`

Run `inspect_host`. Check `hyperVCommandsAvailable` and `hypervisorPresent`.
The plugin does not enable Windows features or alter firmware settings. Repair
host prerequisites outside the plugin and inspect again.

For `list_vms`, bounded `error.details.stage: vmInventory` means the required
`Get-VM` provider inventory itself was unavailable. It does not prove that the
host has no VMs, and the response deliberately omits the provider exception,
VM identity, paths, token facts, and environment. Do not retry through shell,
WMI, direct Hyper-V cmdlets, handwritten JSON-RPC, or another transport.

### `list_vms` projection boundaries

`list_vms` uses a list-specific minimal projection. The inventory path reads
only VM ID, name, state, generation, Notes, and configuration path; Notes and
path are internal ownership-screening fields and are not returned in public VM
summaries. It does not inspect adapters, switches, checkpoints, firmware,
security, or full VM configuration. A candidate storage projection rebinds the
expected ID/name and revalidates the live Notes marker before verification.
`inspect_vm` remains the separately authorized deep read.

- `INTERNAL_ERROR` with `error.details.stage: vmSummaryProjection` means at
  least one required minimal summary could not be read. The failure remains
  `changed=false` and exposes no raw exception or VM identity.
- A successful result warning ending in `stage ownershipProjection` means an
  existing ownership candidate passed the keyed state-record and ID/name/Notes
  marker screen, but its separately rebound minimal storage projection was
  unavailable. The VM is never reported as verified: `managedOnly=true` skips
  it, while `managedOnly=false` retains the reduced summary with
  `ownershipStatus: OWNERSHIP_UNVERIFIED`. Multiple affected candidates produce
  one bounded warning without names, IDs, paths, SIDs, or token information.
- `STATE_ROOT_ACCESS_DENIED` and `STATE_INTEGRITY_ERROR` remain hard list
  failures. They are not converted to unmanaged or ownership-projection
  warnings; restore the state root's bounded access/integrity outside the
  plugin before a separately authorized typed retry.

An unmanaged VM has no keyed ownership record and therefore never enters disk
or VHD enrichment. Do not create or edit an ownership record merely to make a
VM appear managed.

### `HYPERV_AUTHORIZATION_REQUIRED`

Run `inspect_host` and read `elevated`,
`hyperVAdministratorsTokenEnabled`, `hyperVAuthorized`, and
`authorizationMode`. Prefer a normal non-elevated Codex process whose current
token has enabled local `Hyper-V Administrators` membership. Group changes take
effect only after a complete sign-out/sign-in. An elevated Administrator token
is compatible but intentionally emits `BROADER_PRIVILEGE_CONTEXT`. Do not
disable the authorization check or grant unrelated administrator rights.

### `ISO_ACCESS_DENIED`, `VM_ROOT_ACCESS_DENIED`, or `STATE_ROOT_ACCESS_DENIED`

The current MCP token cannot read the ISO, enumerate the chosen existing VM
root, or enumerate/write the plugin state root and one of its required
`plans`, `operations`, `ownership`, `evidence-staging`, or `locks` children.
Correct the path or access outside the plugin, then create a fresh plan. State
initialization uses bounded delete-on-close probes but does not change ACLs.
The plugin does not create a replacement VM root, elevate itself, or retry a
consumed plan.

### `INVALID_ISO`

`isoPath` must be an existing non-empty local ordinary `.iso` file. UNC paths,
directories, reparse files, missing files, and other extensions are rejected.
The Gate 2 real-host smoke intentionally expects `INVALID_ISO` from a unique
nonexistent path; that failure demonstrates that planning stops before
mutation.

### `SWITCH_NOT_FOUND`, `VM_ALREADY_EXISTS`, or path conflict

Inspect the host with `vmRoot` and `vmName`, choose an existing switch, and
resolve the conflict outside the plugin. The plugin does not create switches or
delete conflicting resources.

### `INSUFFICIENT_SPACE` or target-volume drift

The plan records volume identity and conservative required capacity. Current
free space may change, but apply requires the same volume and at least the
recorded required bytes. Free space recovery is an external administrator
task. Create a new plan after it is complete.

### `PLAN_EXPIRED`, `PLAN_ALREADY_CONSUMED`, or drift error

Do not replay the plan. Inspect current state and create a new plan. Wrong
restore names or confirmation tokens also consume a well-formed plan by
design.

### `OWNERSHIP_UNVERIFIED`

Compare the VM ID, name, path, VHDX, Hyper-V Notes marker, and state record.
Read-only inspection remains safe. Do not edit the marker or state merely to
force agreement; establish resource provenance first.

If `inspect_vm` reports an active `.avhdx`, compare
`ownership.recordedBaseVhdxPath`, `ownership.activeVhdxPath`, and
`ownership.storageBinding`. A legitimate automatic-checkpoint chain is verified
only as `verifiedDifferencingChain`: every identity-bearing parent link must be
complete and acyclic, the chain fingerprint must match, and the terminal VHDX
must be the unchanged recorded base. Do not replace the recorded path with the
leaf, hand-edit ownership, or delete/merge/rename the checkpoint to make the
check pass. An unrelated, incomplete, or forged chain must remain
`OWNERSHIP_UNVERIFIED`.

### Power transitions are rejected until automatic checkpoints are disabled

New H5A-created VMs disable automatic checkpoints before ownership
publication. A pre-fix VM can remain chain-verified while the setting is true
or unavailable, but `plan_vm_power` rejects both actions with
`VM_STATE_UNSUPPORTED`. Preserve the current power state and follow the
reviewed recovery sequence in
[operations.md](operations.md#pre-fix-automatic-checkpoint-recovery): one
separately approved setting-only disablement, read-only reinspection, and only
then a fresh guarded power plan. Do not force-off the VM or change its
checkpoint/disk chain.

## Credential profiles and PowerShell Direct

### `CREDENTIAL_PROFILE_NOT_FOUND`

Verify the profile name and the Windows account running the MCP server. DPAPI
profiles are current-user/current-machine data and are also bound to one VM
name. Run the interactive initializer only when real credential enrollment is
explicitly authorized.

### `CREDENTIAL_PROFILE_VM_MISMATCH`

The profile belongs to another VM. Do not copy or edit metadata. Enroll a new
profile for the intended VM with two validated accounts.

### `CREDENTIAL_PROFILE_UNREADABLE`

The CLIXML cannot be decrypted by the current Windows user on this machine, or
the bundle is damaged. DPAPI data is not portable. Re-enroll on the correct
host/account after authorization. Never inspect or paste serialized secret
content into a report.

Enrollment publishes only after both DPAPI files and metadata pass readback in
a private pending directory. A failed enrollment does not replace an existing
profile and does not expose the pending directory under the requested profile
name. Publication uses exact-destination directory move, so one concurrent
initializer may win and the other must fail without merging. The winner's final
protected ACL and exact three-file bundle are read-validated again. Diagnose
leftover pending state as credential material; do not copy it into a profile or
repository.

### `POWERSHELL_DIRECT_UNAVAILABLE`

Confirm the VM exists, is running, has a supported Windows guest, and accepts
the orchestration administrator credential. PowerShell Direct does not use
WinRM or guest networking. Do not fall back to SSH, WinRM, plaintext password
arguments, or a network command channel.

The adapter configures remoting open, operation, and cancel timeouts and checks
an end-to-end deadline, but `New-PSSession`, `Invoke-Command`, and guest copy are
synchronous transport calls outside the fixed worker's Windows job object. If
the transport hangs past its bound, the plugin cannot kill that call through
the guest worker job. Treat the operation as indeterminate, preserve VM state,
repair PowerShell Direct externally, and inspect again before any mutation.

### `GUEST_TEST_USER_MISMATCH` or privilege error

The standard-user worker SID, administrator status, elevation, or integrity did
not match enrollment. Re-run identity inspection and, if accounts changed,
enroll a new profile. An administrator or elevated test token cannot produce a
passed current-user lifecycle.

## Guest staging and fixed worker

### `ARTIFACT_SOURCE_CHANGED`

The host file changed between selection and supervised transfer. Stop using
the file, establish a stable build artifact, validate the profile hash if one
is declared, and start a new operation.

### `ARTIFACT_HASH_MISMATCH`

The stable host `sourceSha256`, guest `guestSha256`, or byte length disagreed.
Do not retry with hash validation disabled. Inspect storage integrity and stage
a known stable artifact in a new operation.

### Worker transfer or hash failure

The plugin-owned `GuestWorker.ps1` did not copy or hash identically. Check
PowerShell Direct, guest storage, ACLs, and endpoint-security events. Do not
execute a caller-provided replacement script.

### Guest workspace or reparse failure

The fixed `ProgramData` operation path could not be created or contained a
reparse point. Preserve the path for diagnosis. Do not follow, replace, or
delete it automatically. A host administrator should determine provenance
before any manual recovery.

The plugin also rejects an ACL that still inherits permissions, contains an
unexpected SID, or gives the test SID any write-capable right. Inspect the
guest parent ACL for provenance, but do not weaken the protected explicit
workspace policy to accommodate it. New plugin ancestors receive the protected
descriptor during creation; an existing path must transfer to the live
administrator owner and exact grants or the operation stops.

### Worker timeout

The administrator supervisor creates the worker suspended, assigns it to the
Windows job, resumes it, and recomputes the remaining deadline. After a timeout,
late/unbound launch result, or unexpected descendant, it terminates the job and
requires root exit plus zero active processes. A package child may already have
changed guest state. Preserve evidence and inspect the guest; a deliberately
surviving `launchApplication` child was first suspended and rebound as the only
active job process. It may be stopped only through its separately recorded
current-operation identity and the same retained handle used to revalidate it.

## Profile and step failures

### `PROFILE_INVALID`

Call `validate_test_profile` and address every bounded error. Typical causes:

- the first and only `stageArtifact` rule is violated;
- `cleanupSteps` is missing;
- `fixtures`, `applications`, `steps`, `cleanupSteps`, or
  `manualAssertions` is an object or scalar instead of a JSON array;
- IDs are duplicated across ordinary, cleanup, and manual arrays;
- an application reference is unknown;
- a path is rooted, traversing, expanding, or otherwise unsafe;
- a command/script/shell/URL field or unknown property is present;
- action `required` is false;
- cleanup type or timeout budget is invalid.

Use [profile-authoring.md](profile-authoring.md) for the field contract.

### Install or uninstall returns nonzero

Preserve the exact exit code and fixed installer type in evidence. The adapter
does not add caller arguments. Confirm that the artifact actually supports the
frozen NSIS or MSI current-user behavior. If it does not, the profile cannot
claim support by injecting a custom command.

### A unique uninstaller cannot be found

For `hkcuUninstall`, the worker requires exactly one matching ordinary
uninstaller below the declared application directory and refuses embedded
arguments. For `msiProduct`, it requires one matching MSI product-code entry.
Ambiguity fails safely. Fix product registration or revise the formal contract;
do not execute an unrestricted registry uninstall string.

### Cleanup stop reports identity mismatch

The PID exited, was reused, changed executable path, or no longer matches the
recorded start identity. The worker deliberately did not stop it. Continue
reviewing later cleanup results and handle any remaining process manually only
with separate authorization.

## Evidence

### `EVIDENCE_INVALID`

Run `validate_evidence` and inspect bounded errors. Common causes include
modified identities or order, forged cleanup trigger state, performed cleanup
while untriggered, a wrong derived overall status, mismatched hashes, or a
passed result with invalid ownership/token facts.

### Manual evidence reference rejected

The referenced file must already be under the operation's server-controlled
evidence staging root, use a safe relative path, be an ordinary non-reparse
file, and match the supplied SHA-256. An exported file or absolute path is not
a live reference. Mutable control documents cannot reference themselves. A
file changed after attestation is rejected under the operation lock when export
rechecks the claim and source/copy/inventory hashes.

### Evidence output forbidden or already exists

Choose an existing safe parent directory outside protected, plugin, credential,
state, and managed Hyper-V roots. `collect_evidence` creates a new operation
directory and refuses to overwrite an existing one.

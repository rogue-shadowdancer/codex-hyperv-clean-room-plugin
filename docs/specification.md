# Hyper-V Clean Room v1 specification

Status: Gate 1.1 frozen baseline. The MCP entry point remains a fail-closed
stub; no runtime behavior is implemented in this gate.

## Purpose and boundary

The plugin provides typed MCP tools for Windows Hyper-V host inspection,
guarded VM lifecycle operations, PowerShell Direct guest inspection,
declarative package lifecycle tests, and structured evidence. The MCP server is
the functional product. The companion skill is optional guidance and must not
be required to discover or call any tool.

The plugin does not download Windows, manage licenses, inject plaintext
credentials, remove WebView2, disable Windows security features, or expose
arbitrary shell execution. It provides no public operation that deletes a VM,
VHDX, checkpoint, or host file.

## Runtime and transport

- The production runtime supports Windows PowerShell 5.1 and the Hyper-V
  PowerShell module. It must not depend on Python. Python and the Draft 2020-12
  `jsonschema` validator are development and CI dependencies only.
- Use JSON-RPC MCP over stdio. Read and write one UTF-8 JSON message per line.
- Reserve stdout for protocol messages. Send bounded diagnostics to stderr.
- Support exactly these MCP protocol versions: `2024-11-05`, `2025-03-26`,
  `2025-06-18`, and `2025-11-25`. Negotiate a mutually supported value and
  never announce a version newer than the request or outside this set.
- Return every tool result as a JSON string in the MCP text content block.
- Set the MCP `isError` flag when the envelope has `ok: false`.
- Never serialize a PowerShell error record or stack trace into a response.

## Common result envelope

Every tool returns the shape defined by
`hyperv-clean-room/schemas/operation-envelope.schema.json`:

```json
{
  "schemaVersion": 1,
  "ok": true,
  "operationId": "d6de12e7-66d4-454f-b205-5d7f744a0aa7",
  "changed": false,
  "data": {},
  "warnings": [],
  "evidencePath": null
}
```

Failures add `error.code`, `error.message`, and optional bounded
`error.details`. Stable error codes use upper snake case. Responses must redact
passwords, serialized credentials, tokens, complete environment blocks, and
machine paths that are not necessary to act on the result.

## State and ownership

Store mutable plugin state below
`%LOCALAPPDATA%\Codex\hyperv-clean-room\v1`. Store DPAPI credential profiles
separately below `%APPDATA%\Codex\hyperv-clean-room\credentials`; never copy
that directory into plugin state or evidence. A credential profile is a bundle
with two explicit roles: a guest administrator used only to open and supervise
PowerShell Direct sessions, and a standard test user used to execute the
installer and application. Never treat the administrator session itself as
ordinary-user lifecycle evidence.

A managed VM must have both:

1. a Hyper-V Notes marker `hyperv-clean-room/v1:<ownership-id>`; and
2. a matching state record containing the VM ID, name, normalized VM root,
   VHDX path, creation operation ID, and ownership ID.

Treat disagreement, missing markers, renamed resources, or a VM ID mismatch as
`OWNERSHIP_UNVERIFIED`. Read-only inspection may continue, but all mutations
must stop.

Plans live for 15 minutes. A VM-creation plan records normalized ISO, VM, and
VHDX paths; ISO identity; selected switch identity; target-volume identity,
`availableBytes`, and `requiredBytes`; relevant resource absence; host
fingerprint; creation time; expiry; and a random plan ID. A checkpoint plan
records the VM and ownership identity, VM and checkpoint-inventory
fingerprints, intended checkpoint name, and operation-specific preconditions.

For an existing, unconsumed plan, the first apply call whose input is
well-formed for that apply tool atomically consumes the plan before checking a
confirmation token, checkpoint name, expiry, identity, fingerprint, or other
drift. A wrong value or detected drift therefore still consumes the plan;
retrying requires a new plan. Malformed tool input and an unknown plan ID do
not identify a consumable plan. Apply then rechecks every recorded
precondition. For VM target-volume drift, the volume identity must still match
and current `availableBytes` must be at least the recorded `requiredBytes`;
current free space need not equal the earlier `availableBytes` snapshot.

Do not automatically remove partial resources after a failed mutation. Return
their exact managed identity and a recovery warning, while leaving destructive
cleanup outside the public tool surface.

## Tool contract

Schema v1 exposes exactly the 16 tools in this section. The companion skill is
not part of tool discovery, and no additional direct, shell, or deletion tool
is public.

### Read-only tools

`inspect_host`

- Inputs: optional `vmRoot`, `minimumFreeSpaceGb`, and `vmName`.
- Report Windows edition/build/architecture, Hyper-V command availability,
  hypervisor presence, elevation, CPU, memory, target volume space, virtual
  switches, and relevant name/path conflicts.
- Do not enable Windows features or enumerate secrets.

`list_vms`

- Input: `managedOnly`, default `true`.
- Return managed VM summaries by default. When explicitly false, return only
  names, IDs, state, generation, and ownership status for other VMs.

`inspect_vm`

- Input: `vmName`.
- Report generation, firmware security, vTPM, CPU, memory, disk, switch, state,
  checkpoints, and ownership verification without changing the VM.

`validate_test_profile`

- Input: `profilePath`.
- Validate schema plus semantic constraints: local file, no reparse escape, no
  command/script fields, allowed step types, bounded timeouts, application
  references, safe guest-relative paths, and unique IDs.

`validate_evidence`

- Input: `evidencePath`.
- Validate schema, operation identity, artifact hash shape, result status,
  automatic/manual separation, and overall-status derivation. Recompute the
  overall status instead of trusting the serialized value, require matching
  source and guest artifact SHA-256 values, and reject a passed result whose VM
  ownership or ordinary-user token invariants are false.
- Validate `cleanupTriggered` against immutable operation trigger state. Bind
  `cleanupResults` one-to-one and in order to the operation, profile,
  cleanup-step ID, and cleanup-step type. When the flag is false, every result
  must be `notPerformed`. Exclude cleanup state and results from overall-status
  derivation.

### Guarded VM mutation tools

`plan_vm_create`

- Required inputs: `name`, `isoPath`, `vmRoot`, `switchName`.
- Optional inputs: `processorCount`, `startupMemoryGb`, `maximumMemoryGb`, and
  `diskSizeGb`.
- Defaults: Generation 2, 4 processors, 8 GiB startup memory, 12 GiB maximum
  dynamic memory, 100 GiB dynamic VHDX, Secure Boot, and vTPM.
- Return a plan conforming to `vm-plan.schema.json`; make no mutation.

`apply_vm_create`

- Input: `planId` only.
- Atomically consume an existing plan on the first well-formed apply call,
  revalidate the full plan including the current target-volume identity and
  capacity rule, then create exactly the resources described by it.
- Mark ownership only after the VM identity is known. Report partial state
  without deleting it if a later step fails.

`plan_checkpoint_create`

- Inputs: `vmName` and `checkpointName`.
- Require verified ownership and a unique checkpoint name. Return a
  `checkpointCreate` plan conforming to `checkpoint-plan.schema.json`, bound to
  VM ID, ownership ID, VM fingerprint, checkpoint-inventory fingerprint, and
  checkpoint-name absence. Make no mutation.

`apply_checkpoint_create`

- Input: `planId` only.
- Atomically consume an existing creation plan before validating name or drift,
  then create exactly the named checkpoint only if every check succeeds.
  Record checkpoint ID, parent, VM configuration fingerprint, and creation
  time.

`plan_checkpoint_restore`

- Inputs: `vmName` and `checkpointName`.
- Require verified ownership. Return a `checkpointRestore` plan conforming to
  `checkpoint-plan.schema.json`, report the current state that will be
  discarded, and return a single-use random confirmation token bound to the
  plan. Plaintext may appear exactly once, only in this tool's successful plan
  response. Persist only its hash in server state and redact it from errors,
  diagnostics, logs, and evidence.

`apply_checkpoint_restore`

- Inputs: `planId`, `checkpointName`, and `confirmationToken`.
- For an existing plan and well-formed input, atomically consume the plan before
  checking the checkpoint name, token, or drift. Wrong values consume it.
  Restore only when the values are exact and the VM, ownership,
  checkpoint-inventory, current-state, and target-checkpoint fingerprints are
  unchanged.

### Guest and test tools

`inspect_guest`

- Inputs: `vmName` and `credentialProfile`.
- Use the profile's orchestration administrator for PowerShell Direct, then
  inspect the standard test user's identity and environment. Report
  OS/build/architecture, test-account identity and administrator membership,
  profile path, DPI, installed products, WebView2, forbidden developer
  commands, user/system PATH summaries, and configured product traces.

`stage_artifact`

- Inputs: `vmName`, `credentialProfile`, `sourcePath`, and
  `guestDestination`.
- Require a local regular file and a safe guest path under the test staging
  root. Copy through a PowerShell Direct session and compare source/destination
  SHA-256. This is a low-level preflight, troubleshooting, or explicitly manual
  workflow tool. Its result is scoped to its own operation and is never
  implicitly reused by a later `run_test_profile` operation.

`run_test_profile`

- Inputs: `vmName`, `credentialProfile`, `profilePath`, and `artifactPath`.
- `artifactPath` is a host-local ordinary file. Reject directories, reparse
  escapes, devices, URLs, and non-local or non-regular inputs. The runner owns
  the operation's staging destination and computes both host-source and
  guest-copy SHA-256 values.
- Allocate a server-controlled evidence staging root unique to the accepted
  test operation. Automatic output and later manual references remain inside
  that root until `collect_evidence` exports a verified copy.
- Validate the complete profile before entering execution. Run only the
  declarative step types allowed by the profile schema. Resolve applications
  through profile declarations; do not execute a caller-supplied command or
  script. Launch installer/application steps with the profile's standard
  test-user credential and record token owner, administrator membership, and
  integrity evidence. An elevated or administrator test token fails a
  current-user lifecycle assertion.
- Apply the cleanup trigger and execution contract in the declarative-profile
  section. Preserve VM state and collect failure evidence; cleanup is not VM
  rollback.

`collect_evidence`

- Inputs: `operationId` and `outputDirectory`.
- Require an existing local directory outside Windows, Program Files, plugin
  installation, credentials, and Hyper-V storage roots. Write UTF-8 JSON and a
  SHA-256 inventory. Export from the operation's server-controlled evidence
  staging root; never treat a caller path as the live staging root. Never
  include a credential or full environment dump.

`record_manual_attestation`

- Inputs: `operationId`, `assertionId`, `status`, `method`, `summary`, and
  optional `evidenceReferences`.
- Allow status `passed`, `failed`, or `unsupported`; leaving an assertion
  unrecorded preserves `notPerformed`.
- Allow method `visualInspection`, `interactiveExercise`, `externalTool`, or
  `declaredUnsupported`. Require `declaredUnsupported` when status is
  `unsupported`, and reject it for passed/failed observations.
- Bind the assertion to the immutable operation/profile/assertion identity.
  Record the current Windows identity and server timestamp; callers cannot
  override either field.
- Accept only evidence-directory-relative references with a SHA-256. Reject
  absolute paths, traversal, reparse escapes, missing files, and hash mismatch.
- Resolve every reference inside the operation's server-controlled evidence
  staging root. Write the attestation into operation state for
  `collect_evidence` to merge and export.
  Never modify an automatic assertion and never let `run_test_profile` produce
  a passed manual assertion.

Credential setup is intentionally not an MCP tool. The future interactive
`Initialize-GuestCredential.ps1` accepts exactly `-ProfileName` and `-VmName`;
it accepts no credential, password, or output-path parameter. It calls
`Get-Credential` separately for the orchestration administrator and standard
test user, validates both through PowerShell Direct, proves that their SIDs
differ, proves the orchestration identity is an administrator, and proves the
test identity is a non-administrator before saving either bundle with
same-user/same-machine DPAPI `Export-Clixml`. Gate 1.1 freezes this contract but
does not create the runtime script. MCP arguments carry only the validated
profile name. Do not log either username unless it is required in final guest
identity evidence.

PowerShell Direct does not by itself prove an interactive desktop result.
Silent install/uninstall and process/module assertions may be automated through
the supervised standard-user process. GUI-visible first-launch, DPI, and other
interactive outcomes remain manual assertions until a separately validated
interactive harness exists.

## Declarative test profiles

Profiles conform to `test-profile.schema.json`. They declare the Windows x64
platform, baseline type, artifact metadata, named applications, automatic
steps, bounded cleanup steps, and manual assertions. `cleanupSteps` is required
even when empty; use `[]` when no safe cleanup is declared.

`artifact.fileNamePattern` is a case-insensitive filename glob, not a regular
expression or path. It may contain wildcard characters but no directory
separator. The caller supplies the concrete local artifact path and the runtime
records both the source and guest SHA-256 values. The ordinary `steps` array
must contain exactly one `stageArtifact`, and it must be the first step. The
runner performs that stage for the current test operation; a prior
`stage_artifact` operation never satisfies it.

Allowed ordinary step types are:

- `stageArtifact`
- `installPackage`
- `launchApplication`
- `stopApplication`
- `uninstallPackage`
- `assertFile`
- `assertRegistry`
- `assertProcess`
- `assertModule`
- `assertShortcut`
- `assertPort`
- `writeSentinel`
- `assertSentinel`
- `wait`

Allowed cleanup step types are exactly:

- `stopApplication`
- `wait`
- `assertFile`
- `assertRegistry`
- `assertProcess`
- `assertModule`
- `assertShortcut`
- `assertPort`
- `assertSentinel`

`cleanupSteps` has at most 16 entries. Each cleanup timeout is from 1 through
120 seconds and their declared sum is at most 300 seconds. A cleanup step is a
separate closed schema object. It cannot stage or install an artifact, launch
or uninstall an application, write a sentinel, run a command, script, shell,
URL, or arbitrary executable, delete anything, restore a checkpoint, or roll
back a VM.

Every application reference must resolve to one declaration. Application IDs
are unique within `applications`; IDs across `steps`, `cleanupSteps`, and
`manualAssertions` are globally unique. Filesystem fields are relative paths
within their schema-defined guest root. `executableRelativePath` and `path`
resolve below the standard test user's profile, `moduleRelativePath` resolves
below the declared application's executable directory, and `registryPath` is
relative to HKCU. Drive-qualified, rooted, UNC, traversal, alternate-stream,
environment-expanding, and reparse-escaping paths are invalid.

Steps reference a declared application or schema-defined assertion fields.
They do not contain `command`, `script`, `shell`, arbitrary executable, inline
PowerShell, or download URL fields. Ordinary step timeouts are from 1 through
900 seconds. Omitted `required` means `true`. `required: false` is valid only
for assertion steps; mutations and actions, including `wait`, cannot be
optional. A failed ordinary optional assertion is recorded and execution
continues. It does not affect `overallStatus`.

Cleanup is armed only after `run_test_profile` has completed validation and
entered the execution phase. Immutable operation state records
`cleanupTriggered: true` only when that phase encounters a failed
required assertion, failed action or mutation, step timeout, or guest-adapter
failure. It does not trigger for pre-execution validation failures or an
ordinary optional-assertion failure. Once triggered, cleanup steps run in
declaration order while time remains in the 300-second total budget.

`stopApplication` may target only a PID recorded as launched by the current
test operation. Immediately before stopping it, the runner must revalidate the
recorded process identity; a missing or changed identity fails that cleanup
step without stopping the process. Cleanup failure never recursively starts
cleanup and does not prevent later declared cleanup steps from running while
budget remains. Cleanup never uninstalls a package, deletes a VM, VHDX,
checkpoint, guest file, registry key, or host path, restores a checkpoint, or
rolls back the VM.

Baseline type is either `stock-clean` or `webview2-absent-derived`. Evidence
must preserve that exact value. The latter can never satisfy a requirement for
an untouched stock Windows image.

## Evidence semantics

Evidence conforms to `evidence.schema.json` and keeps automatic assertions and
manual assertions in different arrays. It also has required `cleanupTriggered`
and `cleanupResults` fields. Each assertion or cleanup result has one of:

- `passed`
- `failed`
- `notPerformed`
- `unsupported`

Automatic assertions carry machine-collected evidence. A manual assertion with
status `notPerformed` has `attestation: null`. A manual assertion with status
`passed`, `failed`, or `unsupported` has an attestation containing the bound
operation/profile/assertion identity, observer, observed timestamp, method,
summary, and verified evidence references.

`cleanupTriggered` is copied from immutable operation trigger state and cannot
be supplied or changed by a caller. `cleanupResults` contains exactly one entry
for each declared cleanup step in the same order. Each entry binds
`operationId`, `profileId`, `cleanupStepId`, and `cleanupStepType` to the
immutable operation and profile cleanup identity, then records `status`,
`summary`, and bounded machine evidence. When `cleanupTriggered` is false,
every declared entry is `notPerformed`; an empty cleanup declaration produces
`[]`. Forged trigger state and missing, reordered, duplicated, performed-while-
untriggered, or identity-mismatched results are invalid.

Overall status is `failed` if any required assertion failed, `incomplete` if a
required assertion is not performed or unsupported, and `passed` only when all
required assertions passed. Optional assertion results, `cleanupTriggered`, and
all cleanup results are excluded from this derivation: successful cleanup
cannot upgrade a failed or incomplete operation, and failed cleanup cannot
downgrade otherwise-passed required assertions. `validate_evidence` recomputes
this value. A tool must
never infer that a GUI-visible outcome passed from process exit alone. Passed
ordinary-user lifecycle evidence must identify verified VM ownership, a
non-administrator, non-elevated test identity with medium integrity, and
matching source and guest artifact SHA-256 values. Failed or incomplete
evidence may preserve elevated or administrator token facts so the failure
remains auditable.

## Versioning

Gate 1.1 is a deliberate pre-first-release correction to the v1 baseline.
Although it adds required cleanup fields and evidence semantics, the plugin
remains version `0.1.0` and every public schema remains `schemaVersion: 1`.
There is no earlier working runtime or released evidence producer to preserve.

After the first working release, plugin semver and JSON schema versions evolve
independently. Additive optional tool fields are minor-compatible. Tool
renames, required-field changes, or evidence semantic changes require a plugin
major version and a new schema major version. Readers reject unknown schema
major versions and may ignore new optional fields within schema v1.

## Gate 1.1 acceptance boundary

Gate 1.1 keeps exactly 16 MCP tools, exactly five public schemas, plugin version
`0.1.0`, and schema version 1. It proves only manifest shape, launch-path
resolution, skill validity, JSON parsing, Draft 2020-12 fixtures, PowerShell
syntax, documentation integrity, and the frozen contract. The MCP entry point
still fails closed. This gate does not prove an MCP handshake, Hyper-V behavior,
guest access, plugin installation, marketplace or cache runtime discovery, VM
mutation, package execution, evidence collection, or clean-machine testing.

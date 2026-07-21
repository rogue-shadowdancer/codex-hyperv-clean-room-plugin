# Hyper-V Clean Room specification

Status: Gate 6/H1 freezes the additive plugin `0.2.0`, schema-v2 automation
contract. The executable plugin is still `0.1.1`: its PowerShell 5.1 runtime,
16-tool registry, five schema-v1 files, installer, and production adapter are
unchanged. H1 adds only machine-readable target contracts, deterministic
fixtures, static tests, and documentation. Implementation belongs to Gate
7/H2. No real host, VM, checkpoint, credential, guest, package, portable,
WebDriver, network, or UI operation was executed for this contract freeze.

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

## Plugin 0.2.0 and schema-v2 target contract

The normative H1 artifacts are under `contracts/v2`. They remain outside the
installable `hyperv-clean-room` payload until H2 implements them. The seven
Draft 2020-12 schema IDs are the canonical repository URLs for:

- `operation-envelope.schema.json`;
- `vm-power-plan.schema.json`;
- `vm-network-plan.schema.json`;
- `portable-manifest.schema.json`;
- `webdriver-manifest.schema.json`;
- `test-profile.schema.json`; and
- `evidence.schema.json`.

`contracts/v2/tool-catalog.json` freezes exactly 20 target tools. The first 16
are byte-for-byte input-schema and annotation snapshots of the shipped v1
registry. The four additions are:

| Tool | Closed input | Contract |
| --- | --- | --- |
| `plan_vm_power` | `vmName`, `action` | `action` is only `start` or `gracefulShutdown`. Planning is non-mutating. |
| `apply_vm_power` | `planId` | Consumes and revalidates one power plan; the caller cannot respecify the action. |
| `plan_vm_network` | `vmName`, `target` | `target` is only the recorded `baseline` or `disconnected` state of the verified primary managed NIC. |
| `apply_vm_network` | `planId` | Consumes and revalidates one change or recovery plan; the caller cannot select an adapter, switch, or target. |

All four return the schema-v2 operation envelope. The machine-readable
`resultContract` beside each catalog entry is normative. Power planning returns
exactly `{ plan }` containing `vm-power-plan`; network planning returns exactly
`{ changePlan, recoveryPlan }`, where recovery is non-null for a disconnect
pair. A successful power apply returns the plan/VM identity, action, previous
and current state, and `effectState: confirmed`. A successful network apply
returns the plan pair/role, VM and adapter identity, target, previous/current
attachment, `effectState: confirmed`, and whether recovery is now required.
Planning success has `changed: false`; apply success has `changed: true`.

The frozen stable failure codes are the applicable subset of the existing
`INVALID_ARGUMENT`, `HYPERV_UNAVAILABLE`, `ELEVATION_REQUIRED`, `VM_NOT_FOUND`,
`VM_STATE_UNSUPPORTED`, `OWNERSHIP_UNVERIFIED`, `STATE_BUSY`,
`PLAN_NOT_FOUND`, `PLAN_ALREADY_CONSUMED`, `PLAN_INVALID`,
`PLAN_KIND_MISMATCH`, `PLAN_EXPIRED`, and `PLAN_DRIFT`, plus the new typed
`PRIMARY_ADAPTER_UNVERIFIED`, `BASELINE_UNAVAILABLE`,
`POWER_TRANSITION_FAILED`, `NETWORK_TRANSITION_FAILED`, and
`NETWORK_RECOVERY_REQUIRED`, exactly as listed per tool in the catalog. Before
the mutation boundary, failure has
`changed: false`. After entry, a confirmed or non-excludable effect has
`changed: true` and bounded `error.details.effectState` of `confirmed` or
`indeterminate`; a disconnect failure that may have changed attachment also
returns the already-created recovery plan ID and
`NETWORK_RECOVERY_REQUIRED`.

Every input object has `additionalProperties: false`. No v2 tool accepts a
password, credential, command, script, shell, URL, selector, JavaScript,
download location, raw uninstall string, caller-selected argument list, host
path deletion, arbitrary adapter, or arbitrary switch.

### Plan consumption, expiry, drift, and recovery

The v1 single-consumption rule remains authoritative: the first well-formed
apply request that resolves a stored plan atomically consumes it before any
expiry, drift, or requested-value check. Power and network apply inputs contain
only the UUID `planId`; that unpredictable, operation-scoped ID is the sole
capability token and is never reusable. A malformed input or unknown plan ID
does not identify a consumable plan. Apply must reject expired or consumed
plans and any change to host fingerprint, VM ID/name, ownership ID or record
hash, VM fingerprint, recorded state, adapter identity/fingerprint, baseline
switch identity, or operation-specific precondition. Drift produces no
mutation and requires a fresh plan.

For network plans, `vmFingerprint` binds all relevant VM configuration except
the verified primary NIC's attachment, and `adapter.fingerprint` binds the NIC
identity/configuration except its attachment. `currentAttachment` and
`targetAttachment` bind that one expected transition separately. This lets the
pre-created recovery plan accept only the disconnect made by its paired change
plan without treating that planned attachment difference as unrelated drift;
every other VM, NIC, ownership, host, or baseline change still rejects apply.

Power plans live exactly 15 minutes. `start` binds `Off -> Running`;
`gracefulShutdown` binds `Running -> Off`. Forced power-off, reset, save,
pause, resume, stop-with-force, and automatic escalation after shutdown timeout
are outside the contract.

Network change plans live exactly 15 minutes. A disconnect plan is published
only as an atomic pair with a pre-created recovery plan that restores the
recorded baseline attachment; the two plans cross-reference each other. The
recovery plan lives exactly 24 hours so it remains usable after the ordinary
change window. Apply affects only the verified primary NIC of the managed VM.
Disconnect starts only from the exact baseline attachment; baseline change or
recovery starts only from the disconnected attachment, so successful apply is
never a no-op and has `changed: true`.
If change outcome is confirmed or indeterminate, recovery becomes required;
failed, expired, drifted, or unverified recovery makes machine evidence fail.
The plugin never adopts an unmanaged VM or invents a new switch binding.

### Portable ZIP lifecycle and fixed WebDriver

A schema-v2 portable candidate is an unsigned Windows x64 ZIP with a clean
40-hex source commit, a UUID build run, a root
`portable-manifest.json`, one `--portable` argument, a fixed `data` directory,
and complete payload-file identities. The manifest binds the entry point, product and
component versions, WebView2 and MaaFramework inventory SHA-256 values, each
payload path, size, and SHA-256. The root manifest is bound separately by the
profile and ZIP hashes and is excluded from its own `files` array to avoid an
impossible recursive self-hash. The immutable archive limits are: at most
4,096 entries, 8 GiB expanded bytes, and 200:1 compression ratio.

Before extraction, the implementation must verify the host ZIP SHA-256 and
manifest identity. It must normalize every path as a relative Windows path,
reject absolute or drive paths, `..`, alternate data streams, percent-encoded
ambiguity, links, reparse points, trailing dot/space segments, duplicate or
case-insensitively colliding names, non-NFC names, Windows reserved device
names, control/invalid filename characters, undeclared entries, missing
entries, size drift, and hash drift. Extraction must use a new operation-owned staging
directory, enforce the limits while streaming, re-open and hash every regular
file, and atomically publish a new deployment slot only after the complete
inventory passes. Existing portable data is copied forward only from the
recorded `data` directory after its binding is revalidated. That copy accepts
only regular files/directories, rejects reparse points, links, ADS, unsafe or
colliding relative paths, and enforces the same 4,096-entry/8-GiB bounds. It
hashes a canonical source inventory before copy and a destination inventory
after copy; a prior inventory must equal the deployed inventory byte-for-byte.
Failed deployment must not replace the active slot or delete prior data. No H1
contract creates a general unzip, copy, delete, or command surface.

The WebDriver manifest fixes Microsoft EdgeDriver x64 to the exact fixed
WebView2 four-part version. Its Microsoft HTTPS acquisition policy, archive
name `edgedriver_win64.zip`, archive size/hash, executable path
`msedgedriver.exe`, executable size/hash, x64 PE identity, Microsoft
Authenticode publisher, and complete file inventory are all verified before
use. A mismatch fails closed. The driver listens only on `127.0.0.1` at a
server-allocated ephemeral port. Navigation, arbitrary browser arguments,
arbitrary selectors, and script execution are forbidden.

### Closed UI DSL

Schema-v2 portable profiles declare fixtures by ID, safe relative file name,
size, and SHA-256; fixture bytes are staged and dual-hashed by the server.

Each `fixture.sourceRelativePath` resolves beneath the already-validated local
directory containing the profile. The server canonicalizes every parent and
the final file, rejects escape, links/reparse points and non-regular files,
then checks the declared size/SHA-256 before creating an operation-owned guest
copy and checking its hash again. The MCP caller cannot supply a separate
fixture root or guest destination. The existing `artifactPath` input remains
the sole candidate-ZIP source, and the server—not the profile or caller—derives
the fixed Microsoft driver acquisition endpoint.

The UI step allowlist is:

- `acquireWebDriver`, `startUiSession`, and `stopUiSession`;
- `uiClick`, `uiSetText`, `uiPressKey`, and `uiSelectOption`;
- `uiUploadFixture` using a declared fixture ID;
- `assertUiElement` with only `visible`, `hidden`, `enabled`, `disabled`,
  `checked`, `unchecked`, `textEquals`, `textContains`, or `valueEquals`; and
- `captureUiScreenshot` with a bounded evidence name.

Key presses are restricted to `Enter`, `Escape`, `Tab`, and the four arrow
keys. There is no CSS/XPath selector, URL/navigation, JavaScript, arbitrary
WebDriver endpoint, arbitrary file path, caller argument, or shell escape. The
`text` and option literals are non-secret test data; the profile has no
credential/secret/reference field and must be rejected if the requested flow
would enter a password, token, or other credential. The
worker maps each closed step to fixed code and records the step ID, test ID,
bounded observation, and screenshot identity without exposing raw protocol
control. Each UI sequence acquires, starts, and stops exactly one owned session
in that order, and every interaction occurs between start and stop. Cleanup
uses type-specific targets, rejects irrelevant fields, and never makes a stop,
session, screenshot, or wait action optional.

### Evidence v2 and compatibility

Evidence v2 binds the profile hash; candidate source commit plus portable ZIP,
profile, fixture-set, and WebDriver-manifest hashes; plugin version/source and
adapter mode; baseline; managed VM/checkpoint/ownership/fingerprint; standard
user token facts; dual artifact hashes; portable deployment identity; fixed
driver version and loopback policy; prior/deployed data inventory hashes;
bounded UI trace; power and network plan
and operation identities; recovery; automatic/manual assertions; cleanup; and
warnings. The canonical status derivation is:

- `machineStatus` is `failed` if any required automatic assertion,
  infrastructure binding, artifact hash, deployment/data-preservation fact,
  UI session fact, or required network recovery is not passed; otherwise it is
  `passed`;
- `overallStatus` is `failed` when `machineStatus` is failed, `incomplete` when
  machine facts pass but any required manual assertion is `notPerformed` or
  `unsupported`, and `passed` only when both machine and required manual facts
  pass; and
- cleanup failure remains separately visible and cannot manufacture a passed
  machine or overall result.

Readers dispatch on the exact integer `schemaVersion`; they never try v2 then
fall back to v1. Unknown versions fail with `UNSUPPORTED_SCHEMA_VERSION`.
All v1 tool names, inputs, annotations, envelopes, profiles, evidence, and
semantics remain available. A valid v1 profile is read as v1, or may be copied
through an explicit deterministic, lossless migration that never rewrites the
source. A v1 NSIS/MSI profile with an unambiguous package kind maps to
`legacyPackageLifecycle`; ambiguous input requires authoring and fails with the
exact `MIGRATION_AMBIGUOUS_PACKAGE_KIND` error. V1 evidence always remains v1 because v2
candidate, driver, fixture, UI, deployment, and recovery provenance cannot be
safely synthesized.

Plugin `0.2.0` continues using the existing v1 state root and
`hyperv-clean-room/v1:<ownership-id>` marker so already-managed resources do
not require adoption or marker rewrite. New plan kinds and schema-v2 operation
records carry explicit kind/version fields under the existing atomic
lock/record rules. H2 must not rewrite valid v1 ownership, plan, operation,
profile, or evidence files in place; corrupt or unknown records fail closed.

## Runtime and transport

- The production runtime supports Windows PowerShell 5.1 and the Hyper-V
  PowerShell module. It must not depend on Python. Python and the Draft 2020-12
  `jsonschema` validator are development and CI dependencies only.
- Use JSON-RPC MCP over stdio. Read and write one UTF-8 JSON message per line.
- Reserve stdout for protocol messages. Suppress warning, verbose, debug,
  information, and progress streams at the server boundary through both
  preferences and explicit per-request stream redirection. Send only bounded
  diagnostics to stderr.
- Support exactly these MCP protocol versions: `2024-11-05`, `2025-03-26`,
  `2025-06-18`, and `2025-11-25`. Negotiate a mutually supported value and
  never announce a version newer than the request or outside this set.
- Require omitted or object-shaped method `params` and reject scalar, null, or
  array forms. Initialize params contain only required, typed
  `protocolVersion`, `capabilities`, and `clientInfo` fields; `clientInfo`
  requires non-empty string `name` and `version`. `ping`, `tools/list`, and
  `notifications/initialized` accept only omitted or empty params. Tool-call
  params contain only `name` and optional object-shaped `arguments`.
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
Target-volume identity is a non-empty stable `Get-Volume.UniqueId`; a drive
letter is never an identity fallback. Immediately before VM mutation, reopen
the recorded VM root as the same normalized local non-reparse directory and
recompute and compare the derived VM and VHDX paths. The production adapter
repeats those path and volume bindings at its mutation boundary.

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
cleanup outside the public tool surface. A failure before the host mutation
boundary reports `changed: false`. After entry, a confirmed effect or one that
cannot safely be excluded reports `changed: true`, with bounded partial
identity and `confirmed` or `indeterminate` effect state in error details.

## Tool contract

Schema v1 exposes exactly the 16 tools in this section. The companion skill is
not part of tool discovery, and no additional direct, shell, or deletion tool
is public.

### Read-only tools

#### `inspect_host`

- Inputs: optional `vmRoot`, `minimumFreeSpaceGb`, and `vmName`.
- Report Windows edition/build/architecture, Hyper-V command availability,
  hypervisor presence, elevation, CPU, memory, target volume space, virtual
  switches, and relevant name/path conflicts.
- Do not enable Windows features or enumerate secrets.

#### `list_vms`

- Input: `managedOnly`, default `true`.
- Return managed VM summaries by default. When explicitly false, return only
  names, IDs, state, generation, and ownership status for other VMs.

#### `inspect_vm`

- Input: `vmName`.
- Report generation, firmware security, vTPM, CPU, memory, disk, switch, state,
  checkpoints, and ownership verification without changing the VM.

#### `validate_test_profile`

- Input: `profilePath`.
- Validate schema plus semantic constraints: local file, no reparse escape, no
  command/script fields, allowed step types, bounded timeouts, application
  references, safe guest-relative paths, and unique IDs.

#### `validate_evidence`

- Input: `evidencePath`.
- Validate schema, operation identity, artifact hash shape, result status,
  automatic/manual separation, and overall-status derivation. Recompute the
  overall status instead of trusting the serialized value, require matching
  source and guest artifact SHA-256 values for passed evidence, and reject a
  passed result whose VM
  ownership or ordinary-user token invariants are false.
- Validate `cleanupTriggered` against immutable operation trigger state. Bind
  `cleanupResults` one-to-one and in order to the operation, profile,
  cleanup-step ID, and cleanup-step type. When the flag is false, every result
  must be `notPerformed`. Exclude cleanup state and results from overall-status
  derivation.

### Guarded VM mutation tools

#### `plan_vm_create`

- Required inputs: `name`, `isoPath`, `vmRoot`, `switchName`.
- Optional inputs: `processorCount`, `startupMemoryGb`, `maximumMemoryGb`, and
  `diskSizeGb`.
- Defaults: Generation 2, 4 processors, 8 GiB startup memory, 12 GiB maximum
  dynamic memory, 100 GiB dynamic VHDX, Secure Boot, and vTPM.
- Return a plan conforming to `vm-plan.schema.json`; make no mutation.

#### `apply_vm_create`

- Input: `planId` only.
- Atomically consume an existing plan on the first well-formed apply call,
  revalidate the full plan including the current target-volume identity and
  capacity rule, then create exactly the resources described by it.
- Mark ownership only after the VM identity is known. Report partial state
  without deleting it if a later step fails.

#### `plan_checkpoint_create`

- Inputs: `vmName` and `checkpointName`.
- Require verified ownership and a unique checkpoint name. Return a
  `checkpointCreate` plan conforming to `checkpoint-plan.schema.json`, bound to
  VM ID, ownership ID, VM fingerprint, checkpoint-inventory fingerprint, and
  checkpoint-name absence. Make no mutation.

#### `apply_checkpoint_create`

- Input: `planId` only.
- Atomically consume an existing creation plan before validating name or drift,
  then create exactly the named checkpoint only if every check succeeds.
  Record checkpoint ID, parent, VM configuration fingerprint, and creation
  time.

#### `plan_checkpoint_restore`

- Inputs: `vmName` and `checkpointName`.
- Require verified ownership and require the managed VM to be `Off`. Return a
  `checkpointRestore` plan conforming to
  `checkpoint-plan.schema.json`, report the current state that will be
  discarded, and return a single-use random confirmation token bound to the
  plan. Plaintext may appear exactly once, only in this tool's successful plan
  response. Persist only its hash in server state and redact it from errors,
  diagnostics, logs, and evidence.

#### `apply_checkpoint_restore`

- Inputs: `planId`, `checkpointName`, and `confirmationToken`.
- For an existing plan and well-formed input, atomically consume the plan before
  checking the checkpoint name, token, or drift. Wrong values consume it.
  Restore only when the values are exact, the VM remains `Off`, and the VM,
  ownership, checkpoint-inventory, current-state including offline VHDX
  identity, and target-checkpoint ID/name/fingerprint are unchanged. The
  production adapter must repeat these checks against a fresh live snapshot at
  the mutation boundary and restore only the exact rebound snapshot object.
  Planning and apply must fail closed when attached-disk enumeration, ordinary
  VHDX file metadata, or Hyper-V VHD identifier and size facts are unavailable.

### Guest and test tools

#### `inspect_guest`

- Inputs: `vmName` and `credentialProfile`.
- Use the profile's orchestration administrator for PowerShell Direct, then
  inspect the standard test user's identity and environment. Report
  OS/build/architecture, test-account identity and administrator membership,
  profile path, DPI, installed products, WebView2, forbidden developer
  commands, user/system PATH summaries, and configured product traces.

#### `stage_artifact`

- Inputs: `vmName`, `credentialProfile`, `sourcePath`, and
  `guestDestination`.
- Require a local regular file and a safe guest path under the test staging
  root. Copy through a PowerShell Direct session and compare source/destination
  SHA-256. This is a low-level preflight, troubleshooting, or explicitly manual
  workflow tool. Its result is scoped to its own operation and is never
  implicitly reused by a later `run_test_profile` operation.

#### `run_test_profile`

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

#### `collect_evidence`

- Inputs: `operationId` and `outputDirectory`.
- Require an existing local directory outside Windows, Program Files, plugin
  installation, credentials, and Hyper-V storage roots. Write UTF-8 JSON and a
  SHA-256 inventory. Export from the operation's server-controlled evidence
  staging root; never treat a caller path as the live staging root. Never
  include a credential or full environment dump.
- Hold the operation lock while re-resolving and rehashing every manual
  reference. Reject mutable control-document self-reference. For every exported
  file, require the pre-copy source, post-copy source, destination, claimed, and
  inventory hashes to agree. Reject a staged root `inventory.json`; parse and
  revalidate the exact copied `evidence.json` against immutable operation state
  before publishing the generated inventory. Reopen the final serialized
  `inventory.json`, require its exact operation/file membership, and recheck
  every final file's size and SHA-256 from those parsed inventory claims before
  reporting success.

#### `record_manual_attestation`

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
  Reject `evidence.json`, `inventory.json`, and other mutable control documents
  as self-referential evidence.
  Never modify an automatic assertion and never let `run_test_profile` produce
  a passed manual assertion.

Credential setup is intentionally not an MCP tool. The interactive
`Initialize-GuestCredential.ps1` accepts exactly `-ProfileName` and `-VmName`;
it accepts no credential, password, or output-path parameter. It calls
`Get-Credential` separately for the orchestration administrator and standard
test user, validates both through PowerShell Direct, proves that their SIDs
differ, proves the orchestration identity is an administrator, and proves the
test identity is a non-administrator before saving either bundle with
same-user/same-machine DPAPI `Export-Clixml`. Gate 2 implements this script and
tests its parameter and prompt boundary without collecting credentials. MCP
arguments carry only the validated profile name. Do not log either username
unless it is required in final guest identity evidence.

The initializer must require the administrator SID and high/system integrity,
require the distinct test SID to have no Administrators SID and exact medium
integrity, build both DPAPI files plus metadata in one private pending
directory, read-validate every component, and publish the profile by one
exact-destination same-volume `[IO.Directory]::Move`. It must then reopen the
final directory and verify its protected ACL, exact three-file membership,
sizes, credential objects, and metadata. It must never merge into or overwrite
an existing or concurrently created profile or expose a partial bundle under
the requested name.

For every production guest operation context, revalidate the live PowerShell
Direct administrator SID and role against profile metadata. For every worker
invocation, revalidate the test-user SID; lifecycle and cleanup modes also
require a non-administrator, non-elevated, exact-medium token.

The fixed worker receives administrator-created, create-new input bound to an
operation, invocation, mode, and SHA-256. It returns at most one MiB of JSON only
over redirected stdout; it accepts no result-file path. The supervisor accepts
the result only when all bindings and the process exit code agree. Guest
workspace directories must disable inheritance, apply an explicit ACL, and
read back administrator ownership, exactly one full-control grant for the live
administrator, `SYSTEM`, and local Administrators, and an operation-only
read/execute test-SID grant with no write capability. Every grant must use the
canonical container/object inheritance flags and no propagation flag. New
plugin ancestors must receive that protected descriptor atomically; existing
owners and ACLs are rebound to it. Create the worker suspended,
assign it to a Windows job object, then resume it and recompute the remaining
deadline.
Terminate on timeout, a late or unbound launch result, or unexpected descendant
survival; verified containment requires root exit and zero active job
processes. A declared `launchApplication` child may intentionally outlive that
worker invocation only after it is suspended and its PID, creation time, path,
job membership, and identity are rebound while it is the only active job
process before the deadline. It is then resumed. It remains stoppable only
through its recorded operation-scoped identity. Revalidation, termination, and
termination wait must use the same retained process handle.

PowerShell Direct session and copy calls use remoting open, operation, and
cancel timeouts plus one end-to-end deadline, checked between calls. They are
not processes in the worker job object; therefore the job-object hard-kill
guarantee does not cover a synchronous remoting call that outlives its bound.
Such a transport failure is indeterminate and must never be reported as a
verified clean stop.

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

When staging cannot produce a verified guest copy, schema v1 records
`guestSha256: null`; when a copy is readable but mismatched, it records the
observed hash. Either form requires a failed stage assertion and prevents a
passed overall result. Existing successful evidence remains unchanged and
requires equal source and guest hashes plus a passed stage assertion.

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
base version remains `0.1.0` and every public schema remains `schemaVersion: 1`.
Gate 4 permits one `+codex.<cachebuster>` build-metadata suffix for local Codex
reinstallation; this does not change the base plugin or schema version.
There is no earlier working runtime or released evidence producer to preserve.

Gate 5.1 advances plugin semver to `0.1.1` for the GPL-3.0-only public release
without changing any MCP tool name, input schema, common envelope, evidence
semantics, public schema, schema version, or supported protocol version. The
installed copy uses one `+codex.<UTC>` cachebuster; that metadata is not part of
the public tag version.

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
remained fail-closed at that gate. Gate 1.1 did not prove an MCP handshake,
Hyper-V behavior, guest access, plugin installation, marketplace or cache
runtime discovery, VM mutation, package execution, evidence collection, or
clean-machine testing.

## Gate 2 acceptance boundary

Gate 2 preserves exactly 16 MCP tools, exactly five public schemas, plugin
version `0.1.0`, and schema version 1. It implements line-delimited UTF-8
JSON-RPC stdio, bounded stderr diagnostics, protocol negotiation across the
four frozen versions, closed tool-input schemas, JSON-string text results, the
common envelope, and MCP `isError` projection.

The runtime implements a test-mode-only mock adapter and a default Hyper-V
adapter. Host, VM, checkpoint, guest inspection, artifact transfer, and
declarative execution have production implementations. Production guest work
uses the DPAPI credential bundle, opens PowerShell Direct only as the
orchestration administrator, transfers and hash-verifies a plugin-owned fixed
worker, then runs its closed dispatcher as the enrolled standard user. Guest
staging, worker I/O, sentinels, and stoppable process identities are bound to
the current operation. Package/install/uninstall/application behavior has
fixed mappings and exposes no command, script, shell, URL, download, raw
uninstall-string, or caller-selected argument surface.

Gate 2 does not execute any production guest method or Hyper-V mutation. Mock
mode requires both `HCR_ADAPTER_MODE=mock` and `HCR_TEST_MODE=1`; the installed
MCP configuration supplies neither.

Under Windows PowerShell 5.1, mock execution proves:

- all 16 tools are discoverable and callable through MCP;
- malformed apply input does not consume a plan, while the first well-formed
  apply atomically consumes it across concurrent server processes;
- expiry, host/ISO/switch/volume/VM/checkpoint drift and ownership disagreement
  stop mutation, and wrong restore confirmation values still consume a plan;
- restore-token plaintext is returned once and never persisted;
- profile and evidence validation, ordinary-user token checks, operation-bound
  automatic/manual/cleanup identities, cleanup triggering and continuation,
  attestation, and evidence export follow schema-v1 semantics; and
- the credential initializer accepts only the two frozen parameters, prompts
  twice, validates distinct roles, and uses two DPAPI `Export-Clixml` writes.

Parser and static source checks separately establish that production guest
source has a closed worker mode/step dispatcher,
  administrator-only supervision, standard-user token enforcement, worker and
  artifact dual-hash checks, operation-scoped staging/PIDs, constrained
  uninstall discovery, and bounded cleanup. Those checks do not execute or
  clean-machine-validate the production guest path.

Separately, the bounded production-adapter host smoke executes only
`inspect_host` and a `plan_vm_create` request that rejects a nonexistent ISO
before mutation. It reports zero real Hyper-V mutations and zero real guest
operations. This read-only host probe is not a mock-adapter guarantee and does
not validate any production guest behavior.

This gate does not prove plugin installation, marketplace/cache runtime
discovery, a real VM or checkpoint mutation, PowerShell Direct guest behavior,
package execution on Windows, credential persistence with live accounts, or
clean-machine evidence. Those claims require separate future authorization and
validation. At the Gate 2 boundary, the next project gate was Birdsgone
profile/acceptance documentation only and carried no authorization for
real-adapter or real-VM validation.

## Gate 4 acceptance boundary

Gate 4 preserves base plugin version `0.1.0`, schema version 1, exactly 16 MCP
tools, and five public schemas. It adds no public MCP tool and changes no
schema-v1 semantics.

The installation source must contain exactly the Git-tracked plugin payload as
ordinary non-reparse files. Installation targets
`%USERPROFILE%\plugins\hyperv-clean-room`, refuses an existing target without
the exact installer ownership marker, copies without deleting unexpected
files, verifies each size and SHA-256, and writes a relative-path/size/SHA-256
manifest bound to the source commit, version, and cachebuster.

The default personal marketplace is created or updated only through the
`plugin-creator` helper and contains exactly one canonical
`hyperv-clean-room` entry. Installation and cachebuster rehearsal both use
`codex plugin add hyperv-clean-room@personal`. The final checker requires
`installed`, `owned`, `matches`, and `marketplaceVisible` to be true and
requires source/installed hashes, version, commit, and cachebuster to match.

Installed-copy acceptance starts the MCP server only from the personal plugin
directory, discovers exactly 16 tools, executes read-only `inspect_host`, and
requires a nonexistent ISO to fail with `INVALID_ISO` before mutation. It
reports zero real guest operations and zero real Hyper-V mutations. Gate 4 does
not claim clean-machine validation, live credential persistence, PowerShell
Direct behavior, package execution, or any VM/checkpoint mutation.

## Gate 5.1 acceptance boundary

Gate 5.1 releases plugin base version `0.1.1` under `GPL-3.0-only` while
preserving exactly 16 MCP tools, five public Draft 2020-12 schemas,
`schemaVersion: 1`, and support for `2024-11-05`, `2025-03-26`, `2025-06-18`,
and `2025-11-25`.

Public-release validation covers the canonical GPL text and manifest SPDX
identifier, community files, strict UTF-8/no-BOM documentation, JSON/YAML and
schema parsing, PowerShell 5.1 parsing, the Gate 1/Gate 2/Gate 4 CI-safe
contracts, prospective-tree and retained-history privacy, commit
identity/message policy, and GitHub Actions log hygiene. The eight preserved
pre-release commits are accepted only through SHA-256 digests of their exact
raw commit objects. New commits use the repository's GitHub noreply identity.

The public installation acceptance remains bounded to the owned personal copy,
16-tool discovery, read-only `inspect_host`, and `INVALID_ISO` before mutation.
Clean-machine testing, credential enrollment, live PowerShell Direct guest
work, package execution, VM/checkpoint mutation, and manual GUI attestation all
remain `notPerformed`. Birdsgone remains a name-level consumer boundary only;
no Birdsgone file or evidence is part of this repository or release.

## Gate 5.2 acceptance boundary

Gate 5.2 keeps plugin and MCP server base version `0.1.1`, exactly 16 MCP
tools, five public Draft 2020-12 schemas, `schemaVersion: 1`, and the four
supported MCP protocol versions. It changes no runtime code, tool input or
output, schema-v1 semantic, production adapter, or mutation path.

The source manifest `homepage`, `repository`, and `interface.websiteURL` must
all equal
`https://github.com/rogue-shadowdancer/codex-hyperv-clean-room-plugin` exactly.
The current `master` personal-install build uses the single Gate 5.2
cachebuster `0.1.1+codex.20260715084043`; the immutable `v0.1.1` tag and GitHub
Release retain `0.1.1+codex.20260715064728`. Gate 5.2 creates no new tag or
GitHub Release.

Installed-copy acceptance remains limited to source/install hash and commit
agreement, 16-tool discovery, read-only `inspect_host`, and `INVALID_ISO`
before mutation. Clean-machine testing, credential enrollment, real guest or
package work, VM/checkpoint mutation, and manual GUI attestation remain
`notPerformed` and require a separately authorized Gate 6 task.

## Gate 6/H1 acceptance boundary

Gate 6 accepts only a frozen, internally consistent target contract. The
contract test must prove seven schema-v2 files with stable IDs, exactly 20
target tools, the exact 16-tool v1 snapshot, byte-identical five v1 schemas,
closed new inputs, fixed plan lifetimes and recovery pairing, portable path and
hash rejection, fixed-driver provenance, closed `data-testid` UI dispatch,
evidence status derivation, candidate/hash binding, and deterministic migration
fixtures. Documentation, repository formats, existing mock/runtime tests, and
the exact staged candidate must also pass review with zero actionable findings.

H1 does not change the executable plugin or claim implementation. Therefore
the runtime remains `0.1.1`, schema v1, and 16 tools; all real Hyper-V,
credential, guest, package, portable, WebDriver, network, UI, clean-room, and
manual-attestation operations remain `notPerformed`. Gate 7/H2 owns the first
implementation of this contract and must preserve these frozen compatibility
and fail-closed boundaries.

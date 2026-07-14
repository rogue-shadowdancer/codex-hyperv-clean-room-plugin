# Hyper-V Clean Room v1 specification

Status: frozen for implementation after Gate 1. The runtime is not implemented
in this gate.

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

- Support Windows PowerShell 5.1 and the Hyper-V PowerShell module.
- Use JSON-RPC MCP over stdio. Read and write one UTF-8 JSON message per line.
- Reserve stdout for protocol messages. Send bounded diagnostics to stderr.
- Negotiate an MCP protocol version supported by the client; never announce a
  version newer than the request.
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

Plans live for 15 minutes. A plan records normalized inputs, ISO SHA-256,
selected switch ID, target-volume identity and free space, relevant resource
absence, host fingerprint, creation time, expiry, and a random plan ID. Applying
a plan rechecks every recorded precondition. Plans are single-use; success or
the first apply attempt consumes them.

Do not automatically remove partial resources after a failed mutation. Return
their exact managed identity and a recovery warning, while leaving destructive
cleanup outside the public tool surface.

## Tool contract

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
  automatic/manual separation, and overall-status derivation.

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
- Revalidate the full plan, then create exactly the resources described by it.
- Mark ownership only after the VM identity is known. Report partial state
  without deleting it if a later step fails.

`create_checkpoint`

- Inputs: `vmName` and `checkpointName`.
- Require verified ownership and a unique checkpoint name. Record checkpoint
  ID, parent, VM configuration fingerprint, and creation time.

`plan_checkpoint_restore`

- Inputs: `vmName` and `checkpointName`.
- Require verified ownership. Report the current state that will be discarded
  and return a single-use random confirmation token bound to the plan.

`apply_checkpoint_restore`

- Inputs: `planId`, `checkpointName`, and `confirmationToken`.
- Require exact values and unchanged VM/checkpoint fingerprints. Consume the
  token on the first apply attempt.

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
  SHA-256.

`run_test_profile`

- Inputs: `vmName`, `credentialProfile`, `profilePath`, and `artifactPath`.
- Validate before execution. Run only the declarative step types allowed by the
  profile schema. Resolve applications through profile declarations; do not
  execute a caller-supplied command or script. Launch installer/application
  steps with the profile's standard test-user credential and record token
  owner, administrator membership, and integrity evidence. An elevated or
  administrator test token fails a current-user lifecycle assertion.
- Stop after a failed mutation, execute only the profile's bounded safe cleanup
  action, preserve the VM state, and collect failure evidence.

`collect_evidence`

- Inputs: `operationId` and `outputDirectory`.
- Require an existing local directory outside Windows, Program Files, plugin
  installation, credentials, and Hyper-V storage roots. Write UTF-8 JSON and a
  SHA-256 inventory. Never include a credential or full environment dump.

Credential setup is intentionally not an MCP tool. Run the interactive
`Initialize-GuestCredential.ps1`, prompt separately for the orchestration
administrator and standard test user, reject identical accounts or a test user
that is an administrator, and persist both with same-user/same-machine DPAPI
`Export-Clixml`. MCP arguments carry only the validated profile name. Do not
log either username unless it is required in the final guest identity evidence.

PowerShell Direct does not by itself prove an interactive desktop result.
Silent install/uninstall and process/module assertions may be automated through
the supervised standard-user process. GUI-visible first-launch, DPI, and other
interactive outcomes remain manual assertions until a separately validated
interactive harness exists.

## Declarative test profiles

Profiles conform to `test-profile.schema.json`. They declare the Windows x64
platform, baseline type, artifact metadata, named applications, automatic
steps, and manual assertions.

`artifact.fileNamePattern` is a case-insensitive filename glob, not a regular
expression or path. It may contain wildcard characters but no directory
separator. The caller supplies the concrete local artifact path and the runtime
records both the source and guest SHA-256 values.

Allowed step types are:

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

Steps reference a declared application or schema-defined assertion fields.
They do not contain `command`, `script`, `shell`, arbitrary executable, inline
PowerShell, or download URL fields. Every wait or action has a timeout from 1
through 900 seconds.

Baseline type is either `stock-clean` or `webview2-absent-derived`. Evidence
must preserve that exact value. The latter can never satisfy a requirement for
an untouched stock Windows image.

## Evidence semantics

Evidence conforms to `evidence.schema.json` and keeps automatic assertions and
manual assertions in different arrays. Each assertion has one of:

- `passed`
- `failed`
- `notPerformed`
- `unsupported`

Overall status is `failed` if any required assertion failed, `incomplete` if a
required assertion is not performed or unsupported, and `passed` only when all
required assertions passed. Optional assertions cannot upgrade the overall
status. A tool must never infer that a GUI-visible outcome passed from process
exit alone. Ordinary-user lifecycle evidence must identify a non-administrator,
non-elevated test identity with medium integrity, and must record matching
source and guest artifact SHA-256 values.

## Versioning

Plugin semver and JSON schema versions evolve independently. Additive optional
tool fields are minor-compatible. Tool renames, required-field changes, or
evidence semantic changes require a plugin major version and a new schema major
version. Readers reject unknown schema major versions and may ignore new
optional fields within schema v1.

## Gate 1 acceptance boundary

Gate 1 proves only manifest shape, launch-path resolution, skill validity, JSON
parsing, PowerShell syntax, and the frozen contract. It does not prove an MCP
handshake, Hyper-V behavior, guest access, installation, marketplace runtime
discovery, or clean-machine testing.

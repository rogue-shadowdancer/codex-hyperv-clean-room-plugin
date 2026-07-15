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

## Plugin installation

### Source validation fails

Run `scripts\validate-install-source.ps1` and use its bounded error. Do not
install a payload with untracked files, reparse points, forbidden machine-state
extensions, an unexpected folder/manifest name, or a version outside base
`0.1.1` plus one optional Codex cachebuster.

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

### `ELEVATION_REQUIRED`

Read-only tools can run without elevation, but VM creation and checkpoint
mutations require an elevated MCP server. Restart through an explicitly
approved elevated workflow. Do not disable the elevation check.

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

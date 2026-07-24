# Operations guide

## Current operating status

Gate 9/H4 applies the ownership-marked personal install and cachebuster-reinstall
workflow to the integrated plugin `0.2.0` runtime. Final acceptance requires the
clean commit/reinstall state recorded in `TASK_HANDOFF.md`. Automated runtime
acceptance still uses mock adapters and static seams for guest behavior. The
installed-copy smoke starts only from `%USERPROFILE%\plugins\hyperv-clean-room`
and discovers exactly 20 tools, performs read-only `inspect_host`, and exercises
only a missing-ISO rejection before mutation. It does not
authorize or prove a real Hyper-V mutation, real credential enrollment, guest
transfer, package lifecycle, or clean-machine result.

H5A repairs the automatic-checkpoint ownership deadlock without changing the
20-tool surface. Future VM creation disables automatic checkpoints before
ownership publication and verifies the setting by readback. For a pre-fix
managed VM, `inspect_vm` may verify an active differencing leaf only when its
complete identity-bearing chain terminates at the unchanged recorded base
VHDX. Recognition is read-only: it never adopts the leaf, rewrites state, or
changes a checkpoint.

Do not infer operational readiness from a green mock run. Real use requires a
separately approved host, owned VM, credential profile, artifact, profile, and
mutation scope. Gate 2 validation itself performs only real `inspect_host` and
a `plan_vm_create` request that is guaranteed to fail on a nonexistent ISO;
reported real mutations remain zero.

## Prerequisites

Production runtime prerequisites:

- Windows PowerShell 5.1;
- the Windows Hyper-V PowerShell module;
- a host capable of Hyper-V and PowerShell Direct;
- elevation for VM/checkpoint mutations;
- a Generation 2 Windows guest for guest operations;
- two distinct guest accounts: an orchestration administrator and a standard,
  non-administrator test user.

Development-only prerequisites:

- Python 3.10 or newer;
- `pip` for the selected interpreter;
- no production Python dependency; Python is development-only, including the
  `plugin-creator` marketplace and cachebuster helpers.

## Personal plugin installation

Validate and install from the repository root:

```powershell
.\scripts\validate-install-source.ps1
.\scripts\install_plugin.ps1
.\scripts\check_install.ps1
```

The installer targets `%USERPROFILE%\plugins\hyperv-clean-room`, requires an
exact ownership marker before any reinstall overwrite, verifies a per-file
relative-path/size/SHA-256 manifest, updates the default personal marketplace
only through `plugin-creator`, and runs
`codex plugin add hyperv-clean-room@personal`. It never deletes unexpected
installed files. See [installation.md](installation.md) for the first install
and [maintenance.md](maintenance.md) for the cachebuster loop.

## Reproducible development validation

Prepare exact development dependencies once. The script selects a supported
`python`, then the Windows launcher for Python 3.10 if needed. To select an
interpreter explicitly:

```powershell
.\scripts\prepare-test-python.ps1 `
  -PythonCommand $env:LOCALAPPDATA\Programs\Python\Python310\python.exe
```

Dependencies are installed below an ignored path keyed by Python ABI and the
SHA-256 of `requirements-dev.txt`. The script writes ignored runtime metadata
that records the interpreter and dependency directory. Repeating the command
is idempotent when both the ABI and requirements hash match.

After preparation, the complete Gate 2 validation has no arguments:

```powershell
.\scripts\validate-gate2.ps1
```

After the single personal cachebuster installation, run the complete Gate 9/H4
installed-copy validation (the historical script name is retained):

```powershell
.\scripts\validate-gate4.ps1
```

If preparation is missing, stale, or points to a removed interpreter,
validation stops with a bounded message telling the operator to rerun
`prepare-test-python.ps1`. It does not fall back to an unrelated global
site-packages directory.

Documentation can be checked independently without Python:

```powershell
.\scripts\validate-docs.ps1
```

### HCI1 local static validation

HCI1 adds a cross-platform Python 3.12 repository core for the future
`hyperv-static-linux` lane. Local contract validation is intentionally
separate from remote dispatch. With the development dependency path prepared
for the selected interpreter, run:

```powershell
$runtime = Get-Content -Raw .artifacts\test-python\runtime.json |
  ConvertFrom-Json
$env:PYTHONPATH = $runtime.dependencyPath
& $runtime.pythonExecutable -S -B tests\hci1_static_runner_tests.py
& $runtime.pythonExecutable -S -B tests\gate7_implementation_tests.py `
  --static-only
```

The complete Linux-safe suite is the fixed `SUITE_CHECKS` tuple in
`scripts/run_hyperv_static_linux.py`. It contains repository-format,
publication-hygiene policy, publication-hygiene, public-release contract,
schema contract, static quality, Gate 7 static integration, and HCI1
runner-contract checks. `runtime_artifact_schema_tests.py` and
`gate6_contract_tests.py` are not Linux lane inputs: the former requires the
Windows mock runtime samples and the latter invokes Windows PowerShell.

The repository core accepts no production command-line request. Direct
execution returns a canonical incomplete receipt with both
`controllerAdapter` and `remoteProof` equal to `notPerformed`. A future
infrastructure runner-integration gate must provide the fixed service seam and
convert the admitted C1 request plus already-verified Git bundle and wheel
bytes into internal `PreparedInputs`.

Do not create `/srv/codex-ci/hyperv-static-linux`, its physical backing path,
the `ci-hyperv-static` account, a mount, a service, or dependency files from
this repository runner. Do not substitute a home-directory lane, clone from
the network, or download wheels on the runner. The core validates the
pre-existing C2 lane facts and creates only the five fixed descendant classes
defined in the specification.

Remote execution remains disabled until all of these are independently read
back:

1. C2 Apply/Verify for the fixed account, ext4 bind mount, visible lane, and
   allowlisted service;
2. a later infrastructure runner-integration gate that binds the spool,
   source-bundle handoff, runtime, fixed invocation/result seam, evidence
   publication, and runner-image enforcement; and
3. an exact pushed HCI1 commit and tree with successful local validation and
   staged review.

At the HCI1 repository gate, remote directory/account/mount creation,
dependency installation, service start, suite enablement, and exact-SHA proof
are `notPerformed`. A timeout, SSH disconnect, or uncertain terminal state is
incomplete; read the operation's ambiguity state before considering any new
operation and never blind-retry.

Never reuse an operation ID with different request material. The core
validates an existing ambiguity record's request hash, idempotency key, source,
suite, and runner-image bindings before a transition and refuses to replace a
conflicting record. Distinct operations are serialized while changing the
lane, and capacity for the full bounded operation is reserved before the
workspace starts; a retention-capacity rejection is incomplete, not a request
to delete completed evidence.

The core publishes an immutable summary while the operation workspace is
still retained. After the adapter reads the summary back by exact SHA-256, it
may invoke the bounded cleanup helper for that operation ID and idempotency
key. A wrong or missing summary hash, workspace marker, or fixed path prevents
cleanup. The repository core never deletes the workspace before result
publication/readback and never removes another or unknown path.

## Credential enrollment

Credential setup is intentionally outside MCP. Run it interactively on the
Hyper-V host:

```powershell
.\hyperv-clean-room\mcp\Initialize-GuestCredential.ps1 `
  -ProfileName cleanroom-lab `
  -VmName cleanroom-test
```

The initializer accepts only those two parameters. It prompts twice with
`Get-Credential` and runs the same fixed PowerShell Direct identity probe once
with each credential. It requires:

- different validated SIDs;
- Administrators SID membership, administrator role, and high/system integrity
  for the orchestration identity;
- no Administrators SID or administrator role and exact medium integrity for
  the test identity.

It builds both DPAPI `Export-Clixml` objects and non-secret metadata in one
private `.pending-*` directory, read-checks every component, and publishes the
complete profile with an exact-destination same-volume
`[IO.Directory]::Move`. It then reopens the final directory and verifies its
protected ACL, exact three-file membership, sizes, credential objects, and
metadata. An existing or concurrently created profile is never merged into or
overwritten, and an incomplete pending bundle is never visible by its requested
profile name. Never place a password,
`PSCredential`, CLIXML document, secure-string serialization, or username and
password pair in an MCP call, profile, shell history, log, issue, or evidence
package.

Enrollment itself is a real guest credential operation. Gate 2 did not run it.

## Host inspection

Start every real-host workflow with `inspect_host`. With no arguments it
reports Windows, Hyper-V command availability, hypervisor presence, elevation,
CPU, memory, and switch summaries. Optional `vmRoot`, `minimumFreeSpaceGb`, and
`vmName` add target-volume and conflict checks.

`inspect_host` is read-only. It does not enable Windows features, create
switches, attach media, or enumerate secrets.

Use `list_vms` with its default `managedOnly: true`. Request unmanaged VMs only
when inventory context is necessary; their projection is deliberately reduced.
Use `inspect_vm` before checkpoint planning or when ownership is uncertain.

## VM creation

VM creation is a two-call guarded workflow:

1. call `plan_vm_create` with a local ordinary ISO, existing VM root, and
   existing switch;
2. review every returned path, identity, capacity value, and default;
3. call `apply_vm_create` once with only the returned plan ID.

The plan expires after 15 minutes. The first well-formed apply consumes it
before expiry, drift, or identity checks. A failed drift check is not a reason
to retry the same plan; create a new plan.

Apply creates only the declared Generation 2 VM, dynamic VHDX, memory/CPU
settings, Secure Boot, DVD attachment, local key protector, vTPM, switch
connection, automatic-checkpoint disablement, and ownership Notes marker. It
disables automatic checkpoints immediately after `New-VM` and requires a fresh
readback to report false before final ownership publication succeeds. If a
later step fails, partial resources are preserved and reported. The plugin
provides no deletion command.

## Pre-fix automatic-checkpoint recovery

Start with the exact accepted installed candidate and use `inspect_host`, then
`inspect_vm`. A recoverable pre-fix VM must report:

- `ownership.verified: true`;
- `ownership.storageBinding: verifiedDifferencingChain`;
- the unchanged recorded base VHDX path;
- the currently attached differencing leaf and a lowercase 64-character chain
  fingerprint;
- `automaticCheckpointRecoveryRequired: true` while automatic checkpoints are
  enabled or their setting is unavailable.

The chain is accepted only when every local ordinary VHD/AVHDX member has a
readable Hyper-V disk identity, parent links are exact and acyclic, and the
terminal path is the recorded base. Do not edit the ownership record or Notes,
adopt the active leaf, or delete, merge, rename, restore, or recreate a
checkpoint.

Recovery is a separate mutation review:

1. Preserve the current VM power state. Do not plan or apply either start or
   graceful shutdown while automatic checkpoints remain enabled or the setting
   is unavailable because either transition can change the differencing-disk
   lifecycle.
2. Because the 20-tool contract has no arbitrary VM-setting tool, separately
   approve one host configuration change whose only effect is disabling
   `AutomaticCheckpointsEnabled` in the current power state. It must not change
   power, disk attachment, checkpoint inventory, Notes, VM identity, ownership
   state, or any other VM setting.
3. Inspect again. Require automatic checkpoints false, ownership still
   verified, the same active chain fingerprint and checkpoint inventory, and
   `automaticCheckpointRecoveryRequired: false`.
4. Only then prepare the ordinary guarded power plan appropriate to the
   operational goal.

H5A itself performs none of these recovery mutations.

## Checkpoint create and restore

Checkpoint creation uses `plan_checkpoint_create` followed by
`apply_checkpoint_create`. The plan binds VM ID, ownership, current VM
fingerprint, checkpoint inventory, and checkpoint-name absence.

Restore uses `plan_checkpoint_restore` followed by
`apply_checkpoint_restore`. A successful restore plan returns one plaintext
confirmation token once. State stores only its SHA-256. Do not paste the token
into notes or logs. The first well-formed apply consumes the plan before the
name, token, or drift check, so a typo requires a new restore plan and token.

The managed VM must be `Off` when restore is planned and must still be `Off`
after the apply consumes the plan and revalidates current state. A running,
paused, or saved VM is rejected; the plugin does not stop it automatically.

The production adapter repeats this rebind immediately at the mutation
boundary. It takes a fresh VM snapshot, requires exact VM/ownership/current-
state and offline VHDX identity, rechecks the whole checkpoint inventory, and
locates exactly one checkpoint with the planned ID, name, and configuration
fingerprint in that same enumerated inventory before passing that exact raw
snapshot object to `Restore-VMSnapshot`.
Planning and apply fail closed if the attached-disk inventory, ordinary VHDX
file metadata, or Hyper-V VHD identifier/size facts cannot be read; two equally
incomplete projections never authorize restore.

Checkpoint restore discards current guest state. It requires explicit
authorization naming the VM and checkpoint even though the plugin provides a
plan gate.

## Guest inspection and staging

`inspect_guest` requires a verified owned VM and a credential profile name.
The orchestration administrator supervises a fixed standard-user worker. The
result includes OS/build/architecture, standard-user token facts, profile path,
DPI registry data, bounded current-user product inventory, WebView2 inventory,
developer-command availability, and hashed PATH summaries. Interactive GUI
outcomes remain manual.

`stage_artifact` is a low-level preflight and troubleshooting tool. It accepts
one host-local ordinary file and a safe path relative to the staging root. The
adapter prefixes the current operation ID, copies through PowerShell Direct,
and checks the stable host hash, guest hash, and byte length. The returned
destination belongs only to that staging operation.

Do not reuse a `stage_artifact` result as input to `run_test_profile`. The test
runner always creates its own operation-scoped copy.

## Declarative package lifecycle

Before execution:

1. call `validate_test_profile`;
2. inspect all application declarations, steps, cleanup steps, and manual
   assertions;
3. confirm that the artifact is the intended local ordinary file;
4. obtain explicit authorization for the package lifecycle on the named VM.

`run_test_profile` validates again, computes the host source SHA-256, inspects
the standard-user token, creates immutable operation state, stages the
artifact, and dispatches only profile-declared step types.

Production execution has fixed behavior:

- the administrator PowerShell Direct session is revalidated against the
  enrolled administrator SID and role before each guest operation context;
- every worker invocation revalidates the enrolled test-user SID, and
  lifecycle/cleanup dispatch additionally requires no administrator SID, no
  elevation, and exact medium integrity;
- plugin-owned guest workspace ancestors are atomically created with protected
  ACLs when absent; readback requires administrator ownership, exact
  administrator/system full-control grants, and operation-only test-user
  read/execute without write-capable inheritance;
- the administrator writes a create-new, hash-bound input document and accepts
  the worker result only from its redirected stdout pipe when operation,
  invocation, mode, input hash, and exit code agree;
- the worker is created suspended, assigned to a Windows job, and then resumed;
  timeout, a late/unbound launch result, or unexpected descendant survival
  terminates the job and requires zero active processes plus root exit;
- one intended launch survivor is suspended and identity/job-revalidated while
  it is the only active job process before release and resume;
- NSIS install uses the operation artifact with fixed silent/current-user
  arguments;
- MSI install uses fixed `msiexec.exe` current-user arguments;
- application launch resolves a declared relative executable below the test
  user's profile;
- ordinary stop and cleanup stop accept only a PID recorded for the same
  operation, revalidate its identity through one retained process handle, and
  terminate and wait through that same handle;
- NSIS uninstall requires a unique HKCU uninstall executable constrained below
  the declared application directory and adds only a fixed silent argument;
- MSI uninstall requires one constrained product-code identity and fixed
  `msiexec.exe` arguments;
- assertions use fixed filesystem, HKCU, process, module, listener, or sentinel
  probes;
- wait and all child processes are time bounded.

There is no command, script, shell, inline PowerShell, URL, download, raw
uninstall-string, or arbitrary argument field.

### Timeout boundaries

The adapter applies PowerShell remoting open, operation, and cancel timeouts,
tracks one end-to-end deadline, and checks remaining time before and after
synchronous PowerShell Direct calls. Once the standard-user worker starts, its
Windows job object provides the stronger boundary: the supervisor can terminate
the worker process tree and verify that it stopped. A `launchApplication` child
may deliberately outlive that one worker invocation and is controlled later by
its recorded process identity.

PowerShell Direct session creation, `Invoke-Command`, and guest copy operations
are transport calls, not processes in the worker job. If the remoting layer
itself ignores or outlives its configured timeout during a host/guest failure,
the adapter cannot apply the job-object hard-kill guarantee to that transport
call. Treat such a call as an indeterminate guest operation, preserve state,
and recover the host/guest transport outside the plugin rather than retrying a
mutation blindly.

## Cleanup

Cleanup is armed only after validation has completed and execution begins. It
triggers after a failed required assertion, failed action or mutation, timeout,
or guest-adapter failure. An optional assertion failure does not trigger it.

Cleanup runs the declared sequence while the 300-second total budget remains.
A failed cleanup step does not stop later steps. Only `stopApplication` may
change process state, and it may stop only a revalidated current-operation PID.
Cleanup cannot uninstall, delete, restore a checkpoint, or roll back the VM.

Cleanup results never change `overallStatus`. Preserve them as separate
operational evidence.

## Evidence and manual observations

After a run, use `record_manual_attestation` only for a declared manual
assertion. References must already exist under that operation's server-owned
evidence root and include their exact SHA-256. The server supplies observer
identity and timestamp. Mutable control documents such as `evidence.json`
cannot reference themselves. Export holds the operation lock, re-resolves and
rehashes every claim, hashes each source before and after copy, hashes the
destination, and writes the verified destination hash into the inventory. A
staged root `inventory.json` is forbidden, and the exact copied
`evidence.json` must still validate against immutable operation state before
the generated inventory is written. The final serialized inventory is reopened,
its exact membership is checked, and every copied file is size/hash-verified
from the parsed final claims before export succeeds.

Use `collect_evidence` to export into an existing, safe directory. Then call
`validate_evidence` on the exported `evidence.json`. See
[evidence.md](evidence.md) for derivation and provenance rules.

## Failure and recovery principles

- Do not repeat a consumed plan; plan again from current state.
- Do not bypass ownership disagreement; investigate the Notes marker and state
  record.
- Do not weaken a hash check; reselect the intended stable artifact.
- Do not treat a cleanup success as a successful test.
- Do not claim real guest validation from mock output.
- Do not improvise a shell command when the declarative profile cannot express
  a scenario. Revise the specification and schema deliberately instead.
- Preserve partial VM/package state for diagnosis. Destructive recovery is an
  external administrator decision and is not a plugin tool.

For error-specific actions, use [troubleshooting.md](troubleshooting.md).

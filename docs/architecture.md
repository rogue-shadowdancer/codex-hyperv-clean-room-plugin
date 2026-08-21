# Architecture

## Status and assurance boundary

Hyper-V Clean Room is a Windows-only Codex plugin whose product surface is a
PowerShell 5.1 MCP server. Source version `0.4.1` preserves the exact 16
schema-v1 tools, five public schema-v1 documents, four schema-v2 power/network
tools, and seven schema-v2 paths. It adds an external portable branch while
preserving the embedded `0.2.0` branch. Gate 2 implements both the mock adapter and the
production Hyper-V/PowerShell Direct adapter, but validates guest execution
only through mock behavior, parser checks, and closed-dispatch static seams.
No real guest credential, file transfer, package process, VM mutation, or
checkpoint mutation was exercised in Gate 2.

The host authorization seam evaluates only the current MCP server token. It
projects whether that token is elevated and whether local built-in SID
`S-1-5-32-578` (`Hyper-V Administrators`) is enabled, then derives one of
`elevatedAdministrator`, `hyperVAdministrators`, or `none`. No user name or
user SID is emitted. VM inventory/inspection and host Plan/Apply paths require
authorization. The production VM-create, checkpoint-create/restore,
power-transition, and network-transition adapters recompute authorization at
the final mutation boundary so a mock snapshot or earlier plan cannot confer
authority.

The v0.4.1 production VM listing path has a separate shallow adapter seam from deep VM
inspection. `ListVms` enumerates once and projects only ID, name, state,
generation, Notes, and configuration path. Ownership then performs a keyed
state lookup by VM ID. Unmanaged entries stop there; only a matching record and
ID/name/Notes marker can request the internal expected-ID/name storage
projection. That second projection revalidates the live Notes marker and reads
only the primary attached-disk path and, when necessary, the bounded VHD chain
needed to compare the recorded base.
It never reads NICs, switches, checkpoints, firmware, security, or the full VM
configuration. `inspect_vm` and guarded mutation paths retain the full snapshot.

The v0.4.1 source Gate validates this seam through mock/runtime/static evidence;
production typed readback remains a later post-install Gate. Implementation is
therefore not the same as clean-machine validation. A real
operator must treat guest transfer and lifecycle actions as state-changing and
obtain explicit authorization for the named VM and operation before use.

Gate 6/H1 additionally freezes the schema-v2 contract under `contracts/v2`.
Gate 7/H2 integrates exact schema copies and the 20-tool runtime without
weakening the v1 paths described below. H2 assurance is limited to mock,
parser, schema, and static production-seam validation; it is not clean-machine
or real-operation evidence.

## Schema-v2 integrated architecture

The target remains one PowerShell 5.1 MCP server and one closed production
worker; it does not add a general automation endpoint. H2 adds four registry
entries (`plan_vm_power`, `apply_vm_power`, `plan_vm_network`, and
`apply_vm_network`) and version-dispatched validators while preserving the 16
existing entries exactly. Profile and evidence routing reads the exact integer
`schemaVersion` once. V1 and v2 have independent validators; there is no
try-v2-then-v1 fallback.

The integrated runtime has five internal, non-public seams:

| Seam | Fixed responsibility | Forbidden responsibility |
| --- | --- | --- |
| Power planner/apply | Bind and revalidate managed VM state for start or graceful shutdown | Force-off, reset, pause, or caller-selected cmdlets |
| Network planner/apply | Bind one recorded primary NIC and baseline switch, with paired recovery | Arbitrary adapter/switch choice or unmanaged adoption |
| Portable deployment | Stream-validate one manifest-bound ZIP into a new atomic slot and preserve recorded data | General extraction, deletion, or arbitrary copy |
| Fixed-driver manager | Verify exact Microsoft archive/executable provenance and own a loopback session | Caller URL, arguments, port, navigation, or script |
| UI dispatcher | Map the closed `data-testid` DSL to fixed WebDriver operations | Raw WebDriver, CSS/XPath selectors, JavaScript, or file paths |

P3.2 adds a mutually exclusive external portable path at the same seams. The
profile resolves one regular profile-relative manifest sidecar and binds its
declared size/SHA. Native validation closes the manifest and its provenance,
while the fixed worker independently verifies that every regular ZIP entry and
every declared inventory entry match. The sidecar, fixtures, and mutable
`data/` bytes remain outside the deployment payload. Publication is atomic
only after validation; launch uses the declared executable with no caller
arguments. External evidence separates the elevated orchestration identity
from the exact-medium standard user and records conditional driver identity.
No branch probing or fallback is permitted.

The target operation flow is:

1. validate the exact schema version and closed input;
2. bind source commit, profile, candidate ZIP, fixture set, driver manifest,
   VM ownership, baseline, guest identity, and current fingerprints;
3. for power/network, publish an immutable plan and atomically consume it at
   apply; for disconnect, publish the change and recovery plans as one pair;
4. for portable deployment, stream into a new operation-owned staging root,
   verify every manifest path/size/hash, and atomically publish a deployment
   slot only after full validation;
5. run only fixed worker modes, acquire an exact-version loopback driver, and
   dispatch only the declared UI step types to declared `data-testid` values;
6. retain operation-scoped processes and resources for bounded containment;
7. derive schema-v2 machine and overall evidence from immutable observations,
   including recovery and data-preservation facts.

Power and ordinary network plans expire after 15 minutes; a paired network
recovery plan expires after 24 hours. The plan ID is the only apply capability
input. Portable and WebDriver archives never become trusted merely because the
outer ZIP hash matches: archive policy, manifest membership, extracted file
identity, PE architecture, publisher, version, and loopback policy are
independently rebound.

## Components

| Area | Responsibility | Production dependency |
| --- | --- | --- |
| `.codex-plugin/plugin.json` | Plugin identity, version, capability declaration | Codex plugin loader |
| `.mcp.json` | Starts the stdio server from the plugin root | Windows PowerShell 5.1 |
| `mcp/server.ps1` | Line-delimited UTF-8 JSON-RPC and MCP negotiation | PowerShell 5.1 |
| `mcp/lib/ToolSchemas.ps1` | Closed input schemas for the 16 tools | None beyond PowerShell |
| `mcp/lib/Runtime.ps1` | Tool dispatch, operation IDs, bounded envelopes | None beyond PowerShell |
| `mcp/lib/State.ps1` | Atomic JSON, locks, plans, operations, ownership, evidence staging | Local filesystem |
| `mcp/lib/Validation.ps1` | Native profile and evidence contract validation | None beyond PowerShell |
| `mcp/lib/Tools.Host.ps1` | Host/VM/checkpoint inspection, plan, apply, drift guards | Hyper-V module for real operations |
| `mcp/lib/Tools.Guest.ps1` | Guest inspection, staging, test orchestration, attestations, export | Adapter boundary |
| `mcp/lib/Adapters.ps1` | Test-only mock adapter; shallow VM-list and candidate-only storage projections; deep production Hyper-V/PowerShell Direct paths | Hyper-V module and PowerShell Direct |
| `mcp/lib/GuestWorker.ps1` | Fixed standard-user dispatcher copied and hash-verified per operation | Windows PowerShell in the guest |
| `mcp/Initialize-GuestCredential.ps1` | Interactive two-role credential enrollment | DPAPI and PowerShell Direct |
| `schemas/*.json` | Portable Draft 2020-12 result/profile contracts | Development and CI validation only |

Python never participates in the production MCP process. It is isolated below
ignored `.artifacts` only for schema and repository-quality checks.

## Request and mutation flow

Every tool call receives a fresh UUID operation ID. Read-only tools inspect
state directly. Guarded host mutations use the following sequence:

1. inspect the current host or owned VM;
2. create a 15-minute immutable plan with identities and fingerprints;
3. atomically consume the plan on the first well-formed apply;
4. re-read every recorded precondition;
5. apply only the exact planned mutation;
6. preserve and report partial resources if the mutation fails.

The server never supplies a public deletion operation. A failed create does
not automatically remove a VM or VHDX, and a failed checkpoint operation does
not perform an implicit rollback.

The guest lifecycle flow is separate:

1. verify plugin ownership of the VM;
2. resolve a DPAPI credential profile by name, never by password input;
3. open PowerShell Direct with the orchestration administrator and revalidate
   that session's SID, Administrators SID, administrator role, and high/system
   integrity against the enrolled metadata;
4. create a server-controlled operation workspace under guest `ProgramData`,
   create plugin ancestors with protected ACLs atomically when absent, take and
   read back administrator ownership, and verify the exact privileged and
   non-write test-user grants;
5. copy and SHA-256-verify the plugin-owned `GuestWorker.ps1`;
6. create that worker suspended with the standard-user credential and a loaded
   user profile, assign it to an administrator-owned Windows job object, then
   resume it;
7. have the worker revalidate its SID for every invocation and, for lifecycle
   or cleanup work, require a non-administrator, non-elevated, exact-medium
   token;
8. return bounded JSON only through the redirected stdout pipe held by the
   administrator supervisor and bind it to operation, invocation, mode, input
   hash, and process exit code;
9. record automatic results, operation-scoped PIDs, and evidence state.

The supervisor and fixed worker bind their internal request object through a
`$WorkerInput` parameter. Production guest functions must never declare a
parameter named `Input`: PowerShell variable names are case-insensitive, so
that spelling collides with the automatic `$input` enumerator and can replace
the validated request object before schema dispatch.

The administrator session is supervision and transfer infrastructure. It is
never ordinary-user package evidence. Read-only guest inspection can report a
privilege mismatch, but lifecycle and cleanup execution fail before dispatch
when the standard-user token is elevated, administrative, non-medium, or no
longer matches the enrolled SID.

The initializer and production adapter share one self-contained Windows token
probe that can run unchanged through PowerShell Direct. The standalone worker
contains the equivalent closed native implementation. Both query
`GetTokenInformation` for `TokenIntegrityLevel`, `TokenElevation`, and
`TokenElevationType`; require the entire mandatory-label SID to remain inside
the returned buffer with exact `S-1-16` authority, one subauthority, and
`SE_GROUP_INTEGRITY`; classify only the exact low, medium, medium-plus, high,
and system RIDs; and reject inconsistent elevation/type combinations. The
elevation type is an internal consistency check and is not added to public
guest evidence. `WindowsIdentity.Groups` remains useful only for the separate
local Administrators SID membership proof and is never an integrity source.

## Trust boundaries

### MCP client to server

All 16 tool inputs use closed schemas. Unknown fields are rejected before tool
dispatch. Passwords, serialized credentials, commands, scripts, shell text,
URLs, and arbitrary executable arguments have no MCP field.

### Host process to Hyper-V

Read-only inspection may observe unmanaged VMs in a reduced projection. A
mutation requires both an exact Hyper-V Notes marker and a matching ownership
record containing VM ID, name, paths, creation operation, and ownership ID.
Any disagreement is `OWNERSHIP_UNVERIFIED`.

The reduced list path has three bounded stages. `vmInventory` covers provider
enumeration and fails with `HYPERV_UNAVAILABLE`; `vmSummaryProjection` covers
the required shallow fields and fails with `INTERNAL_ERROR`; and
`ownershipProjection` is the internal candidate-only storage boundary. The
first two are unrecoverable list failures with identity-free `error.details`.
An incomplete ownership projection is recoverable for enumeration but never
for trust: the VM remains `OWNERSHIP_UNVERIFIED`, the all-VM view retains only
its public summary, and one bounded warning reports the stage without an
identity. State-root access and integrity failures propagate instead of being
reclassified. Every path is read-only and returns or preserves
`changed: false`.

### Host process to credential storage

Credential metadata and two DPAPI `Export-Clixml` objects live below
`%APPDATA%\Codex\hyperv-clean-room\credentials`, separate from operational
state. The MCP surface carries only a profile name. DPAPI binds decryption to
the current Windows user and machine.

### Administrator supervisor to standard-user worker

The administrator creates fixed `control`, `output`, and `staging`
subdirectories for the operation. From the plugin-owned guest ancestors down,
new directories receive the protected descriptor atomically; existing paths
are rebound. Readback requires the live administrator owner and exactly one
full-control grant for that identity, `SYSTEM`, and local Administrators.
Every grant has exact container/object inheritance and no propagation flag;
operation paths add exactly one test-user read/execute grant without
write-capable rights. The
test user therefore cannot retain ownership through a permissive parent,
replace the worker, rewrite create-new input, or publish a result there. The
worker script and input remain administrator-written, and the copied worker
hash must match the plugin source hash before execution.

Worker results use the child process's redirected stdout, not a
standard-user-writable file. The administrator strictly decodes and parses at
most one MiB of UTF-8 JSON and accepts it only when `operationId`, invocation
ID, mode, input SHA-256, and the worker exit code all agree. Stderr is an
untrusted raw-byte diagnostic stream, not a result channel: a fixed 4 KiB
buffer drains it, the byte count saturates at 64 KiB, and excess bytes are
discarded while draining continues so a full pipe cannot block the worker.
The supervisor never decodes, accumulates beyond the fixed buffer, persists,
or exposes stderr content.

The synchronous raw drain runs on a plugin-owned background thread and opens a
non-inheritable handle to that exact thread with only `THREAD_TERMINATE` access.
An accepted `launchApplication`/UI descendant may keep its inherited stderr
writer open after the root worker exits. Before that declared descendant can
be released, the supervisor sets its private cancellation state, calls
`CancelSynchronousIo` on the drain-thread handle, and requires the task to join
within two seconds. Only an exception observed after that private cancellation
request becomes `Cancelled`; an uninterruptible or faulted drain fails
containment and the job is terminated instead of releasing the descendant.

The worker mode is one of `InspectGuest`, `RunTestStep`, or
`RunCleanupStep`. Step types are enumerated again inside the guest. Package
installation uses only the current operation's staged artifact with fixed NSIS
or MSI arguments. Application launch uses only a declared, safe path below the
test user's profile. Uninstall uses a unique constrained HKCU entry or MSI
product identity; it never executes an unrestricted uninstall string.

### Filesystem paths and evidence

Host inputs must be local absolute ordinary files or directories with no
reparse-point endpoint. Profile paths are relative, bounded, free of roots,
drives, traversal, alternate streams, and environment expansion. Both host and
guest resolve a candidate and verify that it remains below the expected root.

Each test has a server-controlled host evidence root and a distinct guest
operation workspace. Manual references are relative to the host evidence root
and hash-verified before acceptance. Caller-selected directories are export
destinations only; they never become live staging roots.

## Operation-scoped resources

The production guest adapter binds these resources to the MCP operation UUID:

- staged artifact destination;
- fixed-worker input and output documents;
- standard-user sentinel directory;
- launched application PID, start time, executable path, and identity hash;
- cleanup `stopApplication` authority.

Each fixed-worker invocation is created suspended, assigned to a Windows job
object, and then resumed. The supervisor recomputes the remaining deadline
before waiting. A timeout, late or unbound launch result, or unexpected
surviving descendant terminates the job; containment succeeds only after the
root exits and the active-process count reaches zero. `launchApplication` is
the single deliberate exception that may leave its declared child running
after the worker exits. The child is released only after its bound PID is
suspended and its PID, creation time, executable path, job membership, and
identity are rebound while it is the job's only active process. It is then
resumed only after any inherited pending stderr read has been cancelled and
joined as described above. Extra descendants fail containment, and later stop
authority is limited to the recorded, revalidated process identity.

Before stopping a process, the worker retains one opened process handle and
uses that handle to read creation time and path and to recompute the bound PID,
operation ID, and identity hash. A missing, exited, inaccessible, or reused PID
fails safely and is not stopped. A match is terminated and waited through that
same handle. This applies to ordinary declared stop steps and to cleanup.

The job object supervises the standard-user worker process tree, not the
PowerShell Direct transport itself. Session open/operation/cancel timeouts and
an end-to-end deadline bound synchronous remoting work, with checks between
transport calls. A stuck `New-PSSession`, `Invoke-Command`, or copy operation
does not expose a local guest PID that the host can terminate through that job;
this is a documented PowerShell Direct limitation, not a hard-kill guarantee.

## State layout and concurrency

Mutable host state defaults to
`%LOCALAPPDATA%\Codex\hyperv-clean-room\v1`:

```text
v1/
  plans/
  operations/
  ownership/
  evidence-staging/
  locks/
```

JSON is written as UTF-8 through a same-directory temporary file and atomic
replacement. Per-record exclusive locks coordinate server processes. Plans,
operations, and ownership records are separate so consuming a plan cannot
silently rewrite resource ownership or evidence.

Initialization validates the root and all five required children as ordinary,
enumerable directories and opens one unique file in each with
`DeleteOnClose`. This proves the current server token can perform the bounded
state writes and cleanup required by the runtime without changing ACLs. Later
state read, write, enumeration, and lock access denials use the same
`STATE_ROOT_ACCESS_DENIED` boundary.

Credential storage is deliberately outside this tree. Exported evidence is
also outside this tree and must be placed in an existing caller-selected
directory that is not under Windows, Program Files, plugin, credential,
Hyper-V storage, or operational state roots.

## Compatibility and non-goals

The 0.x line preserves schema version 1, the five public
schemas, the 16 tool names, JSON-string MCP text results, and the common result
envelope unless the specification is deliberately revised. Plugin `0.1.1` is
the first GPL-3.0-only public release; plugin semver and schema version evolve
independently.

The architecture intentionally excludes:

- VM, VHDX, checkpoint, guest-file, registry-key, or host-path deletion tools;
- WinRM, SSH, network management, or remote download;
- arbitrary command, script, shell, URL, or executable-argument execution;
- plaintext credential transport or evidence;
- automatic claims about GUI visibility, DPI correctness, or interactive
  behavior;
- automatic rollback after package or VM failure.

See [security.md](security.md) for the threat controls,
[operations.md](operations.md) for operator sequencing, and
[evidence.md](evidence.md) for provenance and status derivation.

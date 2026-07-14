# Security design

## Security objective

The plugin narrows a high-impact Hyper-V and package-testing workflow into a
typed, reviewable, fail-safe surface. It does not make virtualization or
untrusted installers intrinsically safe. The operator remains responsible for
host isolation, licensing, artifact provenance, and explicit authorization of
each real mutation.

The primary security properties are:

- inspect and plan before guarded host mutation;
- mutate only a VM whose Hyper-V marker and state record agree;
- carry no plaintext credential through MCP, profiles, logs, or evidence;
- run package lifecycle work as a validated standard user;
- expose no arbitrary command, script, shell, URL, download, or executable
  argument surface;
- bind guest staging, sentinels, worker I/O, and stoppable PIDs to one
  operation;
- provide no VM, VHDX, checkpoint, guest-file, registry-key, or host-path
  deletion tool;
- keep evidence provenance and cleanup state immutable.

## Threats and controls

### Accidental mutation or stale approval

VM and checkpoint changes require a plan and a separate apply. Plans expire in
15 minutes and bind host, resource, volume, switch, path, ownership, VM state,
checkpoint inventory, and target identities as appropriate. An apply consumes
the plan before checking confirmation or drift, preventing repeated guesses or
stale reuse.

Malformed input and unknown plan IDs do not consume a plan because they do not
identify a well-formed apply request. Every other failure after plan lookup
requires a new plan from current state.

### Mutation of an unmanaged or renamed VM

A managed VM needs both `hyperv-clean-room/v1:<ownership-id>` in Hyper-V Notes
and a state record with matching VM ID, name, VM root, VHDX path, creation
operation, and ownership ID. Missing or divergent data stops every mutation
with `OWNERSHIP_UNVERIFIED`. Read-only inspection remains available for
recovery diagnosis.

### Credential disclosure

`Initialize-GuestCredential.ps1` accepts only profile name and VM name. Two
interactive prompts collect credentials in memory. PowerShell Direct probes
prove distinct SIDs and the required roles before persistence.

Each credential is serialized separately with DPAPI-backed `Export-Clixml`.
Both credential files and metadata are first built, ACL-protected, size-checked,
and read-validated in one private pending directory. Publication uses an
exact-destination same-volume `[IO.Directory]::Move` after checking that the
profile name is still absent. The final directory is then reopened and must
contain exactly `orchestration-admin.clixml`, `standard-test-user.clixml`, and
`profile.json`; its protected ACL, file sizes, credential objects, and metadata
are read-validated again. A concurrent loser cannot merge into or overwrite the
winning profile, and a partial bundle is never exposed as usable. The
credential directory is outside operational state and evidence. MCP inputs
carry only the profile name. Runtime errors return bounded stable codes and do
not serialize a `PSCredential`, secure string, password, PowerShell error
record, stack, or full environment.

DPAPI is not a backup mechanism and does not protect against compromise of the
same Windows user and machine. Protect the host account, profile directory,
and backups accordingly. Never commit `.clixml`, credential directories, VM
state, or evidence containing private observations.

### Administrator execution mistaken for user evidence

The orchestration credential only opens and supervises PowerShell Direct,
creates operation roots, transfers the fixed worker and artifact, reads bounded
results, and applies ACLs. The declared install, application, assertion,
sentinel, and cleanup work runs in a new process created with the standard-user
credential and `-LoadUserProfile`.

The runtime revalidates the PowerShell Direct session against the enrolled
administrator SID, Administrators SID, administrator role, and high/system
integrity whenever it creates a guest operation context. The fixed worker then
compares its current SID with credential metadata on every invocation.
Lifecycle and cleanup modes reject administrator membership, elevation, any
integrity other than exact medium, or SID mismatch. Read-only inspection reports
the observed test token so drift can be diagnosed without performing lifecycle
work. Evidence separately records those standard-user token facts.

### Forged worker result or escaped process tree

The administrator creates each input file with create-new semantics and keeps
the worker script and input outside standard-user write authority. The worker
emits bounded JSON only through redirected stdout. No result-file path is
accepted. The supervisor verifies operation ID, invocation ID, mode, input
SHA-256, and exit-code agreement before accepting the result.

Every plugin-owned guest workspace ancestor is created with its protected ACL
atomically when absent, then owner and rules are read back. The live
administrator owns the directory; that identity, `SYSTEM`, and the local
Administrators group each have exactly one full-control grant. Only operation
directories grant the enrolled test SID read/execute, never a write-capable
permission. All grants use exact container/object inheritance with no
propagation flag, and existing paths have both owner and DACL rebound. An
existing or inherited permissive parent grant therefore cannot
leave the test user owning an ancestor or able to replace worker/control input.

The worker primary thread is created suspended, assigned to a Windows job
object, and only then resumed. The remaining absolute-deadline budget is
recomputed immediately before waiting. A timeout, late/unbound launch result,
or unexpected descendant causes whole-job termination; success requires the
root to exit and the job's active-process count to reach zero. Failure to verify
termination is a containment error. A declared `launchApplication` child is
the only intended survivor of an otherwise completed worker invocation. Before
release, that process is suspended and its PID, creation time, path, job
membership, and identity are revalidated while the job contains exactly one
active process; it is then resumed. Extra descendants make the launch fail and
the whole job is terminated. Later stop authority is bound to its
operation-scoped process identity.

### Arbitrary code execution through a test profile

The public profile schema and native semantic validator reject unknown fields,
commands, scripts, shell text, URLs, inline PowerShell, arbitrary arguments,
rooted paths, traversal, alternate streams, and environment expansion.

The production adapter repeats a closed-field and closed-type check before
guest dispatch. `GuestWorker.ps1` has only three modes and its own allowed step
type lists. It never evaluates a string as code and never calls an arbitrary
command supplied by the client.

Package execution is necessarily code execution, but its source is constrained:

- the file must be a host-local ordinary artifact selected for the operation;
- the stable host hash, guest hash, and byte length must agree;
- the guest path is under the current operation staging root;
- NSIS and MSI install arguments are fixed;
- application launch resolves only a declared relative executable below the
  test user's profile;
- NSIS uninstall accepts only one ordinary non-reparse executable below the
  declared application directory, discovered from a matching HKCU entry, and
  adds only a fixed silent argument;
- MSI uninstall accepts only one constrained product-code identity and fixed
  `msiexec.exe` arguments.

There is no network download behavior. WinRM, SSH, and network management are
outside the design.

### Path traversal and reparse attacks

Host file inputs must be absolute local paths and ordinary files. UNC paths,
devices, directories in file fields, and reparse endpoints are rejected.

Profile paths are relative and bounded. They reject drive prefixes, leading
separators, empty segments, `.`/`..`, colons, percent expansion, NULs, and
overlength values. After combining a root and relative path, both host and
guest compare normalized paths and inspect existing segments for reparse
points. Evidence exports perform the same containment and reparse checks.

The guest worker accepts input/output paths only under the server-created
operation root and requires the expected `control` and `output` directories.

### PowerShell Direct transport timeout

Remoting session options and an end-to-end deadline bound session creation and
synchronous PowerShell Direct operations. The adapter checks the deadline
between calls. These transport calls are not members of the standard-user
Windows job, so the job-object hard-kill guarantee begins only when the fixed
worker process starts. A stuck remoting call can therefore outlive the intended
deadline on a faulty host or guest; it must be treated as indeterminate and
recovered externally, never as proof that the guest mutation failed cleanly.

### PID reuse or cross-operation process stopping

On application launch, the standard-user worker records operation ID,
application ID, PID, UTC start time, executable path, and a SHA-256 identity
over those values. A stop step requires that exact record. Immediately before
stopping, the worker opens one retained process handle, obtains start time and
path from that handle, and recomputes the identity. A mismatch, missing
process, inaccessible path, or reused PID fails without stopping it. A matching
process is terminated and waited through that same retained handle; a separate
PID lookup is never used for the stop.

Cleanup has no general process-name kill. Its only state-changing step is this
operation-scoped stop.

### Evidence forgery

The runtime persists immutable automatic/manual/cleanup identities before
results are exported. `validate_evidence` binds arrays one-to-one and in order,
recomputes overall status, verifies dual artifact hashes, checks ownership and
token invariants for passed results, and rejects forged cleanup trigger state.

Manual references must already exist below the server staging root and must
match their supplied SHA-256. `evidence.json` and other mutable control
documents cannot reference themselves. At export, the operation lock is held
while every claim is resolved and rehashed; each source is hashed before and
after copy, the destination is hashed, and the inventory records that verified
destination hash. A staged root `inventory.json` is reserved and rejected, and
the exact copied `evidence.json` is parsed and rebound to immutable operation
state before inventory publication. The final serialized inventory is then
reopened; its exact operation/file membership drives a final size and SHA-256
readback of every copied file. Any state/source/copied/claimed/inventory
disagreement stops the export. Caller paths never become live evidence roots.

### Secret or machine-state files entering Git

The repository ignores `.artifacts`, state, evidence, plans, credentials,
CLIXML, VHD/VHDX, ISO, logs, Python bytecode, and common desktop metadata.
Validation scans tracked and untracked project files for sensitive filename
patterns and rejects production Python dependencies. Operators must still
review `git status` before committing.

## Bounded cleanup

Cleanup is failure follow-up, not rollback. It has at most 16 steps, each from
1 to 120 seconds, with a declared total of at most 300 seconds. It cannot stage,
install, launch, uninstall, write a sentinel, delete, restore a checkpoint, or
run a command/script/shell/URL. A cleanup failure does not recursively trigger
cleanup and does not block later steps while budget remains.

## Diagnostics and redaction

Stdout is reserved for one JSON-RPC response per line. The server suppresses
PowerShell warning, verbose, debug, information, and progress output both by
preference and by explicit per-request stream redirection, so imported modules
or handlers cannot corrupt stdio framing. Stderr diagnostics are bounded and
redact common credential/token assignments. Tool failures expose stable codes,
short actionable messages, and intentionally bounded details.

Do not add debug output that prints:

- complete environment blocks or PATH entries;
- credential usernames unless identity evidence requires them;
- `PSCredential`, secure-string, CLIXML, restore-token, or password material;
- PowerShell exception records, invocation info, or stack traces;
- complete host storage paths unrelated to the requested action.

## Assurance limitations

Gate 2 proves mock behavior, schema semantics, parser compatibility, static
closed-dispatch properties, documentation, and read-only host behavior. It
does not prove that a particular Windows build, installer, guest account,
PowerShell Direct transport, desktop session, ACL configuration, or Hyper-V
host behaves correctly in production.

A future real validation requires separate explicit authorization and a
dedicated environment. It must not weaken the schema-v1 or 16-tool contract to
make a machine pass.

For vulnerability reporting and supported-version policy, see the repository
[SECURITY.md](../SECURITY.md).

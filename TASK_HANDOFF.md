# Task handoff: post-merge Hyper-V validation closure

`relayProtocolVersion: 1`

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

## Objective and authorization

Close the post-merge validation gap on protected commit
`16c3b7faf6fa353afead47cbf02b7e67fc0fa39c`: preserve the already installed
stderr-drain payload, make publication-history validation accept the recurring
GitHub protected squash shape without an endless exact-hash follow-up cycle,
revalidate the exact candidate, and publish the test/documentation-only repair
through the ordinary protected pull-request path before resuming Birdsgone G8.

This closure gate performs no VM/checkpoint/network mutation, credential prompt
or persistence, guest operation, package lifecycle, restore, tag, or GitHub
Release. Its only live Hyper-V evidence is the separately recorded typed
read-only admission and the repository-defined bounded installed-copy smoke,
both with `changed=false` and zero Hyper-V mutations.

## Current follow-up state

- Protected `master`, the installer-bound checkout, and the installed manifest
  identify commit `16c3b7faf6fa353afead47cbf02b7e67fc0fa39c`, build
  `0.4.1+codex.20260821104322`, and 31 payload files. The canonical install
  readback has `installed=true`, `owned=true`, `matches=true`,
  `marketplaceVisible=true`, and one marketplace entry.
- The current model exposes exactly 20 typed Hyper-V tools. Typed read-only
  operations `59e47822-afa0-4f8e-94ae-2bc2e1ba3b83`,
  `e759a34d-ee00-4292-ad6f-7d904ca3f6c1`, and
  `673bbade-f6c8-4008-bdf5-80245b906c2c` proved the host is authorized through
  the non-elevated Hyper-V Administrators token and the only managed VM is Off,
  Generation 2, ownership/direct-base verified, automatic checkpoints disabled,
  with zero checkpoints and no warnings.
- Gate 4 installed-copy acceptance passes on the supported Windows PowerShell
  5.1 host with 20 tools, read-only host inspection, `INVALID_ISO` rejection,
  and zero real guest operations or Hyper-V mutations. Gate 7 passes with 452
  runtime assertions, 16 preserved v1 tools, five v1 schemas, seven v2 schemas,
  and ten generated evidence documents.
- The full publication aggregate passed its first ten lanes, then failed only
  because protected squash commit `16c3b7f...` used the approved public noreply
  email with GitHub's profile display name and web-flow committer. Adding only
  raw commit SHA-256 `9c16aeca6686b280b35c65229b60e124eb2fd53dc1c5803a4a0403e0dc5a8164`
  would recreate the same failure after the next squash merge, so the repair is
  a closed structural GitHub-squash predicate plus fail-closed policy tests.
- An independent trust-boundary review correctly found that signature-envelope
  text is spoofable. The follow-up now treats shape only as a classifier and
  requires local cryptographic verification against a repository-pinned copy
  of GitHub's official web-flow public-key bundle. Both the complete armored
  bundle SHA-256 and current signing fingerprint are pinned. Synthetic
  envelopes, changed bundle bytes, and unpinned fingerprints fail closed.
- PowerShell 7 cannot invoke the production adapter's .NET Framework-only
  `Directory.CreateDirectory(path, DirectorySecurity)` overload. The declared
  runtime and successful Gate 4 host are Windows PowerShell 5.1; this is a
  validator-entry host limitation, not evidence of a failed installed runtime.

## Repository and build state

- Protected base and live `origin/master` at gate start:
  `16c3b7faf6fa353afead47cbf02b7e67fc0fa39c`.
- The task branch checkout is the unique writable follow-up worktree for this
  test and documentation repair.
- Task branch: `codex/fix-post-merge-publication-identity`.
- The permanent original workspace, prior protected-install worktree, installed
  plugin, active cache, and Birdsgone worktrees are outside writable scope.
- Frozen repaired build: `0.4.1+codex.20260821104322`. The plugin-creator
  cachebuster helper ran exactly once and must not be rerun.
- Installed payload: `0.4.1+codex.20260821104322` from protected commit
  `16c3b7faf6fa353afead47cbf02b7e67fc0fa39c`; this test/documentation-only
  follow-up does not change any of the 31 installed payload files.
- Task Mail capability is unavailable in this task; coordination is
  advisory-degraded and no Task Mail credential was created.

## Production evidence and safe host state

- The fresh task registry exposed exactly 20 unique callable
  `mcp__hyperv_clean_room__*` tools before any production call.
- Ordered typed admission passed `inspect_host`, `list_vms(managedOnly:false)`,
  and `inspect_vm` for `Birdsgone-W11-HV-20260723`; the managed VM was Off,
  Generation 2, ownership/direct-base chain verified, automatic checkpoints
  disabled, and zero checkpoints.
- The existing credential profile `birdsgone-w11-rc1` must not be recreated,
  inspected on disk, serialized, or transmitted.
- After a freshly confirmed typed Start, `inspect_guest` operation
  `c9334675-1453-4b5c-9fe0-d301f95c33d3` returned `ok=false`,
  `changed=false`, no warnings, and `GUEST_WORKER_FAILED`. It was not retried;
  no guest baseline or checkpoint evidence was accepted.
- The user later confirmed graceful-shutdown plan
  `342559fd-a715-46cf-a3ed-e43b7ce279c9`. Apply operation
  with recorded prefix `e148847c` changed Running to Off. Typed readback operation
  `3fb1ce19-b044-4842-8963-def096d2f06f` confirmed Off, verified ownership
  and direct-base chain, automatic checkpoints disabled, zero checkpoints,
  and no warnings.
- The post-merge closure performed only the fresh ordered read-only admission
  recorded above. Before G8 performs any lifecycle or guest operation, it must
  repeat the required live readback and obtain a fresh typed plan/confirmation.

## Confirmed root cause

- The supervisor reserved stdout for the bounded JSON result but used strict
  UTF-8 `StreamReader.ReadToEndAsync()` for stderr as well.
- Windows PowerShell 5.1 can emit progress CLIXML containing non-UTF-8 bytes on
  stderr. A source-aligned local process probe faulted only the stderr read with
  `System.Text.DecoderFallbackException`; stdout completed normally.
- The fault propagated through the fixed-worker supervisor and was collapsed by
  the outer adapter mapping to the exact observed `GUEST_WORKER_FAILED`.
- `ReadToEndAsync()` also buffered arbitrary stderr before the post-hoc 64 KiB
  check, contradicting the documented bounded-diagnostics contract.
- An in-memory worker test returned valid one-line JSON with exit code zero,
  excluding the prior `$input` collision and worker result construction.

## Repair and changed areas

- `hyperv-clean-room/mcp/lib/Adapters.ps1` adds a raw asynchronous stderr
  drainer with a fixed 4 KiB buffer, saturated 65,536-byte count, overflow bit,
  and continued drain/discard after overflow. It never decodes, accumulates,
  persists, or exposes stderr bytes beyond the transient fixed buffer.
- Stdout remains the only strict UTF-8 JSON result channel and retains its one
  MiB size limit plus operation, invocation, mode, input-hash, and exit-code
  bindings.
- Completed stderr overflow maps to the bounded safe code
  `GUEST_WORKER_DIAGNOSTIC_TOO_LARGE`.
- Before releasing an intentionally surviving launch/UI descendant, the
  supervisor runs the synchronous stderr read on a plugin-owned background
  thread, sets private cancellation state, calls `CancelSynchronousIo` through
  a non-inheritable `THREAD_TERMINATE`-only handle to that exact thread, and
  requires the pending drain to join within two seconds. Only I/O exceptions
  after that request become count-only cancellation; failure preserves job
  containment.
- `tests/gate2-runtime.tests.ps1` covers valid strict-UTF-8 stdout, invalid
  stderr bytes, more than 64 KiB of stderr, exact saturated accounting, the
  minimal public drain-result shape, and a real local anonymous pipe whose
  writer remains open during prompt cancellation.
- `tests/static_quality_tests.py` requires exactly one strict UTF-8 decoder in
  the supervisor and rejects the old stderr `ReadToEndAsync` path.
- `tests/publication_hygiene_tests.py` binds the immediately preceding
  protected input-binding squash commit's GitHub-substituted identity to raw
  commit-object SHA-256
  `cbab88ff332a2c8d1d51d2fdc68bef252748a3f03ce643ef0b13c87a23caf606`;
  accepted identity patterns are not broadened.
- The same validator now recognizes later GitHub-generated protected squash
  commits structurally only when they have one parent, the exact public noreply
  author email, the exact GitHub web-flow committer, a GitHub signature
  envelope, and a bounded `subject (#PR)` message. Every structurally recognized
  GitHub merge or squash then has its signed payload reconstructed from the raw
  commit header and is verified directly with `gpgv` against an exact-SHA-pinned
  official key bundle and separately pinned current signing fingerprint. Policy
  tests reject missing, malformed, invalid, multiple, and unpinned states.
- Architecture, specification, operations, security, troubleshooting,
  installation, release-process, changelog, and this handoff record the repair
  and its source/install/new-task boundaries.
- Build identity changes only in
  `hyperv-clean-room/.codex-plugin/plugin.json`.

Public tool names and inputs, schemas, positional worker requests, credential
profiles, DPAPI behavior, Plan/Apply semantics, evidence semantics, and the
31-file payload topology are unchanged.

## Verification state

- The current post-review fixed-worker regression passed with 1,843 assertions,
  exactly 20 tools, four protocol versions, and `realHyperVMutations=0`. Its
  pending-pipe writer remained open while `CancelSynchronousIo` produced a joined
  `Cancelled: true` result within two seconds; an otherwise identical
  unrequested I/O failure remained a faulted task.
- Pull request #41 produced an actionable review finding that `CreatePipe`
  supplies a synchronous, non-overlapped handle. Microsoft documents
  `CancelSynchronousIo`, not `CancelIoEx`, as the supported cancellation API for
  that operation. The dedicated-thread repair above closes that finding.
- Final Gate 2 passed with `-SkipRealHostSmoke`: five schema-v1 files, strict
  documentation/static checks, isolated dependencies, `realHostOperations=[]`,
  and `realHyperVMutations=0`.
- Final Gate 7 passed with `-SkipInheritedBaseline`: build
  `0.4.1+codex.20260821104322`, exactly 20 tools, 16 v1 tools preserved, five
  v1 schemas, seven v2 schemas, 452 runtime assertions, and zero real host,
  Hyper-V, guest, portable, WebDriver, or UI operations.
- `validate-install-source.ps1 -RequireCachebuster` passed 31 payload files,
  five v1 schemas, seven v2 schemas, zero reparse points, and zero untracked
  payload files. The plugin-creator validator passed from the isolated Python
  environment.
- Documentation validation passed 17 documents and 101 local links with strict
  UTF-8 and zero mojibake markers. Publication hygiene passed all reachable
  commits and historical blob paths, with 29 exact-object identity exceptions,
  all ordinary public-noreply commits, 29 GitHub web-flow merges, one
  structurally accepted GitHub squash, and 30 cryptographically verified
  signatures from pinned
  fingerprint `968479A1AFF927E37D1A566BB5690EEEBB952194`, zero forbidden
  artifacts, and zero sensitive findings. Seventeen policy regressions pass.
- `validate-public-release.ps1` passed all 13 checks with
  `realGuestOperations=0` and `realHyperVMutations=0`.
- Gate 4 installed-copy acceptance and Gate 7 source acceptance passed on the
  supported Windows PowerShell 5.1 host. The dirty follow-up changes only tests
  and documentation, not the installed payload. Production guest acceptance
  remains `notPerformed`; never reinterpret source or installed-copy smoke as
  real-guest proof.
- The post-install H4/G9 lane must run the bounded installed-copy
  `validate-gate4.ps1` readback defined by repository authority. It must not
  manually launch JSON-RPC or call real `inspect_host`/`list_vms` before the
  fresh selected task proves its exact 20-tool typed registry.
- No VM, guest, checkpoint, credential, DPAPI, install, marketplace, or Codex
  state changed during the plugin source gate.

## Required next gates

1. Stage only the intended publication validator, policy tests, documentation,
   changelog, and handoff changes; rerun affected checks after this final
   handoff update and reach `ZERO ACTIONABLE FINDINGS` on the exact candidate.
2. Commit, push, create a Ready PR against protected `master`, reconcile exact
   head/base, reviews, comments, threads, checks, and protection. Merge only
   after separate authorization through the ordinary protected path.
3. Because the follow-up changes no plugin payload bytes, do not reinstall or
   rerun the cachebuster. Confirm the canonical installed copy still matches
   protected payload commit `16c3b7f...`.
4. Continue Birdsgone G8 only after the source/test closure. Immediately before
   any production call, require exactly 20 typed tools, repeat ordered read-only
   admission, obtain fresh confirmation for any Start plan, use only typed
   Plan/Apply/readback, and retry only `inspect_guest` with the existing profile.

## Safety boundaries

- Never use shell, WMI, Hyper-V cmdlets, PowerShell Direct, manual JSON-RPC, or
  another transport as a substitute for typed production tools.
- Never transmit, log, enumerate, or recreate credentials; do not inspect the
  credential profile's files or bytes.
- Do not perform VM/checkpoint/VHDX/host-file deletion, restore, network
  mutation, guest lifecycle, or package/UI work in the plugin source gate.
- Do not modify branch protection, workflows, tags, Releases, remote branch
  history, the plugin source/install bytes before merge, or Birdsgone's
  permanent checkout and user-owned README.
- Do not interleave Birdsgone G8 with this source/test closure. Any later G8
  gate must establish its own fresh 20-tool registry and ordered admission.

## Ownership

- `previousTask: read-only-after-relay`
- `successorTask: owns-next-gate`

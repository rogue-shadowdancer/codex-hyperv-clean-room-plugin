# Task handoff: fixed-worker stderr-drain repair

`relayProtocolVersion: 1`

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

## Objective and authorization

Repair the confirmed production `GUEST_WORKER_FAILED` boundary discovered by
Birdsgone G8, complete local source validation and exact review, publish and
merge through the ordinary protected pull-request path, install the exact
protected commit once, and relay a new G8 task without starting its Hyper-V
work in this source task.

The source gate performs no Hyper-V tool call, VM/checkpoint/network mutation,
credential prompt or persistence, guest operation, package lifecycle, restore,
tag, or GitHub Release. Installation is allowed only after protected merge.

## Repository and build state

- Protected base and live `origin/master` at gate start:
  `39f577a45702cd434fc63ce5fd49ec60f5b8c48c`.
- The task branch checkout is the unique writable worktree for this repair.
- Task branch: `codex/fix-fixed-worker-stderr-drain`.
- The permanent original workspace, prior protected-install worktree, installed
  plugin, active cache, and Birdsgone worktrees are outside writable scope.
- Frozen repaired build: `0.4.1+codex.20260821104322`. The plugin-creator
  cachebuster helper ran exactly once and must not be rerun.
- Installed predecessor: `0.4.1+codex.20260819091500` from protected commit
  `39f577a45702cd434fc63ce5fd49ec60f5b8c48c`.
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
- This repair task performs no further Hyper-V call. The next G8 task must
  establish fresh typed admission from live state.

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
  UTF-8 and zero mojibake markers. Publication hygiene passed 134 commits and
  1,017 historical blob paths with 29 exact-object identity exceptions, zero
  forbidden artifacts, and zero sensitive findings.
- `validate-public-release.ps1` passed all 13 checks with
  `realGuestOperations=0` and `realHyperVMutations=0`.
- Remaining before the additive review-fix commit: rerun the exact candidate
  after this handoff-only update, reach `ZERO ACTIONABLE FINDINGS`, push
  normally, and reconcile every PR conversation and hosted check again.
- Installed-copy and production guest acceptance remain `notPerformed` for the
  dirty source candidate. Never reinterpret source/mock validation as installed
  or real-guest proof.
- The post-install H4/G9 lane must run the bounded installed-copy
  `validate-gate4.ps1` readback defined by repository authority. It must not
  manually launch JSON-RPC or call real `inspect_host`/`list_vms` before the
  fresh selected task proves its exact 20-tool typed registry.
- No VM, guest, checkpoint, credential, DPAPI, install, marketplace, or Codex
  state changed during the plugin source gate.

## Required next gates

1. Complete the remaining local gates on the frozen candidate, stage only the
   intended source, test, manifest, documentation, and handoff changes, and
   reach `ZERO ACTIONABLE FINDINGS` on that exact staged candidate.
2. Commit, push, create a Ready PR against protected `master`, reconcile exact
   head/base, reviews, comments, threads, checks, and protection, then merge
   only through the ordinary protected path.
3. From a clean checkout of the exact merged protected commit, run
   `scripts/install_plugin.ps1` exactly once. Verify installed, marketplace,
   and active-cache identity plus the complete 31-file size/SHA-256 match.
4. Create a fresh Birdsgone G8 task. Before any Hyper-V call, its selected model
   must expose exactly 20 typed `mcp__hyperv_clean_room__*` tools. It then reruns
   ordered read-only admission, obtains fresh confirmation for any Start plan,
   starts only through typed Plan/Apply/readback, and retries only
   `inspect_guest` with the existing credential profile.

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
- Do not resume Birdsgone G8 in this source task after the protected reinstall;
  the new task must establish its own 20-tool registry and fresh admission.

## Ownership

- `previousTask: read-only-after-relay`
- `successorTask: owns-next-gate`

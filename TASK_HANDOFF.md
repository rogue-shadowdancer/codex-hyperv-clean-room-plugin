# Task handoff: fixed-worker input-binding repair

`relayProtocolVersion: 1`

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

## Objective and authorization

Repair the production guest-worker failure discovered during Birdsgone G8,
where PowerShell bound a function parameter named `$Input` to the
case-insensitive automatic `$input` enumerator instead of the validated request
object. Complete source validation, exact staged review, ordinary protected PR
publication, one installation from the exact merged protected commit, and a
fresh-task registry readback before resuming G8.

This source gate performs no Hyper-V tool call, VM/checkpoint/network mutation,
credential prompt or persistence, guest operation, package lifecycle, restore,
tag, or GitHub Release. Installation is allowed only after protected merge.

## Repository and build state

- Protected base and live `origin/master` at gate start:
  `239bf252735b6195ddc4f27fdd531bc13e9e1272`.
- Task branch: `codex/fix-fixed-worker-input-binding`.
- The current task worktree is the unique writable checkout for this repair.
- The permanent original workspace, installed protected checkout, active
  plugin cache, and retained historical worktrees are outside writable scope.
- Frozen repaired build: `0.4.1+codex.20260819091500`. The plugin-creator
  cachebuster helper ran exactly once and must not be rerun.
- Installed predecessor: `0.4.1+codex.20260819075913` from protected commit
  `239bf252735b6195ddc4f27fdd531bc13e9e1272`.
- Task Mail capability is unavailable in this task; coordination remains
  advisory-degraded and no credential was created for it.

## Production evidence and safe host state

- The Birdsgone credential profile `birdsgone-w11-rc1` was successfully
  initialized interactively by the user and must not be recreated, inspected
  on disk, serialized, or transmitted.
- A typed `inspect_guest` attempt for
  `Birdsgone-W11-HV-20260723` returned operation
  `281e100b-b2a8-40b2-90f4-0831bae0e6eb`, `ok=false`, `changed=false`, and
  `GUEST_WORKER_INPUT_INVALID`; no guest baseline was accepted.
- Minimal probes in both Windows PowerShell 5.1 and PowerShell 7 showed a
  parameter named `$Input` receiving
  `System.Collections.ArrayList+ArrayListEnumeratorSimple` with a null schema
  version.
- The user confirmed graceful-shutdown plan
  `f149449f-d779-41df-aefe-89a71c12f897`. Apply operation
  `821d3250-74ee-4069-b502-cb9cfcb03f7e` changed the VM from Running to Off;
  readback operation `9f7c22eb-a3c3-4d92-8887-b9b1502371a5` confirmed Off,
  Generation 2, verified ownership/direct-base chain, automatic checkpoints
  disabled, and zero checkpoints.

## Repair and changed areas

- `Invoke-HcrFixedGuestWorker` and every fixed-worker helper now bind the
  internal request through `$WorkerInput`; public JSON property names, tool
  schemas, positional call order, and result envelopes are unchanged.
- Gate 2 parses the supervisor and worker ASTs and rejects any production
  parameter whose name equals `Input` case-insensitively.
- Gate 7 static coverage follows the renamed internal symbol.
- Publication hygiene records the immediately preceding protected squash
  commit by its exact raw-object SHA-256 because GitHub retained the approved
  public noreply address while substituting the account display name and
  web-flow committer; accepted identity patterns are not broadened.
- Architecture, specification, operations, security, troubleshooting,
  installation, release-process, changelog, and this handoff document the
  failure mode and repair boundary.
- Build identity changed only in
  `hyperv-clean-room/.codex-plugin/plugin.json`.

Public tool names/inputs, schemas, Plan/Apply behavior, credential-profile
shape, evidence semantics, and the 31-file payload topology are unchanged.

## Verification state

- Windows PowerShell 5.1 parser passed all 44 tracked/untracked PowerShell
  files with zero parse errors.
- `validate-install-source.ps1 -RequireCachebuster` passed build
  `0.4.1+codex.20260819091500`: 31 payload files, five schema-v1 files, seven
  schema-v2 files, zero reparse points, and zero untracked payload files.
- The plugin-creator validator passed from the repository's isolated Python
  environment.
- Final Gate 2 passed with `-SkipRealHostSmoke`, strict documentation/static
  checks, `realHostOperations=[]`, and `realHyperVMutations=0`.
- Final Gate 7 passed with `-SkipInheritedBaseline`: exactly 20 tools, 16 v1
  tools preserved, five v1 schemas, seven v2 schemas, 452 runtime assertions,
  and zero real host, Hyper-V, guest, portable, WebDriver, or UI operations.
- Publication hygiene passed across 133 commits and 1,002 historical blob
  paths with zero forbidden artifacts or sensitive findings.
- `validate-public-release.ps1` passed all 13 checks with
  `realGuestOperations=0` and `realHyperVMutations=0`.
- Installed-copy H4/G9 acceptance remains `notPerformed` for this dirty source
  candidate. After the protected reinstall, run the bounded
  `validate-gate4.ps1`/installed-copy readback from that exact protected commit;
  do not reinterpret source/mock validation as installed or real-guest proof.
- No VM, guest, checkpoint, credential, DPAPI, install, marketplace, or Codex
  state changed during the plugin source gate.
- The frozen candidate now requires only exact staged review, commit/push,
  protected PR/readback, ordinary merge, and one protected-source installation.

## Required next gates

1. Stage only the intended source, test, manifest, documentation, and handoff
   changes; reach `ZERO ACTIONABLE FINDINGS` on the exact staged candidate.
2. Commit, push, create a Ready PR against protected `master`, reconcile the
   exact head/base, reviews, comments, threads, checks, and protection, then
   merge only through the ordinary protected path.
3. From the exact merged protected commit, run the installer exactly once and
   verify installed, marketplace, and active-cache identity plus the complete
   31-file size/SHA payload match.
4. Create a fresh Birdsgone G8 task. The fresh selected model must expose
   exactly 20 typed `mcp__hyperv_clean_room__*` tools before any Hyper-V call.
   It must then rerun ordered read-only admission, obtain fresh confirmation
   for any new Start plan, start the Off VM through typed Plan/Apply/readback,
   and retry only `inspect_guest` with the existing credential profile.

## Safety boundaries

- Never use shell, WMI, Hyper-V cmdlets, PowerShell Direct, or manual JSON-RPC
  as a substitute for typed production tools.
- Never transmit, log, enumerate, or recreate credentials; do not inspect the
  credential profile's files or bytes.
- Do not perform VM/checkpoint/VHDX/host-file deletion, restore, network
  mutation, guest lifecycle, or package/UI work in the plugin source gate.
- Do not modify branch protection, workflows, tags, Releases, remote branches,
  the plugin source/install bytes before merge, or the Birdsgone primary
  checkout and its user-owned README.
- Do not continue Birdsgone G8 in the old task after the protected reinstall;
  the new task must establish its own 20-tool registry and fresh admission.

## Ownership

- `previousTask: read-only-after-relay`
- `successorTask: owns-next-gate`

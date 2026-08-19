# Task handoff: Windows PowerShell credential-module bootstrap repair

`relayProtocolVersion: 1`

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

## Objective and authorization

Repair the Birdsgone G8 interactive credential-initializer blocker caused by a
PowerShell 7/Codex parent leaking its module path into a Windows PowerShell 5.1
child launched through `Start-Process`. Complete source validation, exact
review, ordinary protected publication, exact protected installation, and a
fresh-tool-catalog readback before returning to the separately confirmed G8
credential retry.

The source repair performs no Hyper-V tool call, VM/checkpoint/network change,
credential prompt or persistence, guest operation, package lifecycle, tag, or
GitHub Release. Installation is allowed only from the merged protected commit.

## Repository and build state

- Protected base and live `origin/master` at Gate start:
  `6c46b52a669c05527c7d408f5c30fc9995577fe7`.
- Task branch: `codex/fix-winps51-modulepath`.
- The current task worktree is the unique writable repository checkout.
- The permanent original workspace and retained historical worktrees are not
  writable scope for this repair.
- Frozen repaired build: `0.4.1+codex.20260819075913`. The plugin-creator
  cachebuster helper ran exactly once and must not be rerun.
- Installed predecessor: `0.4.1+codex.20260814082037` from protected commit
  `6c46b52a669c05527c7d408f5c30fc9995577fe7`.
- Task Mail is `credential_state_missing`; Agent Mail remains advisory.

## Reproduced defect and repair

The current Codex command host is PowerShell 7.6.4. Directly invoking
`powershell.exe` produced only the in-box Security `3.0.0.0` candidate, but
`Start-Process` preserved the Codex PowerShell 7 module directory. Windows
PowerShell then saw the incompatible Security `7.0.0.0` before its own
`3.0.0.0`, causing duplicate `ObjectSecurity` type members,
`FormatXmlUpdateException`, and `CouldNotAutoloadMatchingModule` before the
first `Get-Credential` dialog.

The initializer now fails closed unless it is running under Windows PowerShell
5.1. Before any plugin dot-source, module command, VM lookup, or credential
prompt, it replaces only its process `PSModulePath` with the standard
WindowsPowerShell user, all-users, and `$PSHOME` locations. It imports the
in-box Security manifest by exact `$PSHOME` path and verifies that the actual
`Get-Credential` cmdlet is bound to that path. It does not write persistent
environment, registry, marketplace, or Codex state.

## Changed areas

- Runtime: `hyperv-clean-room/mcp/Initialize-GuestCredential.ps1`.
- Tests: contaminated higher-version Security candidate child-process
  regression in `tests/gate2-runtime.tests.ps1`, plus static seam coverage.
- Documentation: changelog, specification, operations, security,
  troubleshooting, release process, and this handoff.
- Build identity: `hyperv-clean-room/.codex-plugin/plugin.json` only.

Public tool names/inputs, schemas, Plan/Apply behavior, DPAPI profile shape,
guest adapter, evidence semantics, and the 31-file payload topology are
unchanged.

## Verification completed before final staging

- Windows PowerShell 5.1 parser: changed PowerShell sources and tests have zero
  parse errors.
- Gate 2 runtime: 1,824 assertions, exactly 20 tools, zero real Hyper-V
  mutations. The regression exposed a foreign `99.0.0.0` Security candidate,
  removed it from the child path, bound the system `3.0.0.0` module, and left
  user/machine environment state untouched.
- `validate-gate2.ps1 -SkipRealHostSmoke`: passed schemas, fixtures, semantic
  checks, runtime, documentation, and isolated static checks; real-host
  operations `[]`, real Hyper-V mutations `0`.
- No VM, guest, checkpoint, credential, DPAPI, install, marketplace, or Codex
  state changed during source repair.

Historical H4/G9 installed-copy acceptance does not apply to the dirty source
candidate and remains `notPerformed`. After the protected merge and exact
installation, run the bounded `validate-gate4.ps1`/installed-copy checks from
that protected commit; do not reinterpret the current mock/source gate as
installed or real-guest evidence.

## Next ordered gates

1. Run exact install-source/plugin validation, final impact-scoped checks, and
   an exact-staged review to `ZERO ACTIONABLE FINDINGS`; rerun affected checks
   after any edit.
2. Commit and push the frozen branch, open one ordinary protected PR to
   `master`, reconcile reviews/checks, and merge only through branch
   protection. Do not regenerate the build.
3. From exact merged protected `master`, run `check_install.ps1`, one
   `install_plugin.ps1`, and post-install readback. Require 31 exact payloads,
   matching source/build/cachebuster, one marketplace entry, and installed /
   enabled state.
4. Start a fresh Codex task and require exactly 20
   `mcp__hyperv_clean_room__*` tools before any production call. Reinspect host
   and VM. Only after a new exact plan/confirmation may the fixed initializer
   retry profile `birdsgone-w11-rc1` for VM
   `Birdsgone-W11-HV-20260723`.

`blockers: []`

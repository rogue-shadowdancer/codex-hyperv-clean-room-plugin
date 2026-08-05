# Task handoff: v0.4.1 Windows MCP `COMPUTERNAME` compatibility repair

`relayProtocolVersion: 1`

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

## Objective and authority

Repair the Windows Codex MCP child environment so Hyper-V PowerShell receives a
usable machine name, while preserving plugin/server base version `0.4.1`, all
31 payload paths, exactly 20 public tools, every schema/envelope/error contract,
and every adapter and Plan/Apply boundary. Publish the exact reviewed candidate
through one ordinary protected pull request and merge it only when all required
exact-head checks, reviews, protection, mergeability, and the fresh 30-minute
window remain satisfied.

This Gate does not install the plugin, enter Gate C, call `inspect_vm`, execute
Plan/Apply, mutate Hyper-V, touch a guest or credential, create evidence, tag,
publish a Release, deploy, force/direct push, or delete a branch.

- Exact protected base: `837ef934c8de6958a79a415f8e6d55016de54264`.
- Base tree: `07fff89642f338edaae22908e90ece196dfc07be`.
- Task branch: `codex/v041-computername-repair`.
- This worktree is the sole writer. The saved primary checkout and all other
  Hyper-V clean-room/Birdsgone worktrees remain read-only.
- Task Mail credential state is `credential_state_missing`; no predecessor
  identity was created, reused, or impersonated.

## Root cause and repair

The original diagnosis proved that a Codex parent could retain
`COMPUTERNAME=ROGUE-PC` while its bound Windows MCP child omitted the variable.
In Windows PowerShell 5.1, removing `COMPUTERNAME` reproduced both `Get-VM` and
`Get-VMSwitch` failures with a null `name` parameter; restoring only the process
value from `[Environment]::MachineName` made both commands succeed. A fresh
exact installed child succeeded, excluding VMMS, Hyper-V authorization,
installed bytes, projection, and VM data as the primary cause.

The candidate applies two compatible defenses:

- `hyperv-clean-room/.mcp.json` still declares exactly one server and now has
  only `env_vars: ["COMPUTERNAME"]`. It contains no environment literal and no
  other environment variable.
- At the start of `Initialize-HcrRuntime`, before plugin-root, adapter, or state
  initialization, a missing or whitespace process value is set from
  `[Environment]::MachineName`. A non-empty explicit value is preserved.

The fallback changes only the MCP child process. It does not write user/system
environment state, the registry, `config.toml`, marketplace data, installed
payloads, logs, public tool input, envelopes, errors, or adapter behavior.

## Regression coverage

- Contract: parse `.mcp.json`, require the sole `hyperv-clean-room` server,
  exact launch fields, and exactly one `COMPUTERNAME` pass-through.
- Runtime environment: prove missing and whitespace values repair to
  `[Environment]::MachineName` and an explicit non-empty value is preserved.
- MCP protocol: launch a PowerShell 5.1 mock MCP child with `COMPUTERNAME`
  removed, complete initialization, list all 20 tools, and call the unchanged
  mock `inspect_host`/`list_vms` path without stderr or contract drift.
- Real host: remove `COMPUTERNAME`, initialize the production adapter, call only
  `inspect_host` and `list_vms(managedOnly=false)`, require successful
  `changed=false` envelopes with no mock warning, and report
  `realHyperVMutations=0` and `realGuestOperations=0`.

The real-host lane is source repair evidence only. It is not installed-plugin
or Gate C acceptance and authorizes no retry, alternate transport,
`inspect_vm`, Plan/Apply, guest, credential, or evidence action.

## Build and documentation

The plugin-creator cachebuster helper was invoked exactly once in this Gate.
The only repair build is `0.4.1+codex.20260805101924`; do not invoke the helper
again during review, merge, installation, tagging, or Release.

README/CHANGELOG, specification, installation, maintenance, operations,
troubleshooting, release-process, documentation-center, and this handoff now
describe the process-only fallback, regression evidence, unchanged public
contract, and later install/Gate C boundary. Historical v0.1.1 through v0.4.0
tags and Releases remain unchanged.

## Local verification

The candidate passes on 2026-08-05:

- plugin-creator `validate_plugin.py` with the prepared pinned dependency set;
- `tests/gate1-contract.tests.ps1`;
- `tests/gate2-runtime.tests.ps1`: 1,692 assertions, 20 tools, four protocol
  versions, missing-environment MCP session, and `realHyperVMutations=0`;
- `tests/gate2-real-readonly.tests.ps1`: `computerNameRepair=passed`, only
  `inspect_host` plus `list_vms managedOnly=false`, zero guest operations, and
  zero Hyper-V mutations;
- `scripts/validate-gate2.ps1`: schema/static/runtime suites plus the authorized
  real-host lane, zero Hyper-V mutations;
- `tests/gate4-installation.tests.ps1`: 45 assertions and 31 source payloads;
- `scripts/validate-install-source.ps1 -RequireCachebuster`: 31 payloads, five
  v1 schemas, seven v2 schemas, one suffix, and no untracked payload;
- `scripts/validate-gate6.ps1 -SkipInheritedBaseline`: 20 target tools, seven
  v2 schemas, 19 dynamic checks, and zero real/guest/portable operations;
- `scripts/validate-gate7.ps1 -SkipInheritedBaseline`: repair build, 20 tools,
  388 runtime assertions, ten evidence validations, and zero real operations;
- `scripts/validate-docs.ps1`: 17 documents, 102 local links, strict UTF-8,
  and zero mojibake markers;
- `scripts/validate-gate4-ci.ps1`: 31 payloads, 45 installer assertions, and
  zero install, marketplace, installed-copy, host, guest, or mutation actions;
- `scripts/validate-public-release.ps1`: all 13 aggregate checks passed with
  `realGuestOperations=0` and `realHyperVMutations=0`.

Historical H4/G9 installed-copy acceptance through
`scripts/validate-gate4.ps1` is `notPerformed` in this source repair Gate. That
workflow requires an exact installed payload and includes installed-copy host
probing, so it belongs to the separately relayed post-merge installation Gate;
it is not evidence for this candidate and was not substituted by another
transport.

The read-only installed-state check found an owned prior candidate at
`0.4.1+codex.20260804074002`, source commit
`837ef934c8de6958a79a415f8e6d55016de54264`, with one marketplace entry. It
correctly reports `matches=false` against the repair build and currently reports
`marketplaceVisible=false`. No installed or marketplace state was changed.
This drift is deferred to the post-merge installation Gate.

## Publication and next Gate

Before publication, stage only the intended source/test/document files, require
`git diff --cached --check`, and complete a substantive exact-staged review with
`ZERO ACTIONABLE FINDINGS`. Any candidate change resets affected validation and
review. Publish one ordinary non-draft PR against protected `master`, require
exact local/remote head equality, required checks, resolved review threads,
clean mergeability/protection, and one fresh full 30-minute unchanged-head
review window. Merge only through the ordinary protected PR path when every
condition still holds.

After a successful merge, read protected `master` back exactly and relay a new
task whose only Gate is installation of this frozen build from that exact
protected commit. The installation task must validate all 31 payload hashes,
source/installed version and commit, cachebuster, one marketplace entry, and
installed/enabled state, but must not call any production Hyper-V tool. Gate C
remains a later separate authorization.

`blockers: []`

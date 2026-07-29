# Task handoff: G7/P3.3-R1 v0.3.1 selected-plugin recovery

`relayProtocolVersion: 1`

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

## Objective

Publish the compatible Hyper-V Clean Room `v0.3.1` patch from one protected
commit, install the precommitted personal build from that same commit, and
prove the exact 20-tool catalog through a genuinely selected fresh Codex
thread. This gate performs no real Hyper-V or package operation.

## Why the recovery exists

The immutable `v0.3.0` annotated tag peels to
`47151fdbe99346ec87af09460c79d0864978eabd`, while the later protected
closeout/install source is
`fb4b130462752eb3a578642f631d4279007a67d8`. That historical split is retained
truthfully and does not satisfy a same-commit publication/install gate.

The earlier fresh task also supplied only raw prompt text, not an actual plugin
selection. A real `selectedCapabilityRoots` probe then identified the concrete
runtime defect: current Codex supplies MCP-standard `tools/list` parameters
and v0.3.0 rejected them with `-32602 Invalid tools-list parameters`.

## Candidate changes

- Runtime and installed evidence base advance to `0.3.1`; the frozen capability
  target remains `0.3.0`.
- `tools/list` accepts optional object `_meta` and optional string-or-null
  `cursor`; unknown or mistyped parameters still fail closed.
- `scripts/validate-codex-app-server-catalog.ps1` launches an isolated Codex
  app-server client. It selects `hyperv-clean-room@personal` in environment
  `local`, reads thread-scoped `mcpServerStatus/list`, and requires exactly 20
  unique tools.
- The validator sends no `turn/start` and no `mcpServer/tool/call`.
- The plugin-creator cachebuster helper was invoked exactly once. The only
  build is `0.3.1+codex.20260729184240`; do not run the helper again.

## Release invariant

The gate closes only when:

`protected master SHA = annotated v0.3.1 peeled SHA = Release tag target = install-manifest sourceCommit`

All release/process/status text is already part of the candidate. Do not add a
post-tag closeout commit. Publish one non-draft, non-prerelease, source-only
Release with zero uploaded assets. Preserve immutable `v0.1.1`, `v0.2.0`, and
`v0.3.0` tags and Releases.

## Required verification

Before commit and again on the exact protected candidate as applicable:

```powershell
.\scripts\prepare-test-python.ps1
.\scripts\validate-docs.ps1
python -S .\tests\publication_hygiene_policy_tests.py
python -S .\tests\publication_hygiene_tests.py
python -S .\tests\public_release_contract_tests.py
.\scripts\validate-gate4-ci.ps1
.\scripts\validate-gate7.ps1 -SkipInheritedBaseline
.\scripts\validate-install-source.ps1 -RequireCachebuster
.\scripts\validate-codex-app-server-catalog.ps1 `
  -PluginRoot .\hyperv-clean-room -ExpectedVersion 0.3.1
```

After protected merge, tag/Release publication, and same-commit install:

```powershell
.\scripts\check_install.ps1
.\scripts\validate-codex-app-server-catalog.ps1 `
  -PluginRoot "$HOME\plugins\hyperv-clean-room" -ExpectedVersion 0.3.1
.\scripts\validate-public-release.ps1
.\scripts\validate-public-github-settings.ps1
.\scripts\validate-v031-release-readback.ps1 `
  -ExpectedMasterCommit <protected-master-sha>
```

The final readback fails closed unless protected `master`, the annotated
`v0.3.1` peeled commit, the Release target, and installed `sourceCommit` are
identical. It also rechecks the immutable v0.1.1, v0.2.0, and v0.3.0 tag
objects, peeled commits, Release identities, flags, and zero-asset state.
`ExpectedMasterCommit` is mandatory, the installed version must equal the
single frozen build `0.3.1+codex.20260729184240`, and the check revalidates
every payload path, size, SHA-256 value, ownership marker, and install manifest
against that reviewed source checkout. The checkout itself must have
`HEAD == ExpectedMasterCommit` and no staged, tracked-worktree, or untracked
change under `hyperv-clean-room/`; assume-unchanged and skip-worktree index
flags are also forbidden on that source. All source identity and inventory Git
reads run with replacement objects disabled.

The historical H4/G9 `validate-gate4.ps1` installed-copy smoke calls
`inspect_host` and a missing-ISO plan. It is not part of this recovery gate and
remains `notPerformed`.

## Safety boundary

- Do not call `inspect_host` or any of the 20 MCP tools.
- Do not execute a real host, Hyper-V, VM, checkpoint, credential, guest,
  package, portable, WebDriver, network, UI, evidence, or manual-attestation
  operation.
- Mock/parser/schema/static tests remain allowed and must report zero real
  operations.
- Do not modify installed state until the protected v0.3.1 commit and annotated
  tag/Release exist.
- Do not begin Birdsgone G8 before Birdsgone protected main records this G7
  result.

## Next gate

After the plugin release and installed readback pass, update the existing
Birdsgone G7 PR with exact v0.3.1 identities, merge it through protection, and
atomically relay G8. No real-operation gate is implicitly authorized here.

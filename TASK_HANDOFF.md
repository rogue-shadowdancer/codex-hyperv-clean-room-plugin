# Task handoff: G7/P3.3-R2 v0.3.2 tool-call metadata repair

`relayProtocolVersion: 1`

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

## Objective

Publish the compatible Hyper-V Clean Room `v0.3.2` patch from one protected
commit, install the precommitted personal build from that same commit, and
prove both the default 20-tool selected catalog and an isolated selected-child
mock tool-call path. This gate does not perform the external production typed
read-only smoke or any real Hyper-V mutation.

## Root cause and source repair

Current Codex sends MCP-standard object `_meta` on `tools/call`. The v0.3.1
server allowed only outer `name` and `arguments`, so valid `inspect_host` and
`list_vms` requests failed with JSON-RPC `-32602` before tool schema validation
or adapter dispatch.

The v0.3.2 server:

- accepts only required string `name`, optional object `arguments`, and
  optional object `_meta`;
- rejects scalar, array, or null `_meta`, mistyped `arguments`, and every
  unknown outer field with `-32602`; and
- discards `_meta` after transport validation so only `arguments` reach the
  tool schema and dispatcher.

The exact 20 tool names and input schemas, schema-v1 behavior, v2 Plan/Apply
guards, and all production adapter boundaries remain unchanged. The capability
target remains `0.3.0`; current runtime/generated provenance advances to
`0.3.2`, while matching v0.3.0 and v0.3.1 external evidence remains readable.

## Selected app-server validation

`scripts/validate-codex-app-server-catalog.ps1` remains catalog-only by default:
it selects `hyperv-clean-room@personal` in an isolated ephemeral Codex home,
requires server `hyperv-clean-room` / `0.3.2` and exactly 20 unique tools, and
reports `toolCallCount: 0`.

Explicit `-MockToolCallSmoke` copies the selected plugin into the isolated
home and launches it through a child-local wrapper that sets:

- `HCR_TEST_MODE=1`;
- `HCR_ADAPTER_MODE=mock`;
- an isolated mock adapter state path; and
- isolated state and credential roots.

It calls `inspect_host` first and requires `ok=true`, `changed=false`, mock host
identity, and the mandatory `TEST_ONLY_MOCK_ADAPTER` warning before sending
`list_vms(managedOnly=false)`. The second call must meet the same envelope and
warning conditions and return the empty mock inventory. The result reports two
mock adapter operations and zero real-operation, Hyper-V-mutation, and guest
operation counts.

## Safety deviation

The first source-iteration app-server harness attempt set mock variables on the
app-server parent only. Codex did not pass them to the selected MCP child, so
one unintended production `inspect_host` call occurred. Its returned envelope
was successful with `changed=false`; no mutation occurred. The harness stopped
before `list_vms`.

This result is recorded separately and is not acceptance evidence, does not
satisfy the external production typed read-only smoke, and authorizes no later
real adapter call. The corrected child-local mock harness passed before
development continued. No production `list_vms` call and no further real
adapter call belongs to this source/release gate.

## Version and release invariant

The plugin-creator cachebuster helper was invoked exactly once. The only build
is `0.3.2+codex.20260731014242`; do not run the helper again.

The gate closes only when:

`protected master SHA = annotated v0.3.2 peeled SHA = Release tag target = install-manifest sourceCommit`

Publish one non-draft, non-prerelease, source-only `v0.3.2` Release with zero
uploaded assets. Preserve the exact immutable v0.1.1, v0.2.0, v0.3.0, and
v0.3.1 tag objects, peeled commits, Release identities, flags, timestamps, and
zero-asset state. Do not add a post-tag closeout commit.

## Required verification

Before commit and on the exact protected candidate as applicable:

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
  -PluginRoot .\hyperv-clean-room -ExpectedVersion 0.3.2
.\scripts\validate-codex-app-server-catalog.ps1 `
  -PluginRoot .\hyperv-clean-room -ExpectedVersion 0.3.2 `
  -MockToolCallSmoke
```

The exact staged candidate must receive a substantive source/diff/test/scope
review with ZERO ACTIONABLE FINDINGS. After push, the exact unchanged head must
pass `public-release-validation`, have all review conversations resolved, and
complete the required fresh review window before a normal protected merge.

After protected merge, tag/Release publication, and same-commit install:

```powershell
.\scripts\check_install.ps1
.\scripts\validate-codex-app-server-catalog.ps1 `
  -PluginRoot "$HOME\plugins\hyperv-clean-room" -ExpectedVersion 0.3.2
.\scripts\validate-codex-app-server-catalog.ps1 `
  -PluginRoot "$HOME\plugins\hyperv-clean-room" -ExpectedVersion 0.3.2 `
  -MockToolCallSmoke
.\scripts\validate-public-release.ps1
.\scripts\validate-public-github-settings.ps1
.\scripts\validate-v032-release-readback.ps1 `
  -ExpectedMasterCommit <protected-master-sha>
```

The v0.3.2 readback is non-mutating and requires a clean checkout at the exact
protected commit, no assume-unchanged or skip-worktree flags, replacement
objects disabled for Git identity/inventory reads, byte identity between each
working payload and reviewed blob after only the frozen PowerShell LF-to-CRLF
checkout transform, 31 payloads plus two installer records, one canonical
personal marketplace entry, installed/enabled Codex state, and the single
frozen build.

## Verification completed before exact-candidate staging

- Strict documentation validation: 17 documents, 100 local links, strict UTF-8,
  zero mojibake markers.
- Gate 1.1: source version `0.3.2+codex.20260731014242`, five v1 schemas,
  42 PowerShell payload files, no mutation.
- Gate 2 mock stdio/runtime: 1,309 assertions, 20 tools, four protocol versions,
  zero real Hyper-V mutations.
- Gate 7: 358 runtime assertions, 16 preserved v1 tools, five preserved v1
  schemas, seven installed v2 schemas, ten generated evidence documents, and
  zero real host, Hyper-V, guest, portable, WebDriver, or UI operations.
- Selected app-server default: 20 observed/unique tools and
  `toolCallCount=0`.
- Selected app-server explicit mock: two tool calls, two mock adapter
  operations, both `changed=false` with mandatory test-only warnings, and zero
  real adapter/operation/Hyper-V-mutation/guest counts.
- Public-release contract validation passed with runtime `0.3.2`, 20 tools,
  five v1 schemas, seven v2 schemas, and preserved protected-branch contract.

## Safety boundary

- Do not perform the fresh external production typed read-only smoke in this
  gate.
- Do not execute any further real adapter, host, Hyper-V, VM, checkpoint,
  credential, guest, package, portable, WebDriver, network, UI, evidence, or
  manual-attestation operation.
- Mock/parser/schema/static tests remain allowed and never count as real
  evidence.
- The historical H4/G9 `.\scripts\validate-gate4.ps1` production-adapter smoke
  remains `notPerformed`; it is not part of this repair gate.
- Do not modify installed state until the protected v0.3.2 commit and annotated
  tag/Release exist.
- Do not force-push, rewrite history, weaken protection, delete branches, move
  tags, or upload Release assets.

## Changed areas

- MCP stdio outer request validation and regressions.
- Selected Codex app-server catalog/mock validation.
- Compatible runtime provenance/schema assertions.
- v0.3.2 build, source/install/release readback, documentation, and release
  records.

## Blockers

None at source-candidate preparation time.

## Next gate

After exact protected publication/install/readback succeeds, relay exact
protected SHA, tag object/peeled SHA, Release URL, build, install manifest and
payload identities, 20-tool catalog, mock-call counts, CI/review/protection,
and the separately recorded safety deviation to a fresh external production
typed read-only smoke task. That task must obtain its own authorization and
must not infer any Hyper-V mutation authority from this release.

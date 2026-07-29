# Task handoff: G7/P3.1 Hyper-V Clean Room 0.3 contract freeze

`relayProtocolVersion: 1`

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

## Status

P3.1 freezes the schema, compatibility, fixture, and documentation target for
plugin base version `0.3.0`. Runtime, installed copies, personal installation,
and the latest immutable plugin Release remain `0.2.0`. P3.2 implementation
and P3.3 source Release/install/readback remain separate atomic gates.

This gate consumes only protected Birdsgone source results. It performs no
Hyper-V, VM, checkpoint, guest, credential, package lifecycle, driver,
network, UI, manual-attestation, installation, tag, or Release operation.

## Protected upstream authority

- Birdsgone protected `main`:
  `5eba3c60e4b95fa461a39adb9d9c1dfb066ce15c`
- Protected tree:
  `dbe98a0b0621353ed09cebff79d7cde64145881d`
- G6.2 reviewed PR candidate:
  `1b616aab0c996ae643a254df352ae9216d919c25`
- G6.2 protected merge:
  PR #22, rebase-merged as the protected `main` commit above
- G6.1 amendment candidate:
  `4ea9de2627f52a47506416b8f71da1932081a184`
- G6.1 protected merge:
  PR #21, rebase-merged as
  `f3f54181769a6187eb9d584fbd2599561319d8f9`
- Consumer contract:
  - path: `docs/gates/hyperv-clean-room-0.3-contract.md`
  - blob: `e2202a8de07cc90d6b31389853437e9fa025843a`
  - bytes: `37610`
  - SHA-256:
    `489555e9bb0365160fb61aa4964e826405afadcec6345220178d65fc45d9102b`
- End-user distribution contract:
  - path: `docs/release/end-user-distribution-contract.json`
  - blob: `65f6559b5275a5f7bb26d66caaf67c6968749980`
  - bytes: `14330`
  - SHA-256:
    `dcb70fbf91155d4db25813458043d30255c2189ce8d8861a49fb05b0105f1bcb`

The earlier `00643a13` / `runtime-and-legal-only` G6 result remains historical
evidence only. It does not satisfy an executable external profile, a
release-ready candidate, or a clean-room pass.

## G6.2 package-local source result

Protected G6.2 verification passed twice with the system unchanged, zero
install side effects, and zero residual owned processes. Hosted CI remained
`notPerformed` because `ci:capacity` was
`unknown/billing-api-unavailable`.

The protected four-asset set is:

| Asset | Bytes | SHA-256 |
| --- | ---: | --- |
| `Birdsgone_0.1.0_windows-x64-portable.zip` | `344467332` | `4f1028a6ce1dd15b13cc1583dbac1f7cb0ff0b4da6993eeb9f8c1ab0016b4f66` |
| `portable-manifest.json` | `141840` | `0f141d12bcfe92a9017a3e19e905214c0e4d9f9c19e0ae485909984fb654f886` |
| `SBOM.cdx.json` | `445475` | `aee22775cf2e5bd7902222e4cf3ed6c47b6c3673d88e378e176ea7cb82848e71` |
| `SHA256SUMS` | `276` | `91dd656b357488f55c33c0e6952f04dd3267a1c62eb747b320d527b9019d3561` |

This is package-local source evidence. Hyper-V/VM, install/uninstall, ADB,
Win32, LAN, signing, tag, and GitHub Release remain `notPerformed`. Do not
reinterpret G6.2 as clean-room or guest evidence.

## P3.1 conclusions

- Exact public tool count remains `20`; every tool name and input is unchanged.
- The original 16 schema-v1 tools and all five public v1 schema files remain
  compatible and byte-identical.
- All seven schema-v2 paths and `$id` values remain stable.
- Exact integer `schemaVersion` dispatch remains fail-closed; unknown versions
  never fall back.
- The embedded portable profile/manifest/evidence branch retains its `0.2.0`
  semantics, fixed `--portable` argument, and mandatory fixed-component/driver
  behavior.
- External profile artifacts require:
  - `portableManifestSource: externalProfileRelative`
  - a safe profile-relative manifest path
  - bounded manifest size and exact SHA-256
  - `requiredDistributionBoundary: end-user-complete`
- External manifests dispatch between two closed branches:
  - `runtime-and-legal-only` is schema-readable historical evidence only and
    cannot back a new executable profile.
  - `end-user-complete` is the only executable branch and requires complete
    ZIP inventory, source-to-ZIP documentation mapping, source commit/tree,
    documentation count/bytes/digest, and retained runtime/legal digests.
- The protected completeness inventory freezes:
  - all tracked regular files below `docs/`
  - six exact root mappings
  - `62` documentation files
  - `1371442` documentation bytes
  - documentation digest
    `dbd8e7fcc1b8222ccc53a94c8ce9a320e766650e05da5a50e3cdbc81499769fc`
  - twelve required user manuals grouped into seven topics
  - fourteen complete non-developer prerequisites
  - exactly four manual distribution assets, with manifest/SBOM/SHA256SUMS
    remaining external companions
- Generic non-UI external packages may omit MaaFramework, WebView2,
  EdgeDriver, and UI steps. UI profiles retain the closed `data-testid` DSL
  and fixed Microsoft x64 EdgeDriver identity/version rules.
- External evidence structurally uses `evidenceKind: externalPortable` and
  binds the required end-user boundary, ZIP/manifest source and guest
  identities, documentation source/inventory identity, retained runtime/legal
  digests, fixtures, deployment/data, conditional driver, Plan/Apply,
  recovery, assertions, cleanup, and status derivation.
- Fixtures remain synthetic. They contain no real asset identity, local
  machine path, OCR data, credential, token, or execution evidence.
- P3.1 acceptance freezes six positive target fixtures, five direct
  schema-negative fixtures, and an exact 41-case negative matrix.
- No arbitrary command, shell, script, selector, URL, JavaScript, download,
  executable argument, unmanaged adoption, VM deletion, or host-file deletion
  surface is introduced.

## Changed areas

- `README.md`
- `TASK_HANDOFF.md`
- `contracts/v2/README.md`
- `contracts/v2/compatibility.json`
- `contracts/v2/consumer-contract.json`
- `contracts/v2/schemas/evidence.schema.json`
- `contracts/v2/schemas/portable-manifest.schema.json`
- `contracts/v2/schemas/test-profile.schema.json`
- `contracts/v2/tool-catalog.json`
- `docs/README.md`
- `docs/specification.md`
- `scripts/validate-gate6.ps1`
- `tests/gate6_contract_tests.py`
- `tests/gate7_implementation_tests.py`
- `tests/fixtures/v3/*`

## Verification

The candidate must retain these exact outcomes after its final commit:

- protected Birdsgone `main`/tree and both protected document hashes read back
  exactly as recorded above
- inherited Gate 2 validation with isolated pinned dependencies and
  `SkipRealHostSmoke`
- schema-v1 tools preserved: `16`
- schema-v1 files preserved: `5`
- schema-v2 files: `7`
- total tools: `20`
- P3.1 positive fixtures: `6`
- P3.1 direct schema-invalid fixtures: `5`
- P3.1 negative cases: `41`
- `p3_1Closable: true`
- Gate 7 mock runtime assertions: `216`
- generated mock evidence documents validated: `5`
- `git diff --check`
- Ten Codex review passes found seventeen actionable fail-closed or regression
  coverage gaps: external ZIP
  artifact leaf/size binding, cleanup-only UI driver dispatch and WebView2
  cross-binding, embedded-evidence rejection of external fixture identities,
  non-passing external fixture-identity status derivation, independently bound
  expected fixture IDs, executable-manifest unsigned enforcement, deployed
  payload inventory binding, fixture-artifact size binding, and executable-
  manifest runtime/packaging provenance, profile/manifest/evidence-consistent
  Windows-safe ZIP-leaf enforcement, superscript COM/LPT aliases, and complete
  manifest/profile/evidence ZIP-leaf regression coverage, Windows console-device
  aliases in inventory paths, non-NFC external ZIP leaves, and comprehensive
  control/NFC enforcement for every schema-bound relative path. All seventeen
  are repaired with direct regression probes; the final published candidate
  requires a fresh zero-actionable-findings review.
- real host operations: `0`
- real Hyper-V mutations: `0`
- real guest operations: `0`
- portable deployments: `0`
- WebDriver launches: `0`
- UI operations: `0`

Existing ignored operational artifacts must not be read, reused, moved,
overwritten, or deleted. Task-owned isolated dependency directories may be
created only for validation and must be removed afterward. Mock test evidence
is not real machine evidence.

The historical H4/G9 installed-copy validator `scripts/validate-gate4.ps1` is
not applicable to P3.1 because the executable and installed runtime
intentionally remain `0.2.0`; target-ahead-of-runtime copies are checked
against `compatibility.json` instead. P3.2 must restore authoritative-to-
installed byte equality before P3.3 publication.

## Next gate

`nextGate: G7/P3.2 runtime implementation and mock/parser/static validation
only`

P3.2 must start in a separate task from exact protected plugin `master` after
P3.1 is protected-merged and read back. It implements the frozen external
staging, strict JSON, complete inventory, conditional component/driver, atomic
deployment/data preservation, and evidence behavior under PowerShell 5.1 and
the fixed worker. It must preserve exactly 20 tools and all legacy behavior,
use only mock/parser/static tests, and keep every real-operation counter at
zero.

P3.2 does not authorize:

- P3.3 source Release/install/readback
- H5E-R2 or any other machine diagnostic
- Hyper-V, VM, checkpoint, credential, guest, package, portable, driver,
  network, UI, evidence, or manual-attestation operation
- Birdsgone G8+
- a Birdsgone tag or GitHub Release

After P3.2 protected closure, P3.3 must be a separate atomic task. H5E-R2 is
still pending and must be separately scheduled before G8. Any real Hyper-V or
guest mutation requires a separate confirmation naming the VM, credential
profile, artifact, profile, and exact intended delta.

## Downstream publication requirement

After all required Hyper-V clean-room and publication gates are genuinely
complete, create a distributable Birdsgone GitHub Release from the final
protected-main four-asset set. Carry this requirement in every subsequent
TaskHandoff. Do not create a Birdsgone tag or Release during G7 or before its
publication gate. The plugin P3.3 source-only `v0.3.0` Release is a separate
plugin-repository gate and must not be confused with this downstream
Birdsgone distribution Release.

## Safety constraints

- One writable plugin gate owner at a time.
- Do not begin P3.2 or P3.3 in this task.
- Do not run H5E-R2 concurrently.
- Do not access or mutate Birdsgone ignored artifact directories.
- Do not run package, installation, Hyper-V, VM, checkpoint, credential,
  guest, ADB, Win32, LAN, driver, UI, network, or evidence operations.
- Do not modify or overwrite the immutable plugin `v0.2.0` tag/Release.
- Do not tag, publish a Release, change visibility, force-push, rewrite
  history, delete a branch, or weaken protection.
- Do not claim hosted CI success when capacity is unavailable.
- Do not convert `notPerformed`, mock, parser, or static results into real
  machine evidence.

`ownership.previousTask: read-only-after-relay`

`ownership.successorTask: owns-next-gate`

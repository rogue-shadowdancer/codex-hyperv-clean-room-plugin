# Task handoff: G7/P3.2 Hyper-V Clean Room 0.3 source runtime

`relayProtocolVersion: 1`

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

## Status

G7/P3.2 implements the frozen P3.1 external portable contract in the Windows
PowerShell 5.1 source runtime as plugin base version `0.3.0`. It preserves the
exact 20 public tool names and inputs, all schema-v1 bytes, the seven public
schema-v2 paths, and the complete embedded `0.2.0` behavior.

P3.2 changes source runtime and source-tree installed schema copies only. It
does not build or install a package, create or modify a tag/Release, update a
cachebuster or marketplace entry, or mutate a personal installed copy. The
immutable plugin `v0.2.0` Release and its release-derived personal installation
remain `0.2.0`. P3.3 publication/install/source-match is the only successor
gate.

The historical H4/G9 installed-copy acceptance remains the authority for that
unchanged personal `0.2.0` installation; P3.2 neither reruns nor supersedes it.

P3.2 validation is synthetic and mock/parser/schema/static only. It performs no
real Hyper-V, VM, checkpoint, credential, guest, package, portable,
WebDriver, UI, network, evidence, or manual-attestation operation.

## Protected input authority

- Plugin protected predecessor `master`:
  `e42dfd4784f0f07382a632190884341e5a3de178`
- Predecessor tree:
  `688645a48ba65f16c415d22a285d6b1d0462e307`
- Birdsgone protected `main`:
  `5eba3c60e4b95fa461a39adb9d9c1dfb066ce15c`
- Birdsgone protected tree:
  `dbe98a0b0621353ed09cebff79d7cde64145881d`
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

The earlier `runtime-and-legal-only` G6 result remains historical evidence
only. It cannot satisfy an executable external profile, a release-ready
candidate, or a clean-room pass.

## P3.2 conclusions

- Plugin manifest, server identity, compatibility metadata, and tool catalog
  expose source runtime base `0.3.0`.
- The exact public tool count remains `20`; every tool name and input is
  unchanged.
- The original 16 schema-v1 tools and all five public schema-v1 files remain
  compatible and byte-identical.
- All seven schema-v2 paths and `$id` values remain stable.
- All seven source-tree installed schema-v2 copies are byte-identical to their
  authorities under `contracts/v2/schemas`.
- Exact integer `schemaVersion` dispatch remains fail closed; unknown versions
  never fall back.
- The embedded portable profile/manifest/evidence branch retains its `0.2.0`
  semantics, fixed `--portable` argument, and fixed component/driver behavior.
- The external branch:
  - resolves one regular non-reparse manifest below the canonical profile
    directory;
  - independently binds profile/source/staged/guest path, size, and SHA-256;
  - parses strict UTF-8 and rejects BOM, NUL, malformed bytes, trailing data,
    duplicate properties, and unknown root or nested provenance fields;
  - applies NFC, ordinal, ordinal-ignore-case, reserved-device, traversal,
    ADS, trailing-dot/space, collision, and reparse/link path controls;
  - treats the manifest as a sidecar, never as a ZIP entry, fixture, or
    mutable-data file;
  - verifies manifest-to-ZIP and ZIP-to-manifest membership, size, and SHA-256;
  - rejects undeclared, missing, colliding, linked, companion, and packaged
    `data/` entries;
  - derives complete portable and documentation inventory identities only from
    validated bytes;
  - atomically publishes a new operation-owned deployment slot only after full
    validation while preserving independently inventoried prior data;
  - launches only the declared entrypoint with zero caller arguments;
  - permits a generic non-UI package to omit MaaFramework, WebView2, driver,
    and UI steps;
  - requires the manifest WebView2 identity and fixed Microsoft x64
    EdgeDriver/data-testid rules for the UI branch;
  - emits structurally separate external evidence with exact candidate,
    runtime, deployment, data, fixture, driver, standard-user, and elevated
    orchestration bindings.
- Plan/Apply, atomic plan consumption, paired single-use recovery, cleanup
  separation, and evidence status derivation remain unchanged.

## Changed areas

- Plugin/runtime identity:
  - `hyperv-clean-room/.codex-plugin/plugin.json`
  - `hyperv-clean-room/mcp/lib/Common.ps1`
  - `contracts/v2/compatibility.json`
  - `contracts/v2/tool-catalog.json`
- External runtime and production seams:
  - `hyperv-clean-room/mcp/lib/Validation.V2.ps1`
  - `hyperv-clean-room/mcp/lib/Tools.Guest.V2.ps1`
  - `hyperv-clean-room/mcp/lib/Adapters.ps1`
  - `hyperv-clean-room/mcp/lib/GuestWorker.ps1`
- Exact source-tree schema copies:
  - `hyperv-clean-room/schemas/v2/evidence.schema.json`
  - `hyperv-clean-room/schemas/v2/portable-manifest.schema.json`
  - `hyperv-clean-room/schemas/v2/test-profile.schema.json`
- Validation and test isolation:
  - `scripts/install-common.ps1`
  - `scripts/validate-gate1.ps1`
  - `scripts/validate-gate4.ps1`
  - `scripts/validate-gate6.ps1`
  - `scripts/validate-gate7.ps1`
  - `tests/gate1-contract.tests.ps1`
  - `tests/gate4-installation.tests.ps1`
  - `tests/gate4-installed-copy.tests.ps1`
  - `tests/gate6_contract_tests.py`
  - `tests/gate7-runtime.tests.ps1`
  - `tests/gate7_implementation_tests.py`
  - `tests/public_release_contract_tests.py`
- Documentation:
  - `README.md`
  - `CHANGELOG.md`
  - `contracts/v2/README.md`
  - `docs/README.md`
  - `docs/architecture.md`
  - `docs/installation.md`
  - `docs/maintenance.md`
  - `docs/operations.md`
  - `docs/profile-authoring.md`
  - `docs/security.md`
  - `docs/specification.md`
  - `docs/troubleshooting.md`
  - `TASK_HANDOFF.md`

## Verification

The final exact candidate must retain:

- strict UTF-8 documentation: `17` documents, `100` local links, zero mojibake
- exact tool count: `20`
- preserved schema-v1 tools: `16`
- preserved schema-v1 files: `5`
- exact source-tree installed schema-v2 copies: `7`
- Gate 7 mock runtime assertions: `299`
- generated mock evidence documents validated: `8`
- P3.1 positive fixtures: `6`
- P3.1 direct schema-invalid fixtures: `5`
- P3.1 negative cases: `41`
- `p3_1Closable: true`
- inherited Gate 2 with isolated pinned dependencies and
  `SkipRealHostSmoke`
- Gate 6 contract validation with isolated pinned dependencies
- `git diff --check`
- substantive exact-candidate review with zero actionable findings
- a fresh 30-minute unchanged-head review window before protected merge
- required exact-head hosted checks and the required post-merge run
- real host operations: `0`
- real Hyper-V mutations: `0`
- real guest operations: `0`
- portable deployments: `0`
- WebDriver launches: `0`
- UI operations: `0`

Existing ignored operational artifacts belong to the user and must not be
read, reused, moved, overwritten, or deleted. P3.2 validation uses only
uniquely named ignored task-owned roots. Mock test evidence is not real
machine evidence.

## Blockers

`blockers: []`

## Next gate

`nextGate: G7/P3.3 source publication, Release/install, and exact readback only`

P3.3 must start in a separate task after P3.2 is protected-merged, its required
post-merge run passes, repository protection is read back unchanged, and Issue
#19 records P3.2 closure. P3.3 owns only the separately reviewed source
publication, plugin Release/install/cachebuster work permitted by its
authoritative gate, and exact installed/source readback. It must preserve the
20-tool catalog, v1/embedded semantics, external branch, Plan/Apply, recovery,
closed UI DSL, and the explicit distinction between mock evidence and real
machine work.

P3.3 does not authorize H5E-R2, Birdsgone G8+, or any real Hyper-V, VM,
checkpoint, credential, guest, package lifecycle, portable execution,
WebDriver, UI, network, or manual-attestation operation unless a later
authority explicitly names and approves that exact operation.

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
- Do not begin P3.3 in P3.2.
- Do not run H5E-R2 concurrently.
- Do not access or mutate Birdsgone ignored artifact directories.
- Do not run package, installation, Hyper-V, VM, checkpoint, credential,
  guest, ADB, Win32, LAN, driver, UI, network, or real evidence operations.
- Do not modify or overwrite the immutable plugin `v0.2.0` tag/Release.
- Do not tag, publish a Release, change visibility, force-push, rewrite
  history, delete a branch, or weaken protection.
- Do not convert `notPerformed`, mock, parser, schema, or static results into
  real machine evidence.

`ownership.previousTask: read-only-after-relay`

`ownership.successorTask: owns-next-gate`

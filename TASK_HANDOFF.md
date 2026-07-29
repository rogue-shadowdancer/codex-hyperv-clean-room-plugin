# Task handoff: G7/P3.3 Hyper-V Clean Room 0.3 publication and install

`relayProtocolVersion: 1`

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

## Status

G7/P3.3 publishes the reviewed P3.2 source runtime and closes the separately
authorized personal-install lane. It does not execute a package, portable
application, Hyper-V tool, VM operation, guest operation, credential flow,
WebDriver/UI step, network transition, evidence operation, or manual
attestation.

The immutable source release is:

- protected source commit:
  `47151fdbe99346ec87af09460c79d0864978eabd`;
- source tree:
  `97a1a194e4d4c31fe0e33bad00b98a45a3be705f`;
- annotated tag: `v0.3.0`;
- tag object: `c4046176e848a0fe8afde58eac35b0f62fed098f`;
- tag peeled commit:
  `47151fdbe99346ec87af09460c79d0864978eabd`;
- tag workflow: `30451106948`, `success`;
- GitHub Release: non-draft, non-prerelease, zero uploaded assets;
- authenticated and anonymous Release/tag readback: matched.

The personal build is `0.3.0+codex.20260729122233`. The plugin-creator
cachebuster helper was invoked exactly once. Final acceptance requires the
installer manifest's `sourceCommit` to equal the clean closeout candidate
`HEAD`; the immutable release tag deliberately remains on the unsuffixed
protected source commit above.

## Preserved authorities

- Plugin protected predecessor `master`:
  `47151fdbe99346ec87af09460c79d0864978eabd`
- Predecessor tree:
  `97a1a194e4d4c31fe0e33bad00b98a45a3be705f`
- Birdsgone protected input commit:
  `5eba3c60e4b95fa461a39adb9d9c1dfb066ce15c`
- Birdsgone protected input tree:
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

The immutable plugin `v0.1.1` and `v0.2.0` tags and Releases are unchanged.
Birdsgone's historical `runtime-and-legal-only` assets remain historical only
and cannot satisfy an executable, release-ready, or clean-room result.

## P3.3 conclusions

- The source-only `v0.3.0` tag/Release binds the exact protected P3.2 source.
- The tag-triggered hosted workflow passed before Release publication.
- GitHub and anonymous APIs agree on tag object/type, Release flags, and zero
  uploaded assets.
- The owned personal install is closed over exactly 31 tracked payload files
  plus `.codex-plugin/install-ownership.json` and
  `.codex-plugin/install-manifest.json`.
- The install manifest binds exact relative paths, byte lengths, SHA-256
  values, source version, source commit, and cachebuster.
- Exactly one canonical personal marketplace entry is present, and Codex
  reports the plugin installed and enabled.
- Catalog-only installed-server readback starts from the personal installed
  path, negotiates MCP `2025-11-25`, reports server
  `hyperv-clean-room` / `0.3.0`, and exposes exactly 20 expected / 20 observed /
  20 unique tool names.
- Catalog acceptance calls no MCP tool. It does not run historical
  `inspect_host` or missing-ISO smoke because P3.3 authorizes no real host or
  machine operation.
- Historical H4/G9 installed-copy acceptance and `validate-gate4.ps1` remain
  the authority for the earlier bounded real-host smoke. P3.3 deliberately
  replaces that lane with catalog-only readback and does not rerun it.
- Schema v1, all five v1 files, seven v2 paths, exact 20 public tool
  names/inputs, embedded `0.2.0` semantics, Plan/Apply, single-use recovery,
  closed UI DSL, and fail-closed end-user-complete rules remain unchanged.

## Changed areas

- Local build identity:
  - `hyperv-clean-room/.codex-plugin/plugin.json`
- Publication and install closeout:
  - `README.md`
  - `CHANGELOG.md`
  - `TASK_HANDOFF.md`
  - `contracts/v2/README.md`
  - `docs/README.md`
  - `docs/installation.md`
  - `docs/maintenance.md`
  - `docs/operations.md`
  - `docs/release-process.md`
  - `docs/security.md`
  - `docs/specification.md`
  - `docs/troubleshooting.md`

## Verification

Before source publication:

- exact protected source local publication aggregate: `13/13`;
- Gate 7: `355` runtime assertions, `10` generated evidence documents;
- source payloads: `31`;
- tools: `20`;
- v1 tools: `16`;
- v1 schemas: `5`;
- v2 installed schema copies: `7`;
- public settings/protection and anonymous protected-master readback: passed;
- real host, Hyper-V, guest, portable, WebDriver, and UI operation counters:
  `0`.

After Release publication and cachebuster install, final acceptance requires:

- `validate-install-source.ps1 -RequireCachebuster`;
- `check_install.ps1`;
- 31/31 installed payload byte/hash closure and exactly 33 ordinary installed
  files including the two installer records;
- catalog-only installed-server readback with exactly 20 unique tools and zero
  tool calls;
- full local publication and Gate 7 validators on the exact final candidate;
- exact-head push and pull-request hosted checks;
- substantive exact-head review with zero actionable findings;
- all review conversations resolved;
- a fresh 30-minute unchanged-head window before protected merge;
- required post-merge `public-release-validation` success;
- exact post-merge tag/Release/install/protection/Issue #19 readback.

Existing ignored operational artifacts belong to the user and must not be
read, reused, moved, overwritten, or deleted. This task used only uniquely
named ignored task-owned validation roots.

## Remaining boundaries

`nextGate: no real-operation gate is implicitly authorized by P3.3`

- H5E remains unchecked. H5E-R2 requires a completely fresh collector,
  credential-free self-tests, static review, an exact proposal, and new
  explicit authorization before any UAC, machine-tool call, credential prompt,
  guest session, or native token query.
- Birdsgone G8+ remains a separate repository/gate and is not authorized by
  P3.3. All clean-room, package, portable, driver, UI, evidence, and manual
  acceptance remains `notPerformed`.
- After all required clean-room/publication gates, create the final
  distributable Birdsgone GitHub Release from the protected four-asset set.
  Never substitute the plugin source-only Release for that product Release.

## Safety constraints

- Do not modify or overwrite immutable `v0.1.1`, `v0.2.0`, or `v0.3.0`.
- Do not invoke the cachebuster helper again for this build.
- Do not weaken visibility, branch protection, conversation resolution,
  required checks, or signature/force-push/deletion settings.
- Do not force-push, rewrite history, delete branches/tags/assets, or touch
  ignored user artifacts.
- Do not infer real-machine readiness from source, mock, install, catalog, CI,
  or Release readback.

`ownership.previousTask: read-only-after-relay`

`ownership.successorTask: owns-next-gate`

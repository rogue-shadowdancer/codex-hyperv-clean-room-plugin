# Hyper-V Clean Room 0.3 target contract

This directory is the authoritative G7/P3.1 machine-readable target for plugin
base version `0.3.0` and public schema version 2. G7/P3.2 implements that target
in the source runtime without changing any MCP tool name or input. P3.2
performs no package/release/install operation and invokes no real Hyper-V or
guest operation; the immutable Release and personal installation remain
`0.2.0` until P3.3.

`consumer-contract.json` binds this target to immutable Birdsgone protected
`main` `5eba3c60e4b95fa461a39adb9d9c1dfb066ce15c`, tree
`dbe98a0b0621353ed09cebff79d7cde64145881d`. The consumer document is blob
`e2202a8de07cc90d6b31389853437e9fa025843a`, 37,610 bytes, SHA-256
`489555e9bb0365160fb61aa4964e826405afadcec6345220178d65fc45d9102b`.
The machine-readable end-user distribution authority is blob
`65f6559b5275a5f7bb26d66caaf67c6968749980`, 14,330 bytes, SHA-256
`dcb70fbf91155d4db25813458043d30255c2189ce8d8861a49fb05b0105f1bcb`.
It freezes the 41-case negative matrix and the explicit P3.1 `notPerformed`
boundary.

The seven Draft 2020-12 schema paths and `$id` values remain stable. Three
schemas add closed, mutually exclusive branches:

- `test-profile.schema.json` retains the embedded-manifest portable artifact
  and adds an `externalProfileRelative` artifact with bounded manifest
  path/size/SHA identity and exact
  `requiredDistributionBoundary: end-user-complete`.
- `portable-manifest.schema.json` retains the complete embedded `0.2.0` shape
  and dispatches external manifests through two closed branches. The
  `runtime-and-legal-only` branch remains schema-readable historical evidence
  and cannot satisfy a new profile. The executable `end-user-complete` branch
  requires source-to-ZIP documentation identity, source commit/tree, count,
  payload size, canonical documentation digest, retained runtime/legal
  digests, and complete archive inventory, plus the closed typed provenance
  fields required by the protected consumer contract.
- `evidence.schema.json` retains embedded evidence without a discriminator and
  adds `evidenceKind: externalPortable`, binding source/guest ZIP and manifest
  identities, runtime provenance, fixture identities, deployment identity,
  and conditional WebDriver evidence.

An external non-UI profile must omit WebDriver and may omit WebView2 and
MaaFramework. An external UI profile still uses the closed `data-testid` DSL,
requires the fixed WebDriver object, requires a manifest WebView2 identity, and
binds the first three numeric WebView2/driver version segments; the fourth may
differ. The old embedded branch keeps exact `--portable`, fixed WebView2/Maa,
and exact driver behavior.

`compatibility.json` pins the five byte-identical schema-v1 files and records
the seven installed/runtime schema-v2 hashes. P3.2 makes source target and
runtime both `0.3.0`; every source-tree installed schema-v2 copy is therefore
byte-identical to this authoritative directory. This is not a personal-install
or Release source-match claim; that readback belongs to P3.3.

`tool-catalog.json` continues to expose exactly 20 typed tools: the original 16
schema-v1 tools are unchanged and the four power/network tools keep their
existing inputs, result envelopes, and Plan/Apply semantics. Schema dispatch
continues to use the exact integer `schemaVersion`; unknown versions fail with
`UNSUPPORTED_SCHEMA_VERSION` and never fall back.

Fixtures under `tests/fixtures/v3` contain only synthetic identities. They
include a generic non-UI portable with no WebView2, MaaFramework, driver, or UI
step; a synthetic end-user-complete consumer-shaped manifest/UI pair; a
historical-only legacy external manifest; external evidence; schema-negative
branch fixtures; and the complete parser/archive/documentation/prerequisite/
cross-document negative-case inventory. They contain no private asset, machine
path, OCR data, credential, token, or runtime evidence.

The P3.2 native reader keeps the external manifest outside both the ZIP and
fixture set, parses strict UTF-8 without BOM/NUL/duplicate properties, closes
nested provenance, applies exact ordinal and ordinal-ignore-case path rules,
and derives inventory/documentation identities from validated bytes. The mock
worker independently rebinds ZIP, sidecar, fixtures, deployment inventory,
standard-user identity, elevated orchestration identity, and conditional UI
facts before schema-v2 evidence validation. The embedded branch retains its
fixed `--portable`, component, and evidence semantics. After deployment, every
portable launch also rebinds the operation-owned application, deployment,
active-record fingerprint, and slot identities; concurrent active-pointer
replacement fails closed rather than changing the candidate under test.

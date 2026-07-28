# Hyper-V Clean Room 0.3 target contract

This directory is the authoritative G7/P3.1 machine-readable target for plugin
base version `0.3.0` and public schema version 2. The executable and installable
runtime remains `0.2.0` until the separate P3.2 implementation gate closes.
P3.1 changes no MCP tool name or input, performs no package/release/install
operation, and invokes no Hyper-V or guest operation.

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
the seven installed/runtime schema-v2 hashes. While target `0.3.0` is ahead of
runtime `0.2.0`, installed copies must match those recorded runtime hashes.
Once P3.2 makes target and runtime equal, every installed schema-v2 copy must be
byte-identical to this authoritative directory.

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

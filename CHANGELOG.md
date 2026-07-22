# Changelog

This file records public releases and earlier source milestones. Plugin semver
and schema versions evolve independently; Codex build metadata only invalidates
the local plugin cache.

## Unreleased - Gate 6/H1 contract and Gate 7/H2 integration

### Added

- A canonical GitHub repository link for Codex plugin details through
  `interface.websiteURL`, aligned exactly with the manifest `homepage` and
  `repository` fields.
- A public-release contract assertion that rejects any missing or divergent
  plugin listing URL.
- A design-time plugin `0.2.0`, schema-v2 contract under `contracts/v2` with
  seven stable Draft 2020-12 schema IDs and an exact 20-tool target catalog.
- Four additive guarded tool contracts for VM start/graceful shutdown and
  primary-NIC baseline/disconnected plan/apply transitions.
- Portable ZIP, fixed Microsoft EdgeDriver, closed `data-testid` UI DSL,
  evidence-v2, v1 compatibility, deterministic migration, and invalid/drift
  fixtures plus the Gate 6 static validator.
- A Windows PowerShell 5.1 plugin `0.2.0` runtime candidate with exact
  schema-version dispatch, four guarded power/network tools, atomic portable
  slots and data inventory preservation, fixed-driver provenance, a closed UI
  dispatcher, evidence-v2 derivation, and additive v1-to-v2 migration.
- Seven byte-identical installable schema-v2 files and the Gate 7 mock runtime,
  parser, generated-evidence-schema, and static production-integration checks.

### Changed

- The current `master` personal-install build is
  `0.1.1+codex.20260715084043`. The immutable `v0.1.1` tag and GitHub Release
  retain their accepted `0.1.1+codex.20260715064728` build.
- The retained Gate 5.2 marketplace metadata changed no MCP tool,
  schema-v1 semantic, runtime behavior, or GitHub Release.
- Gate 7 changes the source runtime candidate to `0.2.0` and exactly 20 MCP
  tools while preserving the exact 16-tool schema-v1 snapshot and byte hashes
  of all five public schema-v1 files. CI now validates the Gate 7 integration.
- Gate 7 executes mock/parser/static checks only. Plugin release, cachebuster
  install, clean-machine validation, and real VM, credential, guest, package,
  portable, WebDriver, network, UI, and manual-attestation work remain
  `notPerformed`.

### Fixed

- The standalone schema-v1-to-v2 migration CLI now loads its atomic JSON writer,
  and the native schema-v2 validator accepts the contract-defined optional
  legacy artifact identity fields and optional legacy `processName`.
- The durable branch-protection contract retains pull-request review and
  conversation-resolution protection while requiring zero approving reviews;
  strict `public-release-validation` remains mandatory.

## 0.1.1 - GPL public release - 2026-07-15

### Added

- GNU GPL v3 licensing with SPDX identifier `GPL-3.0-only`.
- Public contribution guidance, Contributor Covenant 2.1, issue forms, a pull
  request template, Dependabot, and private vulnerability reporting guidance.
- SHA-pinned `public-release-validation` on Windows with full-history checkout,
  public-release contract validation, and the CI-safe Gate 4 suite.
- Fail-closed publication checks for the prospective tree, full retained
  history, commit identities/messages, GitHub Actions logs, credentials in
  URLs, sensitive literals, private paths, and forbidden machine state.
- Anonymous public readback, protected-branch, annotated-tag, source-only
  Release, and installed-copy verification procedures.

### Changed

- Plugin base and MCP server version are `0.1.1`; the installed Codex build is
  `0.1.1+codex.20260715064728`.
- The eight existing commits and their object IDs remain unchanged. Their
  accepted legacy identity metadata is bound only through SHA-256 digests of
  the exact raw commit objects; new commits use the repository's GitHub
  noreply identity.

### Safety and validation boundary

- The public API remains exactly 16 MCP tools, five Draft 2020-12 schemas,
  `schemaVersion: 1`, and four supported MCP protocol versions.
- Mock, parser, schema, static, installer-security, CI-safe, installed-copy,
  license, community, encoding, privacy, and release-contract checks pass.
- Installed-copy acceptance is limited to tool discovery, read-only
  `inspect_host`, and a nonexistent-ISO rejection before mutation.
- Clean-machine validation, credential enrollment, real guest/package work,
  VM/checkpoint mutation, and manual GUI attestation remain `notPerformed`.

## 0.1.0 - Gate 5 private publication baseline - 2026-07-15

### Added

- A PowerShell 5.1 MCP runtime with exactly 16 schema-v1 tools and five public
  Draft 2020-12 schemas.
- Guarded VM/checkpoint plans, fixed production guest-adapter code, declarative
  profiles, evidence validation/export, and the two-role DPAPI credential
  initializer.
- A source-validated, ownership-marked personal installation and helper-only
  marketplace workflow with commit-bound installed-copy acceptance.
- A private-publication runbook, full-history sensitive-state scan, and a
  CI-safe Gate 4 validation path that performs no personal installation,
  marketplace mutation, installed-copy call, real-host operation, guest
  operation, or Hyper-V mutation.
- Fail-closed publication policy regressions for nested Birdsgone/cache,
  evidence and Hyper-V state paths, plus exact-key JSON/YAML/assignment secret
  literals without a directory-wide test exemption.

### Safety and validation boundary

- Mock, parser, schema, static, installer-security, and bounded read-only host
  checks have passed locally for the candidate.
- The installed-copy smoke is limited to tool discovery, read-only
  `inspect_host`, and a nonexistent-ISO rejection before mutation.
- No clean-machine result, real guest lifecycle, credential enrollment,
  package lifecycle, VM/checkpoint mutation, tag, or GitHub Release is claimed.

### Earlier contract milestones

- Gate 1 and Gate 1.1 froze the manifest, tool, schema, cleanup, profile, and
  evidence contracts.
- Gate 2 implemented and closed the runtime, containment, evidence, security,
  documentation, and reproducibility gaps against the frozen v1 contract.
- Gate 4 added and validated the personal plugin installation/cachebuster
  workflow without changing the public tool set or schema-v1 semantics.

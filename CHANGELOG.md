# Changelog

This file records source milestones for the pre-release `0.1.0` line. The
repository has no tag or GitHub Release at the Gate 5 boundary; the installed
personal copy uses build metadata only to invalidate the local Codex cache.

## 0.1.0 - Gate 5 private publication candidate - 2026-07-15

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

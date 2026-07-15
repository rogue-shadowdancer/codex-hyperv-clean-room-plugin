# Contributing to Hyper-V Clean Room

Thank you for helping improve Hyper-V Clean Room. This project accepts bug
reports, documentation improvements, tests, and focused code changes that
preserve its guarded-mutation model.

## Before you contribute

- Read [the security policy](SECURITY.md) before reporting a vulnerability.
  Do not put sensitive host, VM, credential, or evidence data in a public
  issue.
- Read [the frozen v1 specification](docs/specification.md) before changing
  MCP tools, schemas, plans, evidence semantics, or guest execution behavior.
- Follow the [Contributor Covenant](CODE_OF_CONDUCT.md).
- By submitting a contribution, you agree that it may be distributed under
  the repository's [GNU GPL v3 license](LICENSE).

## Development workflow

1. Fork the repository and create a focused branch from `master`.
2. Keep the public contract at exactly 16 tools, five Draft 2020-12 schemas,
   `schemaVersion: 1`, and the four documented MCP protocol versions unless a
   deliberate specification revision is part of the proposal.
3. Use mock adapters for tests. Do not run a real Hyper-V or guest mutation
   without explicit authorization for that named operation.
4. Keep credentials, VM/VHDX/checkpoint/ISO files, evidence, caches, logs,
   installed-control files, and machine-specific state out of Git.
5. Add or update tests and documentation with the implementation.

Prepare the pinned test environment and run the CI-safe checks:

```powershell
.\scripts\prepare-test-python.ps1
.\scripts\validate-docs.ps1
& (Get-Command python).Source -S .\tests\publication_hygiene_policy_tests.py
& (Get-Command python).Source -S .\tests\publication_hygiene_tests.py
& (Get-Command python).Source -S .\tests\public_release_contract_tests.py
.\scripts\validate-gate4-ci.ps1
```

Maintainers with an owned personal installation can additionally run:

```powershell
.\scripts\validate-gate4.ps1
```

That workstation check is intentionally bounded to installed-copy discovery,
read-only host inspection, and rejection of a nonexistent ISO before mutation.
It is not clean-machine or real-guest validation.

## Pull requests

Keep pull requests small enough to review. Explain the safety boundary, list
the commands you ran, and call out anything that remains `notPerformed`.
Source changes must pass `public-release-validation`; maintainers merge through
the protected `master` branch after review and conversation resolution.


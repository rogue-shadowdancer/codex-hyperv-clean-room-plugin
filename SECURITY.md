# Security policy

## Supported versions

The supported release is `0.1.1` and the current `master` baseline. Older
commits, modified schemas, unofficial builds, local forks, and generated
evidence are not supported versions. Security fixes are published as additive
commits and reviewed pull requests; release history is not rewritten.

| Version | Supported |
| --- | --- |
| 0.1.1 | Yes |
| 0.1.0 and earlier | No |

Gate 2 validates mock behavior and static production-adapter contracts. It has
not completed authorized clean-machine validation of real VM mutation,
PowerShell Direct credential enrollment, guest transfer, or package lifecycle.
Do not report that assurance boundary itself as a vulnerability; report any
path that falsely bypasses or overstates it.

## Reporting a vulnerability

Use **Security → Report a vulnerability** in this GitHub repository. Private vulnerability reporting
is enabled and is the required channel for sensitive
details. Do not open a public issue for a suspected vulnerability. If GitHub's
private reporting form is unavailable, contact the repository owner through
GitHub before sharing more than a non-sensitive summary.

Include:

- affected commit and Windows/PowerShell versions;
- the specific MCP tool, script, schema, or documentation contract;
- expected and observed behavior;
- a minimal reproduction that uses mock state whenever possible;
- whether any real VM, VHDX, checkpoint, credential, guest, artifact, or
  evidence data was touched;
- suggested containment if the issue can cause mutation or disclosure.

Do not include:

- a password, secure string, `PSCredential`, DPAPI/CLIXML credential file, or
  restore confirmation token;
- VM, VHDX, checkpoint, ISO, guest-state, or machine-specific evidence files;
- private usernames, hostnames, full environment blocks, or unrelated host
  paths;
- destructive proof-of-concept code or instructions to delete a VM, VHDX,
  checkpoint, guest path, or host path.

Use synthetic names, hashes, and mock adapters. If a real host observation is
essential, obtain explicit authorization and redact it before transmission.

## High-priority issue classes

Please report any verified path that:

- exposes plaintext credential or restore-token material;
- accepts arbitrary command, script, shell, URL, download, or unrestricted
  executable arguments;
- allows a guest lifecycle step to run as administrator while being recorded
  as standard-user evidence;
- bypasses VM ownership, plan consumption, expiry, confirmation, or drift
  checks;
- stops a process without revalidating its operation-scoped identity;
- permits traversal or reparse escape from a protected host, guest, credential,
  staging, or evidence root;
- adds or exposes deletion of a VM, VHDX, checkpoint, guest file, registry key,
  or host path;
- forges automatic, manual, cleanup, hash, ownership, or overall-status
  evidence;
- leaks PowerShell error records, stacks, full environments, or secrets through
  MCP stdout/stderr.

## Safe validation expectations

Tests must use the mock adapter unless a user explicitly authorizes a named
real operation. The standard Gate 2 suite may run only read-only
`inspect_host` and a nonexistent-ISO plan rejection against the real adapter;
it must report zero real Hyper-V mutations and zero real guest operations.

Never weaken a guard to make a reproduction pass. Preserve partial resources
and coordinate any manual recovery outside this repository's public tool
surface.

For design controls and trust boundaries, see
[docs/security.md](docs/security.md). For operator sequencing, see
[docs/operations.md](docs/operations.md).

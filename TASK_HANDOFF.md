# TaskHandoff - HCI1 Hyper-V static Linux repository foundation

`relayProtocolVersion: 1`

## Objective and outcome

HCI1 owns exactly the Hyper-V repository side of the future
`hyperv-static-linux` remote CI lane. This gate adds a cross-platform Python
3.12 execution core, closed exact-source/dependency contracts, immutable
content-addressed evidence, exclusive idempotency behavior, Linux-safe static
tests, and operator documentation.

The infrastructure-owned production adapter is deliberately absent. The
committed C2 dispatcher currently validates admission, environment, mount, and
evidence-store shape, then exits; all suites are disabled. Direct execution of
the repository runner therefore fails closed with
`controllerAdapter: notPerformed` and `remoteProof: notPerformed`.

One repository / one gate / one writer is not global serialization. HCI1 local
repository work may proceed in parallel with C2 or KVM work because their
writable scopes are distinct. Only HCI1 remote exact-SHA proof depends on the
three-way convergence of C2 Apply/Verify, a future infrastructure
runner-integration gate, and an exact committed HCI1 candidate.

## Completed context

- H5A source commit `66df2c63bbfb70e3de1aa01f4b2cf768342210ff`
  was protected-merged as
  `175bc4d7745e7d6b7c384d413a2fcd9001a1abc9`; the accepted installed
  candidate is `0.2.0+codex.20260723113253`.
- H5B separately reviewed and, after exact user confirmation, changed only
  `AutomaticCheckpointsEnabled` from true to false on the managed VM while
  preserving its running state, ownership, VHDX chain, and checkpoint
  inventory. Its evidence SHA-256 is
  `714dacd231d48306e18b848f9473598ecf1859080d42984b4bddb4aa971898fc`.
- HCI1 did not inspect or mutate that VM and does not commit H5B machine
  evidence.
- C1 control-plane commit
  `109e3e95437c485cbadf0904f32ba8391f90e571` defined the closed request and
  all suites disabled.
- C2 contract commit
  `964c411ea0579b6adaca7a7bf7800d76f19028e2`, tree
  `0bffd80a2b1f64ee3e091ff759c11110d988f2c6`, freezes the account
  `ci-hyperv-static`, physical lane
  `/mnt/sdb/tianyi.zhang/codex-ci/hyperv-static-linux`, visible bind mount
  `/srv/codex-ci/hyperv-static-linux`, and service
  `codex-ci-hyperv-static@.service`.
- C2 remote Apply/Verify is `notPerformed`; its fixed targets do not yet
  exist. C2 is bootstrap/admission only and does not yet bind a complete
  runner interface.

## Repository and compatibility boundary

`projectPath: E:\study\great_projects\codex-hyperv-clean-room-plugin`

- Candidate branch: `codex/hci1-linux-static`.
- Candidate base: accepted `origin/master`
  `175bc4d7745e7d6b7c384d413a2fcd9001a1abc9`.
- The candidate identity is the commit containing this handoff; exact remote
  commit/tree readback belongs in the terminal relay/result because a commit
  cannot contain its own SHA.
- HCI1 changes no MCP tool name, public MCP input, schema-v1/v2 runtime
  behavior, plugin base version, cachebuster, installation payload, immutable
  release, or real Hyper-V behavior.
- `.github/workflows/ci.yml` and its Windows
  `public-release-validation` job are unchanged.
- The working tree started with four untracked HCI1 drafts and no user edits.
  All final listed changes belong to HCI1. Ignored `.artifacts` contains only
  prior local test/runtime evidence and is not a publication candidate.

## Changed areas

- `scripts/run_hyperv_static_linux.py`
  - mirrors the closed C1 request-v1 shape and exact idempotency material;
  - exposes only an internal `PreparedInputs` seam for a future trusted
    adapter, with no caller command/path/URL/environment/credential surface;
  - validates the fixed C2 lane facts without creating the lane, mount,
    account, or service;
  - verifies a content-addressed full-history Git bundle, exact detached
    commit/tree, clean before/after state, and candidate runner bytes;
  - installs only the committed wheel closure into the exact operation venv
    using binary-only, hash-required, no-dependency, no-index controls;
  - enforces one non-blocking writer per idempotency key, immutable summary
    reuse, ambiguity state, atomic content publication, and fixed byte limits;
  - prevents operation-ID rebinding, serializes lane-changing operations
    without creating another path, reserves worst-case bounded capacity, and
    rechecks content/summary bytes before publication;
  - fixes all nine summary checks and twelve manifest entries by identity and
    order, re-derives terminal status during reuse, and binds each check log to
    its manifest reference;
  - retains the operation workspace through summary publication and exposes
    only a summary-hash-bound cleanup helper for the future adapter after
    readback;
  - emits an incomplete receipt instead of inventing an infrastructure
    adapter.
- `contracts/ci/`
  - defines the remote request/aggregate status boundary;
  - defines strict summary, log-manifest, and ambiguity schemas version 1;
  - locks seven CPython 3.12.10 Linux wheels by name, version, filename, size,
    SHA-256, ABI/platform, Python constraint, and fixed provenance.
- `tests/hci1_static_runner_tests.py`
  - covers closed parsing, duplicate/unknown rejection, idempotency, aggregate
    status, schemas, zero counters, secure layout, immutable content reuse,
    exclusive locking, exact local Git-bundle checkout, wheel-lock closure,
    and the deliberately absent production adapter.
- `tests/gate7_implementation_tests.py`
  - adds `--static-only`, preserving the default Windows behavior while
    reporting the Windows mock runtime evidence `notPerformed` on Linux.
- The specification, operations, security, troubleshooting, README,
  documentation index, changelog, and this handoff describe the same boundary.

## Verification

Targeted HCI1 validation passed 16 tests and reported:

- `realHostOperations: 0`;
- `realHyperVMutations: 0`;
- `realGuestOperations: 0`;
- `portableDeployments: 0`;
- `webDriverLaunches: 0`;
- `uiOperations: 0`;
- `controllerAdapter: notPerformed`; and
- `remoteProof: notPerformed`.

Read-only PyPI JSON readback found exactly one matching release file for each
of the seven locked wheels; every filename, byte size, SHA-256, and fixed URL
matched the committed manifest. No wheel was installed or retained by that
readback.

The Linux-safe fixed suite consists of:

1. `repository_format_tests.py`;
2. `publication_hygiene_policy_tests.py`;
3. `publication_hygiene_tests.py`;
4. `public_release_contract_tests.py`;
5. `schema_contract_tests.py`;
6. `static_quality_tests.py`;
7. `gate7_implementation_tests.py --static-only`; and
8. `hci1_static_runner_tests.py`.

`runtime_artifact_schema_tests.py` remains Windows-mock-only and
`gate6_contract_tests.py` remains Windows-PowerShell-only; neither is
fabricated as a Linux success.

Before commit, the exact staged candidate must pass the complete applicable
validation, `git diff --check`, documentation validation, and an independent
substantive review at `ZERO ACTIONABLE FINDINGS`. After push, the exact branch
SHA/tree and hosted check result must be read back. The historical installed
acceptance command remains `validate-gate4.ps1`; HCI1 does not replace or
rename H4/G9 or `public-release-validation`.

The final local candidate passed:

```powershell
.\scripts\validate-gate4-ci.ps1
.\scripts\validate-gate7.ps1 -SkipInheritedBaseline
.\scripts\validate-public-release.ps1
```

Gate 4 CI-safe reported 31 source files, 20 tools, five public v1 schemas,
seven v2 schemas, 33 installer assertions, and zero installation, marketplace,
installed-copy, host, guest, or Hyper-V mutation operations. Gate 7 reported
216 runtime assertions and zero real host, Hyper-V, guest, portable,
WebDriver, or UI operations. The public-release aggregate passed 13 checks
with `realGuestOperations: 0` and `realHyperVMutations: 0`.

## Evidence, idempotency, and status boundary

Request v1 contains only operation ID, repository ID, exact commit/tree,
suite/contract, source-bundle SHA-256, and runner-image digest. The idempotency
key excludes operation ID and binds every result-affecting identity.

Complete summaries live at
`results/<idempotency>/summary.json`; logs and other content live at
`content/sha256/<first2>/<sha256>` and are referenced by hash from a strict log
manifest. An uncertain attempt is incomplete and records
`ambiguity/<operationId>/state.json`. A complete summary is reused only after
identity and hash validation; it is never overwritten. Blind retry is
forbidden.

`hyperv-mock-windows` and the aggregate `hyperv-validation` status semantics
are defined but remain `notPerformed`. The aggregate may be `passed` only when
both exact-bound component summaries pass with all six operation counters
zero. Linux static success never proves Windows/mock, real host, Hyper-V,
guest, portable, WebDriver, or UI success.

## Safety boundary, unresolved work, and next gate

HCI1 performed no remote write, SSH proof, directory/account/mount/service
creation, dependency installation on 229, suite start, GitHub check write,
credential use, host inspection, Hyper-V or VM operation, guest operation,
portable deployment, browser launch, UI operation, or cleanup of another
project.

The infrastructure-owned interface still missing from the committed baseline
includes exact spool bundle/auxiliary filenames, wheel/content-cache layout,
bundle verify/checkout wiring, fixed workspace, provisioned and hash-pinned
`/opt/codex-ci` runtime, fixed runner argv/stdin/env/cwd/timeout/result seam,
terminal/idempotency/content/ambiguity publication, runner-image enforcement,
and suite enablement. HCI1 must not freeze those details.

`blockers[]`:

- C2 Apply/Verify is `notPerformed`;
- the infrastructure runner-integration gate is not implemented; and
- consequently the remote exact-SHA proof is `notPerformed`.

The next gate is infrastructure runner integration, owned outside this
repository. After its reviewed implementation and C2 Apply/Verify readback,
an HCI1 successor may execute one allowlisted exact-SHA proof and return source
SHA/tree, operation/idempotency identities, immutable evidence hashes,
assertion counts, before/after source identities, all zero-operation counters,
cleanup state, ambiguity state, and disk bytes used. It must not change the VM
or publish a GitHub check from 229.

`ownership.previousTask: read-only-after-relay`

`ownership.successorTask: owns-next-gate`

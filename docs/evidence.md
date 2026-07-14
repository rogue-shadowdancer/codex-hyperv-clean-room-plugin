# Evidence model

## Purpose

Evidence records what the runner actually observed. It is not a marketing
summary, an execution log dump, or a substitute for the VM baseline. Schema v1
separates automatic assertions, manual assertions, and cleanup results so one
category cannot silently stand in for another.

The authoritative portable shape is
[`evidence.schema.json`](../hyperv-clean-room/schemas/evidence.schema.json).
Native PowerShell validation enforces additional operation-binding and status
derivation rules that JSON Schema alone cannot express.

## Provenance chain

A valid test evidence document binds:

- `operationId` to one immutable `run_test_profile` operation;
- `profileId` and `baselineType` to the validated profile;
- VM ID and name to a verified plugin ownership record;
- guest identity to the standard test-user token observed before execution;
- `sourceSha256` to the host artifact;
- `guestSha256` to the operation-scoped guest copy;
- automatic assertion IDs, order, type, and required flags to operation state;
- manual assertion IDs and required flags to the profile declaration;
- `cleanupTriggered` and every cleanup identity to immutable operation state.

For a successful stage, both artifact hashes are 64-character lowercase
SHA-256 values and must match. If no readable guest copy was produced, a failed
staging assertion records `guestSha256: null`; if a guest copy is readable but
different, it records the observed hash. Either failed-stage form prevents a
passed lifecycle while preserving the source identity and the most accurate
guest fact available. A null or mismatched guest hash is valid only when the
required staging assertion itself is `failed`; `passed`, `notPerformed`, and
`unsupported` staging statuses are invalid for those artifact facts.

## Automatic assertions

`automaticAssertions` contains machine-collected results. The runner creates a
required staging assertion, a required ordinary-user token invariant, and one
entry for every remaining declared ordinary step.

Each entry contains:

- immutable `id` and `required` values;
- `status`: `passed`, `failed`, `notPerformed`, or `unsupported`;
- a bounded summary;
- bounded machine evidence or `null`.

Actions and mutations cannot be optional. A failed optional assertion is
preserved but does not stop the sequence and does not affect overall status.
A prior required execution failure causes later ordinary steps to be recorded
as `notPerformed`, not omitted.

Automatic evidence may prove process exit, file/registry/process/module/port
state, hashes, token facts, and operation-scoped process identity. It cannot
prove that a window was visible, a GUI was usable, DPI rendering was correct,
or an interactive exercise succeeded.

## Manual assertions

`manualAssertions` remains separate from automatic results. A newly executed
profile records every manual item as `notPerformed` with `attestation: null`.

`record_manual_attestation` can change one item to `passed`, `failed`, or
`unsupported`. The method must be one of:

- `visualInspection`;
- `interactiveExercise`;
- `externalTool`;
- `declaredUnsupported`.

`declaredUnsupported` is required for `unsupported` and forbidden for passed
or failed observations. The server, not the caller, supplies observer identity
and timestamp. The attestation repeats the bound operation, profile, and
assertion IDs.

Evidence references are optional but, when present, each reference must:

- use a safe relative path;
- remain below the operation's server-controlled evidence staging root;
- identify an ordinary non-reparse file;
- include the exact SHA-256 of that file.

Absolute paths, traversal, missing files, and hash mismatches are rejected.
`evidence.json`, `inventory.json`, and other mutable control documents cannot
be used as self-referential manual evidence. An exported directory is not
accepted as the live staging root.

## Cleanup evidence

`cleanupTriggered` is copied from immutable operation state. A caller cannot
supply or rewrite it.

`cleanupResults` contains exactly one entry for each declared cleanup step in
the original order. Every entry binds:

- `operationId`;
- `profileId`;
- `cleanupStepId`;
- `cleanupStepType`;
- status, summary, and bounded machine evidence.

When `cleanupTriggered` is false, every declared cleanup result must be
`notPerformed`. An empty declaration produces `[]`. When true, performed,
failed, unsupported, or budget-exhausted results remain in declaration order.

For cleanup `stopApplication`, evidence reports whether the operation-scoped
PID identity was revalidated. A missing, changed, reused, or inaccessible PID
must produce failure evidence and must not be stopped.

Cleanup is operational follow-up, not a test assertion. It never participates
in `overallStatus`.

## Overall-status derivation

The runtime and `validate_evidence` recompute status from required automatic
and manual assertions:

1. `failed` if any required assertion is `failed`;
2. otherwise `incomplete` if any required assertion is `notPerformed` or
   `unsupported`;
3. otherwise `passed` when every required assertion passed.

Optional results are excluded. `cleanupTriggered` and all cleanup results are
excluded. Successful cleanup cannot upgrade failure or incompleteness. Failed
cleanup cannot downgrade an otherwise passed set of required assertions.

A serialized `overallStatus` that differs from this derivation is invalid.

## Passed-lifecycle invariants

In addition to individual assertions, a passed current-user lifecycle requires:

- verified VM ownership;
- a standard test user that is not an administrator;
- a non-elevated, medium-integrity token;
- matching `sourceSha256` and `guestSha256`;
- no missing required automatic or manual result.

Failed and incomplete evidence may preserve an elevated or administrative
token observation. Keeping that failed fact is preferable to discarding it.

## Server staging and export

During execution, evidence remains below the server-controlled host state root:

```text
evidence-staging/<operation-id>/
  evidence.json
  ...manual reference files, if any...
```

`collect_evidence` holds the operation-record lock while it validates the staged
document, resolves and rehashes every attestation claim, and rejects reparse
points. For every ordinary file it verifies the source hash before copy, the
source hash after copy, the destination hash, any claimed hash, and the hash
written to the inventory. Any disagreement aborts export. It copies only the
verified files to a new directory named for the operation and writes a UTF-8
`inventory.json`; each entry contains repository-independent relative path,
byte length, and the verified destination SHA-256. A staged root
`inventory.json` is rejected rather than copied and overwritten. Before the
generated inventory is published, the exact copied `evidence.json` is parsed
and validated again against the still-locked immutable operation record. After
publication, the exact serialized `inventory.json` is reopened, its header and
ordered file membership are rebound, and every final file's byte length and
SHA-256 are verified from those parsed claims before success is returned.

The export destination must already exist and must not be under:

- Windows or Program Files;
- the plugin installation;
- plugin state or credential storage;
- any managed Hyper-V storage root.

The export contains no credential, restore token, full environment block,
PowerShell error record, or stack trace.

## Validation procedure

For every shareable package:

1. record any authorized manual attestations;
2. call `collect_evidence` once into a safe empty parent directory;
3. call `validate_evidence` on the exported `evidence.json`;
4. independently hash `inventory.json` if the package crosses a trust
   boundary;
5. report automatic, manual, and cleanup sections separately;
6. state whether the adapter was mock or production and whether a real guest
   operation was actually authorized and executed.

Gate 2 fixture and runtime samples prove schema and semantic validation logic.
They do not constitute evidence from a real clean machine.

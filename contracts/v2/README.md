# Hyper-V Clean Room 0.2 contract freeze

This directory is the Gate 6/H1 machine-readable contract for plugin `0.2.0`
and public schema version 2. Gate 7/H2 integrates it into the installable
`hyperv-clean-room` source while keeping this directory authoritative. The
runtime candidate now exposes exactly 20 tools, preserves the first 16
schema-v1 definitions and five public schema-v1 files byte-for-byte, and ships
exact copies of all seven schema-v2 contracts under `hyperv-clean-room/schemas/v2`.

The seven Draft 2020-12 schemas have stable versioned IDs. `tool-catalog.json`
freezes the 20-tool `0.2.0` target: all 16 schema-v1 tools retain their exact
input schemas, annotations, and schema-v1 result envelope, while four additive
tools provide guarded VM
power and primary-NIC transitions. Each additive entry also freezes its
schema-v2 envelope, closed success-data schema, `changed` value, and stable
failure-code set. `compatibility.json` pins every v1 schema byte hash and the
exact reader/migration decision.

Schema routing is by the exact integer `schemaVersion`. Readers never try one
schema and fall back to another. Unknown versions fail with
`UNSUPPORTED_SCHEMA_VERSION`. Valid v1 profiles keep v1 behavior; an explicit
lossless migration may create a new v2 document without rewriting the source.
Ambiguous package kinds require authoring. V1 evidence remains v1 because the
candidate, fixed-driver, fixture, UI, and recovery provenance required by v2
cannot be invented.

No file in this directory, nor the H2 mock/parser/static implementation gate,
authorizes or proves a real host, VM, checkpoint, credential, guest, package,
portable deployment, WebDriver, network, UI, installation, release, or
clean-machine operation.

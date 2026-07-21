# Hyper-V Clean Room 0.2 contract freeze

This directory is the Gate 6/H1 machine-readable target contract for plugin
`0.2.0` and public schema version 2. It is deliberately outside the current
`hyperv-clean-room` plugin payload: H1 changes no executable MCP registry,
adapter, installer, or mutation path. The shipped/runtime contract remains
plugin `0.1.1`, schema version 1, 16 tools, and five public schemas until the
separate H2 implementation gate integrates this frozen contract.

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

No file in this directory authorizes a real host, VM, checkpoint, credential,
guest, package, portable deployment, WebDriver, network, or UI operation.

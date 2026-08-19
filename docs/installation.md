# Plugin installation

## Proven boundary

Gate 4 established the local personal-install mechanism for the 16-tool v1
runtime. Gate 9/H4 applied that fail-closed mechanism to the release-derived
plugin `0.2.0` source. The v0.4.1 installation Gate applies it only after the
minimal-list candidate is reviewed and merged to protected `master`; it copies
the payload to
`%USERPROFILE%\plugins\hyperv-clean-room`, creates or updates exactly one entry
in the default personal marketplace through the `plugin-creator` helper, and
runs:

The current fixed-worker input-binding source Gate prepares the one frozen
`0.4.1+codex.20260819091500` build; the credential-module bootstrap build
`0.4.1+codex.20260819075913` is installed predecessor state. The source Gate
does not install or publish the new build. After merge, the installation Gate
requires all 31
tracked payloads, the two installed-state records, exact per-file size/SHA-256,
source commit, version, cachebuster, one canonical marketplace entry, and Codex
installed/enabled state to agree. Production typed read-only acceptance follows
only in a fresh task. A later Release Gate requires the tested protected
commit, annotated `v0.4.1`, GitHub Release target, and installed `sourceCommit`
to be identical. Historical releases through `v0.4.0` remain unchanged.

The repair candidate's `.mcp.json` declares exactly one server and passes
through only `COMPUTERNAME`; it contains no environment literal. The runtime
also restores a missing or whitespace value from `[Environment]::MachineName`
inside the MCP child before adapter or state initialization. The source repair
Gate validates this behavior but does not copy it into the personal plugin,
edit marketplace/Codex configuration, or claim installed runtime acceptance.

The exact Test2 manifest repair follows the same boundary. Source validation
may prove the immutable sidecar/profile compatible, but the currently installed
older payload remains ineligible for the Test2 run. After the ordinary
protected merge, run `validate-install-source.ps1 -RequireCachebuster`,
`check_install.ps1`, `install_plugin.ps1` exactly once, and `check_install.ps1`
again from the exact protected checkout. Require 31/31 payload hashes, exact
source/installed commit and build, one personal marketplace entry,
installed/enabled state, and the 20-tool selected catalog before any VM start,
credential enrollment, or guest call. Do not edit marketplace/configuration or
regenerate the cachebuster during installation.

```powershell
codex plugin add hyperv-clean-room@personal
```

The installed MCP server is then started from the installed directory, not the
repository. The v0.4.1 acceptance requires server identity/version
`hyperv-clean-room` / `0.4.1`, MCP protocol `2025-11-25`, and exactly 20 tools
(all unique) through a fresh Codex app-server thread with an explicit
`selectedCapabilityRoots` binding and thread-scoped `mcpServerStatus/list`.
The default P3.3-R2 check calls no MCP tool. A separate explicit mock mode
launches an isolated selected MCP child, requires the test-only warning and
`changed=false`, and calls only `inspect_host` and `list_vms`; it is mock
transport acceptance, not real-host evidence. Raw prompt text naming the plugin
is not a plugin selection and is not acceptance evidence. This
proves local installation, marketplace visibility, cache pickup, and catalog
discovery only. It does not prove a real host, VM or checkpoint mutation,
credential enrollment, PowerShell Direct guest behavior, package execution,
or a clean Windows result.

## Prerequisites

- Windows PowerShell 5.1;
- the `codex` CLI with plugin commands;
- `$env:SystemRoot\py.exe` and Python 3 for the development-time `plugin-creator`
  helpers;
- the complete `plugin-creator` skill at
  `%USERPROFILE%\.codex\skills\.system\plugin-creator`;
- a Git checkout whose plugin payload is the tracked
  `hyperv-clean-room` directory.

The production MCP runtime still has no Python dependency. Python is used only
by the local marketplace and cachebuster development workflow.

## Validate the source

From the repository root, run:

```powershell
.\scripts\validate-install-source.ps1
```

Validation rejects reparse points, untracked or missing payload files,
reserved install-state files, forbidden VM/credential/evidence file types,
unsafe relative paths, oversized files, an unexpected manifest name or path,
and any version outside the recognized v0.4.0/v0.4.1 patch identities with at
most one `+codex.<cachebuster>` suffix. Gate 1 requires the current source to be
v0.4.1; v0.4.0 is recognized only so read-only install checks can report the
existing installation as drift rather than fail parsing. The integrated source
payload contains exactly 31 Git-tracked ordinary files: five public schema-v1
files and seven schema-v2 files are included. The v0.4.1 Gate freezes one build
only after the source candidate is stable; immutable historical tags through
`v0.4.0` remain unchanged.

## Install the personal copy

Run:

```powershell
.\scripts\install_plugin.ps1
```

The installer performs these bounded operations:

1. validates the repository source and records the current Git commit;
2. refuses an existing target unless its ownership marker exactly identifies
   the Hyper-V Clean Room installer and that target;
3. copies each payload file and immediately checks its size and SHA-256;
4. writes a bounded install manifest whose `files[]` inventory contains only
   relative paths, sizes, and SHA-256 values; top-level metadata also records
   schema/plugin/installation identity, canonical source and target paths,
   source version and commit, cachebuster state, and the installation time;
5. uses `plugin-creator/scripts/create_basic_plugin.py` to create or update the
   canonical personal marketplace entry—`marketplace.json` is never edited by
   the installer itself;
6. reads the marketplace name through
   `plugin-creator/scripts/read_marketplace_name.py` and requires `personal`;
7. runs `codex plugin add hyperv-clean-room@personal`; and
8. requires the final installed, owned, matches, and marketplace-visible checks
   to all pass.

Installed control files are machine state and are not committed:

- `.codex-plugin/install-ownership.json` protects an existing target from
  accidental overwrite;
- `.codex-plugin/install-manifest.json` binds the installation to its source
  commit, version, cachebuster, and per-file size/SHA-256 inventory.

The installer does not delete unexpected installed files. If an owned target
contains a file outside the current payload and the two control files, it
stops and reports that path for operator review.

## Check the installed state

Run:

```powershell
.\scripts\check_install.ps1
```

The JSON report includes:

- `installed` — the target directory exists;
- `owned` — the exact ownership marker is valid for that target;
- `matches` — source and installed file sets, sizes, SHA-256 values, version,
  commit, and cachebuster match;
- `marketplaceVisible` — exactly one canonical personal entry exists and
  `codex plugin list` reports it installed and enabled;
- `sourceVersion` and `installedVersion`;
- `sourceCommit` and `installedSourceCommit`; and
- `cachebuster` and `installedCachebuster`;
- `marketplaceEntryCount` — the number of matching personal marketplace
  entries;
- `sourceFileCount` — the number of validated source payload files;
- `installRoot` — the canonical personal installation directory;
- `payloadError` — the bounded payload/ownership mismatch reason, or `null`;
  and
- `marketplaceError` — the bounded marketplace/CLI visibility reason, or
  `null`.

P3.3-R2 is acceptable only when all four booleans are `true`, the marketplace
entry count is one, and every paired metadata field matches.

Historical H4/G9 installed-copy acceptance uses the retained command:

```powershell
.\scripts\validate-gate4.ps1
```

P3.3-R2 does not run that historical smoke because it calls `inspect_host` and
a missing-ISO plan against the production adapter. P3.3-R2 instead pairs
`check_install.ps1` with the default
`validate-codex-app-server-catalog.ps1` catalog session and its explicit
`-MockToolCallSmoke` session. The former requires 31/31 payload hashes,
exactly 20 unique tool names, zero tool calls, and zero adapter operations; the
latter requires two mock calls, two mandatory test-only warnings,
`changed=false`, and zero real-operation counts. The
separately run local publication aggregate did invoke the inherited Gate 2
bounded read-only `inspect_host` and missing-ISO plan rejection outside the
declared P3.3 no-host boundary; it performed no mutation.

After an install or reinstall, start a new Codex task before testing the newly
loaded skill or MCP tools.

# Plugin installation

## Proven boundary

Gate 4 established the local personal-install mechanism for the 16-tool v1
runtime. Gate 9/H4 applies that same fail-closed mechanism exactly once to the
immutable-release-derived plugin `0.2.0` source. It copies the reviewed plugin
payload to
`%USERPROFILE%\plugins\hyperv-clean-room`, creates or updates exactly one entry
in the default personal marketplace through the `plugin-creator` helper, and
runs:

```powershell
codex plugin add hyperv-clean-room@personal
```

The installed MCP server is then started from the installed directory, not the
repository. Current acceptance requires server identity/version
`hyperv-clean-room` / `0.2.0`, exactly 20 tools, a successful read-only
`inspect_host`, and an `INVALID_ISO` rejection before mutation. This proves
local installation, marketplace visibility, and cache pickup only. It does not
prove a real VM or checkpoint mutation, credential enrollment, PowerShell
Direct guest behavior, package execution, or a clean Windows result.

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
and any version outside base `0.2.0` with at most one
`+codex.<cachebuster>` suffix. The integrated source payload contains exactly
31 Git-tracked ordinary files: five public schema-v1 files and seven schema-v2
files are included. Gate 9/H4 uses the single build
`0.2.0+codex.20260722114845`; the immutable `v0.2.0` tag remains unchanged.

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

Gate 9/H4 is acceptable only when all four booleans are `true`, the marketplace
entry count is one, and every paired metadata field matches.

Run the complete acceptance suite, whose historical name is retained, with:

```powershell
.\scripts\validate-gate4.ps1
```

After an install or reinstall, start a new Codex task before testing the newly
loaded skill or MCP tools.

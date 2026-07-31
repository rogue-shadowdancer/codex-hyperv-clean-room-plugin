# Installation maintenance

## Cachebuster reinstall loop

Codex caches installed plugin metadata. During local development, update the
source manifest only through the `plugin-creator` cachebuster helper:

```powershell
& "$env:SystemRoot\py.exe" -3 `
  "$HOME\.codex\skills\.system\plugin-creator\scripts\update_plugin_cachebuster.py" `
  .\hyperv-clean-room
```

Gate 9/H4 uses the helper's default UTC token exactly once. It preserves base
version `0.2.0`, replaces any previous build suffix, and produces
`0.2.0+codex.20260722114845`. Do not increment the numeric version only to
refresh Codex, do not append multiple cachebusters, and do not rerun the helper
for this accepted build. Gate 7/H2 and Gate 8/H3 performed no cachebuster update
or install.

G7/P3.2 changes the repository source base to `0.3.0` but deliberately performs
no installation or cachebuster update. G7/P3.3 invokes the same helper exactly
once and produces accepted personal build
`0.3.0+codex.20260729122233`. Reinstall that exact build from the final clean
closeout commit without invoking the helper again.

G7/P3.3-R1 advances the compatible patch runtime to `0.3.1`. Its helper was
invoked exactly once before the final release candidate was committed and
produced `0.3.1+codex.20260729184240`. Do not invoke the helper again during or
after merge, tagging, Release publication, or reinstall. The protected
`master`, annotated `v0.3.1` tag, source-only Release, and installed
`sourceCommit` must remain one commit.

G7/P3.3-R2 advances the compatible patch runtime to `0.3.2`. Its helper was
invoked exactly once before the final release candidate was committed and
produced `0.3.2+codex.20260731014242`. Do not invoke the helper again during or
after merge, tagging, Release publication, or reinstall. The protected
`master`, annotated `v0.3.2` tag, source-only Release, and installed
`sourceCommit` must remain one commit. Immutable v0.1.1 through v0.3.1 remain
unchanged.

The historical `v0.1.1` release used the helper exactly once and produced
`0.1.1+codex.20260715064728`. Release verification must preserve that value;
do not run the helper again merely to reinstall the accepted source commit.

Then validate, reinstall, and check:

```powershell
.\scripts\validate-install-source.ps1 -RequireCachebuster
.\scripts\install_plugin.ps1
.\scripts\check_install.ps1
```

`install_plugin.ps1` runs
`codex plugin add hyperv-clean-room@personal` as part of the reinstall. The
default personal marketplace at
`%USERPROFILE%\.agents\plugins\marketplace.json` is discovered implicitly;
do not run `codex plugin marketplace add` for this path. Start a new Codex task
after reinstall so newly loaded tools and skill content come from the updated
plugin.

## Ownership and drift

An existing `%USERPROFILE%\plugins\hyperv-clean-room` is writable by this
installer only when `.codex-plugin/install-ownership.json` has the exact v1
owner, plugin name, installation ID, and canonical target path. A missing,
foreign, malformed, or relocated marker stops the update before payload files
are copied. Do not manufacture a marker merely to force ownership.

The install manifest lists every payload file by relative path, byte size, and
SHA-256. `matches: false` means at least one file, inventory claim, source
commit, version, or cachebuster differs. Review `payloadError`; restore the
intended source and rerun the owned installer. The installer deliberately does
not remove extra files or replace an unowned directory.

After the Gate 4 source changes are committed, rerun `install_plugin.ps1` so
the installed `sourceCommit` records the new repository HEAD. A clean source
tree and a matching installed commit are required for the final gate handoff.

## Marketplace and CLI visibility

The personal marketplace must contain one canonical entry:

- name `hyperv-clean-room`;
- local source `./plugins/hyperv-clean-room`;
- installation policy `AVAILABLE`;
- authentication policy `ON_INSTALL`; and
- category `Developer Tools`.

Marketplace creation and replacement are performed only by
`plugin-creator/scripts/create_basic_plugin.py`. The installer never writes
`marketplace.json` or `config.toml` directly. `marketplaceVisible: false` with
a valid file means the Codex CLI did not report the expected installed and
enabled row. Run `codex plugin list`, confirm the personal path is local, and
rerun the installer; do not switch to an unrelated or remote marketplace.

## Verification boundary

`validate-gate4.ps1` reruns the Gate 2 mock/schema/static suite, source and
installer security tests, plugin-creator manifest validation, install-state
checks, and a 20-tool MCP process started only from the installed copy. The real host
portion remains limited to read-only `inspect_host` plus a nonexistent-ISO
plan rejection. It enrolls no credential, opens no guest session, executes no
package, and performs zero real Hyper-V mutations.

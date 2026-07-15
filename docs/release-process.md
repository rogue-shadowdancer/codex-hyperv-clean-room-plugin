# GPL public release and publication process

## Scope

This runbook governs the in-place conversion of
`rogue-shadowdancer/codex-hyperv-clean-room-plugin` from private to public as
`v0.1.1` under `GPL-3.0-only`. It preserves the repository URL, `master`, all
eight pre-release commits, and every existing object ID. It permits only an
additive release commit, normal pushes, an annotated unsigned tag, and a
source-only GitHub Release.

This process never authorizes a force push, amend, rebase, filter, history
rewrite, clean export, real Hyper-V or guest mutation, credential enrollment,
package lifecycle run, clean-machine claim, or publication of Birdsgone files.
The public API remains exactly 16 tools, five public schemas,
`schemaVersion: 1`, and four supported MCP protocol versions.

## Candidate prerequisites

Before editing or changing GitHub state:

1. Confirm the checkout is clean `master` at the same commit as
   `origin/master`, with exactly one approved HTTPS fetch URL and one approved
   effective push URL.
2. Confirm the GitHub repository is private, the viewer has `ADMIN`, there is
   one `master` branch, and there are no tags, Releases, or artifacts.
3. Confirm the owned personal install matches the source commit and marketplace
   entry and exposes exactly 16 tools.
4. Read `AGENTS.md`, this runbook, `docs/specification.md`, `TASK_HANDOFF.md`,
   and the other release authorities before mutation.
5. Inspect the separate Birdsgone workspace read-only. Never modify, stage,
   commit, remote-connect, or publish it from this process.

The eight preserved pre-release commits contain user-accepted legacy identity
metadata. The current tree must not duplicate that address. Publication hygiene
accepts those commits only when the SHA-256 digest of each exact raw commit
object matches the eight-value allowlist in
`tests/publication_hygiene_tests.py`. Any other legacy identity, changed raw
commit object, unexpected author/committer, or sensitive commit message fails.
All new commits and the tag use
`rogue-shadowdancer <78423508+rogue-shadowdancer@users.noreply.github.com>`
through repository-local Git configuration only.

## Release source

The release source must include:

- the standard GNU GPL version 3 text in `LICENSE` and manifest SPDX identifier
  `GPL-3.0-only`;
- plugin/server base version `0.1.1` and one helper-generated
  `0.1.1+codex.<UTC>` installed build;
- `CONTRIBUTING.md`, Contributor Covenant 2.1, issue forms and configuration,
  a pull request template, Dependabot, the public security policy, and
  synchronized English/Chinese documentation;
- `public-release-validation` with `contents: read`, full-history checkout,
  official v6 Actions pinned to full commit SHAs with version comments; and
- release-contract, publication-hygiene, GitHub Actions-log, anonymous
  readback, and regression checks.

Use `plugin-creator/scripts/update_plugin_cachebuster.py` exactly once after
setting base version `0.1.1`. Do not hand-edit marketplace/cache state and do
not create a second cachebuster during final reinstall.

## Local validation

Save full output only below ignored `.artifacts`. Require all of the following:

```powershell
.\scripts\prepare-test-python.ps1
.\scripts\validate-public-release.ps1
.\scripts\validate-github-actions-history.ps1
.\scripts\validate-gate4.ps1
```

`validate-public-release.ps1` is the aggregate local gate. It performs:

- PowerShell 5.1 parsing for every script;
- strict UTF-8, no BOM, no mojibake, JSON, Draft 2020-12 schema, YAML,
  Markdown/link, Python compile, and `git diff --check` validation;
- plugin-creator `validate_plugin.py` and skill-creator `quick_validate.py`;
- `validate-gate1.ps1`, no-argument `validate-gate2.ps1`,
  `validate-docs.ps1`, and `validate-gate4-ci.ps1`;
- `publication_hygiene_policy_tests.py`,
  `publication_hygiene_tests.py`, and
  `public_release_contract_tests.py`; and
- exact version, license, tool/schema/protocol, community, workflow pin, and
  not-performed boundary checks.

`validate-github-actions-history.ps1` enumerates every retained Actions run,
writes full logs only to `.artifacts/public-release/actions`, and scans them for
secrets, credentialed URLs, private local paths, non-public identities,
Birdsgone files/state, and VM/ISO/VHD/checkpoint/evidence/cache/log material.
Missing or unreadable logs fail closed.

The no-argument `validate-gate4.ps1` is run after the final commit and reinstall
so the installed manifest can bind to the immutable release SHA. Its real-host
surface remains read-only `inspect_host` plus nonexistent-ISO rejection and
must report zero real guest operations and zero Hyper-V mutations.

## Review gates

After the first complete candidate-safe validation pass, obtain three fresh
bounded read-only reviews:

- license, public metadata, community files, documentation, and versioning;
- full retained history, identities/messages, current-tree and Actions-log
  privacy; and
- install, PowerShell 5.1, CI, workflow pinning, and zero-mutation safety.

Fix every actionable finding and rerun affected checks. Then obtain three
entirely fresh signoff reviews over the final working tree. Each report must
contain `actionableFindings: []`. Any finding reopens implementation,
validation, and fresh signoff; only zero findings permits the release commit.

## Immutable release commit and private CI

Set only the repository-local Git identity and create one additive commit with
the exact message:

```text
release: open source v0.1.1 under GPL-3.0-only
```

Reinstall from that commit without another cachebuster. Run
`validate-gate4.ps1`, `check_install.ps1`, the public-release aggregate, and
Actions-history scan. Require source and installed version/cachebuster/SHA and
payload hashes to match.

Fetch, require a normal fast-forward relationship, and push `master` while the
repository is still private. Wait for `public-release-validation` to complete
successfully on the exact release SHA. Read back GitHub license detection as
GPL v3 and rescan all Actions logs including that commit run. Any source fix
must be a new additive private commit followed by affected validation, fresh
reviews, reinstall, push, and exact-commit CI.

## Public visibility and settings

Only after every private prerequisite passes, switch visibility with:

```powershell
gh repo edit rogue-shadowdancer/codex-hyperv-clean-room-plugin `
  --visibility public --accept-visibility-change-consequences
```

After the switch, do not modify repository source files. Freeze repository
metadata to exactly:

- description: `Guarded Windows Hyper-V clean-room and package lifecycle testing for Codex via typed MCP tools.`;
- homepage: empty;
- topics: `codex-plugin`, `mcp-server`, `hyper-v`, `windows`, `powershell`,
  `virtualization`, `clean-room`, `package-testing`, and `test-automation`;
- Issues on; Wiki, Projects, Discussions, and Pages off; and
- private vulnerability reporting on.

Set description/homepage/features with `gh repo edit`, replace topics through
`PUT /repos/{owner}/{repo}/topics`, enable private vulnerability reporting
through its repository endpoint, and require `GET /pages` to return HTTP 404.
Do not leave an extra topic or an unspecified feature state.

Run `scripts/verify-anonymous-public-readback.ps1` without authentication. It
must verify the public `master` SHA, GPL detection, root README and LICENSE,
manifest, companion skill, documentation center, and Simplified Chinese
profile guide as strict UTF-8 without BOM or mojibake.

Protect `master` with this exact API payload:

```powershell
@'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["public-release-validation"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": false,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 1,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": false
}
'@ | gh api --method PUT `
  repos/rogue-shadowdancer/codex-hyperv-clean-room-plugin/branches/master/protection `
  --input -
```

Required commit signatures (`required_signatures`) remain disabled. Run
`scripts/validate-public-github-settings.ps1` and require exact readback of the
metadata, features, GPL detection, Pages/vulnerability state, status-check
strictness/context, one non-stale non-code-owner approval, conversation
resolution, null restrictions, all false Boolean controls, disabled
signatures, and `enforce_admins: false`.

## Tag and GitHub Release

Create annotated unsigned tag `v0.1.1` at the exact release SHA using the
repository noreply identity and push it normally. Wait for the tag-triggered
`public-release-validation` run to succeed. Create a non-prerelease GitHub
Release titled `v0.1.1` that states:

- licensing is GPL-3.0-only;
- the public contract is 16 tools, five schemas, and schema version 1;
- the owned installed copy matches the release SHA and cachebuster; and
- clean-machine, credential, real guest/package, VM/checkpoint, and manual GUI
  scopes remain `notPerformed`.

Upload no binaries, archives, logs, evidence, or other assets. GitHub's source
archives are the only downloads.

## Post-public acceptance and source-fix rule

Obtain two fresh read-only reviews after the Release exists:

- remote SHA, CI, license, community files, repository settings/protection,
  tag, Release, and anonymous access; and
- installed-copy/marketplace consistency plus the read-only Birdsgone
  separation and explicit untested scope.

Both reports must contain `actionableFindings: []`. External evidence for the
public state is retained by the completing task; it does not trigger a source
edit.
If a source defect is found after the visibility switch, create a new public
branch, pull request, and CI/review flow. Never re-private the repository as a
rollback and never bypass protected `master`.

Gate 6 clean-machine and real-guest validation remains `notPerformed` and is
not authorized by this release process.

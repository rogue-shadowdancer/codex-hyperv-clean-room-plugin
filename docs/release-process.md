# Private release and publication process

## Scope

This runbook governs source publication for the pre-release `0.1.0` line to
the private repository `rogue-shadowdancer/codex-hyperv-clean-room-plugin`.
It does not authorize a public visibility change, tag, GitHub Release, history
rewrite, force push, clean-machine test, credential enrollment, guest package
lifecycle, or VM/checkpoint mutation.

The six commits that precede Gate 5 are preserved. Publication adds commits on
`master`; it does not amend, rebase, filter, or replace earlier author metadata.
The local build suffix `0.1.0+codex.20260714150737` is a Codex cachebuster, not
a new base release or schema version.

## Candidate prerequisites

Before creating or changing a remote:

1. Confirm the branch is `master`, the expected history is present, the remote
   destination does not already exist, and every dirty path belongs to the
   Gate 5 candidate.
2. Confirm the plugin still exposes exactly 16 tools, five public schemas,
   base version `0.1.0`, and schema version 1.
3. Confirm Birdsgone and all VM, VHDX, checkpoint, ISO, credential, DPAPI,
   evidence, installed-control, cache, log, and machine-state paths are absent
   from the publishable tree and history.
4. Confirm the GitHub account and exact private destination. Do not create a
   public or internal repository as a substitute.

## Local validation

Prepare the pinned ABI-isolated Python environment, then run the documentation,
publication, CI-safe, and full installed-copy checks:

```powershell
.\scripts\prepare-test-python.ps1
.\scripts\validate-docs.ps1
& (Get-Command python).Source -S .\tests\publication_hygiene_policy_tests.py
& (Get-Command python).Source -S .\tests\publication_hygiene_tests.py
.\scripts\validate-gate4-ci.ps1
.\scripts\validate-gate4.ps1
```

`publication_hygiene_tests.py` examines the prospective working tree and every
reachable historical blob. It rejects forbidden state artifacts, installed
control files, Birdsgone paths at any depth, cache/evidence/Hyper-V state,
high-confidence secret forms, syntax-bound JSON/YAML/assignment secret
literals, absolute user or workspace paths, non-UTF-8 text, UTF-8 BOMs,
unexpected binary blobs, and blobs too large for the bounded scan. The adjacent
policy regression suite proves both rejection cases and narrow allowances for
redaction sentinels and environment/reference expressions; the scanner has no
directory-wide test exemption.

`validate-gate4-ci.ps1` is the non-machine-specific Gate 4 path. It runs the
mock/schema/static/documentation baseline, source inventory, and local
installer-security fixture. It explicitly skips the real-host smoke and
performs zero personal installation operations, marketplace mutations,
installed-copy operations, guest operations, and Hyper-V mutations.

The no-argument `validate-gate4.ps1` remains the workstation acceptance. It
also requires the owned personal install to match the current clean source
commit and runs only the installed-copy tool discovery, read-only host
inspection, and nonexistent-ISO rejection. It is not a clean-machine test.

## Review gate

After the candidate is complete and validation is green, obtain fresh bounded
read-only signoff for all of these scopes:

- affected source, tests, and PowerShell 5.1 behavior;
- documentation, release-state honesty, CI coverage, and reproducibility; and
- publication privacy, tracked/history sensitive state, destination, and
  pre-push safety.

Any actionable finding returns the candidate to implementation and validation.
Do not create the remote until the replacement reviews have zero actionable
findings.

## Immutable terminal commit

After the final pre-push reviews return zero actionable findings, commit the
complete source, documentation, validation, CI, and handoff candidate once.
The commit containing `TASK_HANDOFF.md` is the terminal Gate 5 repository
state. Reinstall from that commit without changing the cachebuster, run the
no-argument full validation, and require the installed source commit to equal
that terminal `HEAD` before creating the remote.

From this point onward, do not edit, commit, or generate any publishable
repository file. Validation logs remain ignored local artifacts. Publication,
Actions, installed-copy readback, and remote reviewer results are external gate
evidence; they do not trigger a follow-up handoff commit.
External gate evidence is retained by the completing Codex task.

## Private publication

Create only the exact private repository, without pushing from the creation
command so visibility can be read back first:

```powershell
gh repo create rogue-shadowdancer/codex-hyperv-clean-room-plugin `
  --private --source . --remote origin
gh repo view rogue-shadowdancer/codex-hyperv-clean-room-plugin `
  --json nameWithOwner,visibility,defaultBranchRef
$expectedOrigin = 'https://github.com/rogue-shadowdancer/codex-hyperv-clean-room-plugin.git'
$fetchUrls = @(git remote get-url --all origin)
$fetchReadSucceeded = $LASTEXITCODE -eq 0
$pushUrls = @(git remote get-url --push --all origin)
$pushReadSucceeded = $LASTEXITCODE -eq 0
if (-not $fetchReadSucceeded -or -not $pushReadSucceeded -or
    $fetchUrls.Count -ne 1 -or $pushUrls.Count -ne 1 -or
    $fetchUrls[0] -cne $expectedOrigin -or
    $pushUrls[0] -cne $expectedOrigin) {
    throw 'Origin fetch/push URLs are not exactly the approved private destination.'
}
git push -u origin master
```

Stop if the destination already exists unexpectedly, visibility is not
`PRIVATE`, the remote URL is not the exact destination, or the push would not
be a normal fast-forward first publication. Never use force push.

## Actions and remote acceptance

The workflow checks out full history and explicitly runs documentation
validation, the publication-sensitive working-tree/history scan, and
`validate-gate4-ci.ps1`. Wait for the final `master` workflow to finish
successfully; do not treat a queued or running workflow as acceptance.

Obtain two fresh remote acceptance reviews against the same immutable terminal
commit. Together they must read back:

- exact private visibility, owner/name, default branch, and local tracking;
- equality of local `HEAD`, `origin/master`, and the remote `master` object;
- strict UTF-8/no-BOM remote source and expected file inventory;
- successful final Actions status at that exact commit; and
- installed source commit/version/cachebuster and payload hashes matching the
  same final commit, with 16 tools and zero real mutations.

The two final review reports and the final command readbacks are external gate
evidence held by the completing Codex task. Do not edit, commit, or push any
repository file after the terminal commit; any later repository edit would
create an unaccepted SHA. Gate 5 ends when that immutable commit satisfies
every check above and both external reviews return zero actionable findings. Any
clean-machine, credential, real guest, package, VM, or checkpoint work belongs
to a separately authorized gate.

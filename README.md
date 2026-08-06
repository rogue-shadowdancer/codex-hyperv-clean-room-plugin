# Hyper-V Clean Room for Codex

## English

`hyperv-clean-room` is a Windows-only Codex plugin design for guarded Hyper-V
VM operations, declarative current-user package lifecycle tests, and structured
evidence.

### Status: 0.4.1 Windows MCP environment compatibility repair candidate

The `0.4.1` repair candidate retains the merged production `list_vms` shallow
projection, the frozen `0.3.0` capability target, exactly 20 public tool names
and closed inputs, and every Plan/Apply consumption and drift boundary. Its MCP
configuration passes through only the host-provided `COMPUTERNAME` variable.
At the earliest runtime initialization stage, a child that still has a missing
or whitespace value restores only its process-local value from
`[Environment]::MachineName`. It does not write user/system environment state,
the registry, Codex configuration, marketplace data, or raw environment logs.

The candidate retains the v0.4.0 least-privilege authorization model.
Production Hyper-V access accepts either an enabled local `Hyper-V
Administrators` token or an elevated Administrator token. The former is the
preferred least-privilege mode; elevated compatibility remains available but
every successful result carries a `BROADER_PRIVILEGE_CONTEXT` warning.

`inspect_host` remains an unauthenticated diagnostic and reports only
`elevated`, `hyperVAdministratorsTokenEnabled`, `hyperVAuthorized`, and the
closed `authorizationMode`; it never returns a user name or user SID.
`list_vms`, `inspect_vm`, and host Plan/Apply paths fail with
`HYPERV_AUTHORIZATION_REQUIRED` when neither authorization is present. Real VM
create, checkpoint create/restore, power, and network adapters independently
re-read the live process token at the mutation boundary. ISO/VM-root checks are
read-only; state initialization validates every required state child with
bounded delete-on-close probes. All access failures use precise fail-closed
errors.

The selected-plugin Codex app-server validator remains catalog-only by default
with 20/20 unique tools and `toolCallCount: 0`. An explicit test-only mode
launches an isolated selected MCP child with the mock adapter, calls only
`inspect_host` and `list_vms`, requires `changed=false` plus the mandatory
`TEST_ONLY_MOCK_ADAPTER` warning, and reports zero real-operation counts.

The repository regression deliberately removes `COMPUTERNAME` from a fresh
PowerShell 5.1 child, completes the MCP handshake in mock mode, and separately
runs production-adapter `inspect_host` plus `list_vms(managedOnly=false)` as a
read-only real-host diagnostic. That diagnostic is repair evidence only: it is
not installed-plugin or Gate C acceptance and performs no `inspect_vm`,
Plan/Apply, guest, credential, evidence, or Hyper-V mutation operation.

The released v0.4.0 source froze exactly one
`0.4.0+codex.20260731141404` personal build. The v0.4.1 source Gate freezes the
single `0.4.1+codex.20260805101924` build only after its code, tests, and
documentation are stable.
Exact installed-plugin and Gate C acceptance remain later gates. Immutable
v0.1.1 through v0.4.0 are historical and are not moved or overwritten.

Gate 2 implements the PowerShell 5.1 MCP runtime against the frozen v1 cleanup,
profile, evidence, plan, and credential contracts. The first public release
used plugin base version `0.1.1` and `schemaVersion: 1`, with exactly 16 MCP tools
and five public Draft 2020-12 schemas.

Gate 4 adds a source-validated, ownership-marked personal installation at
`%USERPROFILE%\plugins\hyperv-clean-room`, one canonical personal marketplace
entry managed only through `plugin-creator`, and one cachebuster reinstall.
Installed-copy acceptance starts the MCP server only from that installed path,
discovers exactly 16 tools, passes read-only `inspect_host`, rejects a missing
ISO before mutation, and reports zero real Hyper-V mutations.

Gate 5.1 releases plugin base version `0.1.1` under
[`GPL-3.0-only`](LICENSE). It adds public contribution and community files,
SHA-pinned `public-release-validation`, Dependabot, a fail-closed public-release
contract, full current-tree/history/identity/Actions-log hygiene, and a
source-only `v0.1.1` GitHub Release. That immutable release used cachebuster
`0.1.1+codex.20260715064728`.

Gate 5.2 keeps base version `0.1.1` and adds the canonical public repository
URL to `homepage`, `repository`, and `interface.websiteURL` for Codex plugin
details. The current `master` personal-install build is
`0.1.1+codex.20260715084043`; build metadata does not change the public plugin
or schema version, and no new GitHub Release is created.

Gate 6/H1 freezes the additive plugin `0.2.0`, schema-v2 automation contract
under [`contracts/v2`](contracts/v2/README.md). It preserves the exact 16 v1
tools and five v1 schemas while specifying four guarded power/network tools,
portable ZIP deployment, fixed Microsoft EdgeDriver verification, a closed
`data-testid` UI DSL, evidence v2, and deterministic compatibility fixtures.
Gate 7/H2 integrates that frozen contract into the PowerShell 5.1 production
source: plugin `0.2.0`, exact schema-version dispatch, the preserved 16 MCP
tools plus four guarded power/network tools (20 MCP tools total), five public
schema-v1 files plus seven schema-v2 files, atomic portable slots/data
preservation, fixed-driver provenance, the closed UI dispatcher, evidence v2,
and deterministic migration. H2 validation used only mock adapters, parsers,
and static checks; at that gate, release and all machine-backed work remained
`notPerformed`.

Gate 8/H3 publishes the immutable source-only
[`v0.2.0`](https://github.com/rogue-shadowdancer/codex-hyperv-clean-room-plugin/releases/tag/v0.2.0)
tag and GitHub Release from accepted commit
`642f20d1d74a54ecbb08115b1a921ca65ef01fb8`. Source publication is verified by
hosted CI plus authenticated and anonymous readback.

Gate 9/H4 preserves that immutable tag and performs the one authorized
release-derived personal cachebuster installation. The installed build is
`0.2.0+codex.20260722114845`: its owned 31-file payload, source commit,
per-file size/SHA-256 inventory, single canonical personal marketplace entry,
and Codex installed/enabled state are commit-bound. Installed-copy acceptance
starts only the personal copy, reads runtime base version `0.2.0`, discovers
exactly 20 tools, passes read-only
`inspect_host`, rejects a nonexistent ISO with `INVALID_ISO` before mutation,
and reports zero real guest operations and zero real Hyper-V mutations. Real
VM, credential, guest, package, portable, WebDriver, network, UI, manual, and
clean-machine operations remain `notPerformed`.

H5A preserves the immutable release and 20-tool surface while repairing the
automatic-checkpoint ownership deadlock found during the first real VM setup.
New VMs disable automatic checkpoints before ownership publication. Existing
pre-fix VMs are recognized only when a complete identity-bearing `.avhdx`
chain hashes consistently and terminates at the unchanged recorded base
`.vhdx`; unrelated, broken, cyclic, incomplete, or forged chains still fail
closed. The H5A personal candidate uses
`0.2.0+codex.20260723113253`. The repair does not adopt or rewrite ownership,
delete or merge a checkpoint, or authorize Windows OOBE/package/UI work.

G7/P3.1 freezes the next additive `0.3.0` schema/fixture target from the
immutable Birdsgone G6 consumer contract. It preserves all 20 tool names and
inputs, all five schema-v1 files, and the old embedded schema-v2 branch while
adding a mutually exclusive, profile-relative external-manifest branch,
generic portable packages with conditional components, and structurally
separate external evidence. The external manifest keeps the historical
`runtime-and-legal-only` shape readable but permits execution only for the
protected `end-user-complete` branch, which binds the complete documentation
mapping, non-developer prerequisites, and four-asset topology. The neutral
fixture has no WebView2, MaaFramework, driver, or UI step; all consumer-shaped
fixtures are synthetic. The plugin manifest, PowerShell runtime, and
source-tree schema copies remained `0.2.0` through P3.1.

G7/P3.2 implements that frozen target in the source runtime as plugin `0.3.0`.
The seven source-tree installed schema copies are now byte-identical to their
authorities. Native readers strictly parse the profile-relative manifest
sidecar, reject unsafe or colliding Windows paths and closed-object drift,
rebind source/staged/guest bytes, enforce bidirectional ZIP inventory, deploy
an atomic data-preserving slot, launch the manifest entrypoint with zero caller
arguments, and emit structurally separate external evidence. Generic non-UI
packages omit driver identity; UI packages retain the closed fixed-driver DSL.
The exact 20-tool catalog, v1 files, and embedded `0.2.0` semantics are
unchanged. P3.2 validation is mock/parser/schema/static only.

G7/P3.3 publishes the accepted protected-master source commit
`47151fdbe99346ec87af09460c79d0864978eabd` as the immutable annotated,
source-only
[`v0.3.0`](https://github.com/rogue-shadowdancer/codex-hyperv-clean-room-plugin/releases/tag/v0.3.0)
tag and GitHub Release. Tag workflow `30451106948`, authenticated readback, and
anonymous readback bind the tag to that commit and confirm a non-draft,
non-prerelease Release with zero uploaded assets. The one authorized personal
build is `0.3.0+codex.20260729122233`; its owned 31-file payload, per-file
size/SHA-256 inventory, exact source commit and cachebuster, single canonical
personal marketplace entry, and Codex installed/enabled state are closed by
the installer. Catalog-only installed-server readback negotiates MCP
`2025-11-25` and discovers exactly 20 unique tools without calling any tool.
That catalog readback performs no real machine or adapter operation. The local
publication aggregate nevertheless invoked its inherited Gate 2 bounded
read-only `inspect_host` and missing-ISO `plan_vm_create` rejection, contrary
to the declared P3.3 no-host boundary. No Hyper-V/VM/checkpoint mutation,
credential or guest operation, package or portable execution, WebDriver/UI or
network operation, evidence collection, or manual attestation was performed.

[![public-release-validation](https://github.com/rogue-shadowdancer/codex-hyperv-clean-room-plugin/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/rogue-shadowdancer/codex-hyperv-clean-room-plugin/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

JSON-RPC transport, common envelopes, persistent ownership and atomic plan
guards, native profile/evidence validation, mock-backed guest/test flows,
evidence export, and the interactive DPAPI credential initializer are
implemented and tested. The production guest adapter now has a fixed,
administrator-supervised PowerShell Direct implementation: a hash-verified
plugin worker executes the closed declarative step set as the standard test
user with operation-scoped staging and PID identity. Gate 2 validates that path
through mock behavior, parsers, and static seams only. No real guest operation,
Hyper-V mutation, or package workflow was authorized or executed; do not
present this revision as clean-machine-validated automation. Clean-machine,
credential, real guest/package, VM/checkpoint, and manual GUI scopes remain
`notPerformed`.

The frozen safety model includes:

- inspect, plan, atomically consume, revalidate, then apply;
- mutate only plugin-owned VM identities;
- never expose VM, VHDX, checkpoint, guest-state, or host-path deletion tools;
- keep credentials out of MCP inputs, repositories, logs, and evidence;
- reject arbitrary commands and unsafe paths in test profiles;
- stage each test artifact and its evidence inside operation-scoped,
  server-controlled roots;
- run only bounded, non-destructive cleanup after an execution-phase failure;
- keep automatic, manual, and cleanup results distinct, with cleanup excluded
  from `overallStatus` derivation.

Read the [documentation center](docs/README.md),
[installation guide](docs/installation.md),
[installation maintenance guide](docs/maintenance.md),
[public release process](docs/release-process.md),
[architecture](docs/architecture.md), [operations guide](docs/operations.md),
[evidence model](docs/evidence.md), [security design](docs/security.md),
[troubleshooting guide](docs/troubleshooting.md), authoritative
[specification](docs/specification.md), Simplified Chinese
[profile authoring guide](docs/profile-authoring.md), and the single complete
[minimal profile example](examples/minimal-test-profile.json). Gate results and
the next entry point are in [TASK_HANDOFF.md](TASK_HANDOFF.md); source milestones
are recorded in the [changelog](CHANGELOG.md).

Public contributions are welcome through [CONTRIBUTING.md](CONTRIBUTING.md)
under the [Contributor Covenant 2.1](CODE_OF_CONDUCT.md). Report
vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

Development and CI use Python for Draft 2020-12 schema checks and repository
quality validation only. The production runtime uses Windows PowerShell 5.1
and does not depend on Python.

Prepare the pinned, ABI-isolated development dependencies once, then run the
complete Gate 2 checks with no arguments:

```powershell
.\scripts\prepare-test-python.ps1
.\scripts\validate-gate2.ps1
```

The validation uses the repository marketplace fixture, touches the real host
only through `inspect_host` and a nonexistent-ISO plan rejection, performs no
real guest operation, and reports zero real Hyper-V mutations.

For the current Gate 9/H4 installed-copy validation (the historical script
name is retained):

```powershell
.\scripts\validate-gate4.ps1
```

For the non-machine-specific CI-safe Gate 4 path and the publication scan:

```powershell
& (Get-Command python).Source -S .\tests\publication_hygiene_policy_tests.py
& (Get-Command python).Source -S .\tests\publication_hygiene_tests.py
.\scripts\validate-gate4-ci.ps1
```

This does not claim clean-machine, live guest, credential, package, VM, or
checkpoint success.

## 简体中文

`hyperv-clean-room` 是一个仅面向 Windows 的 Codex plugin 设计，用于受保护的
Hyper-V VM 操作、声明式 current-user package lifecycle 测试和结构化 evidence。

### 状态：v0.4.1 Windows MCP `COMPUTERNAME` 兼容性修复候选

当前 repair candidate 保留已合并的 `list_vms` 最小投影、冻结的 `0.3.0`
capability target、精确 20 个公开工具、全部 input schema、Plan/Apply、恢复和
evidence 语义。`.mcp.json` 只透传宿主提供的 `COMPUTERNAME`；若新 MCP child
仍缺失该变量或其值仅为空白，最早的 runtime 初始化只在该 child process 内从
`[Environment]::MachineName` 恢复它。此修复不会写 user/system environment、
registry、Codex config、marketplace，也不会记录原始 environment。唯一候选 build
已冻结为
`0.4.1+codex.20260805101924`，不得在 review、merge、安装或 Release 时重生成。

本 Gate 的 repository diagnostic 会在缺失 `COMPUTERNAME` 的条件下完成 mock MCP
handshake，并通过 production adapter 只读调用 `inspect_host` 与
`list_vms(managedOnly=false)`。该结果只证明本次修复，不是 installed-plugin 或
Gate C 验收；`inspect_vm`、Plan/Apply、guest、credential、evidence 与全部 Hyper-V
mutation 均未执行。受保护 PR 普通合并后，后续独立 Gate 才能绑定 exact protected
commit 进行安装。

Codex app-server 验收默认仍只检查 20/20 unique tools，并保持
`toolCallCount: 0`。显式 test-only 模式只在隔离的 selected MCP child 中启用
mock adapter，依次验证 `inspect_host` / `list_vms` 的 `changed=false` 与强制
`TEST_ONLY_MOCK_ADAPTER` warning，并要求真实操作计数为零。

历史 `0.3.2` tool-call metadata 修复及其唯一 personal build
`0.3.2+codex.20260731014242` 保持不可变；v0.1.1 至 v0.4.0 的历史 tag、Release
和 build identity 都不移动、不覆盖。

Gate 2 已依据冻结的 v1 cleanup、profile、evidence、plan 和 credential 合同实现
PowerShell 5.1 MCP runtime。首个 public release 使用 plugin base version
`0.1.1` 与 `schemaVersion: 1`，并保持精确 16 个 MCP tools 和 5 个 public
Draft 2020-12 schemas。

Gate 4 新增经过 source validation 与 ownership marker 保护的个人安装路径
`%USERPROFILE%\plugins\hyperv-clean-room`，通过 `plugin-creator` 维护唯一的
personal marketplace entry，并完成一次 cachebuster 重装演练。installed-copy
验收只从安装目录启动 MCP server，确认 16 个 tools、只读 `inspect_host`、
不存在 ISO 的 mutation 前拒绝，以及真实 Hyper-V mutation 为零。
Gate 4 的最终验收还要求 plugin payload 与已提交的 `HEAD` 一致，并以
[TASK_HANDOFF.md](TASK_HANDOFF.md)记录 post-commit 重装状态。

Gate 5.1 以 [`GPL-3.0-only`](LICENSE) 发布 `v0.1.1`，新增 public community
文件、固定完整 SHA 的 `public-release-validation`、Dependabot、fail-closed release
contract，以及 current tree、完整 history、commit identity 和 Actions log hygiene
检查。不可变的 `v0.1.1` tag 与 GitHub Release 使用 cachebuster
`0.1.1+codex.20260715064728`。

Gate 5.2 保持 base version `0.1.1`，并让 manifest 的 `homepage`、`repository`
与 `interface.websiteURL` 统一指向规范 GitHub 仓库地址。当前 `master` 的
personal-install build 为 `0.1.1+codex.20260715084043`；该 build metadata 不改变
public plugin semver 或 schema version，也不创建新的 GitHub Release。

Gate 6/H1 在 [`contracts/v2`](contracts/v2/README.md) 冻结 plugin `0.2.0`、
schema-v2 目标合同：精确保留 16 个 v1 tools 与五个 v1 schemas，并定义四个受保护的
power/network tools、portable ZIP、固定 Microsoft EdgeDriver、闭合 `data-testid`
UI DSL、evidence v2 与确定性兼容 fixture。Gate 7/H2 已把该冻结合同集成到
PowerShell 5.1 production source：plugin `0.2.0`、精确 schema-version 分派、保留的
16 个 tools 加四个新 tools（合计 20 MCP tools）、五个 public schema-v1 文件加
seven schema-v2 文件，以及对应的 portable、driver、UI、evidence 和 migration
路径。H2 只执行 mock adapter、parser 与 static 验证；当时发布和所有机器侧工作均为
`notPerformed`。

Gate 8/H3 已从 accepted commit
`642f20d1d74a54ecbb08115b1a921ca65ef01fb8` 发布不可变、source-only 的
[`v0.2.0`](https://github.com/rogue-shadowdancer/codex-hyperv-clean-room-plugin/releases/tag/v0.2.0)
tag 与 GitHub Release，并通过 hosted CI、认证及匿名读回。

Gate 9/H4 保持该 tag 不变，并完成一次获授权的、从 release source 派生的 personal
cachebuster 安装。installed build 为 `0.2.0+codex.20260722114845`；受 ownership
marker 保护的 31-file payload、source commit、逐文件 size/SHA-256 inventory、唯一
canonical personal marketplace entry，以及 Codex installed/enabled 状态均与提交绑定。
installed-copy 验收只启动 personal copy，读回 runtime base version `0.2.0`，发现精确
20 个 tools，执行只读
`inspect_host`，并让不存在的 ISO 在 mutation 前以 `INVALID_ISO` 失败；real guest
operation 与 real Hyper-V mutation 均为零。真实 VM、credential、guest、package、
portable、WebDriver、network、UI、manual 与 clean-machine operation 仍为
`notPerformed`。

H5A 保持不可变 release 与 20-tool surface 不变，并修复首次真实 VM setup 暴露的
automatic-checkpoint ownership deadlock。新建 VM 会在发布 ownership 前禁用 automatic
checkpoints。对既有 pre-fix VM，只有完整、带 identity 的 `.avhdx` chain 具有一致 hash，
且终点仍是 ownership record 中未改变的 base `.vhdx` 时才会通过；不相关、断裂、循环、
不完整或伪造 chain 继续 fail closed。H5A personal candidate 为
`0.2.0+codex.20260723113253`。该修复不会 adopt 或重写 ownership，不会删除或 merge
checkpoint，也不授权 Windows OOBE、package 或 UI 工作。

G7/P3.1 从不可变 Birdsgone G6 consumer contract 冻结 `0.3.0` target；G7/P3.2
把该 target 集成到 source runtime。plugin manifest 与 PowerShell source 现为
`0.3.0`，七份 source-tree installed schema 与权威 schema 逐字节一致；精确 20 个
tool 名称/input、五份 v1 schema 与原有 embedded `0.2.0` 行为保持不变。外部
portable manifest 作为 profile-relative sidecar 被 strict UTF-8 解析，经过安全
Windows path、closed provenance、source/staged/guest byte binding 与双向 ZIP
inventory 校验后，才会原子发布 data-preserving slot；entrypoint 不接收 caller
argument。non-UI 分支不生成 driver identity，UI 分支继续使用闭合的固定 driver DSL。
P3.2 仅执行 mock/parser/schema/static 验证。

G7/P3.3 已把 protected `master`
`47151fdbe99346ec87af09460c79d0864978eabd` 发布为不可变、annotated、source-only 的
[`v0.3.0`](https://github.com/rogue-shadowdancer/codex-hyperv-clean-room-plugin/releases/tag/v0.3.0)
tag 与 GitHub Release。tag workflow `30451106948`、认证读回与匿名读回均把 tag
绑定到该 commit，并确认 Release 不是 draft/prerelease，且 uploaded asset 为零。
唯一获授权的 personal build 为 `0.3.0+codex.20260729122233`；installer 对受
ownership marker 保护的 31-file payload、逐文件 size/SHA-256、精确 source
commit/cachebuster、唯一 canonical personal marketplace entry 及 Codex
installed/enabled 状态实行闭合校验。catalog-only installed-server 读回协商 MCP
`2025-11-25`，发现精确 20 个 unique tools，且不调用任何 tool。该 catalog readback
没有执行真实 MCP tool 或 adapter operation。可是 local publication aggregate 仍
调用了继承自 Gate 2 的有界只读 `inspect_host` 与 missing-ISO `plan_vm_create`
拒绝；这偏离了 P3.3 已声明的 no-host boundary。该过程没有执行
Hyper-V/VM/checkpoint mutation、credential/guest operation、package/portable
execution、WebDriver/UI/network operation、evidence collection 或 manual
attestation。

JSON-RPC transport、common envelope、持久 ownership 与原子 plan guard、原生
profile/evidence validation、mock-backed guest/test flow、evidence export 和交互式
DPAPI credential initializer 均已实现并通过测试。Production guest adapter 现已实现
固定的、由 administrator 监督的 PowerShell Direct 路径：经过 SHA-256 校验的 plugin
worker 以 standard test user 身份执行闭合的声明式 step，并把 staging 与 PID identity
绑定到 operation。Gate 2 只通过 mock behavior、parser 与 static seam 验证该路径；未获
授权、也未执行任何真实 guest operation、Hyper-V mutation 或 package workflow，
不得把当前版本描述为已经通过 clean-machine 验证的自动化工具；clean-machine、
credential、real guest/package、VM/checkpoint 与 manual GUI 范围仍为
`notPerformed`。

已冻结的安全边界包括：

- 先 inspect 和 plan，再原子 consume、复核并 apply；
- 只 mutation plugin-owned VM identity；
- 不暴露 VM、VHDX、checkpoint、guest state 或 host path 删除工具；
- credential 不进入 MCP input、repository、log 或 evidence；
- test profile 拒绝任意 command 和不安全 path；
- 每次 test operation 使用独立、server-controlled artifact/evidence staging root；
- 仅在 execution-phase failure 后执行有界、非破坏性 cleanup；
- automatic、manual 与 cleanup results 分离，cleanup 不参与 `overallStatus` 推导。

请从[文档中心](docs/README.md)开始，并参考
[installation](docs/installation.md)、[maintenance](docs/maintenance.md)、
[public release process](docs/release-process.md)、
[architecture](docs/architecture.md)、[operations guide](docs/operations.md)、
[evidence model](docs/evidence.md)、[security design](docs/security.md)、
[troubleshooting guide](docs/troubleshooting.md)、权威
[specification](docs/specification.md)、简体中文
[profile 编写指南](docs/profile-authoring.md)和唯一完整的
[最小 profile 示例](examples/minimal-test-profile.json)。Gate 结果和下一入口位于
[TASK_HANDOFF.md](TASK_HANDOFF.md)，source milestone 记录在
[changelog](CHANGELOG.md)。参与贡献请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)
与 [Contributor Covenant 2.1](CODE_OF_CONDUCT.md)；安全问题请按
[SECURITY.md](SECURITY.md) 使用私密渠道报告。

Python 只用于开发和 CI 的 Draft 2020-12 schema 检查与 repository quality
验证；production runtime 使用 Windows PowerShell 5.1，且不依赖 Python。先准备
pinned、ABI-isolated 开发依赖，再使用无参数命令完成 Gate 2 检查：

```powershell
.\scripts\prepare-test-python.ps1
.\scripts\validate-gate2.ps1
```

验证使用仓库内 marketplace fixture；真实 host 只执行 `inspect_host` 和不存在 ISO 的
安全 plan rejection，不执行 real guest operation，并报告真实 Hyper-V mutation 为零。

当前 Gate 9/H4 installed-copy 验证继续使用历史脚本名：

```powershell
.\scripts\validate-gate4.ps1
```

CI-safe Gate 4 路径与 publication 扫描命令为：

```powershell
& (Get-Command python).Source -S .\tests\publication_hygiene_policy_tests.py
& (Get-Command python).Source -S .\tests\publication_hygiene_tests.py
.\scripts\validate-gate4-ci.ps1
```

该结果不代表 clean-machine、live guest、credential、package、VM 或 checkpoint 已通过。

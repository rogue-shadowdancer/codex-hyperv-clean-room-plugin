# Hyper-V Clean Room for Codex

## English

`hyperv-clean-room` is a Windows-only Codex plugin design for guarded Hyper-V
VM operations, declarative current-user package lifecycle tests, and structured
evidence.

### Status: v0.1.1 GPL public release

Gate 2 implements the PowerShell 5.1 MCP runtime against the frozen v1 cleanup,
profile, evidence, plan, and credential contracts. The public release uses
plugin base version `0.1.1` and `schemaVersion: 1`, with exactly 16 MCP tools
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
source-only `v0.1.1` GitHub Release. The installed build uses the single
cachebuster `0.1.1+codex.20260715064728`; build metadata does not change the
public plugin or schema version.

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

For the complete installed-copy Gate 4 validation:

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

### 状态：v0.1.1 GPL public release

Gate 2 已依据冻结的 v1 cleanup、profile、evidence、plan 和 credential 合同实现
PowerShell 5.1 MCP runtime。当前 public plugin base version 为 `0.1.1`，
`schemaVersion: 1`，并保持精确 16 个 MCP tools 和 5 个 public Draft 2020-12
schemas。

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
检查。安装版本使用唯一 cachebuster `0.1.1+codex.20260715064728`；该 build metadata
不改变 public plugin semver 或 schema version。

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

完整的 installed-copy Gate 4 验证命令为：

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

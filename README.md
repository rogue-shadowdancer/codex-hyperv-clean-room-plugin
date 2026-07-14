# Hyper-V Clean Room for Codex

## English

`hyperv-clean-room` is a Windows-only Codex plugin design for guarded Hyper-V
VM operations, declarative current-user package lifecycle tests, and structured
evidence.

### Status: Gate 2 complete

Gate 2 implements the PowerShell 5.1 MCP runtime against the frozen v1 cleanup,
profile, evidence, plan, and credential contracts. The baseline remains plugin
version `0.1.0` and `schemaVersion: 1`, with exactly 16 MCP tools and five
public Draft 2020-12 schemas.

JSON-RPC transport, common envelopes, persistent ownership and atomic plan
guards, native profile/evidence validation, mock-backed guest/test flows,
evidence export, and the interactive DPAPI credential initializer are
implemented and tested. No real Hyper-V mutation or PowerShell Direct package
workflow was authorized or executed in Gate 2. The real guest adapter therefore
remains fail-closed; do not present this revision as clean-machine-validated
automation.

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

Read the [documentation center](docs/README.md), the authoritative
[specification](docs/specification.md), the Simplified Chinese
[profile authoring guide](docs/profile-authoring.md), and the single complete
[minimal profile example](examples/minimal-test-profile.json). Gate results and
the next entry point are in [TASK_HANDOFF.md](TASK_HANDOFF.md).

Development and CI use Python only to validate Draft 2020-12 schemas. The
production runtime uses Windows PowerShell 5.1 and does not depend on Python.

Run the complete Gate 2 checks without changing a personal marketplace or a
real VM:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-gate2.ps1 -MarketplacePath .\tests\fixtures\marketplace.json
```

## 简体中文

`hyperv-clean-room` 是一个仅面向 Windows 的 Codex plugin 设计，用于受保护的
Hyper-V VM 操作、声明式 current-user package lifecycle 测试和结构化 evidence。

### 状态：Gate 2 已完成

Gate 2 已依据冻结的 v1 cleanup、profile、evidence、plan 和 credential 合同实现
PowerShell 5.1 MCP runtime。基线仍为 plugin version `0.1.0` 与
`schemaVersion: 1`，并保持精确 16 个 MCP tools 和 5 个 public Draft 2020-12
schemas。

JSON-RPC transport、common envelope、持久 ownership 与原子 plan guard、原生
profile/evidence validation、mock-backed guest/test flow、evidence export 和交互式
DPAPI credential initializer 均已实现并通过测试。Gate 2 未获授权、也未执行任何真实
Hyper-V mutation 或 PowerShell Direct package workflow；因此 real guest adapter
仍然 fail closed，不得把当前版本描述为已经通过 clean-machine 验证的自动化工具。

已冻结的安全边界包括：

- 先 inspect 和 plan，再原子 consume、复核并 apply；
- 只 mutation plugin-owned VM identity；
- 不暴露 VM、VHDX、checkpoint、guest state 或 host path 删除工具；
- credential 不进入 MCP input、repository、log 或 evidence；
- test profile 拒绝任意 command 和不安全 path；
- 每次 test operation 使用独立、server-controlled artifact/evidence staging root；
- 仅在 execution-phase failure 后执行有界、非破坏性 cleanup；
- automatic、manual 与 cleanup results 分离，cleanup 不参与 `overallStatus` 推导。

请从[文档中心](docs/README.md)开始，并参考权威
[specification](docs/specification.md)、简体中文
[profile 编写指南](docs/profile-authoring.md)和唯一完整的
[最小 profile 示例](examples/minimal-test-profile.json)。Gate 结果和下一入口位于
[TASK_HANDOFF.md](TASK_HANDOFF.md)。

Python 只用于开发和 CI 的 Draft 2020-12 schema 验证；production runtime 使用
Windows PowerShell 5.1，且不依赖 Python。完整 Gate 2 检查不会改写个人 marketplace，
也不会触碰真实 VM：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-gate2.ps1 -MarketplacePath .\tests\fixtures\marketplace.json
```

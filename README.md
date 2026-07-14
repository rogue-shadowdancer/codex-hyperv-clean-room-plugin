# Hyper-V Clean Room for Codex

## English

`hyperv-clean-room` is a Windows-only Codex plugin design for guarded Hyper-V
VM operations, declarative current-user package lifecycle tests, and structured
evidence.

### Status: Gate 1.1 complete

Gate 1.1 freezes the pre-first-release v1 cleanup, profile, evidence, plan, and
credential contracts. The baseline remains plugin version `0.1.0` and
`schemaVersion: 1`, with exactly 16 MCP tools and five public Draft 2020-12
schemas.

The production runtime is **not implemented**. The MCP entry point deliberately
fails closed, and no real VM, artifact, credential, checkpoint, or evidence
workflow has been executed or validated. Do not install this revision as a
working automation tool.

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
future production runtime must use Windows PowerShell 5.1 and must not depend on
Python.

Run the structural Gate 1.1 checks without changing a personal marketplace:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-gate1.ps1 -MarketplacePath .\tests\fixtures\marketplace.json
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\gate1-contract.tests.ps1
```

## 简体中文

`hyperv-clean-room` 是一个仅面向 Windows 的 Codex plugin 设计，用于受保护的
Hyper-V VM 操作、声明式 current-user package lifecycle 测试和结构化 evidence。

### 状态：Gate 1.1 已完成

Gate 1.1 已冻结首次发布前的 v1 cleanup、profile、evidence、plan 和 credential
合同。基线仍为 plugin version `0.1.0` 与 `schemaVersion: 1`，并保持精确 16 个
MCP tools 和 5 个 public Draft 2020-12 schemas。

Production runtime **尚未实现**。MCP 入口会故意 fail closed；本 gate 没有执行或
验证真实 VM、artifact、credential、checkpoint 或 evidence 流程。不要把当前版本
安装成可工作的自动化工具。

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

Python 只用于开发和 CI 的 Draft 2020-12 schema 验证；未来 production runtime
必须使用 Windows PowerShell 5.1，且不得依赖 Python。

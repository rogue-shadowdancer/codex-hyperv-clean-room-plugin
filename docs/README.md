# Hyper-V Clean Room documentation / 文档中心

## English

Gate 2 implements the pre-release v1 MCP runtime and validates it with mock
adapters under Windows PowerShell 5.1. No real Hyper-V mutation or PowerShell
Direct package lifecycle was authorized or executed. Real guest execution
therefore remains fail-closed and this revision must not be presented as
clean-machine-validated automation.

Start here:

- [Frozen v1 specification](specification.md) — authoritative tool, state,
  profile, cleanup, credential, and evidence semantics.
- [Test profile authoring guide (Simplified Chinese)](profile-authoring.md) —
  field-by-field profile guidance and execution boundaries.
- [Minimal test profile](../examples/minimal-test-profile.json) — the only
  complete documentation example; it is validated by the schema and semantic
  contract tests.
- [Gate handoff](../TASK_HANDOFF.md) — completed Gate 2 verification, known
  real-adapter boundary, and the exact next-gate entry point.
- [Repository overview](../README.md) — bilingual project status and safety
  summary.

The five public Draft 2020-12 schemas live in
[`hyperv-clean-room/schemas`](../hyperv-clean-room/schemas). Python schema
validation is for development and CI only; the production runtime remains
Windows PowerShell 5.1 based and does not depend on Python.

## 简体中文

Gate 2 已实现首次发布前的 v1 MCP runtime，并在 Windows PowerShell 5.1 下使用
mock adapter 完成验证。本 gate 未获授权、也未执行任何真实 Hyper-V mutation 或
PowerShell Direct package lifecycle；real guest execution 因此仍然 fail closed，
不得把当前版本宣传为已经通过 clean-machine 验证的自动化工具。

建议阅读顺序：

- [v1 合同规范](specification.md)：工具、状态、profile、cleanup、凭据和 evidence
  语义的权威来源。
- [测试 profile 编写指南](profile-authoring.md)：逐字段说明与执行边界。
- [最小测试 profile](../examples/minimal-test-profile.json)：文档中唯一的完整示例，
  同时参加 schema 与 semantic contract tests。
- [Gate 交接](../TASK_HANDOFF.md)：Gate 2 验证结论、real-adapter 已知边界和下一
  gate 的精确入口。
- [仓库概要](../README.md)：中英双语状态与安全边界。

五个 Draft 2020-12 public schemas 位于
[`hyperv-clean-room/schemas`](../hyperv-clean-room/schemas)。Python validator
只用于开发和 CI；production runtime 基于 Windows PowerShell 5.1，且不依赖
Python。

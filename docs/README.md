# Hyper-V Clean Room documentation / 文档中心

## English

Gate 1.1 freezes the pre-release v1 contract. The repository still contains a
fail-closed MCP stub: the runtime is not implemented, no Hyper-V behavior has
been validated, and this revision must not be installed or presented as a
working automation tool.

Start here:

- [Frozen v1 specification](specification.md) — authoritative tool, state,
  profile, cleanup, credential, and evidence semantics.
- [Test profile authoring guide (Simplified Chinese)](profile-authoring.md) —
  field-by-field profile guidance and execution boundaries.
- [Minimal test profile](../examples/minimal-test-profile.json) — the only
  complete documentation example; it is validated by the schema and semantic
  contract tests.
- [Gate handoff](../TASK_HANDOFF.md) — completed Gate 1.1 verification and the
  exact Gate 2 entry point.
- [Repository overview](../README.md) — bilingual project status and safety
  summary.

The five public Draft 2020-12 schemas live in
[`hyperv-clean-room/schemas`](../hyperv-clean-room/schemas). Python schema
validation is for development and CI only; the future production runtime must
remain Windows PowerShell 5.1 based and must not depend on Python.

## 简体中文

Gate 1.1 已冻结首次发布前的 v1 合同。仓库中的 MCP 入口仍是 fail-closed
stub：runtime 尚未实现，也没有验证任何真实 Hyper-V 行为，因此当前版本不能安装
或宣传为可工作的自动化工具。

建议阅读顺序：

- [v1 合同规范](specification.md)：工具、状态、profile、cleanup、凭据和 evidence
  语义的权威来源。
- [测试 profile 编写指南](profile-authoring.md)：逐字段说明与执行边界。
- [最小测试 profile](../examples/minimal-test-profile.json)：文档中唯一的完整示例，
  同时参加 schema 与 semantic contract tests。
- [Gate 交接](../TASK_HANDOFF.md)：Gate 1.1 的验证结论和 Gate 2 精确入口。
- [仓库概要](../README.md)：中英双语状态与安全边界。

五个 Draft 2020-12 public schemas 位于
[`hyperv-clean-room/schemas`](../hyperv-clean-room/schemas)。Python validator
只用于开发和 CI；未来 production runtime 必须基于 Windows PowerShell 5.1，且
不得依赖 Python。

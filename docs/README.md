# Hyper-V Clean Room documentation / 文档中心

## English

Gate 5 prepares the source-validated Gate 4 personal installation baseline for
private publication. It adds a release process, changelog, full-history
sensitive-state scan, and a CI-safe Gate 4 path with zero personal install,
marketplace, installed-copy, real-host, guest, or Hyper-V mutation operations.
The inherited Gate 2 suite still uses mock adapters, parser
checks, static production-adapter seams, strict documentation checks, and a
bounded real-host read-only smoke.
The production guest adapter contains fixed administrator-supervised
PowerShell Direct behavior, standard-user execution, operation-scoped staging
and PID identity, dual hashes, and bounded cleanup. Gate 2 did not execute that
real guest path or any real Hyper-V mutation and must not be presented as
clean-machine-validated automation.

Read in this order:

- [Plugin installation](installation.md) defines source validation, ownership,
  personal marketplace registration, installed-copy acceptance, and status
  fields.
- [Installation maintenance](maintenance.md) defines the cachebuster reinstall
  loop, drift handling, and safe recovery.
- [Private release process](release-process.md) defines publication hygiene,
  CI coverage, private remote creation, Actions, and remote acceptance.
- [Changelog](../CHANGELOG.md) records the pre-release source milestones and
  the explicit clean-machine boundary.

1. [Architecture](architecture.md) — components, trust boundaries, state, and
   production guest flow.
2. [Operations guide](operations.md) — reproducible validation, credential
   enrollment, plan/apply sequencing, lifecycle, and recovery.
3. [Evidence model](evidence.md) — provenance, hashes, automatic/manual/cleanup
   separation, derivation, validation, and export.
4. [Security design](security.md) — credential, ownership, path, process,
   execution-surface, and evidence controls.
5. [Troubleshooting](troubleshooting.md) — bounded actions for stable error
   codes and development failures.
6. [Frozen v1 specification](specification.md) — authoritative tool, state,
   profile, cleanup, credential, and evidence semantics.
7. [Test profile authoring guide (Simplified Chinese)](profile-authoring.md) —
   field-by-field profile guidance and execution boundaries.

Related repository entry points:

- [Minimal test profile](../examples/minimal-test-profile.json) — the only
  complete documentation example; schema and semantic tests validate it.
- [Repository overview](../README.md) — bilingual status and validation entry.
- [Security reporting policy](../SECURITY.md) — supported-version and private
  reporting rules.
- [Gate handoff](../TASK_HANDOFF.md) — completed verification and the exact
  next-gate boundary.

The five public Draft 2020-12 schemas live in
[`hyperv-clean-room/schemas`](../hyperv-clean-room/schemas). Python is isolated
development/CI machinery only; the production runtime remains Windows
PowerShell 5.1 based.

## 简体中文

Gate 5 把经过 source validation 的 Gate 4 personal install baseline 准备为 private
publication candidate，并新增 release process、changelog、完整 history sensitive-state
扫描，以及 personal install、marketplace、installed-copy、real-host、guest 与 Hyper-V
mutation 全部为零的 CI-safe Gate 4 路径。继承的 Gate 2 测试仍在 Windows PowerShell 5.1 下使用 mock
adapter、parser、production-adapter static seam、严格文档
检查和有界真实 host 只读 smoke。Production guest adapter 已包含固定的 administrator-supervised
PowerShell Direct、standard-user execution、operation-scoped staging/PID identity、
双 SHA-256 和 bounded cleanup；但 Gate 2 没有执行该真实 guest 路径，也没有执行任何
真实 Hyper-V mutation，不得把当前版本宣传为已经通过 clean-machine 验证。

建议阅读顺序：

- [Plugin installation](installation.md)：source validation、ownership、personal
  marketplace、installed-copy 验收与状态字段。
- [Installation maintenance](maintenance.md)：cachebuster 重装、drift 与安全恢复。
- [Private release process](release-process.md)：publication hygiene、CI、private remote、
  Actions 与 remote acceptance。
- [Changelog](../CHANGELOG.md)：pre-release source milestones 与 clean-machine boundary。

1. [Architecture](architecture.md)：组件、trust boundary、状态与 production guest
   flow。
2. [Operations guide](operations.md)：可复现验证、凭据初始化、plan/apply、lifecycle
   与恢复原则。
3. [Evidence model](evidence.md)：provenance、hash、automatic/manual/cleanup 分离、
   status 推导、验证与导出。
4. [Security design](security.md)：credential、ownership、path、process、执行面与
   evidence 控制。
5. [Troubleshooting](troubleshooting.md)：稳定错误码和开发环境故障的有界处理。
6. [v1 合同规范](specification.md)：工具、状态、profile、cleanup、凭据和 evidence
   语义的权威来源。
7. [测试 profile 编写指南](profile-authoring.md)：逐字段说明与执行边界。

仓库相关入口：

- [最小测试 profile](../examples/minimal-test-profile.json)：文档中唯一完整示例，
  同时参加 schema 与 semantic contract tests。
- [仓库概要](../README.md)：中英双语状态与验证入口。
- [安全报告策略](../SECURITY.md)：支持版本与私密报告规则。
- [Gate 交接](../TASK_HANDOFF.md)：验证结论与下一 gate 的精确边界。

五个 Draft 2020-12 public schemas 位于
[`hyperv-clean-room/schemas`](../hyperv-clean-room/schemas)。Python 只用于隔离的开发
与 CI 检查；production runtime 仍基于 Windows PowerShell 5.1。

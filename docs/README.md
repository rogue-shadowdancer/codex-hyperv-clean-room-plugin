# Hyper-V Clean Room documentation / 文档中心

## English

Gate 5.1 publishes the source-validated Gate 4 personal installation baseline
as GPL-3.0-only `v0.1.1`. It adds public community files, a source-only Release,
full-tree/history/identity/Actions-log hygiene, and SHA-pinned
`public-release-validation` with zero personal install, marketplace,
installed-copy, real-host, guest, or Hyper-V mutation operations.
Gate 5.2 adds one canonical GitHub repository link to the plugin install
surface while preserving base version `0.1.1`, every runtime contract, and the
immutable `v0.1.1` Release. The current `master` personal-install build is
`0.1.1+codex.20260715084043`.
Gate 6/H1 freezes the additive `0.2.0`/schema-v2 target under
[`contracts/v2`](../contracts/v2/README.md), including four guarded
power/network tools, portable automation, fixed WebDriver provenance, a closed
UI DSL, evidence v2, and compatibility fixtures. Gate 7/H2 integrates that
contract into plugin source `0.2.0` as 20 MCP tools, preserving the exact first
16 tools and five public schema-v1 files while installing seven schema-v2
files. H2 validation is mock/parser/static only; release, installation,
clean-machine, and every real operation remain `notPerformed`.
Gate 8/H3 published the immutable source-only `v0.2.0` release, Gate 9/H4
validated the release-derived personal installation, and H5A now repairs
automatic-checkpoint ownership without changing the 20-tool or schema
contracts. Future creation disables automatic checkpoints; pre-fix
differencing chains are recognized only when they terminate at the unchanged
recorded base with a complete canonical identity fingerprint.
G7/P3.1 freezes the additive `0.3.0` external-manifest target under the
same authoritative [`contracts/v2`](../contracts/v2/README.md) directory. It
preserves the old embedded branch and exact 20-tool surface. The external dispatch
keeps `runtime-and-legal-only` historical evidence readable and requires
`end-user-complete` documentation/prerequisite identity for every executable
external profile. G7/P3.2 implements that target in source plugin `0.3.0`:
strict sidecar parsing, closed native provenance, bidirectional ZIP inventory,
atomic data-preserving deployment, zero-argument entrypoint launch, conditional
UI/driver behavior, separate orchestration/test-user identity, and external
evidence. All seven source-tree installed v2 schema copies now exactly match
their authorities. Validation remains mock/parser/schema/static with every
real-operation counter zero. P3.3 release/install/source-match is complete:
immutable source-only `v0.3.0` is bound to protected source commit
`47151fdbe99346ec87af09460c79d0864978eabd`, and the one personal build
`0.3.0+codex.20260729122233` closes all 31 payloads and exactly 20 tools without
calling an MCP tool or adapter operation during catalog readback. The local
publication aggregate did invoke its inherited Gate 2 bounded read-only
`inspect_host` and missing-ISO `plan_vm_create` rejection outside the declared
P3.3 no-host boundary; no mutation or machine acceptance resulted.
G7/P3.3-R1 advances the compatible patch runtime to `0.3.1` while retaining
the frozen `0.3.0` capability target. Current acceptance uses an explicit
`selectedCapabilityRoots` binding and thread-scoped `mcpServerStatus/list`,
requires `hyperv-clean-room` / `0.3.1` with exactly 20 unique tools, and sends
no MCP tool call. The only build is `0.3.1+codex.20260729184240`; protected
`master`, annotated `v0.3.1`, its source-only Release, and installed
`sourceCommit` must be one commit. Immutable earlier tags remain unchanged.
G7/P3.3-R2 advances the compatible runtime to `0.3.2` without changing that
capability target, the 20-tool surface, or tool input schemas. `tools/call`
accepts optional object `_meta`, rejects mistyped metadata and unknown outer
fields, and never forwards transport metadata as tool arguments. The
selected-plugin validator remains catalog-only by default and adds an explicit
isolated-child mock smoke for `inspect_host` and `list_vms`, requiring
`changed=false`, the mandatory test-only warning, and zero real-operation
counts. The only build is `0.3.2+codex.20260731014242`; protected `master`,
annotated `v0.3.2`, the zero-asset Release, and installed `sourceCommit` must
be one commit while v0.1.1 through v0.3.1 remain immutable.
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
- [Public release process](release-process.md) defines publication hygiene,
  CI, private-to-public sequencing, anonymous readback, protection, tag, and
  source-only Release acceptance.
- [Changelog](../CHANGELOG.md) records `v0.1.1`, earlier source milestones, and
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
6. [Specification](specification.md) — authoritative v1 behavior and frozen
   `0.2.0`/schema-v2 target semantics.
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

The five current public Draft 2020-12 schemas live in
[`hyperv-clean-room/schemas`](../hyperv-clean-room/schemas). Python is isolated
development/CI machinery only; the production runtime remains Windows
PowerShell 5.1 based. Seven authoritative schema-v2 contracts live under
[`contracts/v2/schemas`](../contracts/v2/schemas), with byte-identical
installable copies under `hyperv-clean-room/schemas/v2`.

## 简体中文

Gate 5.1 把经过 source validation 的 Gate 4 personal install baseline 以
GPL-3.0-only `v0.1.1` 公开发布，并新增 public community 文件、source-only Release、
完整 tree/history/identity/Actions-log hygiene，以及 personal install、marketplace、
installed-copy、real-host、guest 与 Hyper-V mutation 全部为零的 SHA-pinned CI 路径。
Gate 5.2 只在 plugin install surface 增加统一的 GitHub 仓库链接，保持 base
version `0.1.1`、全部 runtime contract 与不可变的 `v0.1.1` Release；当前
`master` personal-install build 为 `0.1.1+codex.20260715084043`。
Gate 6/H1 在 [`contracts/v2`](../contracts/v2/README.md) 冻结增量
`0.2.0`/schema-v2 目标，包括四个受保护的 power/network tools、portable
automation、固定 WebDriver provenance、闭合 UI DSL、evidence v2 与兼容 fixture。
Gate 7/H2 已将合同集成到 plugin `0.2.0` source：保留精确 16 个 v1 tools 与五个
public schema-v1 文件，新增四个 tools，合计 20 MCP tools，并安装 seven schema-v2
文件。H2 只执行 mock、parser 与 static 验证；发布、安装、clean-machine 与全部真实
operation 仍为 `notPerformed`。
Gate 8/H3 已发布不可变、source-only 的 `v0.2.0` release，Gate 9/H4 已验收由 release
派生的 personal installation；H5A 现修复 automatic-checkpoint ownership，同时保持
20-tool 与 schema contract 不变。新建 VM 会禁用 automatic checkpoints；pre-fix
differencing chain 只有在完整 canonical identity fingerprint 终止于未改变的 recorded
base 时才会被识别。

G7/P3.1 冻结 `0.3.0` external-manifest target；G7/P3.2 已把它集成到 source
plugin `0.3.0`，包括 strict sidecar parser、闭合 native provenance、双向 ZIP
inventory、atomic data-preserving deployment、zero-argument entrypoint、
conditional UI/driver、分离的 orchestration/test-user identity 与 external
evidence。七份 source-tree installed v2 schema 已与权威文件逐字节一致，20-tool
surface、v1 与 embedded `0.2.0` 语义不变。验证仍仅限
mock/parser/schema/static，全部真实 operation counter 为零。P3.3 已发布绑定到
protected source commit `47151fdbe99346ec87af09460c79d0864978eabd` 的不可变、
source-only `v0.3.0`，并以唯一 personal build
`0.3.0+codex.20260729122233` 闭合 31 个 payload 与精确 20 个 tools；期间没有调用
MCP tool，catalog readback 也没有执行 adapter operation。local publication
aggregate 仍调用了继承自 Gate 2 的有界只读 `inspect_host` 与 missing-ISO
`plan_vm_create` 拒绝；这偏离了 P3.3 的 no-host boundary，但没有产生 mutation 或
machine acceptance。
继承的 Gate 2 测试仍在 Windows PowerShell 5.1 下使用 mock
adapter、parser、production-adapter static seam、严格文档
检查和有界真实 host 只读 smoke。Production guest adapter 已包含固定的 administrator-supervised
PowerShell Direct、standard-user execution、operation-scoped staging/PID identity、
双 SHA-256 和 bounded cleanup；但 Gate 2 没有执行该真实 guest 路径，也没有执行任何
真实 Hyper-V mutation，不得把当前版本宣传为已经通过 clean-machine 验证。

建议阅读顺序：

- [Plugin installation](installation.md)：source validation、ownership、personal
  marketplace、installed-copy 验收与状态字段。
- [Installation maintenance](maintenance.md)：cachebuster 重装、drift 与安全恢复。
- [Public release process](release-process.md)：publication hygiene、CI、private-to-public
  sequencing、anonymous readback、branch protection、tag 与 source-only Release。
- [Changelog](../CHANGELOG.md)：`v0.1.1`、早期 source milestones 与 clean-machine boundary。

1. [Architecture](architecture.md)：组件、trust boundary、状态与 production guest
   flow。
2. [Operations guide](operations.md)：可复现验证、凭据初始化、plan/apply、lifecycle
   与恢复原则。
3. [Evidence model](evidence.md)：provenance、hash、automatic/manual/cleanup 分离、
   status 推导、验证与导出。
4. [Security design](security.md)：credential、ownership、path、process、执行面与
   evidence 控制。
5. [Troubleshooting](troubleshooting.md)：稳定错误码和开发环境故障的有界处理。
6. [合同规范](specification.md)：v1 当前行为与已冻结的
   `0.2.0`/schema-v2 目标语义。
7. [测试 profile 编写指南](profile-authoring.md)：逐字段说明与执行边界。

仓库相关入口：

- [最小测试 profile](../examples/minimal-test-profile.json)：文档中唯一完整示例，
  同时参加 schema 与 semantic contract tests。
- [仓库概要](../README.md)：中英双语状态与验证入口。
- [安全报告策略](../SECURITY.md)：支持版本与私密报告规则。
- [Gate 交接](../TASK_HANDOFF.md)：验证结论与下一 gate 的精确边界。

五个当前 Draft 2020-12 public schemas 位于
[`hyperv-clean-room/schemas`](../hyperv-clean-room/schemas)。Python 只用于隔离的开发
与 CI 检查；production runtime 仍基于 Windows PowerShell 5.1。七个权威
schema-v2 合同位于 [`contracts/v2/schemas`](../contracts/v2/schemas)，其逐字节相同的
可安装副本位于 `hyperv-clean-room/schemas/v2`。

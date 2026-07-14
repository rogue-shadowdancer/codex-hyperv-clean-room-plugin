# Hyper-V Clean Room 测试 profile 编写指南

本指南说明 `test-profile.schema.json` 的 schema-v1 合同。字段名、step type 和
tool name 保留精确英文拼写。Gate 2 runtime 已使用 mock adapter 验证；本文及该
验证均不表示真实 VM、PowerShell Direct 或 package lifecycle 已通过验证。

完整 JSON 只维护一份：[minimal-test-profile.json](../examples/minimal-test-profile.json)。
该文件同时参加 Draft 2020-12 schema 和 semantic contract tests。本文不复制第二份
完整 profile，以免示例发生漂移。

## 顶层结构

顶层对象 `additionalProperties: false`，必须包含以下字段：

| 字段 | 约束与含义 |
| --- | --- |
| `schemaVersion` | 固定为 `1`。 |
| `id` | 小写字母、数字和单连字符组成，例如 `package-smoke-test`。 |
| `description` | 可选，最多 1000 个字符。 |
| `platform` | 固定为 `windows-x64`。 |
| `baselineType` | `stock-clean` 或 `webview2-absent-derived`。 |
| `artifact` | 声明文件名模式、架构和可选 SHA-256。 |
| `applications` | 至少一个命名 application；ID 在此数组内唯一。 |
| `steps` | 普通执行序列；必须以唯一的 `stageArtifact` 开头。 |
| `cleanupSteps` | 必填；没有 cleanup 时显式写 `[]`。最多 16 项。 |
| `manualAssertions` | 手工断言清单；没有时写 `[]`。 |

`artifact.fileNamePattern` 是不区分大小写的 filename glob，不是 regex，也不能含
目录分隔符。`artifact.architecture` 固定为 `x64`。可选 `artifact.sha256` 必须是
64 位小写十六进制字符串。

每个 `applications` 项需要：

- `id`
- `installerType`：`nsis` 或 `msi`
- `installMode`：固定为 `currentUser`
- `executableRelativePath`
- `uninstallerDiscovery`：`hkcuUninstall` 或 `msiProduct`

`processName` 可选，只能包含字母、数字、点、下划线和连字符。

## ID、path 和 timeout

`steps[*].id`、`cleanupSteps[*].id` 与 `manualAssertions[*].id` 共用一个全局
命名空间，三者之间也不能重复。`applications[*].id` 在 application 命名空间内
唯一。application 引用必须命中已声明的 `applications[*].id`。

`executableRelativePath` 和 `path` 以 standard test user 的 profile 目录为根；
`moduleRelativePath` 以对应 application 的 executable 目录为根；`registryPath`
以 HKCU 为根，因此不要写 hive 前缀。上述字段均禁止 drive-qualified、rooted、
UNC、`..` traversal、alternate stream、环境变量展开和 reparse escape。runtime
必须在解析后再次确认目标仍位于允许根目录内。

普通 `steps[*].timeoutSeconds` 为 1 到 900。每个
`cleanupSteps[*].timeoutSeconds` 为 1 到 120，且所有 cleanup timeout 的声明值
总和不得超过 300 秒。timeout 是上限，不是等待建议值。

普通 assertion 与 cleanup assertion 省略 `required` 时按 `true` 处理。只有
assertion 可以写 `required: false`；mutation/action（包括 `wait`）不能 optional。

## 普通 `steps`

普通 step object 是闭合对象。允许类型和主要字段如下：

| `type` | 必要专用字段 | 分类 |
| --- | --- | --- |
| `stageArtifact` | 无 | action；整个 `steps` 中恰好一次且必须第一项 |
| `installPackage` | `application` | mutation |
| `launchApplication` | `application` | action |
| `stopApplication` | `application` | action |
| `uninstallPackage` | `application` | mutation |
| `assertFile` | `path` | assertion |
| `assertRegistry` | `registryPath` | assertion |
| `assertProcess` | `application` 或 `processName`，二选一 | assertion |
| `assertModule` | `application`, `moduleRelativePath` | assertion |
| `assertShortcut` | `path` | assertion |
| `assertPort` | `port` | assertion |
| `writeSentinel` | `sentinelId` | mutation |
| `assertSentinel` | `sentinelId` | assertion |
| `wait` | 无 | action |

assertion 可使用 `expected` 表示期望值或存在状态；省略时表示检查默认的存在或
匹配条件。`assertRegistry` 可加 `registryName`。任何 step 都不能携带 `command`、
`script`、`shell`、URL、inline PowerShell 或任意 executable 字段。

普通 `required: false` assertion 失败时只记录结果并继续。required assertion、
mutation/action、timeout 或 guest-adapter failure 才会停止普通序列并触发 cleanup。

## `cleanupSteps`

cleanup 使用独立、闭合的 `cleanupStep` schema，只允许：

- `stopApplication`
- `wait`
- `assertFile`
- `assertRegistry`
- `assertProcess`
- `assertModule`
- `assertShortcut`
- `assertPort`
- `assertSentinel`

字段要求与同名普通 step 一致。cleanup 明确禁止 `stageArtifact`、
`installPackage`、`launchApplication`、`uninstallPackage`、`writeSentinel`、任意
command/script/shell/URL/executable，以及任何删除动作。

cleanup 只有在 `run_test_profile` 完成全部预验证并进入执行阶段后才可能触发。
profile/schema 验证失败或普通 optional assertion 失败不会触发。触发后按声明顺序、
在 300 秒总预算内继续执行；某个 cleanup 失败不会递归触发 cleanup，也不会阻止
预算内的后续 cleanup step。

cleanup `stopApplication` 只能处理当前 test operation 记录的 PID，并且停止前必须
重新核对 process identity。identity 缺失或改变时，该 cleanup step 失败，但不能
停止该 PID。cleanup 永不 uninstall、删除 VM/VHDX/checkpoint/guest file/registry
key/host path、restore checkpoint 或 rollback VM。

## Artifact staging 边界

[`run_test_profile`](specification.md#run_test_profile) 的 `artifactPath` 是 host
本地 ordinary file。runner 为当前 operation 分配 guest staging destination，并
计算 host-source 与 guest-copy 两个 SHA-256；二者必须匹配。

独立 [`stage_artifact`](specification.md#stage_artifact) 仅用于 low-level preflight、
troubleshooting 或明确的 manual workflow。它属于自己的 operation，不能跨
operation 隐式满足后续 `run_test_profile` 的 `stageArtifact`。

## Automatic、manual 与 cleanup 结果边界

automatic assertion 由 runner 收集。GUI 可见、DPI、interactive exercise 等无法由
process exit 证明的结果必须声明在 `manualAssertions`，并通过
`record_manual_attestation` 写入；`run_test_profile` 不能把 manual assertion 自动
标为 `passed`。

每个 test operation 使用 server-controlled evidence staging root。manual
attestation 的 `evidenceReferences` 只能引用该 root 内已存在文件的相对路径和
SHA-256；禁止绝对路径、traversal、reparse escape、缺失文件和 hash mismatch。
`collect_evidence` 之后才把验证过的内容导出到 caller 选择的目录。

Evidence 顶层必须包含 `cleanupTriggered` 和 `cleanupResults`。前者来自 immutable
operation trigger state，caller 不能提供或修改。后者与 `cleanupSteps` 一一对应且
顺序一致，每项绑定 `operationId`、`profileId`、`cleanupStepId` 和
`cleanupStepType`，`status` 只能是 `passed`、`failed`、`notPerformed` 或
`unsupported`。当 `cleanupTriggered` 为 `false` 时，所有声明项必须为
`notPerformed`；空 cleanup 对应 `[]`。

`overallStatus` 只由 required automatic/manual assertions 推导。
`cleanupTriggered` 和 cleanup results 均不参与：cleanup 成功不能把失败或
incomplete 升级，cleanup 失败也不能把 required assertions 已通过的结果降级；
optional assertion 同样不参与推导。

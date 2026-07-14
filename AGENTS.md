# Repository instructions

## Safety

- Treat all Hyper-V mutations as guarded operations: inspect, plan, then apply.
- Never add VM, VHDX, checkpoint, ISO, credential, DPAPI, evidence, or machine-
  specific state files to Git.
- Do not add deletion tools for VMs, VHDX files, checkpoints, or host paths.
- Do not accept plaintext credentials through MCP inputs, command-line
  arguments, profiles, logs, or evidence.
- Tests must use a mock adapter unless a user explicitly authorizes a real
  Hyper-V mutation.

## Gate workflow

- Implement one gate per Codex task.
- Validate and commit the completed gate before continuing.
- Update `TASK_HANDOFF.md` with conclusions, changed areas, verification,
  blockers, and the next gate.
- Start the next gate in a new task and read `docs/specification.md` plus
  `TASK_HANDOFF.md` before editing.
- Use direct subagents only for bounded independent review or testing. They must
  not delegate recursively.

## Compatibility

- Runtime support is Windows PowerShell 5.1 with the Hyper-V PowerShell module.
- Keep MCP tool names and schema v1 semantics backward compatible throughout
  the 0.x implementation unless `docs/specification.md` is deliberately
  revised and the change is documented.

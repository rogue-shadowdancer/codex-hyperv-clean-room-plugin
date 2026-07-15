## Summary

Describe the change and the user-visible outcome.

## Safety boundary

- [ ] Tests use mock adapters unless a specifically authorized read-only check is documented.
- [ ] No credential, token, private path, VM/VHDX/checkpoint/ISO, evidence, cache, log, or installed-control state is included.
- [ ] No arbitrary command surface or destructive VM/host deletion capability is added.
- [ ] Public MCP compatibility remains 16 tools, five schemas, schemaVersion 1, and four protocol versions, or the specification change is explicit.

## Verification

List exact commands and results. Mark clean-machine, credential, real guest,
package, VM, checkpoint, and manual GUI work `notPerformed` unless it was
separately authorized and evidenced.

## Documentation

- [ ] Documentation and changelog are updated where behavior or release state changed.
- [ ] `public-release-validation` is green.


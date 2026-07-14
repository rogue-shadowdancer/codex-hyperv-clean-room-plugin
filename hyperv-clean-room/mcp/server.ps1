[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Gate 1 freezes the public contract but intentionally does not expose a partial
# automation server. Gate 2 replaces this fail-closed entry point with the MCP
# JSON-RPC implementation and its tested Hyper-V adapter.
[Console]::Error.WriteLine(
    'hyperv-clean-room MCP server is not implemented yet; continue with Gate 2.'
)
exit 78

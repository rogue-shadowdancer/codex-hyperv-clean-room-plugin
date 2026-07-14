[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$pluginRoot = Join-Path $repoRoot 'hyperv-clean-room'
$stateRoot = Join-Path $repoRoot '.artifacts\gate2-real-readonly\state'
$credentialRoot = Join-Path $repoRoot '.artifacts\gate2-real-readonly\credentials'
$oldAdapterMode = $env:HCR_ADAPTER_MODE
$oldTestMode = $env:HCR_TEST_MODE
$oldMockPath = $env:HCR_MOCK_ADAPTER_PATH
$oldStateRoot = $env:HCR_STATE_ROOT
$oldCredentialRoot = $env:HCR_CREDENTIAL_ROOT

try {
    $env:HCR_ADAPTER_MODE = 'hyperv'
    $env:HCR_TEST_MODE = '0'
    $env:HCR_MOCK_ADAPTER_PATH = $null
    $env:HCR_STATE_ROOT = $stateRoot
    $env:HCR_CREDENTIAL_ROOT = $credentialRoot
    $script:HcrInitialized = $false
    foreach ($runtimeFile in @(
        'Common.ps1',
        'State.ps1',
        'Validation.ps1',
        'Adapters.ps1',
        'ToolSchemas.ps1',
        'Tools.Host.ps1',
        'Tools.Guest.ps1',
        'Runtime.ps1'
    )) {
        . (Join-Path (Join-Path (Join-Path $pluginRoot 'mcp') 'lib') $runtimeFile)
    }
    Initialize-HcrRuntime $pluginRoot

    $inspection = Invoke-HcrToolCall 'inspect_host' ([pscustomobject]@{})
    if (-not [bool]$inspection.ok -or [bool]$inspection.changed) {
        throw 'The authorized real-host inspect_host smoke did not remain read-only and successful.'
    }
    if (@($inspection.warnings | Where-Object { $_ -match 'MOCK_ADAPTER' }).Count -ne 0) {
        throw 'The real-host inspection unexpectedly used mock evidence.'
    }

    $missingIso = Join-Path $repoRoot (
        '.artifacts\gate2-real-readonly\missing-' + [Guid]::NewGuid().ToString('N') + '.iso'
    )
    $plan = Invoke-HcrToolCall 'plan_vm_create' ([pscustomobject][ordered]@{
        name = 'hcr-gate2-readonly-probe'
        isoPath = $missingIso
        vmRoot = $repoRoot
        switchName = 'not-consulted-for-missing-iso'
    })
    if ([bool]$plan.ok -or [bool]$plan.changed -or
        [string]$plan.error.code -ne 'INVALID_ISO') {
        throw 'The missing-ISO real-adapter plan probe did not fail before mutation.'
    }

    [ordered]@{
        ok = $true
        gate = 2
        realHostOperations = @('inspect_host', 'plan_vm_create missing-ISO rejection')
        realGuestOperations = 0
        realHyperVMutations = 0
    } | ConvertTo-Json -Compress
}
finally {
    $env:HCR_ADAPTER_MODE = $oldAdapterMode
    $env:HCR_TEST_MODE = $oldTestMode
    $env:HCR_MOCK_ADAPTER_PATH = $oldMockPath
    $env:HCR_STATE_ROOT = $oldStateRoot
    $env:HCR_CREDENTIAL_ROOT = $oldCredentialRoot
}

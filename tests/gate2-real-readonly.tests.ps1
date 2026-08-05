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
$hadComputerName = Test-Path Env:COMPUTERNAME
$oldComputerName = $env:COMPUTERNAME

try {
    $env:HCR_ADAPTER_MODE = 'hyperv'
    $env:HCR_TEST_MODE = '0'
    $env:HCR_MOCK_ADAPTER_PATH = $null
    $env:HCR_STATE_ROOT = $stateRoot
    $env:HCR_CREDENTIAL_ROOT = $credentialRoot
    Remove-Item Env:COMPUTERNAME -ErrorAction SilentlyContinue
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
    if ([string]$env:COMPUTERNAME -cne [Environment]::MachineName) {
        throw 'The real-host runtime did not restore missing COMPUTERNAME from the machine identity.'
    }

    $inspection = Invoke-HcrToolCall 'inspect_host' ([pscustomobject]@{})
    if (-not [bool]$inspection.ok -or [bool]$inspection.changed) {
        throw 'The authorized real-host inspect_host smoke did not remain read-only and successful.'
    }
    if (@($inspection.warnings | Where-Object { $_ -match 'MOCK_ADAPTER' }).Count -ne 0) {
        throw 'The real-host inspection unexpectedly used mock evidence.'
    }
    if ([string]$inspection.data.host.computerName -cne [Environment]::MachineName) {
        throw 'The real-host inspection did not report the machine identity after repair.'
    }

    $inventory = Invoke-HcrToolCall 'list_vms' ([pscustomobject]@{
        managedOnly = $false
    })
    if (-not [bool]$inventory.ok -or [bool]$inventory.changed) {
        throw 'The authorized missing-COMPUTERNAME list_vms regression did not remain read-only and successful.'
    }
    if (@($inventory.warnings | Where-Object { $_ -match 'MOCK_ADAPTER' }).Count -ne 0) {
        throw 'The real-host VM inventory unexpectedly used mock evidence.'
    }
    if ([bool]$inventory.data.managedOnly) {
        throw 'The real-host VM inventory did not honor managedOnly=false.'
    }

    [ordered]@{
        ok = $true
        gate = 2
        computerNameRepair = 'passed'
        realHostOperations = @('inspect_host', 'list_vms managedOnly=false')
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
    if ($hadComputerName) { $env:COMPUTERNAME = $oldComputerName }
    else { Remove-Item Env:COMPUTERNAME -ErrorAction SilentlyContinue }
}

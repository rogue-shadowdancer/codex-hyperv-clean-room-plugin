function Initialize-HcrRuntime {
    param([Parameter(Mandatory = $true)][string]$PluginRoot)

    $script:HcrPluginRoot = Get-HcrNormalizedPath $PluginRoot
    if (-not (Test-Path -LiteralPath $script:HcrPluginRoot -PathType Container)) {
        Throw-HcrError 'PLUGIN_ROOT_INVALID' 'The plugin root does not exist.'
    }
    [void](Get-HcrAdapterMode)
    [void](Initialize-HcrStateStore)
    $definitions = @(Get-HcrToolDefinitions)
    $names = @($definitions | ForEach-Object { $_.name })
    if ($names.Count -ne 20 -or @(Compare-Object $script:HcrToolNames $names).Count -ne 0) {
        Throw-HcrError 'INTERNAL_ERROR' 'The runtime tool registry diverges from the frozen 20-tool surface.'
    }
    $script:HcrInitialized = $true
}

function Invoke-HcrToolCall {
    param(
        [Parameter(Mandatory = $true)][string]$ToolName,
        [AllowNull()][object]$Arguments
    )

    $operationId = [Guid]::NewGuid().ToString()
    $envelopeSchemaVersion = if (@(
            'plan_vm_power',
            'apply_vm_power',
            'plan_vm_network',
            'apply_vm_network'
        ) -contains $ToolName) { 2 } else { 1 }
    try {
        if (-not [bool]$script:HcrInitialized) {
            Throw-HcrError 'SERVER_NOT_INITIALIZED' 'The runtime has not been initialized.'
        }
        $argumentsValue = Assert-HcrToolArguments $ToolName $Arguments
        $result = switch ($ToolName) {
            'inspect_host' { Invoke-HcrInspectHost $argumentsValue; break }
            'list_vms' { Invoke-HcrListVms $argumentsValue; break }
            'inspect_vm' { Invoke-HcrInspectVm $argumentsValue; break }
            'validate_test_profile' { Invoke-HcrValidateProfile $argumentsValue; break }
            'validate_evidence' { Invoke-HcrValidateEvidenceTool $argumentsValue; break }
            'plan_vm_create' { Invoke-HcrPlanVmCreate $argumentsValue; break }
            'apply_vm_create' { Invoke-HcrApplyVmCreate $argumentsValue $operationId; break }
            'plan_checkpoint_create' { Invoke-HcrPlanCheckpointCreate $argumentsValue; break }
            'apply_checkpoint_create' { Invoke-HcrApplyCheckpointCreate $argumentsValue $operationId; break }
            'plan_checkpoint_restore' { Invoke-HcrPlanCheckpointRestore $argumentsValue; break }
            'apply_checkpoint_restore' { Invoke-HcrApplyCheckpointRestore $argumentsValue; break }
            'inspect_guest' { Invoke-HcrInspectGuest $argumentsValue $operationId; break }
            'stage_artifact' { Invoke-HcrStageArtifact $argumentsValue $operationId; break }
            'run_test_profile' { Invoke-HcrRunTestProfile $argumentsValue $operationId; break }
            'collect_evidence' { Invoke-HcrCollectEvidence $argumentsValue; break }
            'record_manual_attestation' { Invoke-HcrRecordManualAttestation $argumentsValue; break }
            'plan_vm_power' { Invoke-HcrPlanVmPower $argumentsValue; break }
            'apply_vm_power' { Invoke-HcrApplyVmPower $argumentsValue; break }
            'plan_vm_network' { Invoke-HcrPlanVmNetwork $argumentsValue; break }
            'apply_vm_network' { Invoke-HcrApplyVmNetwork $argumentsValue; break }
            default { Throw-HcrError 'METHOD_NOT_FOUND' 'The requested MCP tool does not exist.' }
        }
        $warnings = @()
        foreach ($warning in (Get-HcrPropertyValue $result 'warnings' @())) {
            $warnings += [string]$warning
        }
        if ((Get-HcrAdapterMode) -eq 'mock' -and $warnings -notcontains $script:HcrMockWarning) {
            $warnings += $script:HcrMockWarning
        }
        return New-HcrEnvelope `
            $true `
            $operationId `
            ([bool](Get-HcrPropertyValue $result 'changed' $false)) `
            (Get-HcrPropertyValue $result 'data' ([pscustomobject]@{})) `
            $warnings `
            (Get-HcrPropertyValue $result 'evidencePath') `
            $null `
            $envelopeSchemaVersion
    }
    catch {
        $failure = Get-HcrExceptionData $_.Exception
        $changed = $false
        $warnings = @()
        if ($null -ne $failure.details -and
            [bool](Get-HcrPropertyValue $failure.details 'mutationEntered' $false)) {
            $effectState = [string](Get-HcrPropertyValue $failure.details 'effectState')
            if ($effectState -eq 'confirmed' -or $effectState -eq 'indeterminate') {
                $changed = $true
                $recoveryWarning = [string](Get-HcrPropertyValue $failure.details 'recoveryWarning')
                if ([string]::IsNullOrWhiteSpace($recoveryWarning)) {
                    $recoveryWarning = 'A host mutation may have taken effect; inspect the bounded partial identity before any further mutation.'
                }
                $warnings = @($recoveryWarning)
            }
        }
        return New-HcrEnvelope `
            $false `
            $operationId `
            $changed `
            ([pscustomobject]@{}) `
            $warnings `
            $null `
            $failure `
            $envelopeSchemaVersion
    }
}

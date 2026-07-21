function New-HcrInputSchema {
    param(
        [hashtable]$Properties = @{},
        [string[]]$Required = @()
    )

    $schema = [ordered]@{
        type = 'object'
        additionalProperties = $false
        properties = $Properties
    }
    if ($Required.Count -gt 0) {
        $schema.required = @($Required)
    }
    return [pscustomobject]$schema
}

function New-HcrToolDefinition {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][object]$InputSchema,
        [bool]$ReadOnly = $false,
        [bool]$Destructive = $false
    )

    return [pscustomobject][ordered]@{
        name = $Name
        description = $Description
        inputSchema = $InputSchema
        annotations = [pscustomobject][ordered]@{
            title = $Name
            readOnlyHint = $ReadOnly
            destructiveHint = $Destructive
            idempotentHint = $ReadOnly
            openWorldHint = $false
        }
    }
}

function Get-HcrToolDefinitions {
    $vmName = @{ type = 'string'; minLength = 1; maxLength = 100 }
    $profileName = @{
        type = 'string'
        minLength = 1
        maxLength = 100
        pattern = '^[a-zA-Z0-9][a-zA-Z0-9._-]*$'
    }
    $localPath = @{ type = 'string'; minLength = 3; maxLength = 32767 }
    $uuid = @{ type = 'string'; format = 'uuid' }
    $checkpointName = @{ type = 'string'; minLength = 1; maxLength = 100 }

    $tools = New-Object System.Collections.Generic.List[object]
    $tools.Add((New-HcrToolDefinition 'inspect_host' `
        'Inspect Hyper-V host readiness and requested path/name conflicts without mutation.' `
        (New-HcrInputSchema @{
            vmRoot = $localPath
            minimumFreeSpaceGb = @{ type = 'integer'; minimum = 1; maximum = 4096 }
            vmName = $vmName
        }) $true))
    $tools.Add((New-HcrToolDefinition 'list_vms' `
        'List plugin-managed VM summaries by default; optionally include bounded unmanaged summaries.' `
        (New-HcrInputSchema @{ managedOnly = @{ type = 'boolean'; default = $true } }) $true))
    $tools.Add((New-HcrToolDefinition 'inspect_vm' `
        'Inspect a VM configuration and ownership status without changing it.' `
        (New-HcrInputSchema @{ vmName = $vmName } @('vmName')) $true))
    $tools.Add((New-HcrToolDefinition 'validate_test_profile' `
        'Validate a local declarative lifecycle-test profile against schema v1 and semantic safety rules.' `
        (New-HcrInputSchema @{ profilePath = $localPath } @('profilePath')) $true))
    $tools.Add((New-HcrToolDefinition 'validate_evidence' `
        'Validate a local evidence document against schema v1 and immutable operation state.' `
        (New-HcrInputSchema @{ evidencePath = $localPath } @('evidencePath')) $true))
    $tools.Add((New-HcrToolDefinition 'plan_vm_create' `
        'Create a 15-minute, non-mutating plan for a guarded Generation 2 VM creation.' `
        (New-HcrInputSchema @{
            name = $vmName
            isoPath = $localPath
            vmRoot = $localPath
            switchName = @{ type = 'string'; minLength = 1; maxLength = 256 }
            processorCount = @{ type = 'integer'; minimum = 1; maximum = 64; default = 4 }
            startupMemoryGb = @{ type = 'integer'; minimum = 2; maximum = 256; default = 8 }
            maximumMemoryGb = @{ type = 'integer'; minimum = 2; maximum = 512; default = 12 }
            diskSizeGb = @{ type = 'integer'; minimum = 40; maximum = 2048; default = 100 }
        } @('name', 'isoPath', 'vmRoot', 'switchName'))))
    $tools.Add((New-HcrToolDefinition 'apply_vm_create' `
        'Atomically consume and revalidate a VM-creation plan, then apply only that plan.' `
        (New-HcrInputSchema @{ planId = $uuid } @('planId'))))
    $tools.Add((New-HcrToolDefinition 'plan_checkpoint_create' `
        'Create a non-mutating checkpoint-creation plan for a verified managed VM.' `
        (New-HcrInputSchema @{
            vmName = $vmName
            checkpointName = $checkpointName
        } @('vmName', 'checkpointName'))))
    $tools.Add((New-HcrToolDefinition 'apply_checkpoint_create' `
        'Atomically consume and revalidate a checkpoint-creation plan, then create its checkpoint.' `
        (New-HcrInputSchema @{ planId = $uuid } @('planId'))))
    $tools.Add((New-HcrToolDefinition 'plan_checkpoint_restore' `
        'Create a non-mutating restore plan and return its one-time confirmation token exactly once.' `
        (New-HcrInputSchema @{
            vmName = $vmName
            checkpointName = $checkpointName
        } @('vmName', 'checkpointName'))))
    $tools.Add((New-HcrToolDefinition 'apply_checkpoint_restore' `
        'Atomically consume a restore plan before checking its name, token, and drift guards.' `
        (New-HcrInputSchema @{
            planId = $uuid
            checkpointName = $checkpointName
            confirmationToken = @{
                type = 'string'
                minLength = 32
                maxLength = 256
                pattern = '^[A-Za-z0-9_-]+$'
            }
        } @('planId', 'checkpointName', 'confirmationToken')) $false $true))
    $tools.Add((New-HcrToolDefinition 'inspect_guest' `
        'Inspect the managed guest and standard test-user environment through a named credential profile.' `
        (New-HcrInputSchema @{
            vmName = $vmName
            credentialProfile = $profileName
        } @('vmName', 'credentialProfile')) $false))
    $tools.Add((New-HcrToolDefinition 'stage_artifact' `
        'Copy one host-local regular file to the managed guest staging root and verify both hashes.' `
        (New-HcrInputSchema @{
            vmName = $vmName
            credentialProfile = $profileName
            sourcePath = $localPath
            guestDestination = @{ type = 'string'; minLength = 1; maxLength = 512 }
        } @('vmName', 'credentialProfile', 'sourcePath', 'guestDestination'))))
    $tools.Add((New-HcrToolDefinition 'run_test_profile' `
        'Run only the validated declarative profile steps as the standard test user and stage evidence.' `
        (New-HcrInputSchema @{
            vmName = $vmName
            credentialProfile = $profileName
            profilePath = $localPath
            artifactPath = $localPath
        } @('vmName', 'credentialProfile', 'profilePath', 'artifactPath'))))
    $tools.Add((New-HcrToolDefinition 'collect_evidence' `
        'Export a verified operation evidence copy and SHA-256 inventory to an allowed existing directory.' `
        (New-HcrInputSchema @{
            operationId = $uuid
            outputDirectory = $localPath
        } @('operationId', 'outputDirectory'))))

    $evidenceReference = [pscustomobject][ordered]@{
        type = 'object'
        additionalProperties = $false
        required = @('path', 'sha256')
        properties = @{
            path = @{ type = 'string'; minLength = 1; maxLength = 512 }
            sha256 = @{ type = 'string'; pattern = '^[a-f0-9]{64}$' }
        }
    }
    $tools.Add((New-HcrToolDefinition 'record_manual_attestation' `
        'Bind a human observation and verified relative evidence references to a pending manual assertion.' `
        (New-HcrInputSchema @{
            operationId = $uuid
            assertionId = @{ type = 'string'; minLength = 1; maxLength = 256 }
            status = @{ type = 'string'; enum = @('passed', 'failed', 'unsupported') }
            method = @{
                type = 'string'
                enum = @('visualInspection', 'interactiveExercise', 'externalTool', 'declaredUnsupported')
            }
            summary = @{ type = 'string'; minLength = 1; maxLength = 2000 }
            evidenceReferences = @{ type = 'array'; maxItems = 64; items = $evidenceReference }
        } @('operationId', 'assertionId', 'status', 'method', 'summary'))))

    $tools.Add((New-HcrToolDefinition 'plan_vm_power' `
        'Create a 15-minute, non-mutating plan to start or gracefully shut down a verified managed VM.' `
        (New-HcrInputSchema @{
            vmName = $vmName
            action = @{ type = 'string'; enum = @('start', 'gracefulShutdown') }
        } @('vmName', 'action'))))
    $tools.Add((New-HcrToolDefinition 'apply_vm_power' `
        'Consume and revalidate a VM-power plan, then perform only its guarded start or graceful shutdown.' `
        (New-HcrInputSchema @{ planId = $uuid } @('planId')) $false $true))
    $tools.Add((New-HcrToolDefinition 'plan_vm_network' `
        'Create guarded change and recovery plans for the verified managed primary NIC and its recorded baseline switch.' `
        (New-HcrInputSchema @{
            vmName = $vmName
            target = @{ type = 'string'; enum = @('baseline', 'disconnected') }
        } @('vmName', 'target'))))
    $tools.Add((New-HcrToolDefinition 'apply_vm_network' `
        'Consume and revalidate one VM-network change or recovery plan, then apply only its baseline or disconnected target.' `
        (New-HcrInputSchema @{ planId = $uuid } @('planId')) $false $true))

    if ($tools.Count -ne 20) {
        Throw-HcrError 'INTERNAL_ERROR' 'The runtime tool registry must contain exactly 20 tools.'
    }
    return @($tools | ForEach-Object { $_ })
}

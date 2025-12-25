<#
.SYNOPSIS
    Implementation of ICimService interface.

.DESCRIPTION
    Provides testable CIM/WMI operations.
    This service can be mocked in tests for full testability.

.NOTES
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
    Version: 1.0.0
#>

using namespace System
using namespace Microsoft.Management.Infrastructure

# Internal CIM provider hook for testability
$script:CimInstanceProvider = $null

# Allows tests to inject a deterministic provider without relying on globals
function Set-InternalCimInstanceProvider {
    [CmdletBinding(SupportsShouldProcess)]
    param([ScriptBlock]$Provider)

    if ($PSCmdlet.ShouldProcess('script:CimInstanceProvider', 'Set custom CIM instance provider')) {
        $script:CimInstanceProvider = $Provider
    }
}

function Reset-InternalCimInstanceProvider {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ($PSCmdlet.ShouldProcess('script:CimInstanceProvider', 'Reset custom CIM instance provider')) {
        $script:CimInstanceProvider = $null
    }
}

<#
.SYNOPSIS
    Production implementation of CIM service.
#>
function Get-InternalCimInstance {
    param([hashtable]$Params)
    # Prefer script-scoped test hook for portability (WSL may lack CIM).
    if ($script:CimInstanceProvider) {
        return $script:CimInstanceProvider.InvokeReturnAsIs($Params)
    }
    elseif (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
        return Get-CimInstance @Params
    }
    else {
        # Gracefully return empty array if CIM unavailable (allow callers to handle)
        return @()
    }
}

class CimService : ICimService {

    <#
    .SYNOPSIS
        Gets CIM instances based on class name and filter.
    #>
    [object[]] GetInstances([string]$className, [hashtable]$filter) {
        if ([string]::IsNullOrWhiteSpace($className)) {
            throw [ArgumentException]::new("Class name cannot be empty", "className")
        }

        $params = @{
            ClassName = $className
            ErrorAction = 'Stop'
        }

        if ($null -ne $filter -and $filter.Count -gt 0) {
            $params['Filter'] = $filter
        }

        try {
            $instances = Get-InternalCimInstance $params
            return @($instances)
        }
        catch {
            throw [CimException]::new("Failed to get CIM instances for $className : $_", $_.Exception)
        }
    }

    <#
    .SYNOPSIS
        Gets a single CIM instance based on key properties.
    #>
    [object] GetInstance([string]$className, [hashtable]$keyProperties) {
        if ([string]::IsNullOrWhiteSpace($className)) {
            throw [ArgumentException]::new("Class name cannot be empty", "className")
        }

        try {
            $instances = $this.GetInstances($className, $keyProperties)

            if ($instances.Count -eq 0) {
                return $null
            }

            return $instances[0]
        }
        catch {
            throw [CimException]::new("Failed to get CIM instance for $className : $_", $_.Exception)
        }
    }
}

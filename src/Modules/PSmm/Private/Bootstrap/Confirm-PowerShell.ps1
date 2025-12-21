<#
.SYNOPSIS
    Validates and manages PowerShell environment requirements for PSmediaManager.

.DESCRIPTION
    Provides functions to verify PowerShell version compatibility and manage
    required PowerShell modules (installation, updates, and health checks).
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function _GetConfigMemberValue {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][object]$Object,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    if ($Object -is [System.Collections.IDictionary]) {
        try { if ($Object.ContainsKey($Name)) { return $Object[$Name] } }
        catch { Write-Verbose "Dictionary ContainsKey failed for '$Name'. $($_.Exception.Message)" }

        try { if ($Object.Contains($Name)) { return $Object[$Name] } }
        catch { Write-Verbose "Dictionary Contains failed for '$Name'. $($_.Exception.Message)" }

        try {
            foreach ($k in $Object.Keys) {
                if ($k -eq $Name) { return $Object[$k] }
            }
        }
        catch { Write-Verbose "Dictionary key enumeration failed for '$Name'. $($_.Exception.Message)" }
        return $null
    }

    $p = $Object.PSObject.Properties[$Name]
    if ($null -ne $p) {
        return $p.Value
    }

    return $null
}

function _SetConfigMemberValue {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][object]$Object,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter()][AllowNull()]$Value
    )

    if ($null -eq $Object) {
        return
    }

    if ($Object -is [System.Collections.IDictionary]) {
        $Object[$Name] = $Value
        return
    }

    try {
        $Object.$Name = $Value
    }
    catch {
        $typeName = $Object.GetType().FullName
        Write-Verbose "Failed to set member '$Name' on object type '$typeName'. $($_.Exception.Message)"
    }
}

function _GetConfigNestedValue {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][object]$Object,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$Path
    )

    $current = $Object
    foreach ($segment in $Path) {
        $current = _GetConfigMemberValue -Object $current -Name $segment
        if ($null -eq $current) {
            return $null
        }
    }

    return $current
}

<#
.SYNOPSIS
    Confirms PowerShell environment meets application requirements.

.DESCRIPTION
    Validates the PowerShell version and manages required modules based on the
    specified scope. Supports version checking, module installation/import,
    and optional module updates with health checks and rollback capability.

.PARAMETER Config
    The AppConfiguration object containing PowerShell requirements.


.PARAMETER Scope
    The validation scope to perform:
    - 'PSVersion': Validates PowerShell version against minimum requirement
    - 'PSModules': Manages required module installation, import, and updates

.EXAMPLE
    Confirm-PowerShell -Config $appConfig -Scope 'PSVersion'
    Validates that the current PowerShell version meets minimum requirements.



.NOTES
    - PSVersion failures will terminate the application
    - Module installation failures are logged but don't stop execution
    - Update mode includes health checks and automatic rollback on failure
#>
function Confirm-PowerShell {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config,

        [Parameter(Mandatory)]
        [ValidateSet('PSVersion', 'PSModules')]
        [string]$Scope
    )

    try {
        Write-Verbose "Confirming PowerShell $Scope..."

        switch ($Scope) {
            'PSVersion' {
                Confirm-PowerShellVersion -Config $Config
            }
            'PSModules' {
                Confirm-PowerShellModules -Config $Config
            }
        }
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Confirm PS $Scope" `
            -Message "Failed to confirm PowerShell $Scope" -ErrorRecord $_ -Console -File
        throw
    }
}

<#
.SYNOPSIS
    Validates PowerShell version against minimum requirements.

.PARAMETER Run
    The runtime configuration hashtable.
#>
function Confirm-PowerShellVersion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config
    )

    Write-PSmmLog -Level INFO -Context 'Confirm PS Version' `
        -Message 'Validating PowerShell version against minimum requirement' -Console -File

    try {
        $requirementsSource = _GetConfigMemberValue -Object $Config -Name 'Requirements'
        $requirements = [RequirementsConfig]::FromObject($requirementsSource)
        _SetConfigMemberValue -Object $Config -Name 'Requirements' -Value $requirements

        $minimumVersion = $requirements.PowerShell.VersionMinimum
        $currentVersion = $PSVersionTable.PSVersion

        # Optionally record current version in configuration if supported
        try { $requirements.PowerShell.VersionCurrent = $currentVersion } catch { Write-Verbose "Unable to record current PowerShell version in config: $_" }

        if ($currentVersion -lt $minimumVersion) {
            $message = "PowerShell version too low. Required: >=$minimumVersion, Current: $currentVersion"
            Write-PSmmLog -Level ERROR -Context 'Confirm PS Version' `
                -Message $message -Console -File

            Wait-Logging
            throw $message
        }

        Write-PSmmLog -Level SUCCESS -Context 'Confirm PS Version' `
            -Message "PowerShell version is sufficient. Required: >=$minimumVersion, Current: $currentVersion" `
            -Console -File
    }
    catch {
        $message = 'Version validation failed'
        Write-PSmmLog -Level ERROR -Context 'Confirm PS Version' `
            -Message $message -ErrorRecord $_ -Console -File
        Wait-Logging
        throw $message
    }
}

<#
.SYNOPSIS
    Manages required PowerShell modules (install, import, update).

.PARAMETER Run
    The runtime configuration hashtable containing module requirements.
#>
function Confirm-PowerShellModules {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Function manages multiple PowerShell modules')]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config
    )

    Write-PSmmLog -Level INFO -Context 'Confirm PS Modules' `
        -Message 'Checking for required PowerShell modules' -Console -File

    $requirementsSource = _GetConfigMemberValue -Object $Config -Name 'Requirements'
    $requirements = [RequirementsConfig]::FromObject($requirementsSource)
    _SetConfigMemberValue -Object $Config -Name 'Requirements' -Value $requirements

    $parametersSource = _GetConfigMemberValue -Object $Config -Name 'Parameters'
    $parameters = [RuntimeParameters]::FromObject($parametersSource)
    _SetConfigMemberValue -Object $Config -Name 'Parameters' -Value $parameters

    # Install and import required modules
    foreach ($module in $requirements.PowerShell.Modules) {
        Install-RequiredModule -ModuleInfo $module
        Import-RequiredModule -ModuleInfo $module
    }

    # Update modules if requested
    if ($parameters.Update) {
        Update-PowerShellModules
    }
}

<#
.SYNOPSIS
    Installs a required PowerShell module if not already present.

.PARAMETER ModuleInfo
    Module information object with Name property.
#>
function Install-RequiredModule {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$ModuleInfo
    )

    $moduleName = $ModuleInfo.Name

    if (Get-InstalledModule -Name $moduleName -ErrorAction SilentlyContinue) {
        Write-Verbose "Module already installed: $moduleName"
        return
    }

    try {
        Write-Verbose "Installing module: $moduleName"
        Install-Module -Name $moduleName -Force -Scope CurrentUser -ErrorAction Stop

        Write-PSmmLog -Level SUCCESS -Context 'Install PS Modules' `
            -Message "Installed missing module: $moduleName" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context 'Install PS Modules' `
            -Message "Failed to install module: $moduleName" -ErrorRecord $_ -Console -File
    }
}

<#
.SYNOPSIS
    Imports a required PowerShell module.

.PARAMETER ModuleInfo
    Module information object with Name property.
#>
function Import-RequiredModule {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$ModuleInfo
    )

    $moduleName = $ModuleInfo.Name

    try {
        Write-Verbose "Importing module: $moduleName"
        Import-Module -Name $moduleName -Force -ErrorAction Stop

        Write-PSmmLog -Level SUCCESS -Context 'Import PS Modules' `
            -Message "Imported module: $moduleName" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context 'Import PS Modules' `
            -Message "Failed to import module: $moduleName" -ErrorRecord $_ -Console -File
    }
}

<#
.SYNOPSIS
    Updates all installed PowerShell modules with user confirmation.

.DESCRIPTION
    Scans for outdated modules, prompts for update confirmation, performs
    updates with health checks, and automatically rolls back on failure.
#>
function Update-PowerShellModules {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Function updates multiple PowerShell modules')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param()

    Write-Verbose 'Starting module update process...'

    if ($PSCmdlet.ShouldProcess('PowerShell modules', 'Update all installed modules')) {
        try {
            $installedModules = Get-InstalledModule -ErrorAction Stop

            foreach ($module in $installedModules) {
                Update-SingleModule -Module $module
            }

            Write-PSmmLog -Level SUCCESS -Context 'Update PS Modules' `
                -Message 'Module update process complete' -Console -File
        }
        catch {
            Write-PSmmLog -Level ERROR -Context 'Update PS Modules' `
                -Message 'Failed to complete module updates' -ErrorRecord $_ -Console -File
        }
    }
}

<#
.SYNOPSIS
    Updates a single PowerShell module with health check and rollback.

.PARAMETER Module
    The installed module object to potentially update.
#>
function Update-SingleModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Module
    )

    $moduleName = $Module.Name
    $currentVersion = $Module.Version

    try {
        # Check for available updates
        $latestModule = Find-Module -Name $moduleName -ErrorAction SilentlyContinue

        if (-not $latestModule) {
            Write-Verbose "Could not find module in repository: $moduleName"
            return
        }

        if ($currentVersion -ge $latestModule.Version) {
            Write-PSmmLog -Level INFO -Context 'Update PS Modules' `
                -Message "$moduleName is up to date (Version: $currentVersion)" -Console -File
            return
        }

        # Update with ShouldProcess support
        if ($PSCmdlet.ShouldProcess("$moduleName", "Update from $currentVersion to $($latestModule.Version)")) {
            Invoke-ModuleUpdate -ModuleName $moduleName `
                -CurrentVersion $currentVersion `
                -TargetVersion $latestModule.Version
        }
        else {
            Write-PSmmLog -Level INFO -Context 'Update PS Modules' `
                -Message "Skipped update for $moduleName" -Console -File
        }
    }
    catch {
        Write-PSmmLog -Level ERROR -Context 'Update PS Modules' `
            -Message "Error processing update for $moduleName" -ErrorRecord $_ -Console -File
    }
}

<#
.SYNOPSIS
    Performs module update with health check and rollback capability.

.PARAMETER ModuleName
    Name of the module to update.

.PARAMETER CurrentVersion
    Current installed version (for rollback).

.PARAMETER TargetVersion
    Target version to update to.
#>
function Invoke-ModuleUpdate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [version]$CurrentVersion,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [version]$TargetVersion
    )

    try {
        Write-Verbose "Updating $ModuleName from $CurrentVersion to $TargetVersion..."

        # Perform update
        Update-Module -Name $ModuleName -Force -ErrorAction Stop

        Write-PSmmLog -Level SUCCESS -Context 'Update PS Modules' `
            -Message "Updated $ModuleName from $CurrentVersion to $TargetVersion" -Console -File

        # Health check: verify module can be imported
        Test-ModuleHealth -ModuleName $ModuleName -RollbackVersion $CurrentVersion
    }
    catch {
        Write-PSmmLog -Level ERROR -Context 'Update PS Modules' `
            -Message "Failed to update $ModuleName" -ErrorRecord $_ -Console -File
    }
}

<#
.SYNOPSIS
    Tests module health after update and rolls back on failure.

.PARAMETER ModuleName
    Name of the module to test.

.PARAMETER RollbackVersion
    Version to rollback to if health check fails.
#>
function Test-ModuleHealth {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [version]$RollbackVersion
    )

    try {
        Write-Verbose "Performing health check on $ModuleName..."

        Import-Module -Name $ModuleName -Force -ErrorAction Stop

        Write-PSmmLog -Level SUCCESS -Context 'Import PS Modules' `
            -Message "Health check passed for $ModuleName" -Console -File
    }
    catch {
        Write-PSmmLog -Level WARNING -Context 'Import PS Modules' `
            -Message "Health check failed for $ModuleName. Rolling back to $RollbackVersion..." `
            -Console -File

        # Attempt rollback
        Invoke-ModuleRollback -ModuleName $ModuleName -Version $RollbackVersion
    }
}

<#
.SYNOPSIS
    Rolls back a module to a previous version.

.PARAMETER ModuleName
    Name of the module to rollback.

.PARAMETER Version
    Version to rollback to.
#>
function Invoke-ModuleRollback {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [version]$Version
    )

    try {
        Write-Verbose "Rolling back $ModuleName to version $Version..."

        Install-Module -Name $ModuleName -RequiredVersion $Version -Force -ErrorAction Stop

        try {
            Import-Module -Name $ModuleName -Force -ErrorAction Stop
            Write-PSmmLog -Level SUCCESS -Context 'Install PS Modules' `
                -Message "Rollback successful: $ModuleName restored to $Version" -Console -File
        }
        catch {
            Write-PSmmLog -Level EMERGENCY -Context 'Install PS Modules' `
                -Message "Rollback import failed for $ModuleName $Version" -ErrorRecord $_ -Console -File
        }
    }
    catch {
        Write-PSmmLog -Level ERROR -Context 'Install PS Modules' `
            -Message "Rollback failed for $ModuleName" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########

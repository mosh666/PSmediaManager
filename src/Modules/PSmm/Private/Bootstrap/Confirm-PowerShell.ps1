<#
.SYNOPSIS
    Validates and manages PowerShell environment requirements for PSmediaManager.

.DESCRIPTION
    Provides functions to verify PowerShell version compatibility and manage
    required PowerShell modules (installation, updates, and health checks).
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

if (-not (Get-Command -Name Get-PSmmConfigMemberValue -ErrorAction SilentlyContinue)) {
    $helperPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Get-PSmmConfigMemberValue.ps1'
    if (Test-Path -LiteralPath $helperPath) {
        . $helperPath
    }
}

if (-not (Get-Command -Name Set-PSmmConfigMemberValue -ErrorAction SilentlyContinue)) {
    $helperPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Set-PSmmConfigMemberValue.ps1'
    if (Test-Path -LiteralPath $helperPath) {
        . $helperPath
    }
}

if (-not (Get-Command -Name Get-PSmmConfigNestedValue -ErrorAction SilentlyContinue)) {
    $helperPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Get-PSmmConfigNestedValue.ps1'
    if (Test-Path -LiteralPath $helperPath) {
        . $helperPath
    }
}

#region ########## PRIVATE ##########

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
        $requirementsSource = Get-PSmmConfigMemberValue -Object $Config -Name 'Requirements' -Default $null
        $requirements = [RequirementsConfig]::FromObject($requirementsSource)
        Set-PSmmConfigMemberValue -Object $Config -Name 'Requirements' -Value $requirements

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

    $requirementsSource = Get-PSmmConfigMemberValue -Object $Config -Name 'Requirements' -Default $null
    $requirements = [RequirementsConfig]::FromObject($requirementsSource)
    Set-PSmmConfigMemberValue -Object $Config -Name 'Requirements' -Value $requirements

    $parametersSource = Get-PSmmConfigMemberValue -Object $Config -Name 'Parameters' -Default $null
    $parameters = [RuntimeParameters]::FromObject($parametersSource)
    Set-PSmmConfigMemberValue -Object $Config -Name 'Parameters' -Value $parameters

    # Validate and import required modules (no runtime installs/updates)
    foreach ($module in $requirements.PowerShell.Modules) {
        Install-RequiredModule -ModuleInfo $module
        Import-RequiredModule -ModuleInfo $module
    }

    if ($parameters.Update) {
        Write-PSmmLog -Level WARNING -Context 'Confirm PS Modules' `
            -Message 'Runtime module updates are disabled by policy. Update modules manually if needed.' -Console -File
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

    $candidate = Get-Module -Name $moduleName -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if ($candidate) {
        return
    }

    $message = "Required PowerShell module '$moduleName' is missing. Install it manually with: Install-Module -Name $moduleName -Scope CurrentUser"
    Write-PSmmLog -Level ERROR -Context 'Confirm PS Modules' -Message $message -Console -File
    throw $message
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

    $alreadyLoaded = Get-Module -Name $moduleName -ErrorAction SilentlyContinue
    if ($alreadyLoaded) {
        Write-Verbose "Module already imported: $moduleName (Version: $($alreadyLoaded.Version))"
        Write-PSmmLog -Level SUCCESS -Context 'Import PS Modules' `
            -Message "Imported module: $moduleName" -Console -File
        return
    }

    try {
        Write-Verbose "Importing module: $moduleName"
        Import-Module -Name $moduleName -ErrorAction Stop

        Write-PSmmLog -Level SUCCESS -Context 'Import PS Modules' `
            -Message "Imported module: $moduleName" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context 'Import PS Modules' `
            -Message "Failed to import module: $moduleName" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########

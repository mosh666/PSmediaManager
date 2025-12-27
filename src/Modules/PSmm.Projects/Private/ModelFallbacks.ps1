#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Resolve-PSmmProjectsType {
    [CmdletBinding()]
    [OutputType([type])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    return ($Name -as [type])
}

function ConvertTo-PSmmProjectsConfig {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][object]$Object
    )

    $projectsConfigType = Resolve-PSmmProjectsType -Name 'ProjectsConfig'
    if ($projectsConfigType) {
        return $projectsConfigType::FromObject($Object)
    }

    if ($null -eq $Object) {
        $cfg = [pscustomobject]@{
            Registry = $null
            Paths    = $null
            Current  = $null
        }
    }
    elseif ($Object -is [System.Collections.IDictionary]) {
        $cfg = [pscustomobject]$Object
    }
    else {
        $cfg = $Object
    }

    if ($cfg -isnot [psobject]) {
        $cfg = [pscustomobject]@{ Value = $cfg }
    }

    if ($cfg.PSObject.Properties.Match('Registry').Count -eq 0) {
        $cfg | Add-Member -NotePropertyName 'Registry' -NotePropertyValue $null -Force
    }
    if ($cfg.PSObject.Properties.Match('Paths').Count -eq 0) {
        $cfg | Add-Member -NotePropertyName 'Paths' -NotePropertyValue $null -Force
    }
    if ($cfg.PSObject.Properties.Match('Current').Count -eq 0) {
        $cfg | Add-Member -NotePropertyName 'Current' -NotePropertyValue $null -Force
    }

    $cfg.PSObject.TypeNames.Insert(0, 'ProjectsConfig')
    return $cfg
}

function ConvertTo-PSmmProjectsPathsConfig {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][object]$Object
    )

    $pathsType = Resolve-PSmmProjectsType -Name 'ProjectsPathsConfig'
    if ($pathsType) {
        return $pathsType::FromObject($Object)
    }

    if ($null -eq $Object) {
        $paths = [pscustomobject]@{ Assets = $null }
    }
    elseif ($Object -is [System.Collections.IDictionary]) {
        $paths = [pscustomobject]$Object
    }
    else {
        $paths = $Object
    }

    if ($paths -isnot [psobject]) {
        $paths = [pscustomobject]@{ Value = $paths }
    }

    if ($paths.PSObject.Properties.Match('Assets').Count -eq 0) {
        $paths | Add-Member -NotePropertyName 'Assets' -NotePropertyValue $null -Force
    }

    if ($paths.PSObject.Methods.Match('ToHashtable').Count -eq 0) {
        $paths | Add-Member -MemberType ScriptMethod -Name 'ToHashtable' -Value {
            @{
                Assets = $this.Assets
            }
        } -Force
    }

    $paths.PSObject.TypeNames.Insert(0, 'ProjectsPathsConfig')
    return $paths
}

function ConvertTo-PSmmProjectCurrentConfig {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][object]$Object
    )

    $currentType = Resolve-PSmmProjectsType -Name 'ProjectCurrentConfig'
    if ($currentType) {
        return $currentType::FromObject($Object)
    }

    if ($null -eq $Object) {
        $cur = [pscustomobject]@{}
    }
    elseif ($Object -is [System.Collections.IDictionary]) {
        $cur = [pscustomobject]$Object
    }
    else {
        $cur = $Object
    }

    $cur.PSObject.TypeNames.Insert(0, 'ProjectCurrentConfig')
    return $cur
}

function New-PSmmProjectsValidationException {
    [CmdletBinding()]
    [OutputType([System.Exception])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Message,
        [Parameter()][AllowNull()][string]$Problem,
        [Parameter()][AllowNull()][string]$Path
    )

    $validationType = Resolve-PSmmProjectsType -Name 'ValidationException'
    if ($validationType) {
        return $validationType::new($Message, $Problem, $Path)
    }

    return [System.InvalidOperationException]::new($Message)
}

function ConvertTo-PSmmPluginsConfig {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][object]$Object
    )

    $pluginsConfigType = Resolve-PSmmProjectsType -Name 'PluginsConfig'
    if ($pluginsConfigType) {
        return $pluginsConfigType::FromObject($Object)
    }

    if ($null -eq $Object) {
        $cfg = [pscustomobject]@{ Paths = $null }
    }
    elseif ($Object -is [System.Collections.IDictionary]) {
        $cfg = [pscustomobject]$Object
    }
    else {
        $cfg = $Object
    }

    if ($cfg -isnot [psobject]) {
        $cfg = [pscustomobject]@{ Value = $cfg }
    }

    if ($cfg.PSObject.Properties.Match('Paths').Count -eq 0) {
        $cfg | Add-Member -NotePropertyName 'Paths' -NotePropertyValue $null -Force
    }

    $cfg.PSObject.TypeNames.Insert(0, 'PluginsConfig')
    return $cfg
}

function ConvertTo-PSmmPluginsPathsConfig {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][object]$Object
    )

    $pathsType = Resolve-PSmmProjectsType -Name 'PluginsPathsConfig'
    if ($pathsType) {
        return $pathsType::FromObject($Object)
    }

    if ($null -eq $Object) {
        $paths = [pscustomobject]@{ Project = $null }
    }
    elseif ($Object -is [System.Collections.IDictionary]) {
        $paths = [pscustomobject]$Object
    }
    else {
        $paths = $Object
    }

    if ($paths -isnot [psobject]) {
        $paths = [pscustomobject]@{ Value = $paths }
    }

    if ($paths.PSObject.Properties.Match('Project').Count -eq 0) {
        $paths | Add-Member -NotePropertyName 'Project' -NotePropertyValue $null -Force
    }

    $paths.PSObject.TypeNames.Insert(0, 'PluginsPathsConfig')
    return $paths
}

function New-PSmmProjectException {
    [CmdletBinding()]
    [OutputType([System.Exception])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Message,
        [Parameter()][AllowNull()][string]$Context
    )

    $type = Resolve-PSmmProjectsType -Name 'ProjectException'
    if ($type) {
        return $type::new($Message, $Context)
    }

    return [System.InvalidOperationException]::new($Message)
}

function New-PSmmStorageException {
    [CmdletBinding()]
    [OutputType([System.Exception])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Message,
        [Parameter()][AllowNull()][string]$SerialNumber
    )

    $type = Resolve-PSmmProjectsType -Name 'StorageException'
    if ($type) {
        return $type::new($Message, $SerialNumber)
    }

    return [System.InvalidOperationException]::new($Message)
}

function New-PSmmProjectStorageDriveInfo {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][string]$Label,
        [Parameter()][AllowNull()][string]$DriveLetter,
        [Parameter()][AllowNull()][string]$SerialNumber,
        [Parameter()][AllowNull()][string]$StorageDriveLabel
    )

    $type = Resolve-PSmmProjectsType -Name 'ProjectStorageDriveInfo'
    if ($type) {
        return $type::new($Label, $DriveLetter, $SerialNumber, $StorageDriveLabel)
    }

    $obj = [pscustomobject]@{
        Label            = $Label
        DriveLetter       = $DriveLetter
        SerialNumber      = $SerialNumber
        StorageDriveLabel = $StorageDriveLabel
    }
    $obj.PSObject.TypeNames.Insert(0, 'ProjectStorageDriveInfo')
    return $obj
}

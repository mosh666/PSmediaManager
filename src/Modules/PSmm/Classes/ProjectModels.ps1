#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function _PSmm_DictionaryHasKey {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Dictionary,
        [Parameter(Mandatory)][object]$Key
    )

    $hasKey = $false
    try { $hasKey = $Dictionary.ContainsKey($Key) } catch { $hasKey = $false }
    if (-not $hasKey) {
        try { $hasKey = $Dictionary.Contains($Key) } catch { $hasKey = $false }
    }

    if (-not $hasKey) {
        try {
            foreach ($k in $Dictionary.Keys) {
                if ($k -eq $Key) { return $true }
            }
        }
        catch {
            Write-Verbose "_PSmm_DictionaryHasKey: Enumerating dictionary keys failed: $($_.Exception.Message)"
        }
    }
    return $hasKey
}

class ProjectStorageDriveRef {
    [string]$Label = ''
    [string]$DriveLetter = ''
    [string]$SerialNumber = ''
    [string]$DriveLabel = ''

    ProjectStorageDriveRef() {
    }

    ProjectStorageDriveRef(
        [string]$label,
        [string]$driveLetter,
        [string]$serialNumber,
        [string]$driveLabel
    ) {
        $this.Label = $label
        $this.DriveLetter = $driveLetter
        $this.SerialNumber = $serialNumber
        $this.DriveLabel = $driveLabel
    }

    static [ProjectStorageDriveRef] FromObject([object]$obj) {
        if ($null -eq $obj) {
            return [ProjectStorageDriveRef]::new()
        }

        if ($obj -is [ProjectStorageDriveRef]) {
            return $obj
        }

        $drive = [ProjectStorageDriveRef]::new()

        if ($obj -is [System.Collections.IDictionary]) {
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Label') { $drive.Label = [string]$obj['Label'] }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'DriveLetter') { $drive.DriveLetter = [string]$obj['DriveLetter'] }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'SerialNumber') { $drive.SerialNumber = [string]$obj['SerialNumber'] }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'DriveLabel') { $drive.DriveLabel = [string]$obj['DriveLabel'] }
            return $drive
        }

        if ($obj.PSObject.Properties.Match('Label').Count -gt 0) { $drive.Label = [string]$obj.Label }
        if ($obj.PSObject.Properties.Match('DriveLetter').Count -gt 0) { $drive.DriveLetter = [string]$obj.DriveLetter }
        if ($obj.PSObject.Properties.Match('SerialNumber').Count -gt 0) { $drive.SerialNumber = [string]$obj.SerialNumber }
        if ($obj.PSObject.Properties.Match('DriveLabel').Count -gt 0) { $drive.DriveLabel = [string]$obj.DriveLabel }

        return $drive
    }

    [hashtable] ToHashtable() {
        return @{
            Label        = $this.Label
            DriveLetter  = $this.DriveLetter
            SerialNumber = $this.SerialNumber
            DriveLabel   = $this.DriveLabel
        }
    }
}

class ProjectCurrentConfig {
    [string]$Name = ''
    [string]$Path = ''
    [string]$Config = ''
    [string]$Backup = ''
    [string]$Databases = ''
    [string]$Documents = ''
    [string]$Libraries = ''
    [string]$Vault = ''
    [string]$Log = ''
    [ProjectStorageDriveRef]$StorageDrive

    ProjectCurrentConfig() {
        $this.StorageDrive = [ProjectStorageDriveRef]::new()
    }

    static [ProjectCurrentConfig] FromObject([object]$obj) {
        if ($null -eq $obj) {
            return [ProjectCurrentConfig]::new()
        }

        if ($obj -is [ProjectCurrentConfig]) {
            return $obj
        }

        $current = [ProjectCurrentConfig]::new()

        if ($obj -is [System.Collections.IDictionary]) {
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Name') { $current.Name = [string]$obj['Name'] }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Path') { $current.Path = [string]$obj['Path'] }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Config') { $current.Config = [string]$obj['Config'] }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Backup') { $current.Backup = [string]$obj['Backup'] }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Databases') { $current.Databases = [string]$obj['Databases'] }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Documents') { $current.Documents = [string]$obj['Documents'] }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Libraries') { $current.Libraries = [string]$obj['Libraries'] }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Vault') { $current.Vault = [string]$obj['Vault'] }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Log') { $current.Log = [string]$obj['Log'] }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'StorageDrive') { $current.StorageDrive = [ProjectStorageDriveRef]::FromObject($obj['StorageDrive']) }
            return $current
        }

        if ($obj.PSObject.Properties.Match('Name').Count -gt 0) { $current.Name = [string]$obj.Name }
        if ($obj.PSObject.Properties.Match('Path').Count -gt 0) { $current.Path = [string]$obj.Path }
        if ($obj.PSObject.Properties.Match('Config').Count -gt 0) { $current.Config = [string]$obj.Config }
        if ($obj.PSObject.Properties.Match('Backup').Count -gt 0) { $current.Backup = [string]$obj.Backup }
        if ($obj.PSObject.Properties.Match('Databases').Count -gt 0) { $current.Databases = [string]$obj.Databases }
        if ($obj.PSObject.Properties.Match('Documents').Count -gt 0) { $current.Documents = [string]$obj.Documents }
        if ($obj.PSObject.Properties.Match('Libraries').Count -gt 0) { $current.Libraries = [string]$obj.Libraries }
        if ($obj.PSObject.Properties.Match('Vault').Count -gt 0) { $current.Vault = [string]$obj.Vault }
        if ($obj.PSObject.Properties.Match('Log').Count -gt 0) { $current.Log = [string]$obj.Log }
        if ($obj.PSObject.Properties.Match('StorageDrive').Count -gt 0) { $current.StorageDrive = [ProjectStorageDriveRef]::FromObject($obj.StorageDrive) }

        return $current
    }

    [hashtable] ToHashtable() {
        return @{
            Name         = $this.Name
            Path         = $this.Path
            Config       = $this.Config
            Backup       = $this.Backup
            Databases    = $this.Databases
            Documents    = $this.Documents
            Libraries    = $this.Libraries
            Vault        = $this.Vault
            Log          = $this.Log
            StorageDrive = if ($null -ne $this.StorageDrive) { $this.StorageDrive.ToHashtable() } else { $null }
        }
    }
}

class ProjectsPortRegistry {
    [hashtable]$ByProject

    ProjectsPortRegistry() {
        $this.ByProject = @{}
    }

    static [ProjectsPortRegistry] FromObject([object]$obj) {
        if ($null -eq $obj) {
            return [ProjectsPortRegistry]::new()
        }

        if ($obj -is [ProjectsPortRegistry]) {
            return $obj
        }

        # If the object wraps a ByProject property, unwrap it
        if ($obj.PSObject.Properties.Match('ByProject').Count -gt 0) {
            return [ProjectsPortRegistry]::FromObject($obj.ByProject)
        }

        $registry = [ProjectsPortRegistry]::new()

        if ($obj -is [System.Collections.IDictionary]) {
            foreach ($key in $obj.Keys) {
                $projectName = [string]$key
                if ([string]::IsNullOrWhiteSpace($projectName)) {
                    continue
                }

                $rawPort = $obj[$key]
                if ($null -eq $rawPort) {
                    continue
                }

                try {
                    $port = [int]$rawPort
                }
                catch {
                    continue
                }

                if ($port -le 0) {
                    continue
                }

                $registry.ByProject[$projectName] = $port
            }

            return $registry
        }

        return $registry
    }

    [hashtable] ToHashtable() {
        $ht = @{}
        foreach ($k in $this.ByProject.Keys) {
            $ht[[string]$k] = [int]$this.ByProject[$k]
        }
        return $ht
    }

    [int] GetCount() {
        return @($this.ByProject.Keys).Count
    }

    [string[]] GetKeys() {
        return @($this.ByProject.Keys)
    }

    [int[]] GetValues() {
        return @($this.ByProject.Values | ForEach-Object { [int]$_ })
    }

    [bool] ContainsKey([string]$projectName) {
        if ([string]::IsNullOrWhiteSpace($projectName)) {
            return $false
        }
        return $this.ByProject.ContainsKey($projectName)
    }

    [int] GetPort([string]$projectName) {
        if ([string]::IsNullOrWhiteSpace($projectName)) {
            return 0
        }

        if ($this.ByProject.ContainsKey($projectName)) {
            return [int]$this.ByProject[$projectName]
        }

        return 0
    }

    [void] SetPort([string]$projectName, [int]$port) {
        if ([string]::IsNullOrWhiteSpace($projectName)) {
            throw [System.ArgumentException]::new('ProjectName cannot be null or empty', 'projectName')
        }
        if ($port -le 0) {
            throw [System.ArgumentOutOfRangeException]::new('port', $port, 'Port must be a positive integer')
        }

        $this.ByProject[$projectName] = $port
    }
}

class ProjectsPathsConfig {
    [string]$Assets = ''

    ProjectsPathsConfig() {
    }

    ProjectsPathsConfig([string]$assets) {
        $this.Assets = $assets
    }

    static [ProjectsPathsConfig] FromObject([object]$obj) {
        if ($null -eq $obj) {
            return [ProjectsPathsConfig]::new()
        }

        if ($obj -is [ProjectsPathsConfig]) {
            return $obj
        }

        $paths = [ProjectsPathsConfig]::new()

        if ($obj -is [System.Collections.IDictionary]) {
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Assets') {
                $paths.Assets = [string]$obj['Assets']
            }
            return $paths
        }

        if ($obj.PSObject.Properties.Match('Assets').Count -gt 0) {
            $paths.Assets = [string]$obj.Assets
        }

        return $paths
    }

    [hashtable] ToHashtable() {
        return @{
            Assets = $this.Assets
        }
    }
}

class PluginsPathsConfig {
    [string]$Global = ''
    [string]$Project = ''

    PluginsPathsConfig() {
    }

    PluginsPathsConfig([string]$global, [string]$project) {
        $this.Global = $global
        $this.Project = $project
    }

    static [PluginsPathsConfig] FromObject([object]$obj) {
        if ($null -eq $obj) {
            return [PluginsPathsConfig]::new()
        }

        if ($obj -is [PluginsPathsConfig]) {
            return $obj
        }

        $paths = [PluginsPathsConfig]::new()

        if ($obj -is [System.Collections.IDictionary]) {
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Global') { $paths.Global = [string]$obj['Global'] }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Project') { $paths.Project = [string]$obj['Project'] }
            return $paths
        }

        if ($obj.PSObject.Properties.Match('Global').Count -gt 0) { $paths.Global = [string]$obj.Global }
        if ($obj.PSObject.Properties.Match('Project').Count -gt 0) { $paths.Project = [string]$obj.Project }

        return $paths
    }

    [hashtable] ToHashtable() {
        return @{
            Global  = $this.Global
            Project = $this.Project
        }
    }
}

class PluginsConfig {
    [object]$Global
    [object]$Project
    [hashtable]$Resolved
    [PluginsPathsConfig]$Paths

    PluginsConfig() {
        $this.Global = $null
        $this.Project = $null
        $this.Resolved = $null
        $this.Paths = [PluginsPathsConfig]::new()
    }

    static [object] UnwrapManifest([object]$value) {
        if ($null -eq $value) {
            return $null
        }

        if ($value -is [System.Collections.IDictionary] -and (_PSmm_DictionaryHasKey -Dictionary $value -Key 'Plugins')) {
            return $value['Plugins']
        }

        if ($value.PSObject.Properties.Match('Plugins').Count -gt 0) {
            try { return $value.Plugins } catch { Write-Verbose "PluginsConfig.UnwrapManifest: Failed to read Plugins property: $($_.Exception.Message)" }
        }

        return $value
    }

    static [PluginsConfig] FromObject([object]$obj) {
        if ($null -eq $obj) {
            return [PluginsConfig]::new()
        }

        if ($obj -is [PluginsConfig]) {
            return $obj
        }

        $cfg = [PluginsConfig]::new()

        if ($obj -is [System.Collections.IDictionary]) {
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Paths') { $cfg.Paths = [PluginsPathsConfig]::FromObject($obj['Paths']) }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Global') { $cfg.Global = [PluginsConfig]::UnwrapManifest($obj['Global']) }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Project') { $cfg.Project = [PluginsConfig]::UnwrapManifest($obj['Project']) }

            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Resolved') {
                $resolvedValue = $obj['Resolved']
                if ($resolvedValue -is [hashtable]) {
                    $cfg.Resolved = $resolvedValue
                }
                elseif ($resolvedValue -is [System.Collections.IDictionary]) {
                    $ht = @{}
                    foreach ($k in $resolvedValue.Keys) { $ht[[string]$k] = $resolvedValue[$k] }
                    $cfg.Resolved = $ht
                }
                else {
                    try { $cfg.Resolved = [hashtable]$resolvedValue } catch { $cfg.Resolved = $null }
                }
            }

            return $cfg
        }

        if ($obj.PSObject.Properties.Match('Paths').Count -gt 0) { $cfg.Paths = [PluginsPathsConfig]::FromObject($obj.Paths) }
        if ($obj.PSObject.Properties.Match('Global').Count -gt 0) { $cfg.Global = [PluginsConfig]::UnwrapManifest($obj.Global) }
        if ($obj.PSObject.Properties.Match('Project').Count -gt 0) { $cfg.Project = [PluginsConfig]::UnwrapManifest($obj.Project) }
        if ($obj.PSObject.Properties.Match('Resolved').Count -gt 0) {
            $resolvedValue = $obj.Resolved
            if ($resolvedValue -is [hashtable]) {
                $cfg.Resolved = $resolvedValue
            }
            elseif ($resolvedValue -is [System.Collections.IDictionary]) {
                $ht = @{}
                foreach ($k in $resolvedValue.Keys) { $ht[[string]$k] = $resolvedValue[$k] }
                $cfg.Resolved = $ht
            }
            else {
                try { $cfg.Resolved = [hashtable]$resolvedValue } catch { $cfg.Resolved = $null }
            }
        }

        if ($null -eq $cfg.Paths) {
            $cfg.Paths = [PluginsPathsConfig]::new()
        }

        return $cfg
    }

    [hashtable] ToHashtable() {
        return @{
            Global  = $this.Global
            Project = $this.Project
            Resolved = $this.Resolved
            Paths   = if ($null -ne $this.Paths) { $this.Paths.ToHashtable() } else { $null }
        }
    }
}

class PowerShellModuleRequirement {
    [string]$Name = ''
    [string]$Repository = ''

    PowerShellModuleRequirement() {
    }

    PowerShellModuleRequirement([string]$name, [string]$repository) {
        $this.Name = $name
        $this.Repository = $repository
    }

    static [PowerShellModuleRequirement] FromObject([object]$obj) {
        if ($null -eq $obj) {
            return [PowerShellModuleRequirement]::new()
        }

        if ($obj -is [PowerShellModuleRequirement]) {
            return $obj
        }

        $m = [PowerShellModuleRequirement]::new()

        if ($obj -is [System.Collections.IDictionary]) {
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Name') { $m.Name = [string]$obj['Name'] }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Repository') { $m.Repository = [string]$obj['Repository'] }
            return $m
        }

        if ($obj.PSObject.Properties.Match('Name').Count -gt 0) { $m.Name = [string]$obj.Name }
        if ($obj.PSObject.Properties.Match('Repository').Count -gt 0) { $m.Repository = [string]$obj.Repository }

        return $m
    }

    [hashtable] ToHashtable() {
        return @{ Name = $this.Name; Repository = $this.Repository }
    }
}

class PowerShellRequirementsConfig {
    [version]$VersionMinimum
    [version]$VersionCurrent
    [PowerShellModuleRequirement[]]$Modules

    PowerShellRequirementsConfig() {
        $this.VersionMinimum = $null
        $this.VersionCurrent = $null
        $this.Modules = @()
    }

    static [version] ParseVersion([object]$value) {
        if ($null -eq $value) {
            return $null
        }

        if ($value -is [version]) {
            return $value
        }

        try {
            return [version]([string]$value)
        }
        catch {
            return $null
        }
    }

    static [PowerShellRequirementsConfig] FromObject([object]$obj) {
        if ($null -eq $obj) {
            return [PowerShellRequirementsConfig]::new()
        }

        if ($obj -is [PowerShellRequirementsConfig]) {
            return $obj
        }

        $cfg = [PowerShellRequirementsConfig]::new()

        if ($obj -is [System.Collections.IDictionary]) {
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'VersionMinimum') { $cfg.VersionMinimum = [PowerShellRequirementsConfig]::ParseVersion($obj['VersionMinimum']) }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'VersionCurrent') { $cfg.VersionCurrent = [PowerShellRequirementsConfig]::ParseVersion($obj['VersionCurrent']) }

            if ((_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Modules') -and $null -ne $obj['Modules']) {
                $mods = @()
                foreach ($m in @($obj['Modules'])) {
                    $mods += [PowerShellModuleRequirement]::FromObject($m)
                }
                $cfg.Modules = $mods
            }

            return $cfg
        }

        if ($obj.PSObject.Properties.Match('VersionMinimum').Count -gt 0) { $cfg.VersionMinimum = [PowerShellRequirementsConfig]::ParseVersion($obj.VersionMinimum) }
        if ($obj.PSObject.Properties.Match('VersionCurrent').Count -gt 0) { $cfg.VersionCurrent = [PowerShellRequirementsConfig]::ParseVersion($obj.VersionCurrent) }
        if ($obj.PSObject.Properties.Match('Modules').Count -gt 0 -and $null -ne $obj.Modules) {
            $mods = @()
            foreach ($m in @($obj.Modules)) {
                $mods += [PowerShellModuleRequirement]::FromObject($m)
            }
            $cfg.Modules = $mods
        }

        return $cfg
    }

    [hashtable] ToHashtable() {
        $modulesTable = @()
        foreach ($m in @($this.Modules)) {
            if ($null -eq $m) { continue }
            $modulesTable += $m.ToHashtable()
        }

        return @{
            VersionMinimum = if ($null -ne $this.VersionMinimum) { $this.VersionMinimum.ToString() } else { $null }
            VersionCurrent = if ($null -ne $this.VersionCurrent) { $this.VersionCurrent.ToString() } else { $null }
            Modules        = $modulesTable
        }
    }
}

class RequirementsConfig {
    [PowerShellRequirementsConfig]$PowerShell

    RequirementsConfig() {
        $this.PowerShell = [PowerShellRequirementsConfig]::new()
    }

    static [RequirementsConfig] FromObject([object]$obj) {
        if ($null -eq $obj) {
            return [RequirementsConfig]::new()
        }

        if ($obj -is [RequirementsConfig]) {
            return $obj
        }

        $cfg = [RequirementsConfig]::new()

        if ($obj -is [System.Collections.IDictionary]) {
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'PowerShell') {
                $cfg.PowerShell = [PowerShellRequirementsConfig]::FromObject($obj['PowerShell'])
            }
            return $cfg
        }

        if ($obj.PSObject.Properties.Match('PowerShell').Count -gt 0) {
            $cfg.PowerShell = [PowerShellRequirementsConfig]::FromObject($obj.PowerShell)
        }

        if ($null -eq $cfg.PowerShell) {
            $cfg.PowerShell = [PowerShellRequirementsConfig]::new()
        }

        return $cfg
    }

    [hashtable] ToHashtable() {
        return @{ PowerShell = if ($null -ne $this.PowerShell) { $this.PowerShell.ToHashtable() } else { $null } }
    }
}

class AnsiBasicConfig {
    [string]$Bold = ''
    [string]$Dim = ''
    [string]$Italic = ''
    [string]$Underline = ''
    [string]$Blink = ''
    [string]$Strikethrough = ''

    AnsiBasicConfig() {
    }

    static [AnsiBasicConfig] FromObject([object]$obj) {
        if ($null -eq $obj) {
            return [AnsiBasicConfig]::new()
        }

        if ($obj -is [AnsiBasicConfig]) {
            return $obj
        }

        $cfg = [AnsiBasicConfig]::new()

        if ($obj -is [System.Collections.IDictionary]) {
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Bold') { $cfg.Bold = [string]$obj['Bold'] }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Dim') { $cfg.Dim = [string]$obj['Dim'] }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Italic') { $cfg.Italic = [string]$obj['Italic'] }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Underline') { $cfg.Underline = [string]$obj['Underline'] }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Blink') { $cfg.Blink = [string]$obj['Blink'] }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Strikethrough') { $cfg.Strikethrough = [string]$obj['Strikethrough'] }
            return $cfg
        }

        if ($obj.PSObject.Properties.Match('Bold').Count -gt 0) { $cfg.Bold = [string]$obj.Bold }
        if ($obj.PSObject.Properties.Match('Dim').Count -gt 0) { $cfg.Dim = [string]$obj.Dim }
        if ($obj.PSObject.Properties.Match('Italic').Count -gt 0) { $cfg.Italic = [string]$obj.Italic }
        if ($obj.PSObject.Properties.Match('Underline').Count -gt 0) { $cfg.Underline = [string]$obj.Underline }
        if ($obj.PSObject.Properties.Match('Blink').Count -gt 0) { $cfg.Blink = [string]$obj.Blink }
        if ($obj.PSObject.Properties.Match('Strikethrough').Count -gt 0) { $cfg.Strikethrough = [string]$obj.Strikethrough }

        return $cfg
    }

    [hashtable] ToHashtable() {
        return @{
            Bold = $this.Bold
            Dim = $this.Dim
            Italic = $this.Italic
            Underline = $this.Underline
            Blink = $this.Blink
            Strikethrough = $this.Strikethrough
        }
    }
}

class AnsiConfig {
    [AnsiBasicConfig]$Basic
    [hashtable]$FG
    [hashtable]$BG

    AnsiConfig() {
        $this.Basic = [AnsiBasicConfig]::new()
        $this.FG = @{}
        $this.BG = @{}
    }

    hidden static [hashtable] ToHashtableShallow([object]$value) {
        if ($null -eq $value) {
            return @{}
        }

        if ($value -is [hashtable]) {
            return $value
        }

        if ($value -is [System.Collections.IDictionary]) {
            $ht = @{}
            foreach ($k in $value.Keys) {
                $ht[[string]$k] = $value[$k]
            }
            return $ht
        }

        $ht2 = @{}
        foreach ($p in $value.PSObject.Properties) {
            if ($null -eq $p) { continue }
            $ht2[[string]$p.Name] = $p.Value
        }
        return $ht2
    }

    static [AnsiConfig] FromObject([object]$obj) {
        if ($null -eq $obj) {
            return [AnsiConfig]::new()
        }

        if ($obj -is [AnsiConfig]) {
            return $obj
        }

        $cfg = [AnsiConfig]::new()

        if ($obj -is [System.Collections.IDictionary]) {
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Basic') { $cfg.Basic = [AnsiBasicConfig]::FromObject($obj['Basic']) }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'FG') { $cfg.FG = [AnsiConfig]::ToHashtableShallow($obj['FG']) }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'BG') { $cfg.BG = [AnsiConfig]::ToHashtableShallow($obj['BG']) }
            return $cfg
        }

        if ($obj.PSObject.Properties.Match('Basic').Count -gt 0) { $cfg.Basic = [AnsiBasicConfig]::FromObject($obj.Basic) }
        if ($obj.PSObject.Properties.Match('FG').Count -gt 0) { $cfg.FG = [AnsiConfig]::ToHashtableShallow($obj.FG) }
        if ($obj.PSObject.Properties.Match('BG').Count -gt 0) { $cfg.BG = [AnsiConfig]::ToHashtableShallow($obj.BG) }

        if ($null -eq $cfg.Basic) { $cfg.Basic = [AnsiBasicConfig]::new() }
        if ($null -eq $cfg.FG) { $cfg.FG = @{} }
        if ($null -eq $cfg.BG) { $cfg.BG = @{} }

        return $cfg
    }

    [hashtable] ToHashtable() {
        return @{
            Basic = if ($null -ne $this.Basic) { $this.Basic.ToHashtable() } else { $null }
            FG = $this.FG
            BG = $this.BG
        }
    }
}

class UIConfig {
    [int]$Width = 80
    [AnsiConfig]$ANSI

    UIConfig() {
        $this.Width = 80
        $this.ANSI = [AnsiConfig]::new()
    }

    static [UIConfig] FromObject([object]$obj) {
        if ($null -eq $obj) {
            return [UIConfig]::new()
        }

        if ($obj -is [UIConfig]) {
            return $obj
        }

        $cfg = [UIConfig]::new()

        if ($obj -is [System.Collections.IDictionary]) {
            if ((_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Width') -and $null -ne $obj['Width']) {
                try { $cfg.Width = [int]$obj['Width'] } catch { Write-Verbose "UIConfig.FromObject: Invalid Width value in dictionary: $($_.Exception.Message)" }
            }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'ANSI') {
                $cfg.ANSI = [AnsiConfig]::FromObject($obj['ANSI'])
            }

            if ($null -eq $cfg.ANSI) { $cfg.ANSI = [AnsiConfig]::new() }
            return $cfg
        }

        if ($obj.PSObject.Properties.Match('Width').Count -gt 0 -and $null -ne $obj.Width) {
            try { $cfg.Width = [int]$obj.Width } catch { Write-Verbose "UIConfig.FromObject: Invalid Width property value: $($_.Exception.Message)" }
        }
        if ($obj.PSObject.Properties.Match('ANSI').Count -gt 0) {
            $cfg.ANSI = [AnsiConfig]::FromObject($obj.ANSI)
        }

        if ($null -eq $cfg.ANSI) { $cfg.ANSI = [AnsiConfig]::new() }
        return $cfg
    }

    [hashtable] ToHashtable() {
        return @{
            Width = $this.Width
            ANSI = if ($null -ne $this.ANSI) { $this.ANSI.ToHashtable() } else { $null }
        }
    }
}

class ProjectsConfig {
    [ProjectCurrentConfig]$Current
    [ProjectsPathsConfig]$Paths
    [ProjectsPortRegistry]$PortRegistry
    [object]$Registry

    ProjectsConfig() {
        $this.Current = [ProjectCurrentConfig]::new()
        $this.Paths = [ProjectsPathsConfig]::new()
        $this.PortRegistry = [ProjectsPortRegistry]::new()
        $this.Registry = $null
    }

    hidden static [object] NormalizeRegistry([object]$value) {
        if ($null -eq $value) {
            return $null
        }

        $registryType = 'ProjectsRegistryCache' -as [type]
        if ($null -ne $registryType) {
            try {
                return $registryType::FromObject($value)
            }
            catch {
                return $value
            }
        }

        return $value
    }

    static [ProjectsConfig] FromObject([object]$obj) {
        if ($null -eq $obj) {
            return [ProjectsConfig]::new()
        }

        if ($obj -is [ProjectsConfig]) {
            return $obj
        }

        $cfg = [ProjectsConfig]::new()

        if ($obj -is [System.Collections.IDictionary]) {
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Current') { $cfg.Current = [ProjectCurrentConfig]::FromObject($obj['Current']) }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Paths') { $cfg.Paths = [ProjectsPathsConfig]::FromObject($obj['Paths']) }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'PortRegistry') { $cfg.PortRegistry = [ProjectsPortRegistry]::FromObject($obj['PortRegistry']) }
            if (_PSmm_DictionaryHasKey -Dictionary $obj -Key 'Registry') { $cfg.Registry = [ProjectsConfig]::NormalizeRegistry($obj['Registry']) }

            if ($null -eq $cfg.Current) { $cfg.Current = [ProjectCurrentConfig]::new() }
            if ($null -eq $cfg.Paths) { $cfg.Paths = [ProjectsPathsConfig]::new() }
            if ($null -eq $cfg.PortRegistry) { $cfg.PortRegistry = [ProjectsPortRegistry]::new() }

            return $cfg
        }

        if ($obj.PSObject.Properties.Match('Current').Count -gt 0) { $cfg.Current = [ProjectCurrentConfig]::FromObject($obj.Current) }
        if ($obj.PSObject.Properties.Match('Paths').Count -gt 0) { $cfg.Paths = [ProjectsPathsConfig]::FromObject($obj.Paths) }
        if ($obj.PSObject.Properties.Match('PortRegistry').Count -gt 0) { $cfg.PortRegistry = [ProjectsPortRegistry]::FromObject($obj.PortRegistry) }
        if ($obj.PSObject.Properties.Match('Registry').Count -gt 0) { $cfg.Registry = [ProjectsConfig]::NormalizeRegistry($obj.Registry) }

        if ($null -eq $cfg.Current) { $cfg.Current = [ProjectCurrentConfig]::new() }
        if ($null -eq $cfg.Paths) { $cfg.Paths = [ProjectsPathsConfig]::new() }
        if ($null -eq $cfg.PortRegistry) { $cfg.PortRegistry = [ProjectsPortRegistry]::new() }

        return $cfg
    }

    hidden static [object] ToHashtableMaybe([object]$value) {
        if ($null -eq $value) {
            return $null
        }

        try {
            $m = $value.GetType().GetMethod('ToHashtable')
            if ($null -ne $m) {
                return $value.ToHashtable()
            }
        }
        catch {
            Write-Verbose "ProjectsConfig.ToHashtableMaybe: ToHashtable() reflection/invocation failed: $($_.Exception.Message)"
        }

        return $value
    }

    [hashtable] ToHashtable() {
        return @{
            Current = if ($null -ne $this.Current) { $this.Current.ToHashtable() } else { $null }
            Paths = if ($null -ne $this.Paths) { $this.Paths.ToHashtable() } else { $null }
            PortRegistry = if ($null -ne $this.PortRegistry) { $this.PortRegistry.ToHashtable() } else { $null }
            Registry = [ProjectsConfig]::ToHashtableMaybe($this.Registry)
        }
    }
}

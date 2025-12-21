#Requires -Version 7.5.4
Set-StrictMode -Version Latest

if (-not (Get-Command -Name 'Get-PSmmProjectsConfigMemberValue' -ErrorAction SilentlyContinue)) {
    $helpersPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Private\ConfigMemberAccessHelpers.ps1'
    if (Test-Path -Path $helpersPath) {
        . $helpersPath
    }
}

class ProjectsDriveRegistryEntry {
    [string]$BackupId
    [string]$Drive
    [string]$DriveType
    [string]$FileSystem
    [double]$FreeSpace
    [string]$HealthStatus
    [string]$Label
    [string]$Manufacturer
    [string]$Model
    [string]$Name
    [string]$PartitionKind
    [string]$Path
    [string]$SerialNumber
    [string]$StorageGroup
    [double]$TotalSpace
    [double]$UsedSpace

    [System.Management.Automation.HiddenAttribute()]
    [object[]]$Projects

    ProjectsDriveRegistryEntry() {
        $this.BackupId = ''
        $this.Drive = ''
        $this.DriveType = ''
        $this.FileSystem = ''
        $this.FreeSpace = 0
        $this.HealthStatus = 'Unknown'
        $this.Label = ''
        $this.Manufacturer = ''
        $this.Model = ''
        $this.Name = ''
        $this.PartitionKind = ''
        $this.Path = ''
        $this.SerialNumber = ''
        $this.StorageGroup = ''
        $this.TotalSpace = 0
        $this.UsedSpace = 0
        $this.Projects = @()
    }

    static [ProjectsDriveRegistryEntry] FromObject([object]$obj) {
        $e = [ProjectsDriveRegistryEntry]::new()
        if ($null -eq $obj) { return $e }

        if ($obj -is [hashtable]) {
            foreach ($k in $obj.Keys) {
                if ($k -isnot [string]) { continue }
                $prop = $k
                if ($prop -eq 'Projects') {
                    $val = $obj[$prop]
                    $e.Projects = if ($null -eq $val) { @() } elseif ($val -is [System.Collections.IEnumerable] -and $val -isnot [string]) { @($val) } else { @($val) }
                    continue
                }
                try { $e.$prop = $obj[$prop] }
                catch {
                    Write-Verbose "ProjectsDriveRegistryEntry.FromObject: failed setting '$prop': $($_.Exception.Message)"
                }
            }
            return $e
        }

        $memberNames = @(
            $obj |
                Get-Member -MemberType NoteProperty, Property -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty Name
        )

        foreach ($memberName in $memberNames) {
            if ([string]::IsNullOrWhiteSpace([string]$memberName)) { continue }

            if ($memberName -eq 'Projects') {
                $val = Get-PSmmProjectsConfigMemberValue -Object $obj -Name $memberName
                $e.Projects = if ($null -eq $val) { @() } elseif ($val -is [System.Collections.IEnumerable] -and $val -isnot [string]) { @($val) } else { @($val) }
                continue
            }

            try {
                $e.$memberName = Get-PSmmProjectsConfigMemberValue -Object $obj -Name $memberName
            }
            catch {
                Write-Verbose "ProjectsDriveRegistryEntry.FromObject: failed setting '$memberName': $($_.Exception.Message)"
            }
        }

        return $e
    }

    static [ProjectsDriveRegistryEntry] FromProjectSample([object]$firstProject, [object[]]$projects) {
        $e = [ProjectsDriveRegistryEntry]::new()
        if ($null -eq $firstProject) {
            $e.Projects = if ($null -eq $projects) { @() } else { @($projects) }
            return $e
        }

        foreach ($name in @(
                'BackupId','Drive','DriveType','FileSystem','FreeSpace','HealthStatus','Label','Manufacturer','Model','Name',
                'PartitionKind','Path','SerialNumber','StorageGroup','TotalSpace','UsedSpace'
            )) {
            try {
                $val = Get-PSmmProjectsConfigMemberValue -Object $firstProject -Name $name
                if ($null -ne $val) { $e.$name = $val }
            }
            catch {
                Write-Verbose "ProjectsDriveRegistryEntry.FromProjectSample: failed setting '$name': $($_.Exception.Message)"
            }
        }

        if ([string]::IsNullOrWhiteSpace($e.Label)) {
            try {
                $labelVal = Get-PSmmProjectsConfigMemberValue -Object $firstProject -Name 'Label'
                if ($null -eq $labelVal) { $e.Label = '' }
            }
            catch {
                $e.Label = ''
            }
        }

        $e.Projects = if ($null -eq $projects) { @() } else { @($projects) }
        return $e
    }
}

class ProjectsRegistryCache {
    [hashtable]$Master
    [hashtable]$Backup
    [datetime]$LastScanned
    [hashtable]$ProjectDirs

    ProjectsRegistryCache() {
        $this.Master = @{}
        $this.Backup = @{}
        $this.LastScanned = [datetime]::MinValue
        $this.ProjectDirs = @{}
    }

    static [ProjectsRegistryCache] FromObject([object]$obj) {
        if ($null -eq $obj) { return [ProjectsRegistryCache]::new() }
        if ($obj -is [ProjectsRegistryCache]) { return $obj }

        $cache = [ProjectsRegistryCache]::new()

        $masterObj = $null
        $backupObj = $null
        $lastScannedObj = $null
        $projectDirsObj = $null

        if ($obj -is [hashtable]) {
            $masterObj = $obj['Master']
            $backupObj = $obj['Backup']
            $lastScannedObj = $obj['LastScanned']
            $projectDirsObj = $obj['ProjectDirs']
        }
        else {
            if (Get-Command -Name Test-PSmmProjectsConfigMember -ErrorAction SilentlyContinue) {
                if (Test-PSmmProjectsConfigMember -Object $obj -Name 'Master') { $masterObj = Get-PSmmProjectsConfigMemberValue -Object $obj -Name 'Master' }
                if (Test-PSmmProjectsConfigMember -Object $obj -Name 'Backup') { $backupObj = Get-PSmmProjectsConfigMemberValue -Object $obj -Name 'Backup' }
                if (Test-PSmmProjectsConfigMember -Object $obj -Name 'LastScanned') { $lastScannedObj = Get-PSmmProjectsConfigMemberValue -Object $obj -Name 'LastScanned' }
                if (Test-PSmmProjectsConfigMember -Object $obj -Name 'ProjectDirs') { $projectDirsObj = Get-PSmmProjectsConfigMemberValue -Object $obj -Name 'ProjectDirs' }
            }
            else {
                $masterObj = Get-PSmmProjectsConfigMemberValue -Object $obj -Name 'Master'
                $backupObj = Get-PSmmProjectsConfigMemberValue -Object $obj -Name 'Backup'
                $lastScannedObj = Get-PSmmProjectsConfigMemberValue -Object $obj -Name 'LastScanned'
                $projectDirsObj = Get-PSmmProjectsConfigMemberValue -Object $obj -Name 'ProjectDirs'
            }
        }

        if ($lastScannedObj -is [datetime]) { $cache.LastScanned = $lastScannedObj }

        foreach ($side in @(
                @{ Name = 'Master'; Target = $cache.Master; Source = $masterObj },
                @{ Name = 'Backup'; Target = $cache.Backup; Source = $backupObj }
            )) {
            $src = $side.Source
            $dst = $side.Target
            if ($null -eq $src) { continue }

            if ($src -is [System.Collections.IDictionary]) {
                foreach ($k in $src.Keys) {
                    $dst[[string]$k] = [ProjectsDriveRegistryEntry]::FromObject($src[$k])
                }
            }
            else {
                # Object with properties
                $memberNames = @(
                    $src |
                        Get-Member -MemberType NoteProperty, Property -ErrorAction SilentlyContinue |
                        Select-Object -ExpandProperty Name
                )
                foreach ($memberName in $memberNames) {
                    if ([string]::IsNullOrWhiteSpace([string]$memberName)) { continue }
                    $dst[[string]$memberName] = [ProjectsDriveRegistryEntry]::FromObject(
                        (Get-PSmmProjectsConfigMemberValue -Object $src -Name ([string]$memberName))
                    )
                }
            }
        }

        if ($null -ne $projectDirsObj) {
            if ($projectDirsObj -is [System.Collections.IDictionary]) {
                foreach ($k in $projectDirsObj.Keys) {
                    $val = $projectDirsObj[$k]
                    if ($val -is [datetime]) { $cache.ProjectDirs[[string]$k] = $val }
                }
            }
            else {
                $memberNames = @(
                    $projectDirsObj |
                        Get-Member -MemberType NoteProperty, Property -ErrorAction SilentlyContinue |
                        Select-Object -ExpandProperty Name
                )
                foreach ($memberName in $memberNames) {
                    if ([string]::IsNullOrWhiteSpace([string]$memberName)) { continue }
                    $val = Get-PSmmProjectsConfigMemberValue -Object $projectDirsObj -Name ([string]$memberName)
                    if ($val -is [datetime]) { $cache.ProjectDirs[[string]$memberName] = $val }
                }
            }
        }

        return $cache
    }

    [hashtable] ConvertProjectDirs([object]$dirs) {
        $out = @{}
        if ($null -eq $dirs) { return $out }

        if ($dirs -is [hashtable]) { return $dirs }

        if ($dirs -is [System.Collections.IDictionary]) {
            foreach ($k in $dirs.Keys) {
                $val = $dirs[$k]
                if ($val -is [datetime]) { $out[[string]$k] = $val }
            }
            return $out
        }

        $memberNames = @(
            $dirs |
                Get-Member -MemberType NoteProperty, Property -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty Name
        )

        foreach ($memberName in $memberNames) {
            if ([string]::IsNullOrWhiteSpace([string]$memberName)) { continue }
            $val = Get-PSmmProjectsConfigMemberValue -Object $dirs -Name ([string]$memberName)
            if ($val -is [datetime]) { $out[[string]$memberName] = $val }
        }

        return $out
    }
}

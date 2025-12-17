#Requires -Version 7.5.4
Set-StrictMode -Version Latest

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
                if ($e.PSObject.Properties.Match($prop).Count -gt 0) {
                    try { $e.$prop = $obj[$prop] } catch { }
                }
            }
            return $e
        }

        foreach ($p in $obj.PSObject.Properties) {
            if ($p.Name -eq 'Projects') {
                $val = $p.Value
                $e.Projects = if ($null -eq $val) { @() } elseif ($val -is [System.Collections.IEnumerable] -and $val -isnot [string]) { @($val) } else { @($val) }
                continue
            }

            if ($e.PSObject.Properties.Match($p.Name).Count -gt 0) {
                try { $e.$($p.Name) = $p.Value } catch { }
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
            if ($firstProject.PSObject.Properties.Match($name).Count -gt 0) {
                try { $e.$name = $firstProject.$name } catch { }
            }
        }

        if ([string]::IsNullOrWhiteSpace($e.Label) -and $firstProject.PSObject.Properties.Match('Label').Count -eq 0) {
            $e.Label = ''
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
            $p = $obj.PSObject.Properties['Master']
            if ($null -ne $p) { $masterObj = $p.Value }

            $p = $obj.PSObject.Properties['Backup']
            if ($null -ne $p) { $backupObj = $p.Value }

            $p = $obj.PSObject.Properties['LastScanned']
            if ($null -ne $p) { $lastScannedObj = $p.Value }

            $p = $obj.PSObject.Properties['ProjectDirs']
            if ($null -ne $p) { $projectDirsObj = $p.Value }
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
                foreach ($p in $src.PSObject.Properties) {
                    $dst[$p.Name] = [ProjectsDriveRegistryEntry]::FromObject($p.Value)
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
                foreach ($p in $projectDirsObj.PSObject.Properties) {
                    if ($p.Value -is [datetime]) { $cache.ProjectDirs[[string]$p.Name] = $p.Value }
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

        foreach ($p in $dirs.PSObject.Properties) {
            if ($p.Value -is [datetime]) { $out[[string]$p.Name] = $p.Value }
        }

        return $out
    }
}

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

class ProjectStorageDriveInfo {
    [string]$Label = ''
    [string]$DriveLetter = ''
    [string]$SerialNumber = ''
    [string]$DriveLabel = ''

    ProjectStorageDriveInfo() {
    }

    ProjectStorageDriveInfo(
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

    [hashtable] ToHashtable() {
        return @{
            Label        = $this.Label
            DriveLetter  = $this.DriveLetter
            SerialNumber = $this.SerialNumber
            DriveLabel   = $this.DriveLabel
        }
    }
}

class ProjectCurrentSelection {
    [string]$Name = ''
    [string]$Path = ''
    [string]$Config = ''
    [string]$Backup = ''
    [string]$Databases = ''
    [string]$Documents = ''
    [string]$Libraries = ''
    [string]$Vault = ''
    [string]$Log = ''
    [ProjectStorageDriveInfo]$StorageDrive

    ProjectCurrentSelection() {
        $this.StorageDrive = [ProjectStorageDriveInfo]::new()
    }

    [hashtable] ToHashtable() {
        return @{
            Name        = $this.Name
            Path        = $this.Path
            Config      = $this.Config
            Backup      = $this.Backup
            Databases   = $this.Databases
            Documents   = $this.Documents
            Libraries   = $this.Libraries
            Vault       = $this.Vault
            Log         = $this.Log
            StorageDrive = if ($null -ne $this.StorageDrive) { $this.StorageDrive.ToHashtable() } else { $null }
        }
    }
}

class ProjectSelectionProjectsContext {
    [ProjectCurrentSelection]$Current
    [hashtable]$Paths
    [object]$Registry

    ProjectSelectionProjectsContext() {
        $this.Current = [ProjectCurrentSelection]::new()
        $this.Paths = @{}
        $this.Registry = $null
    }

    ProjectSelectionProjectsContext([hashtable]$paths, [object]$registry) {
        $this.Current = [ProjectCurrentSelection]::new()
        $this.Paths = if ($null -eq $paths) { @{} } else { $paths }
        $this.Registry = $registry
    }
}

class ProjectSelectionContext {
    [ProjectSelectionProjectsContext]$Projects

    ProjectSelectionContext() {
        $this.Projects = [ProjectSelectionProjectsContext]::new()
    }

    ProjectSelectionContext([hashtable]$projectPaths, [object]$registry) {
        $this.Projects = [ProjectSelectionProjectsContext]::new($projectPaths, $registry)
    }
}

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
$importClassesScript = Join-Path -Path $repoRoot -ChildPath 'tests/Support/Import-PSmmClasses.ps1'
$projectsManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Projects/PSmm.Projects.psd1'
$psmmManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
# `Write-PSmmLog` should be mocked in test scopes or provided by the logging module.

Describe 'Get-PSmmProjects' {
    function script:New-MockDrive {
        param([Parameter(Mandatory)][ValidatePattern('^[A-Za-z]$')]$DriveLetter)

        if (Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue) {
            return
        }

        $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("psmm-mockdrive-{0}-{1}" -f $DriveLetter, ([guid]::NewGuid().ToString('N')))
        if (-not (Test-Path -Path $tempRoot)) {
            $null = New-Item -Path $tempRoot -ItemType Directory -Force
        }

        New-PSDrive -Name $DriveLetter -PSProvider FileSystem -Root $tempRoot -Scope Global | Out-Null
        $script:MockDriveMappings += [pscustomobject]@{ Name = $DriveLetter; Root = $tempRoot }
    }

    BeforeAll {
        $repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $importClassesScript = Join-Path -Path $repoRoot -ChildPath 'tests/Support/Import-PSmmClasses.ps1'
        $projectsManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Projects/PSmm.Projects.psd1'
        $psmmManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'

        if (-not (Test-Path -Path 'variable:script:TestStorageDrives')) {
            $script:TestStorageDrives = @()
        }
        if (-not (Test-Path -Path 'variable:script:MockDriveMappings')) {
            $script:MockDriveMappings = @()
        }
        if (-not (Test-Path -Path 'variable:script:previousTestMode')) {
            $script:previousTestMode = $null
        }

        foreach ($letter in @('X','Y','Z')) {
            New-MockDrive -DriveLetter $letter
        }

        . (Join-Path -Path $repoRoot -ChildPath 'tests/Support/TestFileSystemService.ps1')
        . (Join-Path -Path $repoRoot -ChildPath 'tests/Support/TestConfig.ps1')

        & $importClassesScript -RepositoryRoot $repoRoot

        $script:previousTestMode = $env:MEDIA_MANAGER_TEST_MODE
        $env:MEDIA_MANAGER_TEST_MODE = '1'

        if (Get-Module -Name 'PSmm' -ErrorAction SilentlyContinue) {
            Remove-Module -Name 'PSmm' -Force
        }
        Import-Module -Name $psmmManifest -Force -ErrorAction Stop

        if (Get-Module -Name 'PSmm.Projects' -ErrorAction SilentlyContinue) {
            Remove-Module -Name 'PSmm.Projects' -Force
        }
        Import-Module -Name $projectsManifest -Force -ErrorAction Stop
    }

    AfterAll {
        $hasPreviousTestMode = Test-Path -Path 'variable:script:previousTestMode'
        if ($hasPreviousTestMode -and $null -ne $script:previousTestMode) {
            $env:MEDIA_MANAGER_TEST_MODE = $script:previousTestMode
        }
        else {
            Remove-Item Env:MEDIA_MANAGER_TEST_MODE -ErrorAction SilentlyContinue
        }

        if (Test-Path -Path 'variable:script:MockDriveMappings') {
            foreach ($mapping in $script:MockDriveMappings) {
                Remove-PSDrive -Name $mapping.Name -Scope Global -Force -ErrorAction SilentlyContinue
                if (Test-Path -Path $mapping.Root) {
                    Remove-Item -Path $mapping.Root -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            $script:MockDriveMappings = @()
        }

        # Clean up modules after test to avoid state pollution for next test file
        if (Get-Module -Name 'PSmm.Projects' -ErrorAction SilentlyContinue) { Remove-Module -Name 'PSmm.Projects' -Force }
        if (Get-Module -Name 'PSmm' -ErrorAction SilentlyContinue) { Remove-Module -Name 'PSmm' -Force }
    }

    BeforeEach {
        Mock -CommandName Write-PSmmLog -ModuleName 'PSmm.Projects' -MockWith { }
        Mock -CommandName Test-DriveRootPath -ModuleName 'PSmm.Projects' -MockWith { $true }

        $script:TestStorageDrives = @()
        $storageDriveMock = { $script:TestStorageDrives }
        foreach ($moduleName in @('PSmm', 'PSmm.Projects')) {
            if (Get-Module -Name $moduleName -ErrorAction SilentlyContinue) {
                Mock -CommandName Get-StorageDrive -ModuleName $moduleName -MockWith $storageDriveMock
            }
        }
    }

    It 'discovers projects from master and backup drives using fake file system' {
        $config = New-TestAppConfiguration -InitializeProjectsPaths
        $config.Projects.Registry = @{
            Master = @{}
            Backup = @{}
            LastScanned = [datetime]::MinValue
            ProjectDirs = @{}
        }

        $master = New-TestStorageDrive -Label 'Master-X' -DriveLetter 'X:\' -SerialNumber 'MASTER-001'
        $backup = New-TestStorageDrive -Label 'Backup-X' -DriveLetter 'Y:\' -SerialNumber 'BACKUP-001'
        Add-TestStorageGroup -Config $config -GroupId '1' -Master $master -Backups (@{ '1' = $backup }) | Out-Null

        $fs = [TestFileSystemService]::new(@(
            'X:\',
            'X:\Projects',
            'X:\Projects\ProjectAlpha',
            'X:\Projects\_GLOBAL_',
            'X:\Projects\_GLOBAL_\Libraries',
            'X:\Projects\_GLOBAL_\Libraries\Assets',
            'Y:\',
            'Y:\Projects',
            'Y:\Projects\ProjectArchive'
        ))

        $pathStatus = [System.Collections.Generic.Dictionary[string, bool]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $fs.Entries.Values) {
            $null = $pathStatus[$entry.FullName] = $true
        }
        $pathStatus['X:\'] = $true
        $pathStatus['Y:\'] = $true

        Mock -CommandName Test-Path -ModuleName 'PSmm.Projects' -MockWith {
            param(
                [string]$Path,
                [string]$LiteralPath,
                [System.Management.Automation.SwitchParameter]$IsValid
            )
            $target = if ($PSBoundParameters.ContainsKey('LiteralPath')) { $LiteralPath } else { $Path }
            return $pathStatus.ContainsKey($target)
        }

        $script:TestStorageDrives = @(
            [pscustomobject]@{
                SerialNumber = 'MASTER-001'
                Manufacturer = 'TestCo'
                Model = 'FastDisk'
                FileSystem = 'NTFS'
                PartitionKind = 'GPT'
                TotalSpace = 1024
                FreeSpace = 512
                UsedSpace = 512
                HealthStatus = 'Healthy'
                DriveLetter = 'X:\'
            },
            [pscustomobject]@{
                SerialNumber = 'BACKUP-001'
                Manufacturer = 'TestCo'
                Model = 'ColdStore'
                FileSystem = 'NTFS'
                PartitionKind = 'GPT'
                TotalSpace = 2048
                FreeSpace = 1024
                UsedSpace = 1024
                HealthStatus = 'Healthy'
                DriveLetter = 'Y:\'
            }
        )

        $result = Get-PSmmProjects -Config $config -FileSystem $fs -Force

        $result.Master.ContainsKey('Master-X') | Should -BeTrue
        $result.Master['Master-X'].Count | Should -Be 1
        $result.Master['Master-X'][0].Name | Should -Be 'ProjectAlpha'
        $result.Master['Master-X'][0].DriveType | Should -Be 'Master'

        $result.Backup.ContainsKey('Backup-X') | Should -BeTrue
        $result.Backup['Backup-X'].Count | Should -Be 1
        $result.Backup['Backup-X'][0].Name | Should -Be 'ProjectArchive'
        $result.Backup['Backup-X'][0].BackupId | Should -Be '1'
    }

    It 'creates placeholder projects when Projects folder is missing' {
        $config = New-TestAppConfiguration -InitializeProjectsPaths
        $config.Projects.Registry = @{
            Master = @{}
            Backup = @{}
            LastScanned = [datetime]::MinValue
            ProjectDirs = @{}
        }

        $master = New-TestStorageDrive -Label 'Master-Y' -DriveLetter 'Z:\' -SerialNumber 'MASTER-009'
        Add-TestStorageGroup -Config $config -GroupId '2' -Master $master -Backups $null | Out-Null

        $fs = [TestFileSystemService]::new(@('Z:\'))
        $pathStatus = [System.Collections.Generic.Dictionary[string, bool]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $pathStatus['Z:\'] = $true
        $pathStatus['Z:\Projects'] = $false

        Mock -CommandName Test-Path -ModuleName 'PSmm.Projects' -MockWith {
            param([string]$Path, [string]$LiteralPath)
            $target = if ($PSBoundParameters.ContainsKey('LiteralPath')) { $LiteralPath } else { $Path }
            if ($pathStatus.ContainsKey($target)) {
                return $pathStatus[$target]
            }
            return $false
        }

        $script:TestStorageDrives = @([pscustomobject]@{
            SerialNumber = 'MASTER-009'
            Manufacturer = 'TestCo'
            Model = 'EdgeDisk'
            FileSystem = 'NTFS'
            PartitionKind = 'GPT'
            TotalSpace = 512
            FreeSpace = 400
            UsedSpace = 112
            HealthStatus = 'Healthy'
            DriveLetter = 'Z:\'
        })

        $result = Get-PSmmProjects -Config $config -FileSystem $fs -Force

        $result.Master.ContainsKey('Master-Y') | Should -BeTrue
        $result.Master['Master-Y'].Count | Should -Be 1
        $result.Master['Master-Y'][0].Name | Should -BeNullOrEmpty
        $result.Master['Master-Y'][0].Drive | Should -Be 'Z:\'
    }

    It 'returns cached registry data when project directories are unchanged' {
        $config = New-TestAppConfiguration -InitializeProjectsPaths
        $masterDrive = New-TestStorageDrive -Label 'Master-X' -DriveLetter 'X:\' -SerialNumber 'MASTER-001'
        $backupDrive = New-TestStorageDrive -Label 'Backup-Y' -DriveLetter 'Y:\' -SerialNumber 'BACKUP-001'
        Add-TestStorageGroup -Config $config -GroupId '1' -Master $masterDrive -Backups (@{ '1' = $backupDrive }) | Out-Null

        $masterWriteTime = [datetime]::UtcNow.AddMinutes(-10)
        $backupWriteTime = [datetime]::UtcNow.AddMinutes(-9)

        $cachedMasterProjects = @(
            [pscustomobject]@{
                Name = 'CachedAlpha'
                Path = 'X:\Projects\CachedAlpha'
                Drive = 'X:\'
                Label = 'Master-X'
                SerialNumber = 'MASTER-001'
                StorageGroup = '1'
                DriveType = 'Master'
                BackupId = ''
            }
        )
        $cachedBackupProjects = @(
            [pscustomobject]@{
                Name = 'CachedBeta'
                Path = 'Y:\Projects\CachedBeta'
                Drive = 'Y:\'
                Label = 'Backup-Y'
                SerialNumber = 'BACKUP-001'
                StorageGroup = '1'
                DriveType = 'Backup'
                BackupId = '1'
            }
        )

        $config.Projects.Registry = @{
            Master = @{
                'Master-X' = @{
                    Drive = 'X:\'
                    Label = 'Master-X'
                    DriveType = 'Master'
                    Projects = $cachedMasterProjects
                }
            }
            Backup = @{
                'Backup-Y' = @{
                    Drive = 'Y:\'
                    Label = 'Backup-Y'
                    DriveType = 'Backup'
                    BackupId = '1'
                    Projects = $cachedBackupProjects
                }
            }
            LastScanned = [datetime]::UtcNow.AddMinutes(-5)
            ProjectDirs = @{
                'MASTER-001_Projects' = $masterWriteTime
                'BACKUP-001_Projects' = $backupWriteTime
            }
        }

        $fs = [TestFileSystemService]::new(@('X:\Projects', 'Y:\Projects'))
        $fs.SetLastWriteTime('X:\Projects', $masterWriteTime)
        $fs.SetLastWriteTime('Y:\Projects', $backupWriteTime)

        Mock -CommandName Get-ProjectsFromDrive -ModuleName 'PSmm.Projects' -MockWith {
            @{ Projects = $Projects; ProjectDirs = $ProjectDirs }
        }

        $result = Get-PSmmProjects -Config $config -FileSystem $fs

        Assert-MockCalled -CommandName Get-ProjectsFromDrive -ModuleName 'PSmm.Projects' -Times 0
        $result.Master['Master-X'].Count | Should -Be 1
        $result.Master['Master-X'][0].Name | Should -Be 'CachedAlpha'
        $result.Backup['Backup-Y'].Count | Should -Be 1
        $result.Backup['Backup-Y'][0].Name | Should -Be 'CachedBeta'
    }

    It 'invalidates cache and rescans when Projects directory modified' {
        $config = New-TestAppConfiguration -InitializeProjectsPaths
        $masterDrive = New-TestStorageDrive -Label 'Master-X' -DriveLetter 'X:\' -SerialNumber 'MASTER-001'
        $backupDrive = New-TestStorageDrive -Label 'Backup-Y' -DriveLetter 'Y:\' -SerialNumber 'BACKUP-001'
        Add-TestStorageGroup -Config $config -GroupId '1' -Master $masterDrive -Backups (@{ '1' = $backupDrive }) | Out-Null

        $oldMaster = [datetime]::UtcNow.AddMinutes(-10)
        $oldBackup = [datetime]::UtcNow.AddMinutes(-9)
        $newMaster = $oldMaster.AddMinutes(9) # newer than cached
        $newBackup = $oldBackup.AddMinutes(8) # newer than cached

        $config.Projects.Registry = @{
            Master = @{}
            Backup = @{}
            LastScanned = [datetime]::UtcNow.AddMinutes(-5)
            ProjectDirs = @{
                'MASTER-001_Projects' = $oldMaster
                'BACKUP-001_Projects' = $oldBackup
            }
        }

        $fs = New-TestFileSystemService -Directories @('X:\Projects','Y:\Projects') -LastWriteTimes @{
            'X:\Projects' = $newMaster
            'Y:\Projects' = $newBackup
        }

        Mock -CommandName Get-ProjectsFromDrive -ModuleName 'PSmm.Projects' -MockWith {
            param($Disk,$StorageGroup,$BackupId,$DriveType,[hashtable]$Projects,[hashtable]$ProjectDirs,[object]$Config,$FileSystem)
            return @{ Projects = $Projects; ProjectDirs = $ProjectDirs }
        }
        Mock -CommandName Write-PSmmLog -ModuleName 'PSmm.Projects' -MockWith { param($Level,$Message,$Context) }

        $result = Get-PSmmProjects -Config $config -FileSystem $fs

        Assert-MockCalled -CommandName Get-ProjectsFromDrive -ModuleName 'PSmm.Projects' -Times 2
        Assert-MockCalled -CommandName Write-PSmmLog -ModuleName 'PSmm.Projects' -Times 1 -ParameterFilter {
            $Context -eq 'Get-PSmmProjects' -and $Message -like '*invalidating registry cache*'
        }
    }

    It 'creates Projects folder on Backup when missing and logs success' {
        $config = New-TestAppConfiguration -InitializeProjectsPaths
        $config.Projects.Registry = @{
            Master = @{}
            Backup = @{}
            LastScanned = [datetime]::MinValue
            ProjectDirs = @{}
        }

        $master = New-TestStorageDrive -Label 'Master-X' -DriveLetter 'X:\' -SerialNumber 'MASTER-123'
        $backup = New-TestStorageDrive -Label 'Backup-Z' -DriveLetter 'Y:\' -SerialNumber 'BACKUP-999'
        Add-TestStorageGroup -Config $config -GroupId '9' -Master $master -Backups (@{ '1' = $backup }) | Out-Null

        # Seed drive roots only; omit Y:\Projects to force creation path on backup
        $fs = [TestFileSystemService]::new(@('X:\','Y:\'))

        Mock -CommandName Write-PSmmLog -ModuleName 'PSmm.Projects' -MockWith { param($Level,$Message,$Context) }

        $result = Get-PSmmProjects -Config $config -FileSystem $fs -Force

        # Verify Projects folder created on backup via FileSystem state and success log
        $fs.TestPath('Y:\Projects') | Should -BeTrue
        Assert-MockCalled -CommandName Write-PSmmLog -ModuleName 'PSmm.Projects' -Times 1 -ParameterFilter {
            $Context -eq 'Get-ProjectsFromDrive' -and $Level -eq 'SUCCESS' -and $Message -like '*Created Projects folder on Backup drive*'
        }
    }

    It 'skips drives that fail Test-DriveRootPath outside of test mode' {
        $config = New-TestAppConfiguration -InitializeProjectsPaths
        $config.Projects.Registry = @{
            Master = @{}
            Backup = @{}
            LastScanned = [datetime]::MinValue
            ProjectDirs = @{}
        }

        $master = New-TestStorageDrive -Label 'Master-Z' -DriveLetter 'X:\' -SerialNumber 'MASTER-777'
        Add-TestStorageGroup -Config $config -GroupId '5' -Master $master -Backups $null | Out-Null

        $fs = [TestFileSystemService]::new(@('X:\', 'X:\Projects'))
        $script:TestStorageDrives = @([pscustomobject]@{
            SerialNumber = 'MASTER-777'
            Manufacturer = 'TestCo'
            Model = 'OfflineDisk'
            FileSystem = 'NTFS'
            PartitionKind = 'GPT'
            TotalSpace = 100
            FreeSpace = 50
            UsedSpace = 50
            HealthStatus = 'Unknown'
            DriveLetter = 'X:\'
        })

        $previousMode = $env:MEDIA_MANAGER_TEST_MODE
        Mock -CommandName Test-DriveRootPath -ModuleName 'PSmm.Projects' -MockWith { $false }

        try {
            $env:MEDIA_MANAGER_TEST_MODE = '0'

            $result = Get-PSmmProjects -Config $config -FileSystem $fs -Force

            ($result.Master.Keys).Count | Should -Be 0
            Assert-MockCalled -CommandName Write-PSmmLog -ModuleName 'PSmm.Projects' -Times 1 -ParameterFilter { $Level -eq 'WARNING' -and $Context -eq 'Get-ProjectsFromDrive' }
        }
        finally {
            $env:MEDIA_MANAGER_TEST_MODE = $previousMode
        }
    }

    It "adds a placeholder when only _GLOBAL_ exists" {
        $config = New-TestAppConfiguration -InitializeProjectsPaths
        $config.Projects.Registry = @{
            Master = @{}
            Backup = @{}
            LastScanned = [datetime]::MinValue
            ProjectDirs = @{}
        }

        $master = New-TestStorageDrive -Label 'Master-X' -DriveLetter 'X:\' -SerialNumber 'MASTER-123'
        Add-TestStorageGroup -Config $config -GroupId '3' -Master $master -Backups $null | Out-Null

        $fs = [TestFileSystemService]::new(@(
            'X:\',
            'X:\Projects',
            'X:\Projects\_GLOBAL_',
            'X:\Projects\_GLOBAL_\Libraries',
            'X:\Projects\_GLOBAL_\Libraries\Assets'
        ))

        $script:TestStorageDrives = @([pscustomobject]@{
            SerialNumber = 'MASTER-123'
            Manufacturer = 'TestCo'
            Model = 'SilentDisk'
            FileSystem = 'NTFS'
            PartitionKind = 'GPT'
            TotalSpace = 256
            FreeSpace = 128
            UsedSpace = 128
            HealthStatus = 'Healthy'
            DriveLetter = 'X:\'
        })

        $result = Get-PSmmProjects -Config $config -FileSystem $fs -Force

        $result.Master.ContainsKey('Master-X') | Should -BeTrue
        $result.Master['Master-X'].Count | Should -Be 1
        $result.Master['Master-X'][0].Name | Should -BeNullOrEmpty
        $result.Master['Master-X'][0].Path | Should -BeNullOrEmpty
    }
}

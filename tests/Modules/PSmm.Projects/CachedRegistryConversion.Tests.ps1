#Requires -Version 7.5.4
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
$projectsManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Projects/PSmm.Projects.psd1'
$psmmManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
$importClassesScript = Join-Path -Path $repoRoot -ChildPath 'tests/Support/Import-PSmmClasses.ps1'

if (Get-Command -Name Write-PSmmLog -ErrorAction SilentlyContinue) {
    # noop
}

Describe 'Cached registry conversion' {
    BeforeAll {
        # Compute repo root relative to this test file
        $repoRootLocal = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path

        # Load all test helpers including stubs
        $importAllHelpersScript = Join-Path -Path $repoRootLocal -ChildPath 'tests/Support/Import-AllTestHelpers.ps1'
        $null = Test-Path -Path $importAllHelpersScript
        if ($null -eq (Get-Item -Path $importAllHelpersScript -ErrorAction SilentlyContinue)) {
            throw "Import-AllTestHelpers not found at $importAllHelpersScript"
        }
        . $importAllHelpersScript -RepositoryRoot $repoRootLocal

        $projectsManifestLocal = Join-Path -Path $repoRootLocal -ChildPath 'src/Modules/PSmm.Projects/PSmm.Projects.psd1'
        $psmmManifestLocal = Join-Path -Path $repoRootLocal -ChildPath 'src/Modules/PSmm/PSmm.psd1'

        # Remove modules to ensure clean state for this test
        if (Get-Module -Name 'PSmm.Projects' -ErrorAction SilentlyContinue) { Remove-Module -Name 'PSmm.Projects' -Force }
        if (Get-Module -Name 'PSmm' -ErrorAction SilentlyContinue) { Remove-Module -Name 'PSmm' -Force }

        Import-Module -Name $psmmManifestLocal -Force -ErrorAction Stop
        Import-Module -Name $projectsManifestLocal -Force -ErrorAction Stop
    }

    AfterAll {
        # Clean up modules after test to avoid state pollution for next test file
        if (Get-Module -Name 'PSmm.Projects' -ErrorAction SilentlyContinue) { Remove-Module -Name 'PSmm.Projects' -Force }
        if (Get-Module -Name 'PSmm' -ErrorAction SilentlyContinue) { Remove-Module -Name 'PSmm' -Force }
    }

    It 'Converts cached registry entries back into per-drive hashtables' {
        $config = New-TestAppConfiguration -InitializeProjectsPaths

        $masterWriteTime = [datetime]::UtcNow.AddMinutes(-10)
        $backupWriteTime = [datetime]::UtcNow.AddMinutes(-9)

        $cachedMasterProjects = @(
            [pscustomobject]@{
                Name = 'CachedOne'
                Path = 'X:\\Projects\\CachedOne'
                Drive = 'X:\\'
                Label = 'Master-Test'
                SerialNumber = 'MASTER-TST'
                StorageGroup = '1'
                DriveType = 'Master'
                BackupId = ''
            }
        )

        $cachedBackupProjects = @(
            [pscustomobject]@{
                Name = 'CachedTwo'
                Path = 'Y:\\Projects\\CachedTwo'
                Drive = 'Y:\\'
                Label = 'Backup-Test'
                SerialNumber = 'BACKUP-TST'
                StorageGroup = '1'
                DriveType = 'Backup'
                BackupId = '1'
            }
        )

        $config.Projects.Registry = @{
            Master = @{
                'Master-Test' = @{
                    Drive = 'X:\\'
                    Label = 'Master-Test'
                    DriveType = 'Master'
                    Projects = $cachedMasterProjects
                }
            }
            Backup = @{
                'Backup-Test' = @{
                    Drive = 'Y:\\'
                    Label = 'Backup-Test'
                    DriveType = 'Backup'
                    BackupId = '1'
                    Projects = $cachedBackupProjects
                }
            }
            LastScanned = [datetime]::UtcNow.AddMinutes(-5)
            ProjectDirs = @{
                'MASTER-TST_Projects' = $masterWriteTime
                'BACKUP-TST_Projects' = $backupWriteTime
            }
        }

        $fs = [TestFileSystemService]::new(@('X:\\Projects','Y:\\Projects'))
        $fs.SetLastWriteTime('X:\\Projects', $masterWriteTime)
        $fs.SetLastWriteTime('Y:\\Projects', $backupWriteTime)

        $null = Mock -CommandName Get-ProjectsFromDrive -ModuleName 'PSmm.Projects' -MockWith { @{ Projects = $Projects; ProjectDirs = $ProjectDirs } }

        $serviceContainer = [pscustomobject]@{} | Add-Member -MemberType ScriptMethod -Name Resolve -Value {
            param([string]$ServiceName)
            if ($ServiceName -eq 'FileSystem') { return $fs }
            return $null
        } -PassThru

        $result = Get-PSmmProjects -Config $config -ServiceContainer $serviceContainer

        # Ensure Get-ProjectsFromDrive was not called (cache used)
        $null = Assert-MockCalled -CommandName Get-ProjectsFromDrive -ModuleName 'PSmm.Projects' -Times 0

        # Check returned structure is driveLabel -> array of project objects
        $result.Master.ContainsKey('Master-Test') | Should -BeTrue
        $result.Master['Master-Test'].Count | Should -Be 1
        $result.Master['Master-Test'][0].Name | Should -Be 'CachedOne'

        $result.Backup.ContainsKey('Backup-Test') | Should -BeTrue
        $result.Backup['Backup-Test'].Count | Should -Be 1
        $result.Backup['Backup-Test'][0].Name | Should -Be 'CachedTwo'
    }
}

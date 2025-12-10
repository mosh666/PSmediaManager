#Requires -Version 7.5.4
Set-StrictMode -Version Latest

 $repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
 $projectsManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Projects/PSmm.Projects.psd1'
 $psmmManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'

Describe 'Get-PSmmProjects cached registry conversion' {
    BeforeAll {
        $repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $importAllTestHelpersScript = Join-Path -Path $repoRoot -ChildPath 'tests/Support/Import-AllTestHelpers.ps1'

        . $importAllTestHelpersScript -RepositoryRoot $repoRoot
        $projectsManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Projects/PSmm.Projects.psd1'
        $psmmManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'

        # Remove modules to ensure clean state for this test
        if (Get-Module -Name 'PSmm.Projects' -ErrorAction SilentlyContinue) { Remove-Module -Name 'PSmm.Projects' -Force }
        if (Get-Module -Name 'PSmm' -ErrorAction SilentlyContinue) { Remove-Module -Name 'PSmm' -Force }

        Import-Module -Name $psmmManifest -Force -ErrorAction Stop
        Import-Module -Name $projectsManifest -Force -ErrorAction Stop
    }
    AfterAll {
        # Clean up modules after test to avoid state pollution for next test file
        if (Get-Module -Name 'PSmm.Projects' -ErrorAction SilentlyContinue) { Remove-Module -Name 'PSmm.Projects' -Force }
        if (Get-Module -Name 'PSmm' -ErrorAction SilentlyContinue) { Remove-Module -Name 'PSmm' -Force }
    }

    BeforeEach {
        if (-not (Test-Path -Path 'variable:script:previousTestMode')) { $script:previousTestMode = $null }
        $script:previousTestMode = $env:MEDIA_MANAGER_TEST_MODE
        $env:MEDIA_MANAGER_TEST_MODE = '1'
    }

    AfterEach {
        if ($null -ne $script:previousTestMode) { $env:MEDIA_MANAGER_TEST_MODE = $script:previousTestMode } else { Remove-Item Env:MEDIA_MANAGER_TEST_MODE -ErrorAction SilentlyContinue }
    }

    It 'Converts mixed-shaped cached registry entries back into per-drive arrays' {
        $config = New-TestAppConfiguration -InitializeProjectsPaths

        $now = [datetime]::UtcNow
        $cachedMasterProjectsHash = @(
            [pscustomobject]@{ Name = 'H1'; Path = 'X:\Projects\H1'; Drive = 'X:\'; Label = 'HashLabel'; SerialNumber = 'S-H' ; DriveType = 'Master' }
        )
        $cachedMasterProjectsObject = @(
            [pscustomobject]@{ Name = 'O1'; Path = 'X:\Projects\O1'; Drive = 'X:\'; Label = 'ObjectLabel'; SerialNumber = 'S-O'; DriveType = 'Master' }
        )
        $cachedMasterProjectsArray = @(
            [pscustomobject]@{ Name = 'A1'; Path = 'X:\Projects\A1'; Drive = 'X:\'; Label = 'ArrayLabel'; SerialNumber = 'S-A'; DriveType = 'Master' }
        )

        $config.Projects.Registry = @{
            Master = @{
                'HashLabel' = @{ Drive = 'X:\'; Label = 'HashLabel'; Projects = $cachedMasterProjectsHash }
                'ObjectLabel' = [pscustomobject]@{ Drive = 'X:\'; Label = 'ObjectLabel'; Projects = $cachedMasterProjectsObject }
                'ArrayLabel' = $cachedMasterProjectsArray
            }
            Backup = @{}
            LastScanned = $now
            ProjectDirs = @{ 'S-H_Projects' = $now; 'S-O_Projects' = $now; 'S-A_Projects' = $now }
        }

        # Minimal filesystem that reports Projects directory last-write times
        $fs = [TestFileSystemService]::new(@('X:\Projects'))
        $fs.SetLastWriteTime('X:\Projects', $now)

        $null = Mock -CommandName Get-ProjectsFromDrive -ModuleName 'PSmm.Projects' -MockWith { @{ Projects = $Projects; ProjectDirs = $ProjectDirs } }

        $serviceContainer = [pscustomobject]@{} | Add-Member -MemberType ScriptMethod -Name Resolve -Value {
            param([string]$ServiceName)
            if ($ServiceName -eq 'FileSystem') { return $fs }
            return $null
        } -PassThru

        $result = Get-PSmmProjects -Config $config -ServiceContainer $serviceContainer

        $null = Assert-MockCalled -CommandName Get-ProjectsFromDrive -ModuleName 'PSmm.Projects' -Times 0

        $result.Master.ContainsKey('HashLabel') | Should -BeTrue
        $result.Master['HashLabel'].Count | Should -Be 1
        $result.Master.ContainsKey('ObjectLabel') | Should -BeTrue
        $result.Master['ObjectLabel'].Count | Should -Be 1
        $result.Master.ContainsKey('ArrayLabel') | Should -BeTrue
        $result.Master['ArrayLabel'].Count | Should -Be 1
    }
}

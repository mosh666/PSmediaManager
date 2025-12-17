#Requires -Version 7.5.4
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent

    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/Interfaces.ps1')
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/Exceptions.ps1')
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/UiModels.ps1')
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/ProjectModels.ps1')
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/Services/FileSystemService.ps1')
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/AppConfiguration.ps1')

    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Projects/Public/Get-PSmmProjects.ps1')
}

describe 'InternalErrorMessages typing' {
    It 'AppConfiguration initializes InternalErrorMessages as UiErrorCatalog' {
        $cfg = [AppConfiguration]::new()
        $cfg.InternalErrorMessages | Should -BeOfType ([UiErrorCatalog])
        $cfg.InternalErrorMessages.Storage | Should -Not -BeNullOrEmpty
    }
}

describe 'Get-ProjectsFromDrive storage error flags' {
    It 'Skips drive when UiErrorCatalog contains error key' {
        $catalog = [UiErrorCatalog]::new()
        $catalog.Storage['Master_1'] = 'skip'

        $config = [pscustomobject]@{ InternalErrorMessages = $catalog }
        $disk = [pscustomobject]@{ Label = 'D1'; DriveLetter = 'X:'; SerialNumber = 'SN1' }

        $projects = @{}
        $projectDirs = @{}

        $result = Get-ProjectsFromDrive -Disk $disk -StorageGroup '1' -DriveType 'Master' -Projects $projects -ProjectDirs $projectDirs -Config $config -FileSystem ([pscustomobject]@{})
        $result.Projects.Count | Should -Be 0
        $result.ProjectDirs.Count | Should -Be 0
    }

    It 'Skips drive when legacy hashtable shape contains error key' {
        $legacy = @{ Storage = @{ 'Master_1' = 'skip' } }

        $config = [pscustomobject]@{ InternalErrorMessages = $legacy }
        $disk = [pscustomobject]@{ Label = 'D1'; DriveLetter = 'X:'; SerialNumber = 'SN1' }

        $projects = @{}
        $projectDirs = @{}

        $result = Get-ProjectsFromDrive -Disk $disk -StorageGroup '1' -DriveType 'Master' -Projects $projects -ProjectDirs $projectDirs -Config $config -FileSystem ([pscustomobject]@{})
        $result.Projects.Count | Should -Be 0
        $result.ProjectDirs.Count | Should -Be 0
    }
}

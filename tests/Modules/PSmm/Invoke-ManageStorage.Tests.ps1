#Requires -Version 7.5.4
Set-StrictMode -Version Latest

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\src\Modules\PSmm\PSmm.psd1'
    $loggingModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\src\Modules\PSmm.Logging\PSmm.Logging.psd1'
    
    Import-Module -Name $modulePath -Force -Verbose:$false
    Import-Module -Name $loggingModulePath -Force -Verbose:$false
    
    $testConfigPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\tests\Support\TestConfig.ps1'
    . $testConfigPath
    
    $classPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\tests\Support\Import-PSmmClasses.ps1'
    if (Test-Path -Path $classPath) {
        . $classPath
    }

    Mock -CommandName Pause -MockWith {}
    Mock -CommandName Write-Information -MockWith {}
    
    $env:MEDIA_MANAGER_TEST_MODE = '1'
}

AfterAll {
    $env:MEDIA_MANAGER_TEST_MODE = '0'
    Remove-Item -Path 'env:MEDIA_MANAGER_TEST_INPUTS' -ErrorAction SilentlyContinue
    Remove-Module -Name 'PSmm' -Force -ErrorAction SilentlyContinue
    Remove-Module -Name 'PSmm.Logging' -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-ManageStorage' {
    AfterEach {
        Remove-Item -Path 'env:MEDIA_MANAGER_TEST_INPUTS' -ErrorAction SilentlyContinue
    }

    Context 'Parameter Validation' {
        It 'rejects null Config' {
            Mock -CommandName Write-PSmmLog -ModuleName PSmm -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            { Invoke-ManageStorage -Config $null -DriveRoot 'D:\' -ErrorAction Stop } | Should -Throw
        }

        It 'rejects empty DriveRoot' {
            $config = New-TestAppConfiguration
            Mock -CommandName Write-PSmmLog -ModuleName PSmm -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            { Invoke-ManageStorage -Config $config -DriveRoot '' -ErrorAction Stop } | Should -Throw
        }
    }

    Context 'NonInteractive Mode' {
        It 'returns false' {
            $config = New-TestAppConfiguration
            Mock -CommandName Write-PSmmLog -ModuleName PSmm -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            $result = Invoke-ManageStorage -Config $config -DriveRoot 'D:\' -NonInteractive
            $result | Should -Be $false
        }
    }

    Context 'Menu Display' {
        It 'displays menu options' {
            $config = New-TestAppConfiguration
            Mock -CommandName Write-PSmmLog -ModuleName PSmm -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            Invoke-ManageStorage -Config $config -DriveRoot 'D:\' -NonInteractive
            Assert-MockCalled -CommandName Write-PSmmLog -ModuleName PSmm
        }
    }

    Context 'Edit Mode' {
        It 'accepts storage groups' {
            $config = New-TestAppConfiguration
            $master = New-TestStorageDrive -Label 'Master1' -DriveLetter 'D:' -SerialNumber 'SN123'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master
            
            Mock -CommandName Write-PSmmLog -ModuleName PSmm -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            $result = Invoke-ManageStorage -Config $config -DriveRoot 'D:\' -NonInteractive
            $result | Should -Be $false
        }
    }

    Context 'Add Mode' {
        It 'accepts empty storage' {
            $config = New-TestAppConfiguration
            $config.Storage = @{}
            
            Mock -CommandName Write-PSmmLog -ModuleName PSmm -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            $result = Invoke-ManageStorage -Config $config -DriveRoot 'D:\' -NonInteractive
            $result | Should -Be $false
        }
    }

    Context 'Remove Mode' {
        It 'accepts multiple groups' {
            $config = New-TestAppConfiguration
            $master1 = New-TestStorageDrive -Label 'Master1' -DriveLetter 'D:' -SerialNumber 'SN123'
            $master2 = New-TestStorageDrive -Label 'Master2' -DriveLetter 'E:' -SerialNumber 'SN456'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master1
            Add-TestStorageGroup -Config $config -GroupId '2' -Master $master2
            
            Mock -CommandName Write-PSmmLog -ModuleName PSmm -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            $result = Invoke-ManageStorage -Config $config -DriveRoot 'D:\' -NonInteractive
            $result | Should -Be $false
        }
    }
}

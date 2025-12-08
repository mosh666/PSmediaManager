#Requires -Version 7.5.4
Set-StrictMode -Version Latest

BeforeAll {
    $script:previousTestMode = $env:MEDIA_MANAGER_TEST_MODE
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\.\src\Modules\PSmm\PSmm.psd1'
    $loggingModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\.\src\Modules\PSmm.Logging\PSmm.Logging.psd1'
    Import-Module -Name $modulePath -Force -Verbose:$false
    Import-Module -Name $loggingModulePath -Force -Verbose:$false
    $testConfigPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\.\tests\Support\TestConfig.ps1'
    . $testConfigPath
    $env:MEDIA_MANAGER_TEST_MODE = '1'

    function New-TestStorageFile {
        param(
            [string]$DriveRoot,
            [hashtable]$Data
        )
        $storagePath = Join-Path -Path $DriveRoot -ChildPath 'PSmm.Config/PSmm.Storage.psd1'
        New-Item -ItemType Directory -Force -Path (Split-Path $storagePath) | Out-Null
        [AppConfigurationBuilder]::WriteStorageFile($storagePath, $Data)
        return $storagePath
    }
}

AfterAll {
    if ($null -ne $script:previousTestMode) { $env:MEDIA_MANAGER_TEST_MODE = $script:previousTestMode } else { Remove-Item Env:MEDIA_MANAGER_TEST_MODE -ErrorAction SilentlyContinue }
    Remove-Module -Name 'PSmm' -Force -ErrorAction SilentlyContinue
    Remove-Module -Name 'PSmm.Logging' -Force -ErrorAction SilentlyContinue
}

Describe 'Remove-StorageGroup' {
    BeforeEach {
        $config = New-TestAppConfiguration
        $driveRoot = Join-Path -Path $TestDrive -ChildPath 'Root'
        New-Item -ItemType Directory -Force -Path $driveRoot | Out-Null
        Remove-Item -Path (Join-Path $driveRoot 'PSmm.Config') -Recurse -Force -ErrorAction SilentlyContinue
        Mock -CommandName Get-StorageDrive -MockWith { @() }
        Mock -CommandName Confirm-Storage -MockWith { }
    }

    Context 'Parameter Validation' {
        It 'requires Config parameter' {
            { Remove-StorageGroup -Config $null -DriveRoot 'D:\' -GroupIds @('1') -Confirm:$false -ErrorAction Stop } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError,Remove-StorageGroup'
        }

        It 'requires DriveRoot parameter' {
            { Remove-StorageGroup -Config $config -DriveRoot $null -GroupIds @('1') -Confirm:$false -ErrorAction Stop } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError,Remove-StorageGroup'
        }

        It 'requires GroupIds parameter' {
            { Remove-StorageGroup -Config $config -DriveRoot 'D:\' -GroupIds $null -Confirm:$false -ErrorAction Stop } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError,Remove-StorageGroup'
        }
    }

    Context 'Storage removal' {
        It 'handles missing storage file gracefully' {
            { Remove-StorageGroup -Config $config -DriveRoot $driveRoot -GroupIds @('1') -Confirm:$false } | Should -Not -Throw
        }

        It 'removes specified group and rewrites storage file' {
            $data = @{ '1' = @{ DisplayName = 'G1'; Master = @{ Label = 'M1'; SerialNumber = 'A' } }; '2' = @{ DisplayName = 'G2' } }
            $path = New-TestStorageFile -DriveRoot $driveRoot -Data $data

            $config.Storage['1'] = [StorageGroupConfig]::new('1')
            $config.Storage['1'].Master = [StorageDriveConfig]::new('M1','')
            $config.Storage['1'].Master.SerialNumber = 'A'
            $config.Storage['2'] = [StorageGroupConfig]::new('2')

            Remove-StorageGroup -Config $config -DriveRoot $driveRoot -GroupIds @('1') -Confirm:$false

            $reloaded = [AppConfigurationBuilder]::ReadStorageFile($path)
            $reloaded.Count | Should -Be 1
            $reloaded.Keys | Should -Contain '1'
            $reloaded['1'].DisplayName | Should -Be 'G2'
        }

        It 'returns when group not found' {
            $data = @{ '1' = @{ DisplayName = 'G1' } }
            New-TestStorageFile -DriveRoot $driveRoot -Data $data
            $config.Storage['1'] = [StorageGroupConfig]::new('1')

            { Remove-StorageGroup -Config $config -DriveRoot $driveRoot -GroupIds @('99') -Confirm:$false } | Should -Not -Throw
        }
    }
}

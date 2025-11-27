#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Test-DuplicateSerial' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $script:psmmManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
        $script:psmmLoggingManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'
        $script:importClassesScript = Join-Path -Path $repoRoot -ChildPath 'tests/Support/Import-PSmmClasses.ps1'
        $script:testConfigPath = Join-Path -Path $repoRoot -ChildPath 'tests/Support/TestConfig.ps1'

        . $testConfigPath
        $helperFunctions = @('New-TestRepositoryRoot','New-TestAppConfiguration','New-TestStorageDrive','Add-TestStorageGroup')
        foreach ($helper in $helperFunctions) {
            $command = Get-Command -Name $helper -CommandType Function -ErrorAction Stop
            Set-Item -Path "function:\global:$helper" -Value $command.ScriptBlock -Force
        }

        & $importClassesScript -RepositoryRoot $repoRoot

        Get-Module -Name PSmm, PSmm.Logging -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Module -Name $_.Name -Force -ErrorAction SilentlyContinue
        }

        Import-Module -Name $psmmManifest -Force -ErrorAction Stop
        Import-Module -Name $psmmLoggingManifest -Force -ErrorAction Stop
    }

    Context 'No duplicates' {
        It 'returns true when no serials conflict' {
            InModuleScope PSmm {
                $config = New-TestAppConfiguration
                $m = New-TestStorageDrive -Label 'Master' -DriveLetter '' -SerialNumber 'MASTER-001'
                $null = Add-TestStorageGroup -Config $config -GroupId '1' -Master $m

                Mock Write-PSmmLog {} -ModuleName PSmm

                $inputs = [ref]@('')
                $idx = [ref]0
                $result = Test-DuplicateSerial -Config $config -Serials @('UNIQUE-123') -TestInputs $inputs -TestInputIndex $idx
                $result | Should -BeTrue
            }
        }
    }

    Context 'Duplicates NonInteractive' {
        It 'throws when duplicate is found and NonInteractive is set' {
            InModuleScope PSmm {
                $config = New-TestAppConfiguration
                $m = New-TestStorageDrive -Label 'Master' -DriveLetter '' -SerialNumber 'DUP-001'
                $null = Add-TestStorageGroup -Config $config -GroupId '1' -Master $m

                Mock Write-PSmmLog {} -ModuleName PSmm

                { Test-DuplicateSerial -Config $config -Serials @('DUP-001') -NonInteractive } | Should -Throw -ErrorId *
            }
        }
    }

    Context 'Duplicates Interactive' {
        It 'returns true when user confirms (Y)' {
            InModuleScope PSmm {
                $config = New-TestAppConfiguration
                $m = New-TestStorageDrive -Label 'Master' -DriveLetter '' -SerialNumber 'DUP-YES'
                $null = Add-TestStorageGroup -Config $config -GroupId '1' -Master $m

                Mock Write-PSmmLog {} -ModuleName PSmm

                $inputs = [ref]@('Y')
                $idx = [ref]0
                $result = Test-DuplicateSerial -Config $config -Serials @('DUP-YES') -TestInputs $inputs -TestInputIndex $idx
                $result | Should -BeTrue
            }
        }

        It 'returns false when user declines (N)' {
            InModuleScope PSmm {
                $config = New-TestAppConfiguration
                $m = New-TestStorageDrive -Label 'Master' -DriveLetter '' -SerialNumber 'DUP-NO'
                $null = Add-TestStorageGroup -Config $config -GroupId '1' -Master $m

                Mock Write-PSmmLog {} -ModuleName PSmm

                $inputs = [ref]@('N')
                $idx = [ref]0
                $result = Test-DuplicateSerial -Config $config -Serials @('DUP-NO') -TestInputs $inputs -TestInputIndex $idx
                $result | Should -BeFalse
            }
        }
    }
}

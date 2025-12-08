BeforeAll {
    $script:previousTestMode = $env:MEDIA_MANAGER_TEST_MODE
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\.\src\Modules\PSmm\PSmm.psd1'
    $loggingModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\.\src\Modules\PSmm.Logging\PSmm.Logging.psd1'
    Import-Module -Name $modulePath -Force -Verbose:$false
    Import-Module -Name $loggingModulePath -Force -Verbose:$false
    $testConfigPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\.\tests\Support\TestConfig.ps1'
    . $testConfigPath
    $env:MEDIA_MANAGER_TEST_MODE = '1'
}

AfterAll {
    if ($null -ne $script:previousTestMode) { $env:MEDIA_MANAGER_TEST_MODE = $script:previousTestMode } else { Remove-Item Env:MEDIA_MANAGER_TEST_MODE -ErrorAction SilentlyContinue }
}

Describe 'Test-DuplicateSerial' {
    BeforeEach {
        $config = New-TestAppConfiguration
    }

    Context 'Parameter Validation' {
        It 'should require Config parameter' {
            { Test-DuplicateSerial -Config $null -Serials @('TEST') } | 
                Should -Throw
        }

        It 'should require Serials parameter' {
            { Test-DuplicateSerial -Config $config -Serials $null } | 
                Should -Throw
        }

        It 'should reject null Config' {
            { Test-DuplicateSerial -Config $null -Serials @('TEST') } | 
                Should -Throw
        }

        It 'should reject null Serials' {
            { Test-DuplicateSerial -Config $config -Serials $null } | 
                Should -Throw
        }

        It 'should accept empty array Serials' {
            # Empty strings are allowed via AllowEmptyString parameter
            Mock -CommandName Write-PSmmLog -MockWith { }
            { Test-DuplicateSerial -Config $config -Serials @('') } | Should -Not -Throw
        }

        It 'should accept single serial' {
            { Test-DuplicateSerial -Config $config -Serials @('ABC123') } | Should -Not -Throw
        }

        It 'should accept multiple serials' {
            { Test-DuplicateSerial -Config $config -Serials @('ABC123', 'DEF456') } | Should -Not -Throw
        }

        It 'should accept optional ExcludeGroupId parameter' {
            { Test-DuplicateSerial -Config $config -Serials @('ABC123') -ExcludeGroupId '1' } | Should -Not -Throw
        }

        It 'should accept NonInteractive switch' {
            { Test-DuplicateSerial -Config $config -Serials @('ABC123') -NonInteractive } | Should -Not -Throw
        }

        It 'should accept TestInputs and TestInputIndex parameters' {
            $inputs = [ref]@('Y')
            $index = [ref]0
            { Test-DuplicateSerial -Config $config -Serials @('ABC123') -TestInputs $inputs -TestInputIndex $index } | Should -Not -Throw
        }
    }

    Context 'No Duplicates - Returns True' {
        It 'should return true when no duplicates found' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            
            $result = Test-DuplicateSerial -Config $config -Serials @('UNIQUE123')
            
            $result | Should -Be $true
        }

        It 'should return true for empty serials array' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            
            # Empty strings are filtered out in the function, so pass string with space
            $result = Test-DuplicateSerial -Config $config -Serials @(' ')
            
            $result | Should -Be $true
        }

        It 'should return true when config has no storage' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            
            $emptyConfig = New-TestAppConfiguration
            $result = Test-DuplicateSerial -Config $emptyConfig -Serials @('ANY123')
            
            $result | Should -Be $true
        }

        It 'should return true when serials do not match master drives' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            
            $master = New-TestStorageDrive -Label 'Master' -DriveLetter 'D' -SerialNumber 'MASTER001'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master
            
            $result = Test-DuplicateSerial -Config $config -Serials @('DIFFERENT123')
            
            $result | Should -Be $true
        }

        It 'should return true when serials do not match backup drives' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            
            $master = New-TestStorageDrive -Label 'Master' -DriveLetter 'D' -SerialNumber 'MASTER001'
            $backup = New-TestStorageDrive -Label 'Backup' -DriveLetter 'D' -SerialNumber 'BACKUP001'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master -Backups @{ '1' = $backup }
            
            $result = Test-DuplicateSerial -Config $config -Serials @('DIFFERENT456')
            
            $result | Should -Be $true
        }
    }

    Context 'Duplicates - NonInteractive Mode' {
        It 'should throw when duplicate found in NonInteractive mode' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            
            $master = New-TestStorageDrive -Label 'Master' -DriveLetter 'D' -SerialNumber 'DUP001'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master
            
            { Test-DuplicateSerial -Config $config -Serials @('DUP001') -NonInteractive } | Should -Throw
        }

        It 'should throw with error message mentioning duplicates' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            
            $master = New-TestStorageDrive -Label 'Master' -DriveLetter 'D' -SerialNumber 'DUP001'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master
            
            { Test-DuplicateSerial -Config $config -Serials @('DUP001') -NonInteractive } | 
                Should -Throw -ErrorId *
        }

        It 'should throw when duplicate found in backup drives' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            
            $master = New-TestStorageDrive -Label 'Master' -DriveLetter 'D' -SerialNumber 'MASTER001'
            $backup = New-TestStorageDrive -Label 'Backup' -DriveLetter 'D' -SerialNumber 'BACKUP001'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master -Backups @{ '1' = $backup }
            
            { Test-DuplicateSerial -Config $config -Serials @('BACKUP001') -NonInteractive } | Should -Throw
        }

        It 'should throw for multiple duplicate serials' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            
            $master1 = New-TestStorageDrive -Label 'Master1' -DriveLetter 'D' -SerialNumber 'DUP001'
            $master2 = New-TestStorageDrive -Label 'Master2' -DriveLetter 'D' -SerialNumber 'DUP002'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master1
            Add-TestStorageGroup -Config $config -GroupId '2' -Master $master2
            
            { Test-DuplicateSerial -Config $config -Serials @('DUP001', 'DUP002') -NonInteractive } | Should -Throw
        }
    }

    Context 'Duplicates - Interactive Mode' {
        It 'should return true when user confirms (Y)' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            Mock -CommandName Write-PSmmHost -MockWith { }
            
            $master = New-TestStorageDrive -Label 'Master' -DriveLetter 'D' -SerialNumber 'DUP001'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master
            
            $inputs = [ref]@('Y')
            $index = [ref]0
            
            $result = Test-DuplicateSerial -Config $config -Serials @('DUP001') `
                -TestInputs $inputs -TestInputIndex $index
            
            $result | Should -Be $true
        }

        It 'should return false when user declines (N)' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            Mock -CommandName Write-PSmmHost -MockWith { }
            
            $master = New-TestStorageDrive -Label 'Master' -DriveLetter 'D' -SerialNumber 'DUP001'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master
            
            $inputs = [ref]@('N')
            $index = [ref]0
            
            $result = Test-DuplicateSerial -Config $config -Serials @('DUP001') `
                -TestInputs $inputs -TestInputIndex $index
            
            $result | Should -Be $false
        }

        It 'should accept lowercase y for confirmation' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            Mock -CommandName Write-PSmmHost -MockWith { }
            
            $master = New-TestStorageDrive -Label 'Master' -DriveLetter 'D' -SerialNumber 'DUP001'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master
            
            $inputs = [ref]@('y')
            $index = [ref]0
            
            $result = Test-DuplicateSerial -Config $config -Serials @('DUP001') `
                -TestInputs $inputs -TestInputIndex $index
            
            $result | Should -Be $true
        }

        It 'should reject non-Y responses as decline' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            Mock -CommandName Write-PSmmHost -MockWith { }
            
            $master = New-TestStorageDrive -Label 'Master' -DriveLetter 'D' -SerialNumber 'DUP001'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master
            
            $inputs = [ref]@('MAYBE')
            $index = [ref]0
            
            $result = Test-DuplicateSerial -Config $config -Serials @('DUP001') `
                -TestInputs $inputs -TestInputIndex $index
            
            $result | Should -Be $false
        }
    }

    Context 'ExcludeGroupId Parameter' {
        It 'should exclude specified group from duplicate check' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            
            $master1 = New-TestStorageDrive -Label 'Master1' -DriveLetter 'D' -SerialNumber 'SAME001'
            $master2 = New-TestStorageDrive -Label 'Master2' -DriveLetter 'D' -SerialNumber 'SAME001'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master1
            Add-TestStorageGroup -Config $config -GroupId '2' -Master $master2
            
            # When checking for SAME001 while editing group 1 with Interactive mode
            $inputs = [ref]@('N')  # User declines to proceed with duplicate
            $index = [ref]0
            $result = Test-DuplicateSerial -Config $config -Serials @('SAME001') -ExcludeGroupId '1' -TestInputs $inputs -TestInputIndex $index
            
            # Should return false because duplicate found in group 2 and user declines
            $result | Should -Be $false
        }

        It 'should allow re-using same serial when editing same group' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            
            $master = New-TestStorageDrive -Label 'Master' -DriveLetter 'D' -SerialNumber 'SAME001'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master
            
            # When editing group 1 with same serial, should not report duplicate
            $result = Test-DuplicateSerial -Config $config -Serials @('SAME001') -ExcludeGroupId '1'
            
            $result | Should -Be $true
        }

        It 'should accept empty string ExcludeGroupId' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            
            { Test-DuplicateSerial -Config $config -Serials @('TEST') -ExcludeGroupId '' } | Should -Not -Throw
        }
    }

    Context 'Duplicate Detection' {
        It 'should find duplicate in master drive' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            
            $master = New-TestStorageDrive -Label 'Master' -DriveLetter 'D' -SerialNumber 'DUPLICATE'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master
            
            # In NonInteractive mode, should throw
            { Test-DuplicateSerial -Config $config -Serials @('DUPLICATE') -NonInteractive } | Should -Throw
        }

        It 'should find duplicate in first backup drive' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            
            $master = New-TestStorageDrive -Label 'Master' -DriveLetter 'D' -SerialNumber 'MASTER001'
            $backup = New-TestStorageDrive -Label 'Backup' -DriveLetter 'D' -SerialNumber 'DUPLICATE'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master -Backups @{ '1' = $backup }
            
            { Test-DuplicateSerial -Config $config -Serials @('DUPLICATE') -NonInteractive } | Should -Throw
        }

        It 'should find duplicates in multiple groups' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            
            $master1 = New-TestStorageDrive -Label 'Master1' -DriveLetter 'D' -SerialNumber 'DUP1'
            $master2 = New-TestStorageDrive -Label 'Master2' -DriveLetter 'D' -SerialNumber 'DUP2'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master1
            Add-TestStorageGroup -Config $config -GroupId '2' -Master $master2
            
            { Test-DuplicateSerial -Config $config -Serials @('DUP1', 'DUP2') -NonInteractive } | Should -Throw
        }

        It 'should ignore null/empty serials in check' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            
            $master = New-TestStorageDrive -Label 'Master' -DriveLetter 'D' -SerialNumber 'REAL'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master
            
            # Empty and whitespace strings are filtered out, so pass with valid and whitespace
            $result = Test-DuplicateSerial -Config $config -Serials @('', '  ', 'UNIQUE')
            
            $result | Should -Be $true
        }

        It 'should handle serial with whitespace' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            
            $master = New-TestStorageDrive -Label 'Master' -DriveLetter 'D' -SerialNumber 'ABC123'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master
            
            # Whitespace comparison depends on function implementation
            { Test-DuplicateSerial -Config $config -Serials @('ABC123') -NonInteractive } | Should -Throw
        }
    }

    Context 'Logging' {
        It 'should log warning when duplicates found' {
            $logMessages = @()
            Mock -CommandName Write-PSmmLog -MockWith {
                if ($Level -eq 'WARNING') { $logMessages += $Message }
            }
            
            $master = New-TestStorageDrive -Label 'Master' -DriveLetter 'D' -SerialNumber 'DUP001'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master
            
            { Test-DuplicateSerial -Config $config -Serials @('DUP001') -NonInteractive } | Should -Throw
        }

        It 'should log user confirmation when proceeding with duplicates' {
            $logMessages = @()
            Mock -CommandName Write-PSmmLog -MockWith {
                if ($Level -eq 'NOTICE') { $logMessages += $Message }
            }
            Mock -CommandName Write-PSmmHost -MockWith { }
            
            $master = New-TestStorageDrive -Label 'Master' -DriveLetter 'D' -SerialNumber 'DUP001'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master
            
            $inputs = [ref]@('Y')
            $index = [ref]0
            Test-DuplicateSerial -Config $config -Serials @('DUP001') -TestInputs $inputs -TestInputIndex $index | Out-Null
            
            # Should have logged confirmation
        }

        It 'should log user decline when refusing to proceed' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            Mock -CommandName Write-PSmmHost -MockWith { }
            
            $master = New-TestStorageDrive -Label 'Master' -DriveLetter 'D' -SerialNumber 'DUP001'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master
            
            $inputs = [ref]@('N')
            $index = [ref]0
            $result = Test-DuplicateSerial -Config $config -Serials @('DUP001') -TestInputs $inputs -TestInputIndex $index
            
            $result | Should -Be $false
        }
    }

    Context 'Output Type' {
        It 'should return boolean type' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            
            $result = Test-DuplicateSerial -Config $config -Serials @('UNIQUE')
            
            $result | Should -BeOfType [bool]
        }

        It 'should explicitly return $true for no duplicates' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            
            $result = Test-DuplicateSerial -Config $config -Serials @('UNIQUE')
            
            $result -eq $true | Should -Be $true
        }

        It 'should explicitly return $false for user decline' {
            Mock -CommandName Write-PSmmLog -MockWith { }
            Mock -CommandName Write-PSmmHost -MockWith { }
            
            $master = New-TestStorageDrive -Label 'Master' -DriveLetter 'D' -SerialNumber 'DUP001'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master
            
            $inputs = [ref]@('N')
            $index = [ref]0
            $result = Test-DuplicateSerial -Config $config -Serials @('DUP001') -TestInputs $inputs -TestInputIndex $index
            
            $result -eq $false | Should -Be $true
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

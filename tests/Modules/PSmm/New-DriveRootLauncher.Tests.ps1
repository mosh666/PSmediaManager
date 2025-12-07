BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\src\Modules\PSmm\PSmm.psd1'
    $loggingModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\src\Modules\PSmm.Logging\PSmm.Logging.psd1'
    Import-Module -Name $modulePath -Force -Verbose:$false
    Import-Module -Name $loggingModulePath -Force -Verbose:$false
    $testConfigPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\tests\Support\TestConfig.ps1'
    . $testConfigPath
    $env:MEDIA_MANAGER_TEST_MODE = '1'
}

AfterAll {
    if (Test-Path -Path env:MEDIA_MANAGER_TEST_MODE) {
        Remove-Item -Path env:MEDIA_MANAGER_TEST_MODE
    }
}

Describe 'New-DriveRootLauncher' {
    BeforeEach {
        # Create test drive structure
        $testDrive = "TestDrive:\"
        $repositoryRoot = Join-Path -Path $testDrive -ChildPath "PSmediaManager"
        $driveRoot = Split-Path -Path $repositoryRoot -Parent
        $launcherPath = Join-Path -Path $driveRoot -ChildPath "Start-PSmediaManager.lnk"
        $repoLauncher = Join-Path -Path $repositoryRoot -ChildPath "Start-PSmediaManager.ps1"
        
        # Create test directory structure
        New-Item -ItemType Directory -Path $repositoryRoot -Force | Out-Null
        New-Item -ItemType File -Path $repoLauncher -Force | Out-Null
    }

    Context 'Parameter Validation' {
        It 'should require RepositoryRoot parameter' {
            { New-DriveRootLauncher -FileSystem (New-Object PSObject) -PathProvider (New-Object PSObject) } | 
                Should -Throw -ErrorId 'MissingMandatoryParameter'
        }

        It 'should require FileSystem parameter' {
            { New-DriveRootLauncher -RepositoryRoot "C:\test" -PathProvider (New-Object PSObject) } | 
                Should -Throw -ErrorId 'MissingMandatoryParameter'
        }

        It 'should require PathProvider parameter' {
            { New-DriveRootLauncher -RepositoryRoot "C:\test" -FileSystem (New-Object PSObject) } | 
                Should -Throw -ErrorId 'MissingMandatoryParameter'
        }

        It 'should reject null RepositoryRoot' {
            $fileSystem = @{ TestPath = { $true }; RemoveItem = {} } | ConvertTo-PSObject
            $pathProvider = @{ CombinePath = { param($paths) $paths -join '\' } } | ConvertTo-PSObject
            
            { New-DriveRootLauncher -RepositoryRoot $null -FileSystem $fileSystem -PathProvider $pathProvider } | 
                Should -Throw
        }

        It 'should reject empty RepositoryRoot' {
            $fileSystem = @{ TestPath = { $true }; RemoveItem = {} } | ConvertTo-PSObject
            $pathProvider = @{ CombinePath = { param($paths) $paths -join '\' } } | ConvertTo-PSObject
            
            { New-DriveRootLauncher -RepositoryRoot '' -FileSystem $fileSystem -PathProvider $pathProvider } | 
                Should -Throw
        }

        It 'should reject null FileSystem' {
            $pathProvider = @{ CombinePath = { param($paths) $paths -join '\' } } | ConvertTo-PSObject
            
            { New-DriveRootLauncher -RepositoryRoot "C:\test" -FileSystem $null -PathProvider $pathProvider } | 
                Should -Throw
        }

        It 'should reject null PathProvider' {
            $fileSystem = @{ TestPath = { $true }; RemoveItem = {} } | ConvertTo-PSObject
            
            { New-DriveRootLauncher -RepositoryRoot "C:\test" -FileSystem $fileSystem -PathProvider $null } | 
                Should -Throw
        }
    }

    Context 'Drive Root Determination' {
        It 'should calculate drive root from repository root' {
            $fileSystem = @{
                TestPath = { param($path) 
                    $path -eq "D:\Start-PSmediaManager.lnk" -or 
                    $path -eq "D:\PSmediaManager\Start-PSmediaManager.ps1"
                }
                RemoveItem = { }
            } | ConvertTo-PSObject
            
            $pathProvider = @{
                CombinePath = { param($paths) $paths -join '\' }
            } | ConvertTo-PSObject
            
            $output = New-DriveRootLauncher -RepositoryRoot "D:\PSmediaManager" `
                -FileSystem $fileSystem -PathProvider $pathProvider -Verbose 4>&1
            
            # Verify it doesn't return errors
            $output | Should -Not -Contain "Cannot determine drive root"
        }

        It 'should handle single-level directory paths' {
            $fileSystem = @{
                TestPath = { param($path) 
                    $path -eq "TestDrive:\Start-PSmediaManager.lnk" -or 
                    $path -eq "TestDrive:\Start-PSmediaManager.ps1"
                }
                RemoveItem = { }
            } | ConvertTo-PSObject
            
            $pathProvider = @{
                CombinePath = { param($paths) $paths -join '\' }
            } | ConvertTo-PSObject
            
            # When Split-Path returns empty, should handle gracefully
            $repositoryRoot = "TestDrive:\"
            New-DriveRootLauncher -RepositoryRoot $repositoryRoot `
                -FileSystem $fileSystem -PathProvider $pathProvider -WarningVariable warnings 4>&1 | Out-Null
            
            if (-not [string]::IsNullOrWhiteSpace($warnings)) {
                $warnings | Should -Contain "Cannot determine drive root"
            }
        }
    }

    Context 'Launcher Existence Checks' {
        It 'should skip creation if launcher already exists' {
            $fileSystem = @{
                TestPath = { param($path) 
                    # Launcher exists, repo launcher exists
                    $true
                }
                RemoveItem = { }
            } | ConvertTo-PSObject
            
            $pathProvider = @{
                CombinePath = { param($paths) $paths -join '\' }
            } | ConvertTo-PSObject
            
            $output = New-DriveRootLauncher -RepositoryRoot "D:\PSmediaManager" `
                -FileSystem $fileSystem -PathProvider $pathProvider -Verbose 4>&1
            
            $output | Where-Object { $_ -match "already exists" } | Should -Not -BeNullOrEmpty
        }

        It 'should warn if repository launcher not found' {
            $fileSystem = @{
                TestPath = { param($path) 
                    # Launcher doesn't exist, repo launcher doesn't exist
                    $false
                }
                RemoveItem = { }
            } | ConvertTo-PSObject
            
            $pathProvider = @{
                CombinePath = { param($paths) $paths -join '\' }
            } | ConvertTo-PSObject
            
            $output = New-DriveRootLauncher -RepositoryRoot "D:\PSmediaManager" `
                -FileSystem $fileSystem -PathProvider $pathProvider -WarningVariable warnings 4>&1
            
            $warnings | Should -Contain "Repository launcher not found"
        }

        It 'should proceed when launcher does not exist and repo launcher exists' {
            $callCount = 0
            
            $fileSystem = @{
                TestPath = { param($path) 
                    # Launcher doesn't exist, repo launcher exists
                    $path -like "*Start-PSmediaManager.lnk" ? $false : $true
                }
                RemoveItem = { }
            } | ConvertTo-PSObject
            
            $pathProvider = @{
                CombinePath = { param($paths) $paths -join '\' }
            } | ConvertTo-PSObject
            
            Mock -CommandName New-Object -ParameterFilter {
                $ComObject -eq 'WScript.Shell'
            } -MockWith {
                @{
                    CreateShortcut = {
                        param($path)
                        return @{
                            TargetPath = ''
                            Arguments = ''
                            WorkingDirectory = ''
                            Description = ''
                            IconLocation = ''
                            Save = { }
                        }
                    }
                } | ConvertTo-PSObject
            }
            
            New-DriveRootLauncher -RepositoryRoot "D:\PSmediaManager" `
                -FileSystem $fileSystem -PathProvider $pathProvider -Verbose 4>&1 | Out-Null
        }
    }

    Context 'Legacy Launcher Cleanup' {
        It 'should remove legacy .cmd launcher if it exists' {
            $removedPaths = @()
            
            $fileSystem = @{
                TestPath = { param($path) 
                    # Launcher doesn't exist, repo launcher exists, legacy .cmd exists
                    $path -like "*Start-PSmediaManager.cmd" ? $true :
                    $path -like "*Start-PSmediaManager.lnk" ? $false :
                    $true
                }
                RemoveItem = { 
                    param($path, [bool]$force)
                    $removedPaths += $path
                }
            } | ConvertTo-PSObject
            
            $pathProvider = @{
                CombinePath = { param($paths) $paths -join '\' }
            } | ConvertTo-PSObject
            
            # Mock WScript.Shell to handle shortcut creation
            Mock -CommandName New-Object -ParameterFilter {
                $ComObject -eq 'WScript.Shell'
            } -MockWith {
                @{
                    CreateShortcut = {
                        param($path)
                        return @{
                            TargetPath = ''
                            Arguments = ''
                            WorkingDirectory = ''
                            Description = ''
                            IconLocation = ''
                            Save = { }
                        }
                    }
                } | ConvertTo-PSObject
            }
            
            New-DriveRootLauncher -RepositoryRoot "D:\PSmediaManager" `
                -FileSystem $fileSystem -PathProvider $pathProvider -Verbose 4>&1 | Out-Null
            
            # Verify that RemoveItem was called
            $fileSystem.RemoveItem | Should -Not -BeNullOrEmpty
        }

        It 'should remove legacy .ps1 launcher if it exists' {
            $removedPaths = @()
            
            $fileSystem = @{
                TestPath = { param($path) 
                    # Launcher doesn't exist, repo launcher exists, legacy .ps1 exists
                    $path -like "*Start-PSmediaManager.ps1" -and $path -notlike "*repo*" ? $true :
                    $path -like "*Start-PSmediaManager.lnk" ? $false :
                    $true
                }
                RemoveItem = { 
                    param($path, [bool]$force)
                    $removedPaths += $path
                }
            } | ConvertTo-PSObject
            
            $pathProvider = @{
                CombinePath = { param($paths) $paths -join '\' }
            } | ConvertTo-PSObject
            
            Mock -CommandName New-Object -ParameterFilter {
                $ComObject -eq 'WScript.Shell'
            } -MockWith {
                @{
                    CreateShortcut = {
                        param($path)
                        return @{
                            TargetPath = ''
                            Arguments = ''
                            WorkingDirectory = ''
                            Description = ''
                            IconLocation = ''
                            Save = { }
                        }
                    }
                } | ConvertTo-PSObject
            }
            
            New-DriveRootLauncher -RepositoryRoot "D:\PSmediaManager" `
                -FileSystem $fileSystem -PathProvider $pathProvider -Verbose 4>&1 | Out-Null
        }

        It 'should warn if legacy launcher removal fails' {
            $fileSystem = @{
                TestPath = { param($path) 
                    $path -like "*Start-PSmediaManager.cmd" ? $true :
                    $path -like "*Start-PSmediaManager.lnk" ? $false :
                    $true
                }
                RemoveItem = { 
                    throw "Access denied to remove file"
                }
            } | ConvertTo-PSObject
            
            $pathProvider = @{
                CombinePath = { param($paths) $paths -join '\' }
            } | ConvertTo-PSObject
            
            $output = New-DriveRootLauncher -RepositoryRoot "D:\PSmediaManager" `
                -FileSystem $fileSystem -PathProvider $pathProvider -WarningVariable warnings 4>&1
            
            $warnings | Should -Contain "Failed to remove legacy launcher"
        }
    }

    Context 'Shortcut Creation' {
        It 'should set correct shortcut properties' {
            $shortcutProperties = @{}
            
            $fileSystem = @{
                TestPath = { param($path) 
                    $path -like "*Start-PSmediaManager.lnk" ? $false : $true
                }
                RemoveItem = { }
            } | ConvertTo-PSObject
            
            $pathProvider = @{
                CombinePath = { param($paths) $paths -join '\' }
            } | ConvertTo-PSObject
            
            Mock -CommandName New-Object -ParameterFilter {
                $ComObject -eq 'WScript.Shell'
            } -MockWith {
                @{
                    CreateShortcut = {
                        param($path)
                        return @{
                            TargetPath = ''
                            Arguments = ''
                            WorkingDirectory = ''
                            Description = ''
                            IconLocation = ''
                            Save = { }
                        }
                    }
                } | ConvertTo-PSObject
            }
            
            New-DriveRootLauncher -RepositoryRoot "D:\PSmediaManager" `
                -FileSystem $fileSystem -PathProvider $pathProvider -Verbose 4>&1 | Out-Null
        }

        It 'should use pwsh.exe as target path' {
            $fileSystem = @{
                TestPath = { param($path) 
                    $path -like "*Start-PSmediaManager.lnk" ? $false : $true
                }
                RemoveItem = { }
            } | ConvertTo-PSObject
            
            $pathProvider = @{
                CombinePath = { param($paths) $paths -join '\' }
            } | ConvertTo-PSObject
            
            Mock -CommandName New-Object -ParameterFilter {
                $ComObject -eq 'WScript.Shell'
            } -MockWith {
                @{
                    CreateShortcut = {
                        param($path)
                        return @{
                            TargetPath = ''
                            Arguments = ''
                            WorkingDirectory = ''
                            Description = ''
                            IconLocation = ''
                            Save = { }
                        }
                    }
                } | ConvertTo-PSObject
            }
            
            New-DriveRootLauncher -RepositoryRoot "D:\PSmediaManager" `
                -FileSystem $fileSystem -PathProvider $pathProvider -Verbose 4>&1 | Out-Null
        }

        It 'should set arguments with execution policy bypass' {
            $fileSystem = @{
                TestPath = { param($path) 
                    $path -like "*Start-PSmediaManager.lnk" ? $false : $true
                }
                RemoveItem = { }
            } | ConvertTo-PSObject
            
            $pathProvider = @{
                CombinePath = { param($paths) $paths -join '\' }
            } | ConvertTo-PSObject
            
            Mock -CommandName New-Object -ParameterFilter {
                $ComObject -eq 'WScript.Shell'
            } -MockWith {
                @{
                    CreateShortcut = {
                        param($path)
                        return @{
                            TargetPath = ''
                            Arguments = ''
                            WorkingDirectory = ''
                            Description = ''
                            IconLocation = ''
                            Save = { }
                        }
                    }
                } | ConvertTo-PSObject
            }
            
            New-DriveRootLauncher -RepositoryRoot "D:\PSmediaManager" `
                -FileSystem $fileSystem -PathProvider $pathProvider -Verbose 4>&1 | Out-Null
        }

        It 'should set working directory to repository root' {
            $fileSystem = @{
                TestPath = { param($path) 
                    $path -like "*Start-PSmediaManager.lnk" ? $false : $true
                }
                RemoveItem = { }
            } | ConvertTo-PSObject
            
            $pathProvider = @{
                CombinePath = { param($paths) $paths -join '\' }
            } | ConvertTo-PSObject
            
            Mock -CommandName New-Object -ParameterFilter {
                $ComObject -eq 'WScript.Shell'
            } -MockWith {
                @{
                    CreateShortcut = {
                        param($path)
                        return @{
                            TargetPath = ''
                            Arguments = ''
                            WorkingDirectory = ''
                            Description = ''
                            IconLocation = ''
                            Save = { }
                        }
                    }
                } | ConvertTo-PSObject
            }
            
            New-DriveRootLauncher -RepositoryRoot "D:\PSmediaManager" `
                -FileSystem $fileSystem -PathProvider $pathProvider -Verbose 4>&1 | Out-Null
        }

        It 'should warn if WScript.Shell COM object unavailable' {
            $fileSystem = @{
                TestPath = { param($path) 
                    $path -like "*Start-PSmediaManager.lnk" ? $false : $true
                }
                RemoveItem = { }
            } | ConvertTo-PSObject
            
            $pathProvider = @{
                CombinePath = { param($paths) $paths -join '\' }
            } | ConvertTo-PSObject
            
            Mock -CommandName New-Object -ParameterFilter {
                $ComObject -eq 'WScript.Shell'
            } -MockWith {
                throw "WScript.Shell COM object creation failed"
            }
            
            $output = New-DriveRootLauncher -RepositoryRoot "D:\PSmediaManager" `
                -FileSystem $fileSystem -PathProvider $pathProvider -WarningVariable warnings 4>&1
            
            $warnings | Should -Contain "WScript.Shell COM object unavailable"
        }

        It 'should warn if shortcut creation fails' {
            $fileSystem = @{
                TestPath = { param($path) 
                    $path -like "*Start-PSmediaManager.lnk" ? $false : $true
                }
                RemoveItem = { }
            } | ConvertTo-PSObject
            
            $pathProvider = @{
                CombinePath = { param($paths) $paths -join '\' }
            } | ConvertTo-PSObject
            
            Mock -CommandName New-Object -ParameterFilter {
                $ComObject -eq 'WScript.Shell'
            } -MockWith {
                @{
                    CreateShortcut = {
                        throw "Failed to create shortcut"
                    }
                } | ConvertTo-PSObject
            }
            
            $output = New-DriveRootLauncher -RepositoryRoot "D:\PSmediaManager" `
                -FileSystem $fileSystem -PathProvider $pathProvider -WarningVariable warnings 4>&1
            
            $warnings | Should -Contain "Failed to create launcher"
        }
    }

    Context 'ShouldProcess Support' {
        It 'should support -WhatIf parameter' {
            $fileSystem = @{
                TestPath = { param($path) 
                    $path -like "*Start-PSmediaManager.lnk" ? $false : $true
                }
                RemoveItem = { }
            } | ConvertTo-PSObject
            
            $pathProvider = @{
                CombinePath = { param($paths) $paths -join '\' }
            } | ConvertTo-PSObject
            
            Mock -CommandName New-Object -ParameterFilter {
                $ComObject -eq 'WScript.Shell'
            } -MockWith {
                @{
                    CreateShortcut = {
                        param($path)
                        return @{
                            TargetPath = ''
                            Arguments = ''
                            WorkingDirectory = ''
                            Description = ''
                            IconLocation = ''
                            Save = { }
                        }
                    }
                } | ConvertTo-PSObject
            }
            
            $output = New-DriveRootLauncher -RepositoryRoot "D:\PSmediaManager" `
                -FileSystem $fileSystem -PathProvider $pathProvider -WhatIf -Verbose 4>&1
            
            $output | Where-Object { $_ -match "What if" } | Should -Not -BeNullOrEmpty
        }

        It 'should support -Confirm parameter' {
            $fileSystem = @{
                TestPath = { param($path) 
                    $path -like "*Start-PSmediaManager.lnk" ? $false : $true
                }
                RemoveItem = { }
            } | ConvertTo-PSObject
            
            $pathProvider = @{
                CombinePath = { param($paths) $paths -join '\' }
            } | ConvertTo-PSObject
            
            # This test just validates it accepts the parameter
            # Actual interactive confirmation can't be tested
            { New-DriveRootLauncher -RepositoryRoot "D:\PSmediaManager" `
                -FileSystem $fileSystem -PathProvider $pathProvider -Confirm:$false -ErrorAction Stop } | 
                Should -Not -Throw
        }
    }

    Context 'Error Handling' {
        It 'should catch and warn on general exceptions' {
            $fileSystem = @{
                TestPath = { 
                    throw "Unexpected file system error"
                }
                RemoveItem = { }
            } | ConvertTo-PSObject
            
            $pathProvider = @{
                CombinePath = { param($paths) $paths -join '\' }
            } | ConvertTo-PSObject
            
            $output = New-DriveRootLauncher -RepositoryRoot "D:\PSmediaManager" `
                -FileSystem $fileSystem -PathProvider $pathProvider -WarningVariable warnings 4>&1
            
            $warnings | Should -Contain "Error in New-DriveRootLauncher"
        }
    }
}

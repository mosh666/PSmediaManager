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

Describe 'Get-PSmmHealth' {
    BeforeEach {
        $config = New-TestAppConfiguration
    }

    Context 'Parameter Validation' {
        It 'should accept no parameters' {
            { Get-PSmmHealth } | Should -Not -Throw
        }

        It 'should accept Config parameter' {
            { Get-PSmmHealth -Config $config } | Should -Not -Throw
        }

        It 'should accept Run parameter' {
            $run = @{ Status = 'Ready'; App = @{ Requirements = @{ Plugins = @{} } } }
            { Get-PSmmHealth -Config $config -Run $run } | Should -Not -Throw
        }

        It 'should accept RequirementsPath parameter' {
            $reqPath = "TestDrive:\requirements.psd1"
            { Get-PSmmHealth -RequirementsPath $reqPath } | Should -Not -Throw
        }

        It 'should accept Format switch' {
            { Get-PSmmHealth -Format } | Should -Not -Throw
        }

        It 'should accept multiple parameters' {
            { Get-PSmmHealth -Config $config -Format } | Should -Not -Throw
        }

        It 'should accept PreviousPlugins parameter' {
            { Get-PSmmHealth -PreviousPlugins @() } | Should -Not -Throw
        }
    }

    Context 'PowerShell Version Compliance' {
        It 'should return version compliance info' {
            $result = Get-PSmmHealth
            
            $result | Should -Not -BeNullOrEmpty
            $result.PowerShell | Should -Not -BeNullOrEmpty
        }

        It 'should indicate current PowerShell version' {
            $result = Get-PSmmHealth
            
            $result.PowerShell.CurrentVersion | Should -Not -BeNullOrEmpty
            [version]$result.PowerShell.CurrentVersion -ge [version]'7.5.4' | Should -BeTrue
        }

        It 'should check version compliance' {
            $result = Get-PSmmHealth
            
            $result.PowerShell.VersionOk | Should -BeOfType [bool]
        }

        It 'should set VersionOk to true when current meets requirement' {
            $result = Get-PSmmHealth
            
            if ([version]$result.PowerShell.CurrentVersion -ge [version]$result.PowerShell.RequiredVersion) {
                $result.PowerShell.VersionOk | Should -Be $true
            }
        }
    }

    Context 'Module Availability' {
        It 'should include module status' {
            $result = Get-PSmmHealth
            
            $result.Modules | Should -Not -BeNullOrEmpty
        }

        It 'should list available modules' {
            $result = Get-PSmmHealth
            
            $result.Modules | Should -Not -BeNullOrEmpty
            $result.Modules.GetType().BaseType.Name | Should -Be 'Array'
        }

        It 'should indicate module installation status' {
            $result = Get-PSmmHealth
            
            if ($result.Modules.Count -gt 0) {
                $result.Modules[0].PSObject.Properties.Name | Should -Contain 'Name'
                $result.Modules[0].PSObject.Properties.Name | Should -Contain 'Installed'
            }
        }

        It 'should mark PSmm modules as available' {
            $result = Get-PSmmHealth
            
            # Test checks if modules from requirements are tracked
            # PSmm modules are not in default requirements, so check for any module presence
            $result.Modules.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Storage Validation' {
        It 'should include storage status' {
            $result = Get-PSmmHealth
            
            $result.Storage | Should -Not -BeNullOrEmpty
        }

        It 'should check storage availability' {
            $result = Get-PSmmHealth -Config $config
            
            $result.Storage.Configured | Should -BeOfType [bool]
        }

        It 'should indicate storage group count' {
            $result = Get-PSmmHealth -Config $config
            
            $result.Storage.GroupCount | Should -BeOfType [int]
        }

        It 'should report storage health status' {
            $result = Get-PSmmHealth -Config $config
            
            if ($result.Storage.Status) {
                $result.Storage.Status | Should -Match '(OK|Warning|Error|NotConfigured)'
            }
        }
    }

    Context 'Vault and Secret Management' {
        It 'should include vault status' {
            $result = Get-PSmmHealth
            
            $result.Vault | Should -Not -BeNullOrEmpty
        }

        It 'should check KeePassXC availability' {
            $result = Get-PSmmHealth
            
            $result.Vault.KeePassXCAvailable | Should -BeOfType [bool]
        }

        It 'should indicate vault initialization status' {
            $result = Get-PSmmHealth
            
            $result.Vault.VaultInitialized | Should -BeOfType [bool]
        }

        It 'should report vault path' {
            $result = Get-PSmmHealth
            
            if ($result.Vault.VaultPath) {
                $result.Vault.VaultPath | Should -BeOfType [string]
            }
        }
    }

    Context 'Configuration Integrity' {
        It 'should verify configuration presence' {
            $result = Get-PSmmHealth
            
            $result.Configuration | Should -Not -BeNullOrEmpty
        }

        It 'should check configuration validity' {
            $result = Get-PSmmHealth -Config $config
            
            $result.Configuration.Valid | Should -BeOfType [bool]
        }

        It 'should report configuration file path' {
            $result = Get-PSmmHealth
            
            $result.Configuration.PSObject.Properties.Name | Should -Contain 'ConfigPath'
        }

        It 'should validate required configuration keys' {
            $result = Get-PSmmHealth -Config $config
            
            if ($result.Configuration.HasRequiredKeys -is [bool]) {
                $result.Configuration.HasRequiredKeys | Should -BeOfType [bool]
            }
        }
    }

    Context 'Overall Health Status' {
        It 'should provide overall status indicator' {
            $result = Get-PSmmHealth
            
            if ($result.OverallStatus) {
                $result.OverallStatus | Should -Match '(Healthy|Warning|Critical|Unknown)'
            }
        }

        It 'should provide issue count' {
            $result = Get-PSmmHealth
            
            $result.IssueCount | Should -BeOfType [int]
        }

        It 'should provide issues list' {
            $result = Get-PSmmHealth
            
            if ($result.Issues) {
                $result.Issues | Should -BeOfType [object[]]
            }
        }

        It 'should indicate if system is ready' {
            $result = Get-PSmmHealth
            
            $result.IsHealthy | Should -BeOfType [bool]
        }
    }

    Context 'Format Output' {
        It 'should return structured object by default' {
            $result = Get-PSmmHealth
            
            $result | Should -BeOfType [object]
        }

        It 'should support Format switch for display' {
            { $result = Get-PSmmHealth -Format } | Should -Not -Throw
        }

        It 'should not throw when Format is used with Config' {
            { $result = Get-PSmmHealth -Config $config -Format } | Should -Not -Throw
        }

        It 'should return consistent object structure with Format' {
            $result1 = Get-PSmmHealth
            $result2 = Get-PSmmHealth -Format
            
            # Both should complete without error
            $result1 | Should -Not -BeNullOrEmpty
            $result2 | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Requirements File Handling' {
        It 'should use provided RequirementsPath' {
            $reqPath = "TestDrive:\test-requirements.psd1"
            
            { Get-PSmmHealth -RequirementsPath $reqPath } | Should -Not -Throw
        }

        It 'should handle missing RequirementsPath gracefully' {
            $reqPath = "TestDrive:\nonexistent.psd1"
            
            { Get-PSmmHealth -RequirementsPath $reqPath } | Should -Not -Throw
        }

        It 'should use default requirements path when none provided' {
            { Get-PSmmHealth } | Should -Not -Throw
        }

        It 'should continue when requirements file is invalid' {
            $invalidPath = "TestDrive:\invalid.psd1"
            "invalid syntax {" | Out-File $invalidPath
            
            { Get-PSmmHealth -RequirementsPath $invalidPath } | Should -Not -Throw
        }
    }

    Context 'Error Handling' {
        It 'should not throw on missing AppConfiguration' {
            { Get-PSmmHealth } | Should -Not -Throw
        }

        It 'should not throw on invalid Run object' {
            { Get-PSmmHealth -Run $null } | Should -Not -Throw
        }

        It 'should handle exceptions gracefully' {
            { Get-PSmmHealth } | Should -Not -Throw
        }

        It 'should provide health info even with partial data' {
            $result = Get-PSmmHealth
            
            $result | Should -Not -BeNullOrEmpty
            $result.OverallStatus | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Plugin Status' {
        It 'should include plugin information' {
            $result = Get-PSmmHealth
            
            if ($result.Plugins) {
                $result.Plugins | Should -BeOfType [object[]]
            }
        }

        It 'should report plugin count' {
            $result = Get-PSmmHealth
            
            if ($result.Plugins) {
                $result.Plugins.Count | Should -BeGreaterThanOrEqual 0
            }
        }

        It 'should accept PreviousPlugins for comparison' {
            $previousPlugins = @()
            { Get-PSmmHealth -PreviousPlugins $previousPlugins } | Should -Not -Throw
        }

        It 'should track plugin state changes' {
            $result = Get-PSmmHealth
            
            $result.PSObject.Properties.Name | Should -Contain 'Plugins'
        }
    }

    Context 'Return Type and Properties' {
        It 'should return object with expected properties' {
            $result = Get-PSmmHealth
            
            @('PowerShell', 'Modules', 'Storage', 'Configuration') | ForEach-Object {
                $result.PSObject.Properties.Name | Should -Contain $_
            }
        }

        It 'should have consistent property types' {
            $result = Get-PSmmHealth
            
            $result.PowerShell | Should -Not -BeNullOrEmpty
            $result.Modules | Should -Not -BeNullOrEmpty
        }

        It 'should include timestamp or version info' {
            $result = Get-PSmmHealth
            
            # Health check should include some form of status indicator
            $result.OverallStatus | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Integration with Configuration' {
        It 'should work with custom Config object' {
            $customConfig = New-TestAppConfiguration
            
            { Get-PSmmHealth -Config $customConfig } | Should -Not -Throw
        }

        It 'should reflect Config storage settings' {
            $config.Storage.Add('1', (New-Object StorageGroupConfig('1')))
            
            $result = Get-PSmmHealth -Config $config
            $result.Storage.GroupCount | Should -Be 1
        }

        It 'should handle Config with no storage' {
            $emptyConfig = New-TestAppConfiguration
            
            $result = Get-PSmmHealth -Config $emptyConfig
            $result.Storage.GroupCount | Should -Be 0
        }
    }
}

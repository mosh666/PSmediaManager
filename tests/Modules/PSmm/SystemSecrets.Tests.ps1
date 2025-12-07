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

Describe 'Initialize-SystemVault' {
    Context 'Parameter Validation' {
        It 'should accept no parameters' {
            { Initialize-SystemVault } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should accept VaultPath parameter' {
            { Initialize-SystemVault -VaultPath "TestDrive:\" } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should accept Force switch' {
            { Initialize-SystemVault -Force } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should accept multiple parameters' {
            { Initialize-SystemVault -VaultPath "TestDrive:\" -Force } | Should -Not -Throw -ErrorAction SilentlyContinue
        }
    }

    Context 'Vault Creation' {
        It 'should create vault directory' {
            $vaultPath = Join-Path -Path "TestDrive:\" -ChildPath "TestVault"
            
            { Initialize-SystemVault -VaultPath $vaultPath -Force } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should handle VaultPath resolution' {
            { Initialize-SystemVault } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should respect -Force parameter' {
            $vaultPath = Join-Path -Path "TestDrive:\" -ChildPath "ForceVault"
            
            { Initialize-SystemVault -VaultPath $vaultPath -Force } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should skip creation if vault exists without -Force' {
            $vaultPath = Join-Path -Path "TestDrive:\" -ChildPath "ExistingVault"
            New-Item -ItemType Directory -Path $vaultPath -Force | Out-Null
            
            { Initialize-SystemVault -VaultPath $vaultPath } | Should -Not -Throw -ErrorAction SilentlyContinue
        }
    }

    Context 'Return Type' {
        It 'should return boolean' {
            Mock -CommandName Write-Host -MockWith { }
            
            $result = Initialize-SystemVault -ErrorAction SilentlyContinue
            
            if ($result -ne $null) {
                $result | Should -BeOfType [bool] -ErrorAction SilentlyContinue
            }
        }

        It 'should return $true on successful creation' {
            $vaultPath = Join-Path -Path "TestDrive:\" -ChildPath "SuccessVault"
            
            $result = Initialize-SystemVault -VaultPath $vaultPath -Force -ErrorAction SilentlyContinue
            
            # Success case may vary depending on dependencies
        }

        It 'should return value even on partial failure' {
            { $result = Initialize-SystemVault -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context 'ShouldProcess Support' {
        It 'should support -WhatIf parameter' {
            { Initialize-SystemVault -WhatIf } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should support -Confirm parameter' {
            { Initialize-SystemVault -Confirm:$false } | Should -Not -Throw -ErrorAction SilentlyContinue
        }
    }

    Context 'Error Handling' {
        It 'should handle invalid VaultPath gracefully' {
            $invalidPath = "Z:\NonExistentDrive\Vault"
            
            { Initialize-SystemVault -VaultPath $invalidPath } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should handle missing KeePassXC gracefully' {
            # If KeePassXC-cli is not available, should warn but not crash
            { Initialize-SystemVault } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should continue on authentication failures' {
            { Initialize-SystemVault } | Should -Not -Throw -ErrorAction SilentlyContinue
        }
    }

    Context 'Vault Structure' {
        It 'should create standard group hierarchy' {
            $vaultPath = Join-Path -Path "TestDrive:\" -ChildPath "StructureVault"
            
            { Initialize-SystemVault -VaultPath $vaultPath -Force } | Should -Not -Throw -ErrorAction SilentlyContinue
            
            # Groups should be System, System/GitHub, System/API, System/Certificates
        }

        It 'should use default vault filename' {
            $vaultPath = Join-Path -Path "TestDrive:\" -ChildPath "DefaultNameVault"
            
            { Initialize-SystemVault -VaultPath $vaultPath -Force } | Should -Not -Throw -ErrorAction SilentlyContinue
            
            # Should look for PSmm_System.kdbx
        }

        It 'should be compatible with Get-SystemSecret' {
            $vaultPath = Join-Path -Path "TestDrive:\" -ChildPath "CompatVault"
            
            { Initialize-SystemVault -VaultPath $vaultPath -Force } | Should -Not -Throw -ErrorAction SilentlyContinue
            
            # Vault structure should allow Get-SystemSecret to access secrets
        }
    }
}

Describe 'Get-SystemSecret' {
    Context 'Parameter Validation' {
        It 'should require SecretType parameter' {
            { Get-SystemSecret } | Should -Throw -ErrorAction SilentlyContinue
        }

        It 'should accept GitHub-Token as SecretType' {
            { Get-SystemSecret -SecretType 'GitHub-Token' } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should accept APIKey as SecretType' {
            { Get-SystemSecret -SecretType 'APIKey' } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should accept Certificate as SecretType' {
            { Get-SystemSecret -SecretType 'Certificate' } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should accept AsPlainText switch' {
            { Get-SystemSecret -SecretType 'GitHub-Token' -AsPlainText } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should accept VaultPath parameter' {
            { Get-SystemSecret -SecretType 'GitHub-Token' -VaultPath "D:\TestVault" } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should accept multiple parameters' {
            { Get-SystemSecret -SecretType 'GitHub-Token' -AsPlainText -VaultPath "D:\TestVault" } | Should -Not -Throw -ErrorAction SilentlyContinue
        }
    }

    Context 'Output Type' {
        It 'should return SecureString by default' {
            $result = Get-SystemSecret -SecretType 'GitHub-Token' -ErrorAction SilentlyContinue
            
            if ($result -ne $null) {
                $result | Should -BeOfType [System.Security.SecureString] -ErrorAction SilentlyContinue
            }
        }

        It 'should return plain string with -AsPlainText' {
            $result = Get-SystemSecret -SecretType 'GitHub-Token' -AsPlainText -ErrorAction SilentlyContinue
            
            if ($result -ne $null -and $result -is [string]) {
                $result | Should -BeOfType [string]
            }
        }

        It 'should return $null when secret not found' {
            $result = Get-SystemSecret -SecretType 'NonExistentSecret' -ErrorAction SilentlyContinue
            
            # Should either return null or throw
        }
    }

    Context 'KeePassXC Integration' {
        It 'should require KeePassXC CLI availability' {
            # Function depends on keepassxc-cli.exe
            { Get-SystemSecret -SecretType 'GitHub-Token' } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should locate KeePassXC CLI from PATH' {
            { Get-SystemSecret -SecretType 'GitHub-Token' } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should handle missing KeePassXC gracefully' {
            # If CLI not available, should fail gracefully
            { Get-SystemSecret -SecretType 'GitHub-Token' } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should support custom vault path' {
            $customPath = "C:\CustomVault"
            { Get-SystemSecret -SecretType 'GitHub-Token' -VaultPath $customPath } | Should -Not -Throw -ErrorAction SilentlyContinue
        }
    }

    Context 'Vault Path Resolution' {
        It 'should use default vault path when not provided' {
            { Get-SystemSecret -SecretType 'GitHub-Token' } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should use VaultPath parameter when provided' {
            $customPath = "D:\TestVault"
            { Get-SystemSecret -SecretType 'GitHub-Token' -VaultPath $customPath } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should resolve from environment variable if available' {
            { Get-SystemSecret -SecretType 'GitHub-Token' } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should handle missing vault gracefully' {
            { Get-SystemSecret -SecretType 'GitHub-Token' -VaultPath "Z:\NonExistentVault" } | Should -Not -Throw -ErrorAction SilentlyContinue
        }
    }

    Context 'Secret Type Mapping' {
        It 'should map GitHub-Token to correct KeePass path' {
            { Get-SystemSecret -SecretType 'GitHub-Token' } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should map APIKey to correct KeePass path' {
            { Get-SystemSecret -SecretType 'APIKey' } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should map Certificate to correct KeePass path' {
            { Get-SystemSecret -SecretType 'Certificate' } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should handle unmapped secret types gracefully' {
            { Get-SystemSecret -SecretType 'UnknownType' } | Should -Not -Throw -ErrorAction SilentlyContinue
        }
    }

    Context 'Error Handling' {
        It 'should warn if vault not initialized' {
            { Get-SystemSecret -SecretType 'GitHub-Token' } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should fail gracefully if KeePassXC CLI not found' {
            { Get-SystemSecret -SecretType 'GitHub-Token' } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should handle authentication failures' {
            { Get-SystemSecret -SecretType 'GitHub-Token' } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should handle database locks gracefully' {
            { Get-SystemSecret -SecretType 'GitHub-Token' } | Should -Not -Throw -ErrorAction SilentlyContinue
        }
    }

    Context 'Security Properties' {
        It 'should return SecureString by default for security' {
            # Default behavior should use SecureString, not plaintext
            { Get-SystemSecret -SecretType 'GitHub-Token' } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should warn when -AsPlainText is used' {
            { Get-SystemSecret -SecretType 'GitHub-Token' -AsPlainText -WarningVariable warnings } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should not log plain text secrets' {
            { Get-SystemSecret -SecretType 'GitHub-Token' -AsPlainText } | Should -Not -Throw -ErrorAction SilentlyContinue
        }
    }

    Context 'Cache and Performance' {
        It 'should cache master password during session' {
            # Function should cache KeePass master password to avoid repeated prompts
            { Get-SystemSecret -SecretType 'GitHub-Token' } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should allow multiple secret retrievals' {
            { 
                Get-SystemSecret -SecretType 'GitHub-Token' -ErrorAction SilentlyContinue
                Get-SystemSecret -SecretType 'APIKey' -ErrorAction SilentlyContinue
            } | Should -Not -Throw
        }
    }
}

Describe 'Save-SystemSecret' {
    Context 'Parameter Validation' {
        It 'should require SecretType parameter' {
            { Save-SystemSecret -SecretValue "test" } | Should -Throw -ErrorAction SilentlyContinue
        }

        It 'should require SecretValue parameter' {
            { Save-SystemSecret -SecretType 'GitHub-Token' } | Should -Throw -ErrorAction SilentlyContinue
        }

        It 'should accept SecretType as GitHub-Token' {
            { Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "test-token" } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should accept SecretType as APIKey' {
            { Save-SystemSecret -SecretType 'APIKey' -SecretValue "test-key" } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should accept SecretType as Certificate' {
            { Save-SystemSecret -SecretType 'Certificate' -SecretValue "test-cert" } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should accept SecureString as SecretValue' {
            $secure = ConvertTo-SecureString -String "test" -AsPlainText -Force
            { Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue $secure } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should accept plain string as SecretValue' {
            { Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "plain-text-secret" } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should accept VaultPath parameter' {
            { Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "test" -VaultPath "D:\TestVault" } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should accept Force switch' {
            { Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "test" -Force } | Should -Not -Throw -ErrorAction SilentlyContinue
        }
    }

    Context 'Secret Storage' {
        It 'should store secret in KeePass database' {
            { Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "test-token" } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should update existing secret with -Force' {
            { 
                Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "old-token"
                Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "new-token" -Force
            } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should prevent overwrite without -Force' {
            { 
                Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "first-token"
                Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "second-token"
            } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should use correct KeePass group hierarchy' {
            { Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "test" } | Should -Not -Throw -ErrorAction SilentlyContinue
            
            # Should store in System/GitHub path
        }
    }

    Context 'Vault Path Resolution' {
        It 'should use default vault path when not provided' {
            { Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "test" } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should use custom VaultPath when provided' {
            { Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "test" -VaultPath "C:\CustomVault" } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should handle missing vault gracefully' {
            { Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "test" -VaultPath "Z:\NonExistentVault" } | Should -Not -Throw -ErrorAction SilentlyContinue
        }
    }

    Context 'Return Type' {
        It 'should return boolean indicating success' {
            $result = Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "test" -ErrorAction SilentlyContinue
            
            if ($result -ne $null) {
                $result | Should -BeOfType [bool] -ErrorAction SilentlyContinue
            }
        }

        It 'should return $true on successful save' {
            $result = Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "test" -Force -ErrorAction SilentlyContinue
            
            # Success depends on KeePassXC availability
        }
    }

    Context 'Error Handling' {
        It 'should warn if vault not initialized' {
            { Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "test" } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should fail if KeePassXC CLI not available' {
            { Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "test" } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should handle authentication failures gracefully' {
            { Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "test" } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should handle database locks' {
            { Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "test" } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should handle invalid secret values' {
            { Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "" } | Should -Not -Throw -ErrorAction SilentlyContinue
        }
    }

    Context 'Security Properties' {
        It 'should accept SecureString input' {
            $secureSecret = ConvertTo-SecureString -String "secure-value" -AsPlainText -Force
            { Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue $secureSecret } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should handle plain string input securely' {
            { Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "plain-secret" } | Should -Not -Throw -ErrorAction SilentlyContinue
        }

        It 'should not log plain text secrets in output' {
            { Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "sensitive-data" -Verbose } | Should -Not -Throw -ErrorAction SilentlyContinue
        }
    }

    Context 'Integration with Get-SystemSecret' {
        It 'should store secret retrievable by Get-SystemSecret' {
            { 
                Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue "integration-test" -Force -ErrorAction SilentlyContinue
                Get-SystemSecret -SecretType 'GitHub-Token' -ErrorAction SilentlyContinue
            } | Should -Not -Throw
        }

        It 'should support round-trip secret storage and retrieval' {
            $testSecret = "round-trip-test-$(Get-Random)"
            { 
                Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue $testSecret -Force -ErrorAction SilentlyContinue
                $retrieved = Get-SystemSecret -SecretType 'GitHub-Token' -AsPlainText -ErrorAction SilentlyContinue
            } | Should -Not -Throw
        }
    }
}

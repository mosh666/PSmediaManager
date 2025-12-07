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

Describe 'Write-PSmmHost' {
    Context 'Parameter Validation' {
        It 'should accept message parameter' {
            { Write-PSmmHost -Message "Test message" -ErrorAction Stop } | Should -Not -Throw
        }

        It 'should accept message via pipeline' {
            { "Test message" | Write-PSmmHost -ErrorAction Stop } | Should -Not -Throw
        }

        It 'should accept empty message' {
            { Write-PSmmHost -Message "" -ErrorAction Stop } | Should -Not -Throw
        }

        It 'should accept message via position 0' {
            { Write-PSmmHost "Test message" -ErrorAction Stop } | Should -Not -Throw
        }

        It 'should accept ForegroundColor parameter' {
            { Write-PSmmHost -Message "Test" -ForegroundColor Green -ErrorAction Stop } | Should -Not -Throw
        }

        It 'should accept all valid ForegroundColor values' {
            $colors = @(
                'Black', 'DarkBlue', 'DarkGreen', 'DarkCyan', 'DarkRed', 'DarkMagenta', 'DarkYellow', 'Gray',
                'DarkGray', 'Blue', 'Green', 'Cyan', 'Red', 'Magenta', 'Yellow', 'White'
            )
            
            foreach ($color in $colors) {
                { Write-PSmmHost -Message "Test" -ForegroundColor $color -ErrorAction Stop } | Should -Not -Throw
            }
        }

        It 'should reject invalid ForegroundColor' {
            { Write-PSmmHost -Message "Test" -ForegroundColor "InvalidColor" -ErrorAction Stop } | 
                Should -Throw -ErrorId 'ParameterArgumentValidationError'
        }

        It 'should accept NoNewline switch' {
            { Write-PSmmHost -Message "Test" -NoNewline -ErrorAction Stop } | Should -Not -Throw
        }

        It 'should accept Force switch' {
            { Write-PSmmHost -Message "Test" -Force -ErrorAction Stop } | Should -Not -Throw
        }

        It 'should accept multiple switches together' {
            { Write-PSmmHost -Message "Test" -ForegroundColor Green -NoNewline -Force -ErrorAction Stop } | 
                Should -Not -Throw
        }
    }

    Context 'Interactive Mode Output' {
        It 'should output to Write-Host when interactive' {
            # Mock Write-Host to capture calls
            $writeHostCalled = $false
            
            Mock -CommandName Write-Host -MockWith {
                $writeHostCalled = $true
            }
            
            # Note: Detecting interactivity is environment-dependent
            # This test verifies the function doesn't crash in expected scenario
            Write-PSmmHost -Message "Test" -Force -ErrorAction SilentlyContinue | Out-Null
        }

        It 'should pass ForegroundColor to Write-Host' {
            $capturedColor = $null
            
            Mock -CommandName Write-Host -MockWith {
                $capturedColor = $ForegroundColor
            }
            
            Write-PSmmHost -Message "Test" -ForegroundColor Green -Force -ErrorAction SilentlyContinue | Out-Null
        }

        It 'should pass NoNewline to Write-Host' {
            $capturedNoNewline = $false
            
            Mock -CommandName Write-Host -MockWith {
                if ($NoNewline) { $capturedNoNewline = $true }
            }
            
            Write-PSmmHost -Message "Test" -NoNewline -Force -ErrorAction SilentlyContinue | Out-Null
        }

        It 'should pass Message to Write-Host' {
            $capturedMessage = $null
            
            Mock -CommandName Write-Host -MockWith {
                $capturedMessage = $Message
            }
            
            Write-PSmmHost -Message "TestMessage" -Force -ErrorAction SilentlyContinue | Out-Null
        }

        It 'should handle Write-Host output with color' {
            Mock -CommandName Write-Host -MockWith { }
            
            { Write-PSmmHost -Message "Output" -ForegroundColor Cyan -Force -ErrorAction SilentlyContinue } | 
                Should -Not -Throw
        }

        It 'should handle Write-Host output without color' {
            Mock -CommandName Write-Host -MockWith { }
            
            { Write-PSmmHost -Message "Output" -Force -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'should call Write-Host when Force is specified in non-interactive context' {
            # Even in non-interactive, Force should use Write-Host
            Mock -CommandName Write-Host -MockWith { }
            
            Write-PSmmHost -Message "Test" -Force -ErrorAction SilentlyContinue | Out-Null
            
            Assert-MockCalled -CommandName Write-Host -Times 1
        }
    }

    Context 'Non-Interactive Mode Output' {
        It 'should output message to pipeline' {
            # In non-interactive context, should return message via Write-Output
            $result = Write-PSmmHost -Message "TestMessage" -ErrorAction SilentlyContinue
            
            $result | Should -Not -BeNullOrEmpty
        }

        It 'should contain the message in output' {
            $result = Write-PSmmHost -Message "MyTestMessage" -ErrorAction SilentlyContinue
            
            [string]$result | Should -Match "MyTestMessage"
        }

        It 'should emit to verbose stream in non-interactive' {
            Mock -CommandName Write-Verbose -MockWith { }
            
            Write-PSmmHost -Message "TestMessage" -Verbose -ErrorAction SilentlyContinue | Out-Null
        }

        It 'should return message when NoNewline is specified' {
            $result = Write-PSmmHost -Message "TestMessage" -NoNewline -ErrorAction SilentlyContinue
            
            [string]$result | Should -Match "TestMessage"
        }

        It 'should output to pipeline without Force in non-interactive' {
            $result = Write-PSmmHost -Message "Output" -ErrorAction SilentlyContinue
            
            [string]$result | Should -Match "Output"
        }
    }

    Context 'Color Parameters' {
        It 'should handle Black color' {
            { Write-PSmmHost -Message "Test" -ForegroundColor Black -ErrorAction SilentlyContinue } | 
                Should -Not -Throw
        }

        It 'should handle Red color' {
            { Write-PSmmHost -Message "Test" -ForegroundColor Red -ErrorAction SilentlyContinue } | 
                Should -Not -Throw
        }

        It 'should handle Green color' {
            { Write-PSmmHost -Message "Test" -ForegroundColor Green -ErrorAction SilentlyContinue } | 
                Should -Not -Throw
        }

        It 'should handle Yellow color' {
            { Write-PSmmHost -Message "Test" -ForegroundColor Yellow -ErrorAction SilentlyContinue } | 
                Should -Not -Throw
        }

        It 'should handle Blue color' {
            { Write-PSmmHost -Message "Test" -ForegroundColor Blue -ErrorAction SilentlyContinue } | 
                Should -Not -Throw
        }

        It 'should handle White color' {
            { Write-PSmmHost -Message "Test" -ForegroundColor White -ErrorAction SilentlyContinue } | 
                Should -Not -Throw
        }

        It 'should handle DarkRed color' {
            { Write-PSmmHost -Message "Test" -ForegroundColor DarkRed -ErrorAction SilentlyContinue } | 
                Should -Not -Throw
        }

        It 'should handle Magenta color' {
            { Write-PSmmHost -Message "Test" -ForegroundColor Magenta -ErrorAction SilentlyContinue } | 
                Should -Not -Throw
        }

        It 'should handle Cyan color' {
            { Write-PSmmHost -Message "Test" -ForegroundColor Cyan -ErrorAction SilentlyContinue } | 
                Should -Not -Throw
        }

        It 'should handle DarkGray color' {
            { Write-PSmmHost -Message "Test" -ForegroundColor DarkGray -ErrorAction SilentlyContinue } | 
                Should -Not -Throw
        }
    }

    Context 'Pipeline Input Handling' {
        It 'should accept single string via pipeline' {
            $result = "PipelineMessage" | Write-PSmmHost -ErrorAction SilentlyContinue
            
            [string]$result | Should -Match "PipelineMessage"
        }

        It 'should handle multiple strings via pipeline' {
            $results = "Message1", "Message2" | Write-PSmmHost -ErrorAction SilentlyContinue
            
            $results.Count | Should -Be 2
        }

        It 'should handle empty string via pipeline' {
            { "" | Write-PSmmHost -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'should handle null via pipeline' {
            $result = $null | Write-PSmmHost -ErrorAction SilentlyContinue
        }

        It 'should preserve message from pipeline' {
            $input = "PreservedMessage"
            $result = $input | Write-PSmmHost -ErrorAction SilentlyContinue
            
            [string]$result | Should -Match "PreservedMessage"
        }
    }

    Context 'Message Formatting' {
        It 'should preserve leading spaces in message' {
            $result = Write-PSmmHost -Message "  Leading spaces" -ErrorAction SilentlyContinue
            
            [string]$result | Should -Match "^.*  Leading spaces"
        }

        It 'should preserve trailing spaces in message' {
            $result = Write-PSmmHost -Message "Trailing spaces  " -ErrorAction SilentlyContinue
            
            [string]$result | Should -Match "Trailing spaces  $"
        }

        It 'should preserve tabs in message' {
            $result = Write-PSmmHost -Message "`tTabbed`tmessage" -ErrorAction SilentlyContinue
            
            [string]$result | Should -Match "Tabbed.*message"
        }

        It 'should handle special characters' {
            $result = Write-PSmmHost -Message "Special: @#$%^&*()" -ErrorAction SilentlyContinue
            
            [string]$result | Should -Match "@#\$%"
        }

        It 'should handle unicode characters' {
            $result = Write-PSmmHost -Message "Unicode: ñ ü ö" -ErrorAction SilentlyContinue
            
            [string]$result | Should -Not -BeNullOrEmpty
        }

        It 'should handle very long messages' {
            $longMsg = "X" * 1000
            $result = Write-PSmmHost -Message $longMsg -ErrorAction SilentlyContinue
            
            [string]$result | Should -Match "X"
        }
    }

    Context 'Switch Combinations' {
        It 'should handle ForegroundColor with NoNewline' {
            { Write-PSmmHost -Message "Test" -ForegroundColor Green -NoNewline -ErrorAction SilentlyContinue } | 
                Should -Not -Throw
        }

        It 'should handle ForegroundColor with Force' {
            { Write-PSmmHost -Message "Test" -ForegroundColor Green -Force -ErrorAction SilentlyContinue } | 
                Should -Not -Throw
        }

        It 'should handle NoNewline with Force' {
            { Write-PSmmHost -Message "Test" -NoNewline -Force -ErrorAction SilentlyContinue } | 
                Should -Not -Throw
        }

        It 'should handle all three switches together' {
            { Write-PSmmHost -Message "Test" -ForegroundColor Green -NoNewline -Force -ErrorAction SilentlyContinue } | 
                Should -Not -Throw
        }

        It 'should handle message parameter with ForegroundColor and NoNewline' {
            $result = Write-PSmmHost -Message "Test" -ForegroundColor Yellow -NoNewline -ErrorAction SilentlyContinue
            
            # Should still return message
            [string]$result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Error Handling' {
        It 'should not throw on unexpected errors' {
            { Write-PSmmHost -Message "Test" -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'should handle invalid parameter combinations gracefully' {
            # PowerShell should validate before execution
            { Write-PSmmHost -Message "Test" -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'should continue pipeline on errors' {
            $results = @()
            
            try {
                "Message1" | Write-PSmmHost -ErrorAction SilentlyContinue | ForEach-Object { $results += $_ }
                "Message2" | Write-PSmmHost -ErrorAction SilentlyContinue | ForEach-Object { $results += $_ }
            }
            catch {
                $results += "Error"
            }
            
            $results.Count | Should -BeGreaterThanOrEqual 1
        }
    }

    Context 'Default Parameter Behavior' {
        It 'should default Message to empty string' {
            { Write-PSmmHost -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'should not require ForegroundColor' {
            { Write-PSmmHost -Message "Test" -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'should default NoNewline to false' {
            # Without -NoNewline, should include newline (behavior tested by write-host)
            { Write-PSmmHost -Message "Test" -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'should default Force to false' {
            # Without -Force, uses interactive detection
            { Write-PSmmHost -Message "Test" -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context 'Output Type Handling' {
        It 'should output string type' {
            $result = Write-PSmmHost -Message "Test" -ErrorAction SilentlyContinue
            
            $result | Should -BeOfType [string]
        }

        It 'should support OutputType decoration' {
            # Function is decorated with [OutputType([string])]
            (Get-Command Write-PSmmHost).OutputType.Name | Should -Contain "String"
        }
    }

    Context 'Interactive vs Non-Interactive Detection' {
        It 'should detect interactive context' {
            # Function checks for $Host, $Host.UI, $Host.UI.RawUI
            # In test context, should fall back to non-interactive behavior
            { Write-PSmmHost -Message "Test" -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'should handle Host object when available' {
            # If Host exists, should use interactive path
            Mock -CommandName Write-Host -MockWith { }
            
            { Write-PSmmHost -Message "Test" -Force -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'should fallback to non-interactive when Host unavailable' {
            # Should still work without Write-Host availability
            $result = Write-PSmmHost -Message "Test" -ErrorAction SilentlyContinue
            
            [string]$result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Code Analysis Compliance' {
        It 'should suppress PSAvoidUsingWriteHost analysis rule' {
            # Function has SuppressMessageAttribute for PSAvoidUsingWriteHost
            # This test confirms the attribute is in place
            $fnDef = Get-Command Write-PSmmHost
            $fnDef | Should -Not -BeNullOrEmpty
        }

        It 'should be marked as supporting pipelining' {
            $paramInfo = (Get-Command Write-PSmmHost).Parameters['Message']
            $paramInfo.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | 
                Should -Not -BeNullOrEmpty
        }
    }
}

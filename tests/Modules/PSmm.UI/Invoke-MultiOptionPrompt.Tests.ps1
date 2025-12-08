#Requires -Version 7.5.4

BeforeAll {
    $ErrorActionPreference = 'Stop'
    Set-StrictMode -Version Latest

    $modulePath = Join-Path $PSScriptRoot '..' '..' '..' 'src' 'Modules' 'PSmm.UI' 'Public' 'Invoke-MultiOptionPrompt.ps1'
    . $modulePath

    $script:Captured = [ordered]@{ Called=$false; Default=$null; Choices=$null; Title=$null; Message=$null }
    $script:PromptForChoice_Return = $null
    function PromptForChoice {
        param($Title, $Message, $Choices, $Default)
        $script:Captured.Called = $true
        $script:Captured.Default = $Default
        $script:Captured.Choices = $Choices
        $script:Captured.Title = $Title
        $script:Captured.Message = $Message
        if ($script:PromptForChoice_Return -ne $null) { return $script:PromptForChoice_Return }
        return 0
    }
}

Describe 'Invoke-MultiOptionPrompt' {
    Context 'Parameter Validation' {
        It 'Should accept valid parameters' {
            Mock -CommandName Write-Verbose { }
            $script:PromptForChoice_Return = 0
            $params = @{
                Title = 'Test Title'
                Message = 'Test Message'
                Options = @('&Yes:Confirm', '&No:Cancel')
                Default = 0
            }

            { Invoke-MultiOptionPrompt @params } | Should -Not -Throw
        }

        It 'Should use default values when parameters are not provided' {
            Mock -CommandName Write-Verbose { }
            $script:PromptForChoice_Return = 0

            { Invoke-MultiOptionPrompt } | Should -Not -Throw
        }
    }

    Context 'Option Parsing' {
        It 'Should parse valid option format correctly' {
            Mock -CommandName Write-Verbose { }
            $script:PromptForChoice_Return = 0
            $null = Invoke-MultiOptionPrompt -Options @('&Yes:Confirm', '&No:Cancel')
            $script:Captured.Called | Should -Be $true
            $script:Captured.Choices.Count | Should -Be 2
            $script:Captured.Choices[0].Label | Should -Be '&Yes'
            $script:Captured.Choices[0].HelpMessage | Should -Be 'Confirm'
        }

        It 'Should warn on invalid option format and continue with valid options' {
            Mock -CommandName Write-Verbose { }
            Mock -CommandName Write-Warning { }
            $script:PromptForChoice_Return = 0
            $null = Invoke-MultiOptionPrompt -Options @('&Yes:Confirm', 'InvalidOption', '&No:Cancel')
            Should -Invoke Write-Warning -Times 1
        }

        It 'Should throw when no valid options are provided' {
            Mock -CommandName Write-Verbose { }
            Mock -CommandName Write-Warning { }

            { Invoke-MultiOptionPrompt -Options @('InvalidFormat1', 'InvalidFormat2') } | Should -Throw 'No valid options provided*'
        }
    }

    Context 'Default Index Handling' {
        It 'Should use provided default index when valid' {
            Mock -CommandName Write-Verbose { }
            $script:PromptForChoice_Return = 1
            Invoke-MultiOptionPrompt -Options @('&Yes:Confirm', '&No:Cancel', '&Maybe:Unsure') -Default 2
            $script:Captured.Default | Should -Be 2
        }

        It 'Should adjust default index when it exceeds option count' {
            Mock -CommandName Write-Verbose { }
            Mock -CommandName Write-Warning { }
            $script:PromptForChoice_Return = 0
            Invoke-MultiOptionPrompt -Options @('&Yes:Confirm', '&No:Cancel') -Default 5
            $script:Captured.Default | Should -Be 0
            Should -Invoke Write-Warning -Times 1
        }
    }

    Context 'Return Value' {
        It 'Should return the selected option index' {
            Mock -CommandName Write-Verbose { }
            $script:PromptForChoice_Return = 1
            $result = Invoke-MultiOptionPrompt -Options @('&Yes:Confirm', '&No:Cancel')
            $result | Should -Be 1
        }

        It 'Should return integer type' {
            Mock -CommandName Write-Verbose { }
            $script:PromptForChoice_Return = 0
            $result = Invoke-MultiOptionPrompt -Options @('&Yes:Confirm', '&No:Cancel')
            $result | Should -BeOfType [int]
        }
    }

    Context 'Verbose Logging' {
        It 'Should log prompt display' {
            $script:PromptForChoice_Return = 0
            Invoke-MultiOptionPrompt -Title 'Test Title' -Verbose
            $script:Captured.Title | Should -Be 'Test Title'
        }

        It 'Should log user selection' {
            $script:PromptForChoice_Return = 2
            $result = Invoke-MultiOptionPrompt -Verbose
            $result | Should -Be 2
        }
    }

    Context 'Integration Scenarios' {
        It 'Should handle single option' {
            Mock -CommandName Write-Verbose { }
            $script:PromptForChoice_Return = 0
            { Invoke-MultiOptionPrompt -Options @('&Only:Single option') } | Should -Not -Throw
        }

        It 'Should handle multiple options with various formats' {
            Mock -CommandName Write-Verbose { }
            $script:PromptForChoice_Return = 0
            $options = @(
                '&1:First option'
                '&2:Second option'
                '&A:Alpha option'
                '&Z:Zulu option'
            )

            { Invoke-MultiOptionPrompt -Options $options } | Should -Not -Throw
        }
    }
}

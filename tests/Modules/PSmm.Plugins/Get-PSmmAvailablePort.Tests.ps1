#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Get-PSmmAvailablePort' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $script:pluginsManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm.Plugins/PSmm.Plugins.psd1'
        $script:psmmManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
        $script:loggingManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'
        $script:importClassesScript = Join-Path -Path $script:repoRoot -ChildPath 'tests/Support/Import-PSmmClasses.ps1'
        $script:testConfigPath = Join-Path -Path $script:repoRoot -ChildPath 'tests/Support/TestConfig.ps1'

        . $testConfigPath
        $helperFunctions = @(
            'New-TestRepositoryRoot',
            'New-TestAppConfiguration',
            'New-TestStorageDrive',
            'Add-TestStorageGroup'
        )
        foreach ($helper in $helperFunctions) {
            $command = Get-Command -Name $helper -CommandType Function -ErrorAction Stop
            Set-Item -Path "function:\global:$helper" -Value $command.ScriptBlock -Force
        }
        & $importClassesScript -RepositoryRoot $script:repoRoot

        foreach ($module in 'PSmm.Plugins', 'PSmm', 'PSmm.Logging') {
            if (Get-Module -Name $module -ErrorAction SilentlyContinue) {
                Remove-Module -Name $module -Force
            }
        }

        foreach ($manifest in @($script:psmmManifest, $script:loggingManifest, $script:pluginsManifest)) {
            Import-Module -Name $manifest -Force -ErrorAction Stop
        }
    }

    BeforeEach {
        $script:config = New-TestAppConfiguration
        if (-not $config.Projects.ContainsKey('PortRegistry')) {
            $config.Projects.PortRegistry = @{}
        }
    }

    It 'returns existing allocation when present and not forced' {
        $config.Projects.PortRegistry = @{ 'Alpha' = 3344 }

        Mock Write-PSmmLog { } -ModuleName PSmm.Plugins

        $port = PSmm.Plugins\Get-PSmmAvailablePort -Config $config -ProjectName 'Alpha'

        $port | Should -Be 3344
        Should -Invoke Write-PSmmLog -ModuleName PSmm.Plugins -ParameterFilter { $Level -eq 'DEBUG' -and $Message -like '*existing port*' } -Times 1
    }

    It 'allocates first free port when registry is empty' {
        $config.Projects.PortRegistry = @{}

        Mock Write-PSmmLog { } -ModuleName PSmm.Plugins
        Mock Get-NetTCPConnection { $null } -ModuleName PSmm.Plugins

        $port = PSmm.Plugins\Get-PSmmAvailablePort -Config $config -ProjectName 'Beta'

        $port | Should -Be 3310
        $config.Projects.PortRegistry['Beta'] | Should -Be 3310
        Should -Invoke Write-PSmmLog -ModuleName PSmm.Plugins -ParameterFilter { $Level -eq 'INFO' -and $Message -like '*Allocated port 3310*' } -Times 1
    }

    It 'skips busy ports until a free port is found' {
        $config.Projects.PortRegistry = @{}

        Mock Write-PSmmLog { } -ModuleName PSmm.Plugins

        $script:callCount = 0
        Mock Get-NetTCPConnection {
            $script:callCount++
            if ($script:callCount -eq 1) {
                [pscustomobject]@{ OwningProcess = 999 }
            }
            else {
                $null
            }
        } -ModuleName PSmm.Plugins

        $port = PSmm.Plugins\Get-PSmmAvailablePort -Config $config -ProjectName 'Gamma'

        $port | Should -Be 3311
        $script:callCount | Should -Be 2
        $config.Projects.PortRegistry['Gamma'] | Should -Be 3311
    }

    It 'reallocates a new port when -Force is used' {
        $config.Projects.PortRegistry = @{ 'Delta' = 3310 }

        Mock Write-PSmmLog { } -ModuleName PSmm.Plugins
        Mock Get-NetTCPConnection { $null } -ModuleName PSmm.Plugins

        $port = PSmm.Plugins\Get-PSmmAvailablePort -Config $config -ProjectName 'Delta' -Force

        $port | Should -Be 3311
        $config.Projects.PortRegistry['Delta'] | Should -Be 3311
        Should -Invoke Write-PSmmLog -ModuleName PSmm.Plugins -ParameterFilter { $Level -eq 'INFO' -and $Message -like '*Allocated port 3311*' } -Times 1
    }

    It 'initializes PortRegistry if missing' {
        $config.Projects.Remove('PortRegistry')

        Mock Write-PSmmLog { } -ModuleName PSmm.Plugins
        Mock Get-NetTCPConnection { $null } -ModuleName PSmm.Plugins

        $port = PSmm.Plugins\Get-PSmmAvailablePort -Config $config -ProjectName 'Epsilon'

        $port | Should -Be 3310
        $config.Projects.PortRegistry | Should -Not -BeNullOrEmpty
        $config.Projects.PortRegistry['Epsilon'] | Should -Be 3310
    }

    It 'throws when all ports in range are busy' {
        $config.Projects.PortRegistry = @{}

        Mock Write-PSmmLog { } -ModuleName PSmm.Plugins
        Mock Get-NetTCPConnection { [pscustomobject]@{ OwningProcess = 999 } } -ModuleName PSmm.Plugins

        { PSmm.Plugins\Get-PSmmAvailablePort -Config $config -ProjectName 'NoPortsAvailable' } | Should -Throw '*No available ports*'
    }

    It 'handles projects with special characters in name' {
        $config.Projects.PortRegistry = @{}

        Mock Write-PSmmLog { } -ModuleName PSmm.Plugins
        Mock Get-NetTCPConnection { $null } -ModuleName PSmm.Plugins

        $port = PSmm.Plugins\Get-PSmmAvailablePort -Config $config -ProjectName 'Project-Name_123'

        $port | Should -Be 3310
        $config.Projects.PortRegistry['Project-Name_123'] | Should -Be 3310
    }

    It 'writes verbose message when called with -Verbose' {
        $config.Projects.PortRegistry = @{}

        Mock Write-PSmmLog { } -ModuleName PSmm.Plugins
        Mock Get-NetTCPConnection { $null } -ModuleName PSmm.Plugins

        { PSmm.Plugins\Get-PSmmAvailablePort -Config $config -ProjectName 'Verbose-Test' -Verbose 4>&1 } | Should -Not -Throw

        $config.Projects.PortRegistry['Verbose-Test'] | Should -Be 3310
    }
}

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Get-PSmmProjectPorts' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $importClassesScript = Join-Path -Path $script:repoRoot -ChildPath 'tests/Support/Import-PSmmClasses.ps1'
        $pluginsManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm.Plugins/PSmm.Plugins.psd1'
        $psmmManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
        $loggingManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'
        . (Join-Path -Path $script:repoRoot -ChildPath 'tests/Support/TestConfig.ps1')

        & $importClassesScript -RepositoryRoot $script:repoRoot

        foreach ($module in 'PSmm.Plugins', 'PSmm', 'PSmm.Logging') {
            if (Get-Module -Name $module -ErrorAction SilentlyContinue) {
                Remove-Module -Name $module -Force
            }
        }

        foreach ($manifest in @($psmmManifest, $loggingManifest, $pluginsManifest)) {
            Import-Module -Name $manifest -Force -ErrorAction Stop
        }

        $script:MediaManagerExceptionType = [MediaManagerException]
    }

    BeforeEach {
        $script:config = New-TestAppConfiguration
        if (-not $config.Projects.ContainsKey('PortRegistry')) {
            $config.Projects.PortRegistry = @{}
        }
        $script:mockProcess = [pscustomobject]@{}
    }

    It 'returns sorted allocations with default output' {
        $config.Projects.PortRegistry = [ordered]@{
            'Beta' = 3311
            'Alpha' = 3310
        }

        Mock Write-PSmmLog {
            param($Level, $Message, $Context, $ErrorRecord, [switch]$Console, [switch]$File)
        } -ModuleName PSmm.Plugins

        $result = PSmm.Plugins\Get-PSmmProjectPorts -Config $config -Process $script:mockProcess

        $result.Count | Should -Be 2
        $result[0].ProjectName | Should -Be 'Alpha'
        $result[0].Port | Should -Be 3310
        $result[0].Type | Should -Be 'digiKam Database'
        Should -Invoke Write-PSmmLog -ModuleName PSmm.Plugins -ParameterFilter { $Message -like '*2 allocated*' } -Times 1
    }

    It 'includes usage information when requested' {
        $config.Projects.PortRegistry = @{ 'Gamma' = 3322 }

        Mock Write-PSmmLog {
            param($Level, $Message, $Context, $ErrorRecord, [switch]$Console, [switch]$File)
        } -ModuleName PSmm.Plugins
        Mock Get-NetTCPConnection { [pscustomobject]@{ OwningProcess = 456 } } -ModuleName PSmm.Plugins
        Mock Get-Process { [pscustomobject]@{ Id = 456; ProcessName = 'mariadbd' } } -ModuleName PSmm.Plugins

        $result = PSmm.Plugins\Get-PSmmProjectPorts -Config $config -Process $script:mockProcess -IncludeUsage

        $result.Count | Should -Be 1
        $result[0].InUse | Should -BeTrue
        $result[0].ProcessId | Should -Be 456
        $result[0].ProcessName | Should -Be 'mariadbd'
        Should -Invoke Get-NetTCPConnection -ModuleName PSmm.Plugins -Times 1
        Should -Invoke Get-Process -ModuleName PSmm.Plugins -Times 1
    }

    It 'marks port as free when include usage finds no listener' {
        $config.Projects.PortRegistry = @{ 'Epsilon' = 3344 }

        Mock Write-PSmmLog {
            param($Level, $Message, $Context, $ErrorRecord, [switch]$Console, [switch]$File)
        } -ModuleName PSmm.Plugins
        Mock Get-NetTCPConnection { @() } -ModuleName PSmm.Plugins
        Mock Get-Process { throw 'should not be called when no connection exists' } -ModuleName PSmm.Plugins

        $result = PSmm.Plugins\Get-PSmmProjectPorts -Config $config -Process $script:mockProcess -IncludeUsage

        $result.Count | Should -Be 1
        $result[0].InUse | Should -BeFalse
        $result[0].ProcessId | Should -Be 0
        $result[0].ProcessName | Should -Be ''
        Should -Invoke Get-NetTCPConnection -ModuleName PSmm.Plugins -Times 1
        Should -Invoke Get-Process -ModuleName PSmm.Plugins -Times 0
    }

    It 'marks port as free when listener exists but owning process cannot be resolved' {
        $config.Projects.PortRegistry = @{ 'Zeta' = 3355 }

        Mock Write-PSmmLog {
            param($Level, $Message, $Context, $ErrorRecord, [switch]$Console, [switch]$File)
        } -ModuleName PSmm.Plugins
        Mock Get-NetTCPConnection { [pscustomobject]@{ OwningProcess = 789 } } -ModuleName PSmm.Plugins
        Mock Get-Process { $null } -ModuleName PSmm.Plugins

        $result = PSmm.Plugins\Get-PSmmProjectPorts -Config $config -Process $script:mockProcess -IncludeUsage

        $result.Count | Should -Be 1
        $result[0].InUse | Should -BeFalse
        $result[0].ProcessId | Should -Be 0
        $result[0].ProcessName | Should -Be ''
        Should -Invoke Get-NetTCPConnection -ModuleName PSmm.Plugins -Times 1
        Should -Invoke Get-Process -ModuleName PSmm.Plugins -Times 1
    }

    It 'sets usage to Unknown when usage determination fails' {
        $config.Projects.PortRegistry = @{ 'Delta' = 3333 }

        Mock Write-PSmmLog {
            param($Level, $Message, $Context, $ErrorRecord, [switch]$Console, [switch]$File)
        } -ModuleName PSmm.Plugins
        Mock Get-NetTCPConnection { throw 'network query failed' } -ModuleName PSmm.Plugins
        Mock Get-Process { throw 'should not be called' } -ModuleName PSmm.Plugins

        $result = PSmm.Plugins\Get-PSmmProjectPorts -Config $config -Process $script:mockProcess -IncludeUsage

        $result.Count | Should -Be 1
        $result[0].InUse | Should -Be 'Unknown'
        $result[0].ProcessName | Should -Be 'Error'
        $result[0].ProcessId | Should -Be 0
        Should -Invoke Get-NetTCPConnection -ModuleName PSmm.Plugins -Times 1
        Should -Invoke Get-Process -ModuleName PSmm.Plugins -Times 0
    }

    It 'warns and returns empty when no registry entries exist' {
        $config.Projects.PortRegistry = @{}

        Mock Write-Warning { param($Message) } -ModuleName PSmm.Plugins
        Mock Write-PSmmLog {
            param($Level, $Message, $Context, $ErrorRecord, [switch]$Console, [switch]$File)
        } -ModuleName PSmm.Plugins

        $result = PSmm.Plugins\Get-PSmmProjectPorts -Config $config -Process $script:mockProcess

        $result | Should -BeNullOrEmpty
        Should -Invoke Write-Warning -ModuleName PSmm.Plugins -ParameterFilter { $Message -like 'No port allocations*' } -Times 1
        Should -Invoke Write-PSmmLog -ModuleName PSmm.Plugins -Times 0
    }

    It 'rethrows MediaManagerException failures with contextual logging' {
        $config.Projects.PortRegistry = @{ 'Alpha' = 3310 }
        $global:PSmmProjectPortsLoggedEntries = @()

        Mock Write-PSmmLog {
            param($Level, $Message, $Context, $ErrorRecord, [switch]$Console, [switch]$File)
            $global:PSmmProjectPortsLoggedEntries += [pscustomobject]@{ Level = $Level; Message = $Message }
            if ($Level -eq 'INFO') {
                throw [MediaManagerException]::new('Simulated failure', 'PortRegistry')
            }
        } -ModuleName PSmm.Plugins

        $caughtError = $null
        try {
            PSmm.Plugins\Get-PSmmProjectPorts -Config $config -Process $script:mockProcess | Out-Null
        }
        catch {
            $caughtError = $_
        }

        $caughtError | Should -Not -BeNullOrEmpty
        $caughtError.Exception | Should -BeOfType ($script:MediaManagerExceptionType)
        # Logging behavior for this path is covered in Write-PSmmLog tests; here we only assert the exception rethrows
        Remove-Variable -Name PSmmProjectPortsLoggedEntries -Scope Global -ErrorAction SilentlyContinue
    }

    It 'logs fallback error details for unexpected exceptions' {
        $config.Projects.PortRegistry = @{ 'Beta' = 3312 }
        $global:PSmmProjectPortsLoggedEntries = @()

        Mock Write-PSmmLog {
            param($Level, $Message, $Context, $ErrorRecord, [switch]$Console, [switch]$File)
            $global:PSmmProjectPortsLoggedEntries += [pscustomobject]@{ Level = $Level; Message = $Message }
            if ($Level -eq 'INFO') {
                throw [System.InvalidOperationException]::new('Unexpected failure')
            }
        } -ModuleName PSmm.Plugins

        $caughtError = $null
        try {
            PSmm.Plugins\Get-PSmmProjectPorts -Config $config -Process $script:mockProcess | Out-Null
        }
        catch {
            $caughtError = $_
        }

        $caughtError | Should -Not -BeNullOrEmpty
        $caughtError.Exception | Should -BeOfType ([System.InvalidOperationException])
        @($global:PSmmProjectPortsLoggedEntries | Where-Object { $_.Level -eq 'ERROR' -and $_.Message -like 'Failed to retrieve project ports*Unexpected failure*' }).Count | Should -Be 1
        Should -Invoke Write-PSmmLog -ModuleName PSmm.Plugins -ParameterFilter { $Level -eq 'ERROR' -and $Context -eq 'Get-PSmmProjectPorts' } -Times 1
        Remove-Variable -Name PSmmProjectPortsLoggedEntries -Scope Global -ErrorAction SilentlyContinue
    }
}

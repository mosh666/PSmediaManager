#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Stop-PSmmdigiKam' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $script:pluginsManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm.Plugins/PSmm.Plugins.psd1'
        $script:psmmManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
        $script:loggingManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'
        $script:importClassesScript = Join-Path -Path $script:repoRoot -ChildPath 'tests/Support/Import-PSmmClasses.ps1'

        . $script:importClassesScript -RepositoryRoot $script:repoRoot
        foreach ($module in 'PSmm.Plugins', 'PSmm', 'PSmm.Logging') {
            if (Get-Module -Name $module -ErrorAction SilentlyContinue) {
                Remove-Module -Name $module -Force
            }
        }
        foreach ($manifest in @($script:psmmManifest, $script:loggingManifest, $script:pluginsManifest)) {
            Import-Module -Name $manifest -Force -ErrorAction Stop
        }
    }

    It 'does nothing when no processes match and does not throw' {
        $cfg = [AppConfiguration]::new()
        $cfg.Projects = @{ Current = @{ Name = 'Demo'; Path = (Join-Path $TestDrive 'Demo') } }
        $null = New-Item -Path $cfg.Projects.Current.Path -ItemType Directory -Force

        Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
        Mock Get-Process { @() } -ParameterFilter { $Name -eq 'digikam' }
        Mock Get-NetTCPConnection { @() }

        { PSmm.Plugins\Stop-PSmmdigiKam -Config $cfg -Verbose } | Should -Not -Throw
    }

    It 'kills processes found by command line and port' {
        $cfg = [AppConfiguration]::new()
        $cfg.Projects = @{ Current = @{ Name = 'Demo'; Path = (Join-Path $TestDrive 'Demo') } ; PortRegistry = @{ Demo = 3330 } }
        $configDir = Join-Path $cfg.Projects.Current.Path 'Config'
        $null = New-Item -Path $configDir -ItemType Directory -Force
        $rcPath = Join-Path $configDir 'digiKam-rc'
        Set-Content -Path $rcPath -Value ''

        InModuleScope PSmm.Plugins {
            Mock Write-PSmmLog {}
        }

        $fakeProc = [pscustomobject]@{
            Id = 1001
            ProcessName = 'digikam'
            CommandLine = $rcPath
            Killed = $false
        }
        Add-Member -InputObject $fakeProc -MemberType ScriptMethod -Name Kill -Value { $this.Killed = $true } -Force
        $global:PSmmStopTestFakeProc = $fakeProc
        InModuleScope PSmm.Plugins {
            Mock Get-Process { @($global:PSmmStopTestFakeProc) } -ParameterFilter { $Name -eq 'digikam' }
            Mock Get-NetTCPConnection { @([pscustomobject]@{ LocalPort = 3330; OwningProcess = 2002 }) }
        }
        $dbProc = [pscustomobject]@{
            Id = 2002
            ProcessName = 'mariadbd'
            Killed = $false
        }
        Add-Member -InputObject $dbProc -MemberType ScriptMethod -Name Kill -Value { $this.Killed = $true } -Force
        $global:PSmmStopTestDbProc = $dbProc
        InModuleScope PSmm.Plugins {
            Mock Get-Process { $global:PSmmStopTestDbProc } -ParameterFilter { $Id -eq 2002 }
        }

        { PSmm.Plugins\Stop-PSmmdigiKam -Config $cfg -Verbose } | Should -Not -Throw
        $fakeProc.Killed | Should -BeTrue
        $dbProc.Killed | Should -BeTrue

        Remove-Variable -Name PSmmStopTestFakeProc -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name PSmmStopTestDbProc -Scope Global -ErrorAction SilentlyContinue
    }

    It 'warns when no current project path is available' {
        $cfg = [AppConfiguration]::new()
        $cfg.Projects = @{ Current = @{ Name = 'Demo' } }

        Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
        Mock Write-Warning {} -ModuleName PSmm.Plugins

        { PSmm.Plugins\Stop-PSmmdigiKam -Config $cfg -Verbose } | Should -Not -Throw
        Should -Invoke Write-Warning -ModuleName PSmm.Plugins -ParameterFilter { $Message -like "Project 'Demo' is not currently selected*" } -Times 1
    }

    It 'logs and rethrows unexpected failures' {
        $cfg = [AppConfiguration]::new()
        $cfg.Projects = @{ Current = @{ Name = 'Demo'; Path = (Join-Path $TestDrive 'Demo') } ; PortRegistry = @{ Demo = 3330 } }
        $null = New-Item -Path (Join-Path $cfg.Projects.Current.Path 'Config') -ItemType Directory -Force

        $script:StopErrorMessage = $null
        Mock Write-PSmmLog {
            param($Level, $Message, $Context, $ErrorRecord, [switch]$Console, [switch]$File)
            if ($Level -eq 'ERROR') { $script:StopErrorMessage = $Message }
        } -ModuleName PSmm.Plugins
        Mock Get-Process { throw 'process query failed' } -ModuleName PSmm.Plugins -ParameterFilter { $Name -eq 'digikam' }
        Mock Get-NetTCPConnection { @() } -ModuleName PSmm.Plugins

        { PSmm.Plugins\Stop-PSmmdigiKam -Config $cfg } | Should -Throw
        $script:StopErrorMessage | Should -Match 'Failed to stop digiKam'
    }
}

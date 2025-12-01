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

    BeforeEach {
        # Mock FileSystemService
        $script:mockFS = [PSCustomObject]@{
            PSTypeName = 'FileSystemService'
        }
        $script:mockFS | Add-Member -MemberType ScriptMethod -Name 'TestPath' -Value { param($path) Test-Path $path }

        # Mock PathProvider
        $script:mockPath = [PSCustomObject]@{
            PSTypeName = 'PathProvider'
        }
        $script:mockPath | Add-Member -MemberType ScriptMethod -Name 'Join' -Value { param([string[]]$parts) $parts -join [IO.Path]::DirectorySeparatorChar }
        $script:mockPath | Add-Member -MemberType ScriptMethod -Name 'CombinePath' -Value { param([string[]]$parts) $parts -join [IO.Path]::DirectorySeparatorChar }

        # Mock Process
        $script:mockProcess = [PSCustomObject]@{
            PSTypeName = 'ProcessService'
        }
        $script:mockProcess | Add-Member -MemberType ScriptMethod -Name 'Stop' -Value { param($id, $force) }
        $script:mockProcess | Add-Member -MemberType ScriptMethod -Name 'GetProcess' -Value { param($name) @() }
        $script:mockProcess | Add-Member -MemberType ScriptMethod -Name 'GetProcessById' -Value { param($id) $null }
    }

    It 'does nothing when no processes match and does not throw' {
        $cfg = [AppConfiguration]::new()
        $cfg.Projects = @{ Current = @{ Name = 'Demo'; Path = (Join-Path $TestDrive 'Demo') } }
        $null = New-Item -Path $cfg.Projects.Current.Path -ItemType Directory -Force

        Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
        Mock Get-Process { @() } -ParameterFilter { $Name -eq 'digikam' }
        Mock Get-NetTCPConnection { @() }

        { PSmm.Plugins\Stop-PSmmdigiKam -Config $cfg -FileSystem $script:mockFS -PathProvider $script:mockPath -Process $script:mockProcess -Verbose } | Should -Not -Throw
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
            Mock Get-NetTCPConnection { @([pscustomobject]@{ LocalPort = 3330; OwningProcess = 2002 }) }
        }
        # Provide processes via Process service mock
        $script:mockProcess | Add-Member -MemberType ScriptMethod -Name 'GetProcess' -Force -Value { param($name) @($global:PSmmStopTestFakeProc) }
        $dbProc = [pscustomobject]@{
            Id = 2002
            ProcessName = 'mariadbd'
            Killed = $false
        }
        Add-Member -InputObject $dbProc -MemberType ScriptMethod -Name Kill -Value { $this.Killed = $true } -Force
        $global:PSmmStopTestDbProc = $dbProc
        # Return DB proc by Id through service
        $script:mockProcess | Add-Member -MemberType ScriptMethod -Name 'GetProcessById' -Force -Value { param($id) if ($id -eq 2002) { $global:PSmmStopTestDbProc } else { $null } }

        { PSmm.Plugins\Stop-PSmmdigiKam -Config $cfg -FileSystem $script:mockFS -PathProvider $script:mockPath -Process $script:mockProcess -Verbose } | Should -Not -Throw
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

        { PSmm.Plugins\Stop-PSmmdigiKam -Config $cfg -FileSystem $script:mockFS -PathProvider $script:mockPath -Process $script:mockProcess -Verbose } | Should -Not -Throw
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
        # Simulate failure via Process service
        $script:mockProcess | Add-Member -MemberType ScriptMethod -Name 'GetProcess' -Force -Value { param($name) throw 'process query failed' }
        Mock Get-NetTCPConnection { @() } -ModuleName PSmm.Plugins

        { PSmm.Plugins\Stop-PSmmdigiKam -Config $cfg -FileSystem $script:mockFS -PathProvider $script:mockPath -Process $script:mockProcess } | Should -Throw
        $script:StopErrorMessage | Should -Match 'Failed to stop digiKam'
    }

    It 'respects ShouldProcess cancellation and uses Unknown project label' {
        $cfg = [AppConfiguration]::new()
        $cfg.Projects = @{}

        Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
        Mock Write-Verbose {} -ModuleName PSmm.Plugins

        { PSmm.Plugins\Stop-PSmmdigiKam -Config $cfg -FileSystem $script:mockFS -PathProvider $script:mockPath -Process $script:mockProcess -WhatIf } | Should -Not -Throw
        Should -Invoke Write-Verbose -ModuleName PSmm.Plugins -ParameterFilter { $Message -eq 'Stop digiKam operation cancelled by user' } -Times 1
    }

    It 'logs verbose message when digiKam process command line cannot be read' {
        $cfg = [AppConfiguration]::new()
        $cfg.Projects = @{ Current = @{ Name = 'Gamma'; Path = (Join-Path $TestDrive 'Gamma') } }
        $null = New-Item -Path (Join-Path $cfg.Projects.Current.Path 'Config') -ItemType Directory -Force

        Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
        Mock Write-PSmmHost {} -ModuleName PSmm.Plugins
        Mock Get-NetTCPConnection { @() } -ModuleName PSmm.Plugins

        $script:StopCmdLineErrors = 0
        $proc = New-Object psobject
        $proc | Add-Member -NotePropertyName Id -NotePropertyValue 4112 -Force
        $proc | Add-Member -NotePropertyName ProcessName -NotePropertyValue 'digikam' -Force
        $proc | Add-Member -MemberType ScriptProperty -Name CommandLine -Value { $script:StopCmdLineErrors++; throw 'Access denied' } -Force
        $proc | Add-Member -MemberType ScriptMethod -Name Kill -Value { } -Force

        # Provide process list via service
        $script:mockProcess | Add-Member -MemberType ScriptMethod -Name 'GetProcess' -Force -Value { param($name) @($proc) }

        { PSmm.Plugins\Stop-PSmmdigiKam -Config $cfg -FileSystem $script:mockFS -PathProvider $script:mockPath -Process $script:mockProcess -Verbose } | Should -Not -Throw
        $script:StopCmdLineErrors | Should -Be 1
    }

    It 'warns when digiKam process Kill fails' {
        $cfg = [AppConfiguration]::new()
        $cfg.Projects = @{ Current = @{ Name = 'Delta'; Path = (Join-Path $TestDrive 'Delta') } }
        $configDir = Join-Path $cfg.Projects.Current.Path 'Config'
        $null = New-Item -Path $configDir -ItemType Directory -Force
        $rcPath = Join-Path $configDir 'digiKam-rc'
        Set-Content -Path $rcPath -Value ''

        Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
        Mock Write-PSmmHost {} -ModuleName PSmm.Plugins
        Mock Write-Warning {} -ModuleName PSmm.Plugins
        Mock Get-NetTCPConnection { @() } -ModuleName PSmm.Plugins

        $proc = [pscustomobject]@{
            Id = 5120
            ProcessName = 'digikam'
            CommandLine = "$rcPath --other"
        }
        Add-Member -InputObject $proc -MemberType ScriptMethod -Name Kill -Value { throw 'kill failed' } -Force

        # Provide process via service
        $script:mockProcess | Add-Member -MemberType ScriptMethod -Name 'GetProcess' -Force -Value { param($name) @($proc) }

        { PSmm.Plugins\Stop-PSmmdigiKam -Config $cfg -FileSystem $script:mockFS -PathProvider $script:mockPath -Process $script:mockProcess -Verbose } | Should -Not -Throw
        Should -Invoke Write-Warning -ModuleName PSmm.Plugins -ParameterFilter { $Message -like 'Failed to stop digiKam process (PID: 5120)*' } -Times 1
    }

    It 'handles MariaDB access errors and kill failures gracefully' {
        $cfg = [AppConfiguration]::new()
        $cfg.Projects = @{
            Current = @{ Name = 'Zeta'; Path = (Join-Path $TestDrive 'Zeta') }
            PortRegistry = @{ Zeta = 4455 }
        }
        $null = New-Item -Path (Join-Path $cfg.Projects.Current.Path 'Config') -ItemType Directory -Force

        Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
        Mock Write-PSmmHost {} -ModuleName PSmm.Plugins
        Mock Write-Verbose {} -ModuleName PSmm.Plugins
        Mock Write-Warning {} -ModuleName PSmm.Plugins
        Mock Get-Process { @() } -ModuleName PSmm.Plugins -ParameterFilter { $Name -eq 'digikam' }

        Mock Get-NetTCPConnection { @(
            [pscustomobject]@{ LocalPort = 4455; OwningProcess = 9001 },
            [pscustomobject]@{ LocalPort = 4455; OwningProcess = 9002 }
        ) } -ModuleName PSmm.Plugins

        $dbProc = [pscustomobject]@{ Id = 9002; ProcessName = 'mariadbd' }
        Add-Member -InputObject $dbProc -MemberType ScriptMethod -Name Kill -Value { throw 'db kill failed' } -Force
        # Service-based behavior for by-id lookups
        $script:mockProcess | Add-Member -MemberType ScriptMethod -Name 'GetProcessById' -Force -Value { param($id) if ($id -eq 9001) { throw 'process access denied' } elseif ($id -eq 9002) { $dbProc } else { $null } }

        { PSmm.Plugins\Stop-PSmmdigiKam -Config $cfg -FileSystem $script:mockFS -PathProvider $script:mockPath -Process $script:mockProcess -Verbose } | Should -Not -Throw
        Should -Invoke Write-Verbose -ModuleName PSmm.Plugins -ParameterFilter { $Message -eq 'Cannot access process for PID: 9001' } -Times 1
        Should -Invoke Write-Warning -ModuleName PSmm.Plugins -ParameterFilter { $Message -like 'Failed to stop MariaDB process (PID: 9002)*' } -Times 1
    }

    It 'logs when no MariaDB processes are found for allocated port' {
        $cfg = [AppConfiguration]::new()
        $cfg.Projects = @{
            Current = @{ Name = 'Eta'; Path = (Join-Path $TestDrive 'Eta') }
            PortRegistry = @{ Eta = 5551 }
        }
        $null = New-Item -Path (Join-Path $cfg.Projects.Current.Path 'Config') -ItemType Directory -Force

        Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
        Mock Write-PSmmHost {} -ModuleName PSmm.Plugins
        Mock Write-Verbose {} -ModuleName PSmm.Plugins
        Mock Get-Process { @() } -ModuleName PSmm.Plugins -ParameterFilter { $Name -eq 'digikam' }
        Mock Get-NetTCPConnection { @() } -ModuleName PSmm.Plugins

        { PSmm.Plugins\Stop-PSmmdigiKam -Config $cfg -FileSystem $script:mockFS -PathProvider $script:mockPath -Process $script:mockProcess -Verbose } | Should -Not -Throw
        Should -Invoke Write-Verbose -ModuleName PSmm.Plugins -ParameterFilter { $Message -eq "No MariaDB processes found on port 5551 for project Eta" } -Times 1
    }

    It 'formats MediaManagerException messages in error log' {
        $cfg = [AppConfiguration]::new()
        $cfg.Projects = @{ Current = @{ Name = 'Theta'; Path = (Join-Path $TestDrive 'Theta') } }
        $null = New-Item -Path (Join-Path $cfg.Projects.Current.Path 'Config') -ItemType Directory -Force

        $script:lastErrorMessage = $null
        Mock Write-PSmmLog {
            param($Level, $Message, $Context, $ErrorRecord, [switch]$Console, [switch]$File)
            if ($Level -eq 'ERROR') { $script:lastErrorMessage = $Message }
        } -ModuleName PSmm.Plugins
        Mock Write-PSmmHost { throw ([MediaManagerException]::new('Simulated failure', 'StopDigiKam')) } -ModuleName PSmm.Plugins

        { PSmm.Plugins\Stop-PSmmdigiKam -Config $cfg -FileSystem $script:mockFS -PathProvider $script:mockPath -Process $script:mockProcess } | Should -Throw
        $script:lastErrorMessage | Should -Be '[StopDigiKam] Simulated failure'
    }
}

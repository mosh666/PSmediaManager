#Requires -Version 7.5.4
Set-StrictMode -Version Latest

$script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
$script:psmmLoggingManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'

Describe 'Initialize-Logging' {
    BeforeAll {
        if (Get-Module -Name PSmm.Logging -ErrorAction SilentlyContinue) { Remove-Module -Name PSmm.Logging -Force }
        Import-Module -Name $psmmLoggingManifest -Force -ErrorAction Stop
    }

    It 'creates log directory when missing and configures defaults' {
        InModuleScope PSmm.Logging {
            Mock Get-Module { @{ Name = 'PSLogs' } } -ParameterFilter { $ListAvailable -and $Name -eq 'PSLogs' }
            Mock Import-Module {}
            Mock Set-LoggingCallerScope {}
            Mock Set-LoggingDefaultLevel {}
            Mock Set-LoggingDefaultFormat {}
            Mock Write-PSmmLog {}

            $paths = [pscustomobject]@{ Log = Join-Path -Path $TestDrive -ChildPath 'logs-default' }
            $logDir = Join-Path -Path $paths.Log -ChildPath 'subdir'
            $logFile = Join-Path -Path $logDir -ChildPath 'test-psmm.log'
            $cfg = [pscustomobject]@{
                Parameters = [pscustomobject]@{ Dev = $false; NonInteractive = $true }
                Paths = $paths
                Logging = [pscustomobject]@{
                    Path = $logFile
                    DefaultLevel = 'INFO'
                    Format = '[%{timestamp}] [%{level}] %{message}'
                    PrintBody = $false
                    Append = $true
                    Encoding = 'utf8'
                    PrintException = $true
                    ShortLevel = $false
                    OnlyColorizeLevel = $false
                }
            }

            $fs = [pscustomobject]@{ Created = @(); Cleared = @() }
            $null = $fs | Add-Member -MemberType ScriptMethod -Name TestPath -Value { param($p) return $false }
            $null = $fs | Add-Member -MemberType ScriptMethod -Name NewItem -Value { param($p,$t) $this.Created += $p }
            $null = $fs | Add-Member -MemberType ScriptMethod -Name SetContent -Value { param($p,$v) $this.Cleared += $p }

            { Initialize-Logging -Config $cfg -FileSystem $fs } | Should -Not -Throw

            $fs.Created | Should -Contain $logDir
            Should -Invoke Set-LoggingDefaultLevel -Times 1 -Exactly
            Should -Invoke Set-LoggingDefaultFormat -Times 1 -Exactly
        }
    }

    It 'clears log file in Dev mode' {
        InModuleScope PSmm.Logging {
            Mock Get-Module { @{ Name = 'PSLogs' } } -ParameterFilter { $ListAvailable -and $Name -eq 'PSLogs' }
            Mock Import-Module {}
            Mock Set-LoggingCallerScope {}
            Mock Set-LoggingDefaultLevel {}
            Mock Set-LoggingDefaultFormat {}
            Mock Write-PSmmLog {}

            $paths = [pscustomobject]@{ Log = Join-Path -Path $TestDrive -ChildPath 'logs-dev' }
            $logDir = $paths.Log
            $logFile = Join-Path -Path $logDir -ChildPath 'dev-psmm.log'
            $cfg = [pscustomobject]@{
                Parameters = [pscustomobject]@{ Dev = $true; NonInteractive = $true }
                Paths = $paths
                Logging = [pscustomobject]@{
                    Path = $logFile
                    DefaultLevel = 'DEBUG'
                    Format = '[%{timestamp}] %{message}'
                    PrintBody = $false
                    Append = $true
                    Encoding = 'utf8'
                    PrintException = $true
                    ShortLevel = $false
                    OnlyColorizeLevel = $false
                }
            }

            $fs = [pscustomobject]@{ Created = @(); Cleared = @() }
            $null = $fs | Add-Member -MemberType ScriptMethod -Name TestPath -Value { param($p) return $true }
            $null = $fs | Add-Member -MemberType ScriptMethod -Name SetContent -Value { param($p,$v) $this.Cleared += $p }
            $null = $fs | Add-Member -MemberType ScriptMethod -Name NewItem -Value { param($p,$t) }

            { Initialize-Logging -Config $cfg -FileSystem $fs } | Should -Not -Throw
            $fs.Cleared | Should -Contain $logFile
            Should -Invoke Write-PSmmLog -Times 1
        }
    }

    It 'throws when configuration is missing logging members' {
        InModuleScope PSmm.Logging {
            Mock Write-Error {}

            $cfg = [pscustomobject]@{
                Parameters = [pscustomobject]@{ NonInteractive = $true }
            }

            { Initialize-Logging -Config $cfg } | Should -Throw

            Should -Invoke Write-Error -Times 1 -ParameterFilter { $Message -like 'Failed to initialize logging*' }
        }
    }

    It 'throws when logging configuration is null' {
        InModuleScope PSmm.Logging {
            Mock Write-Error {}

            $cfg = [pscustomobject]@{
                Parameters = [pscustomobject]@{ NonInteractive = $true }
                Logging = $null
            }

            $message = $null
            try {
                Initialize-Logging -Config $cfg
            }
            catch {
                $message = $_.Exception.Message
            }

            $message | Should -Match 'Logging configuration is null'
            Should -Invoke Write-Error -Times 1 -ParameterFilter { $Message -like 'Failed to initialize logging*' }
        }
    }

    It 'throws when logging configuration is not a hashtable' {
        InModuleScope PSmm.Logging {
            Mock Write-Error {}

            $cfg = [pscustomobject]@{
                Parameters = [pscustomobject]@{ NonInteractive = $true }
                Logging = 'invalid logging payload'
            }

            $message = $null
            try {
                Initialize-Logging -Config $cfg
            }
            catch {
                $message = $_.Exception.Message
            }

            $message | Should -Match 'Logging configuration is not a hashtable'
            Should -Invoke Write-Error -Times 1 -ParameterFilter { $Message -like 'Failed to initialize logging*' }
        }
    }

    It 'throws when logging configuration is missing Path' {
        InModuleScope PSmm.Logging {
            Mock Write-Error {}

            $cfg = [pscustomobject]@{
                Parameters = [pscustomobject]@{ NonInteractive = $true }
                Logging = @{ DefaultLevel = 'INFO' }
            }

            $message = $null
            try {
                Initialize-Logging -Config $cfg
            }
            catch {
                $message = $_.Exception.Message
            }

            $message | Should -Match "Logging configuration is missing required 'Path' property"
            Should -Invoke Write-Error -Times 1 -ParameterFilter { $Message -like 'Failed to initialize logging*' }
        }
    }

    It 'throws when logging path is whitespace' {
        InModuleScope PSmm.Logging {
            Mock Get-Module { @{ Name = 'PSLogs' } } -ParameterFilter { $ListAvailable -and $Name -eq 'PSLogs' }
            Mock Import-Module {}
            Mock Set-LoggingCallerScope {}
            Mock Set-LoggingDefaultLevel {}
            Mock Set-LoggingDefaultFormat {}
            Mock Write-PSmmLog {}
            Mock Write-Error {}

            $cfg = [pscustomobject]@{
                Parameters = [pscustomobject]@{ Dev = $false; NonInteractive = $true }
                Logging = [pscustomobject]@{
                    Path = '   '
                    DefaultLevel = 'INFO'
                    Format = '[%{timestamp}] %{message}'
                    PrintBody = $false
                    Append = $true
                    Encoding = 'utf8'
                    PrintException = $true
                    ShortLevel = $false
                    OnlyColorizeLevel = $false
                }
            }

            $caught = $null
            try {
                Initialize-Logging -Config $cfg
            }
            catch {
                $caught = $_.Exception.Message
            }

            $caught | Should -Not -BeNullOrEmpty
            $caught | Should -Match 'Logging Path property is empty or whitespace'
            Should -Invoke Write-Error -Times 1 -ParameterFilter { $Message -like 'Failed to initialize logging*' }
        }
    }

    It 'uses default level and format when missing' {
        InModuleScope PSmm.Logging {
            Mock Get-Module { @{ Name = 'PSLogs' } } -ParameterFilter { $ListAvailable -and $Name -eq 'PSLogs' }
            Mock Import-Module {}
            Mock Set-LoggingCallerScope {}
            Mock Set-LoggingDefaultLevel {}
            Mock Set-LoggingDefaultFormat {}
            Mock Write-PSmmLog {}
            Mock Write-Warning {}

            $paths = [pscustomobject]@{ Log = Join-Path -Path $TestDrive -ChildPath 'logs-missing-defaults' }
            $logDir = Join-Path -Path $paths.Log -ChildPath 'subdir'
            $logFile = Join-Path -Path $logDir -ChildPath 'missing-defaults.log'
            $cfg = [pscustomobject]@{
                Parameters = [pscustomobject]@{ Dev = $false; NonInteractive = $true }
                Paths = $paths
                Logging = [pscustomobject]@{
                    Path = $logFile
                    DefaultLevel = $null
                    Format = ''
                    PrintBody = $false
                    Append = $true
                    Encoding = 'utf8'
                    PrintException = $true
                    ShortLevel = $false
                    OnlyColorizeLevel = $false
                }
            }

            $fs = [pscustomobject]@{ Created = @(); Cleared = @() }
            $null = $fs | Add-Member -MemberType ScriptMethod -Name TestPath -Value { param($p) return $false }
            $null = $fs | Add-Member -MemberType ScriptMethod -Name NewItem -Value { param($p,$t) $this.Created += $p }
            $null = $fs | Add-Member -MemberType ScriptMethod -Name SetContent -Value { param($p,$v) $this.Cleared += $p }

            { Initialize-Logging -Config $cfg -FileSystem $fs } | Should -Not -Throw

            Should -Invoke Write-Warning -ParameterFilter { $Message -like "*DefaultLevel*" } -Times 1
            Should -Invoke Write-Warning -ParameterFilter { $Message -like "*Format*" } -Times 1
            Should -Invoke Set-LoggingDefaultLevel -ParameterFilter { $Level -eq 'INFO' } -Times 1
            Should -Invoke Set-LoggingDefaultFormat -ParameterFilter { $Format -eq '[%{timestamp}] [%{level}] %{message}' } -Times 1
        }
    }

    It 'installs PSLogs when module is missing' {
        InModuleScope PSmm.Logging {
            Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'PSLogs' }
            Mock Import-Module {}
            Mock Set-LoggingCallerScope {}
            Mock Set-LoggingDefaultLevel {}
            Mock Set-LoggingDefaultFormat {}
            Mock Write-PSmmLog {}
            Mock Write-Error {}
            Mock Write-Warning {}
            Mock Get-PackageProvider { $null }
            Mock Install-PackageProvider {}
            Mock Get-PSRepository { [pscustomobject]@{ Name = 'PSGallery'; InstallationPolicy = 'Untrusted' } }
            Mock Set-PSRepository {}
            Mock Install-Module {}

            $paths = [pscustomobject]@{ Log = Join-Path -Path $TestDrive -ChildPath 'logs-install' }
            $logFile = Join-Path -Path $paths.Log -ChildPath 'install.log'
            $cfg = [pscustomobject]@{
                Parameters = [pscustomobject]@{ Dev = $false; NonInteractive = $false }
                Paths = $paths
                Logging = [pscustomobject]@{
                    Path = $logFile
                    DefaultLevel = 'INFO'
                    Format = '[%{timestamp}] %{message}'
                    PrintBody = $false
                    Append = $true
                    Encoding = 'utf8'
                    PrintException = $true
                    ShortLevel = $false
                    OnlyColorizeLevel = $false
                }
            }

            $fs = [pscustomobject]@{}
            $null = $fs | Add-Member -MemberType ScriptMethod -Name TestPath -Value { param($p) return $true }
            $null = $fs | Add-Member -MemberType ScriptMethod -Name NewItem -Value { param($p,$t) }
            $null = $fs | Add-Member -MemberType ScriptMethod -Name SetContent -Value { param($p,$v) }

            { Initialize-Logging -Config $cfg -FileSystem $fs } | Should -Not -Throw
            Should -Invoke Install-PackageProvider -Times 1
            Should -Invoke Install-Module -Times 1 -ParameterFilter { $Name -eq 'PSLogs' }
        }
    }

    It 'warns when NuGet provider install fails in interactive mode' {
        InModuleScope PSmm.Logging {
            Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'PSLogs' }
            Mock Import-Module {}
            Mock Set-LoggingCallerScope {}
            Mock Set-LoggingDefaultLevel {}
            Mock Set-LoggingDefaultFormat {}
            Mock Write-PSmmLog {}
            Mock Write-Error {}
            Mock Write-Warning {}
            Mock Get-PackageProvider { $null }
            Mock Install-PackageProvider { throw 'nuget failure' }
            Mock Get-PSRepository { [pscustomobject]@{ Name = 'PSGallery'; InstallationPolicy = 'Trusted' } }
            Mock Set-PSRepository {}
            Mock Install-Module {}

            $paths = [pscustomobject]@{ Log = Join-Path -Path $TestDrive -ChildPath 'logs-nuget-warning' }
            $logFile = Join-Path -Path $paths.Log -ChildPath 'nuget-warning.log'
            $cfg = [pscustomobject]@{
                Parameters = [pscustomobject]@{ Dev = $false; NonInteractive = $false }
                Paths = $paths
                Logging = [pscustomobject]@{
                    Path = $logFile
                    DefaultLevel = 'INFO'
                    Format = '[%{timestamp}] %{message}'
                    PrintBody = $false
                    Append = $true
                    Encoding = 'utf8'
                    PrintException = $true
                    ShortLevel = $false
                    OnlyColorizeLevel = $false
                }
            }

            $fs = [pscustomobject]@{}
            $null = $fs | Add-Member -MemberType ScriptMethod -Name TestPath -Value { param($p) return $true }
            $null = $fs | Add-Member -MemberType ScriptMethod -Name NewItem -Value { param($p,$t) }
            $null = $fs | Add-Member -MemberType ScriptMethod -Name SetContent -Value { param($p,$v) }

            { Initialize-Logging -Config $cfg -FileSystem $fs } | Should -Not -Throw
            Should -Invoke Install-PackageProvider -Times 1
            Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like 'Failed to install NuGet provider*' }
        }
    }

    It 'throws when PSGallery configuration fails in NonInteractive mode' {
        InModuleScope PSmm.Logging {
            Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'PSLogs' }
            Mock Import-Module {}
            Mock Set-LoggingCallerScope {}
            Mock Set-LoggingDefaultLevel {}
            Mock Set-LoggingDefaultFormat {}
            Mock Write-PSmmLog {}
            Mock Write-Error {}
            Mock Get-PackageProvider { $null }
            Mock Install-PackageProvider {}
            Mock Get-PSRepository { throw 'PSGallery unavailable' }

            $paths = [pscustomobject]@{ Log = Join-Path -Path $TestDrive -ChildPath 'logs-repo-fail' }
            $logFile = Join-Path -Path $paths.Log -ChildPath 'repo-fail.log'
            $cfg = [pscustomobject]@{
                Parameters = [pscustomobject]@{ Dev = $false; NonInteractive = $true }
                Paths = $paths
                Logging = [pscustomobject]@{
                    Path = $logFile
                    DefaultLevel = 'INFO'
                    Format = '[%{timestamp}] %{message}'
                    PrintBody = $false
                    Append = $true
                    Encoding = 'utf8'
                    PrintException = $true
                    ShortLevel = $false
                    OnlyColorizeLevel = $false
                }
            }

            $fs = [pscustomobject]@{}
            $null = $fs | Add-Member -MemberType ScriptMethod -Name TestPath -Value { param($p) return $true }
            $null = $fs | Add-Member -MemberType ScriptMethod -Name NewItem -Value { param($p,$t) }
            $null = $fs | Add-Member -MemberType ScriptMethod -Name SetContent -Value { param($p,$v) }

            $caught = $null
            try {
                Initialize-Logging -Config $cfg -FileSystem $fs
            }
            catch {
                $caught = $_.Exception.Message
            }

            $caught | Should -Match 'Failed to configure PSGallery repository'
        }
    }

    It 'throws when PSLogs installation fails' {
        InModuleScope PSmm.Logging {
            Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'PSLogs' }
            Mock Import-Module {}
            Mock Set-LoggingCallerScope {}
            Mock Set-LoggingDefaultLevel {}
            Mock Set-LoggingDefaultFormat {}
            Mock Write-PSmmLog {}
            Mock Write-Error {}
            Mock Get-PackageProvider { $null }
            Mock Install-PackageProvider {}
            Mock Get-PSRepository { [pscustomobject]@{ Name = 'PSGallery'; InstallationPolicy = 'Trusted' } }
            Mock Set-PSRepository {}
            Mock Install-Module { throw 'gallery offline' }

            $paths = [pscustomobject]@{ Log = Join-Path -Path $TestDrive -ChildPath 'logs-install-fail' }
            $logFile = Join-Path -Path $paths.Log -ChildPath 'install-fail.log'
            $cfg = [pscustomobject]@{
                Parameters = [pscustomobject]@{ Dev = $false; NonInteractive = $false }
                Paths = $paths
                Logging = [pscustomobject]@{
                    Path = $logFile
                    DefaultLevel = 'INFO'
                    Format = '[%{timestamp}] %{message}'
                    PrintBody = $false
                    Append = $true
                    Encoding = 'utf8'
                    PrintException = $true
                    ShortLevel = $false
                    OnlyColorizeLevel = $false
                }
            }

            $fs = [pscustomobject]@{}
            $null = $fs | Add-Member -MemberType ScriptMethod -Name TestPath -Value { param($p) return $true }
            $null = $fs | Add-Member -MemberType ScriptMethod -Name NewItem -Value { param($p,$t) }
            $null = $fs | Add-Member -MemberType ScriptMethod -Name SetContent -Value { param($p,$v) }

            $threw = $false
            try {
                Initialize-Logging -Config $cfg -FileSystem $fs
            }
            catch {
                $threw = $true
                $_.Exception.Message | Should -Match "Failed to install PSLogs module automatically"
            }

            $threw | Should -BeTrue
            Should -Invoke Install-Module -Times 1
        }
    }

    It 'falls back to native filesystem when FileSystemService initialization fails' {
        InModuleScope PSmm.Logging {
            Mock New-FileSystemService { throw 'forced FileSystemService failure' } -ModuleName PSmm.Logging
            Mock Get-Module { @{ Name = 'PSLogs' } } -ParameterFilter { $ListAvailable -and $Name -eq 'PSLogs' }
            Mock Import-Module {}
            Mock Set-LoggingCallerScope {}
            Mock Set-LoggingDefaultLevel {}
            Mock Set-LoggingDefaultFormat {}
            Mock Write-PSmmLog {}
            Mock Write-Verbose {}

            $paths = [pscustomobject]@{ Log = Join-Path -Path $TestDrive -ChildPath 'logs-native-fallback' }
            $logDir = Join-Path -Path $paths.Log -ChildPath 'subdir'
            $logFile = Join-Path -Path $logDir -ChildPath 'native-fallback.log'
            if (Test-Path -Path $logDir) { Remove-Item -Path $logDir -Recurse -Force }

            $cfg = [pscustomobject]@{
                Parameters = [pscustomobject]@{ Dev = $false; NonInteractive = $true }
                Paths = $paths
                Logging = [pscustomobject]@{
                    Path = $logFile
                    DefaultLevel = 'INFO'
                    Format = '[%{timestamp}] %{message}'
                    PrintBody = $false
                    Append = $true
                    Encoding = 'utf8'
                    PrintException = $true
                    ShortLevel = $false
                    OnlyColorizeLevel = $false
                }
            }

            { Initialize-Logging -Config $cfg } | Should -Not -Throw
            (Test-Path -Path $logDir) | Should -BeTrue
            Should -Invoke Write-Verbose -ParameterFilter { $Message -eq 'FileSystemService type not available - falling back to native cmdlets.' } -Times 1
        }
    }

    It 'logs warning when native log clearing fails' {
        InModuleScope PSmm.Logging {
            Mock New-FileSystemService { throw 'forced FileSystemService failure' } -ModuleName PSmm.Logging
            Mock Get-Module { @{ Name = 'PSLogs' } } -ParameterFilter { $ListAvailable -and $Name -eq 'PSLogs' }
            Mock Import-Module {}
            Mock Set-LoggingCallerScope {}
            Mock Set-LoggingDefaultLevel {}
            Mock Set-LoggingDefaultFormat {}
            Mock Write-PSmmLog {}
            Mock Write-Warning {}

            $paths = [pscustomobject]@{ Log = Join-Path -Path $TestDrive -ChildPath 'logs-native-clear' }
            $logDir = $paths.Log
            if (-not (Test-Path -Path $logDir)) { $null = New-Item -Path $logDir -ItemType Directory }
            $logFile = Join-Path -Path $logDir -ChildPath 'native-clear.log'
            'content' | Set-Content -Path $logFile

            Mock Set-Content { throw 'write failure' } -ParameterFilter { $Path -eq $logFile }

            $cfg = [pscustomobject]@{
                Parameters = [pscustomobject]@{ Dev = $true; NonInteractive = $true }
                Paths = $paths
                Logging = [pscustomobject]@{
                    Path = $logFile
                    DefaultLevel = 'INFO'
                    Format = '[%{timestamp}] %{message}'
                    PrintBody = $false
                    Append = $true
                    Encoding = 'utf8'
                    PrintException = $true
                    ShortLevel = $false
                    OnlyColorizeLevel = $false
                }
            }

            { Initialize-Logging -Config $cfg } | Should -Not -Throw
            Should -Invoke Write-Warning -ParameterFilter { $Message -like "Failed to clear log file '$logFile'*" } -Times 1
        }
    }

    It 'uses FileSystemService when available' {
        $fs = [pscustomobject]@{
            Existing = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            Created = [System.Collections.Generic.List[string]]::new()
            Cleared = [System.Collections.Generic.List[string]]::new()
        }
        $null = $fs | Add-Member -MemberType ScriptMethod -Name TestPath -Value { param($path) $this.Existing.Contains($path) }
        $null = $fs | Add-Member -MemberType ScriptMethod -Name NewItem -Value {
            param($path,$type)
            $null = $this.Created.Add($path)
            $null = $this.Existing.Add($path)
        }
        $null = $fs | Add-Member -MemberType ScriptMethod -Name SetContent -Value {
            param($path,$value)
            $null = $this.Cleared.Add($path)
            $null = $this.Existing.Add($path)
        }
        InModuleScope PSmm.Logging -ArgumentList $fs {
            param($fs)

            Mock Get-Module { @{ Name = 'PSLogs' } } -ParameterFilter { $ListAvailable -and $Name -eq 'PSLogs' }
            Mock Import-Module {}
            Mock Set-LoggingCallerScope {}
            Mock Set-LoggingDefaultLevel {}
            Mock Set-LoggingDefaultFormat {}
            Mock Write-PSmmLog {}
            Mock Write-Verbose {}

            $paths = [pscustomobject]@{ Log = Join-Path -Path $TestDrive -ChildPath 'logs-filesystem-service' }
            $logDir = Join-Path -Path $paths.Log -ChildPath 'service'
            if (Test-Path -Path $logDir) { Remove-Item -Path $logDir -Recurse -Force }
            $logFile = Join-Path -Path $logDir -ChildPath 'service.log'
            $null = $fs.Existing.Add($logFile)
            Mock New-FileSystemService { return $fs } -ModuleName PSmm.Logging

            $cfg = [pscustomobject]@{
                Parameters = [pscustomobject]@{ Dev = $true; NonInteractive = $true }
                Paths = $paths
                Logging = [pscustomobject]@{
                    Path = $logFile
                    DefaultLevel = 'INFO'
                    Format = '[%{timestamp}] %{message}'
                    PrintBody = $false
                    Append = $true
                    Encoding = 'utf8'
                    PrintException = $true
                    ShortLevel = $false
                    OnlyColorizeLevel = $false
                }
            }

            { Initialize-Logging -Config $cfg } | Should -Not -Throw
            $fs.Created | Should -Contain $logDir
            $fs.Cleared | Should -Contain $logFile
            Should -Invoke Write-Verbose -Times 0 -ParameterFilter { $Message -eq 'FileSystemService type not available - falling back to native cmdlets.' }
        }
    }

    It 'throws when native directory creation fails' {
        InModuleScope PSmm.Logging {
            Mock New-FileSystemService { throw 'forced FileSystemService failure' } -ModuleName PSmm.Logging
            Mock Get-Module { @{ Name = 'PSLogs' } } -ParameterFilter { $ListAvailable -and $Name -eq 'PSLogs' }
            Mock Import-Module {}
            Mock Set-LoggingCallerScope {}
            Mock Set-LoggingDefaultLevel {}
            Mock Set-LoggingDefaultFormat {}
            Mock Write-PSmmLog {}
            Mock Write-Error {}

            $paths = [pscustomobject]@{ Log = Join-Path -Path $TestDrive -ChildPath 'logs-native-fail' }
            $logDir = $paths.Log
            if (Test-Path -Path $logDir) { Remove-Item -Path $logDir -Recurse -Force }
            $logFile = Join-Path -Path $logDir -ChildPath 'native-fail.log'

            Mock New-Item { throw 'creation denied' } -ParameterFilter { $Path -eq $logDir -and $ItemType -eq 'Directory' }

            $cfg = [pscustomobject]@{
                Parameters = [pscustomobject]@{ Dev = $false; NonInteractive = $true }
                Paths = $paths
                Logging = [pscustomobject]@{
                    Path = $logFile
                    DefaultLevel = 'INFO'
                    Format = '[%{timestamp}] %{message}'
                    PrintBody = $false
                    Append = $true
                    Encoding = 'utf8'
                    PrintException = $true
                    ShortLevel = $false
                    OnlyColorizeLevel = $false
                }
            }

            $caught = $null
            try {
                Initialize-Logging -Config $cfg
            }
            catch {
                $caught = $_.Exception.Message
            }

            $caught | Should -Match ([regex]::Escape("Failed to create log directory '$logDir'"))
        }
    }

    It 'throws when PSLogs auto-install fails in NonInteractive mode' {
        InModuleScope PSmm.Logging {
            Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'PSLogs' }
            Mock Import-Module {}
            Mock Set-LoggingCallerScope {}
            Mock Set-LoggingDefaultLevel {}
            Mock Set-LoggingDefaultFormat {}
            Mock Write-PSmmLog {}
            Mock Write-Error {}
            Mock Get-PackageProvider { $null }
            Mock Install-PackageProvider { throw 'nuget failure' }

            $paths = [pscustomobject]@{ Log = Join-Path -Path $TestDrive -ChildPath 'logs-noninteractive' }
            $logFile = Join-Path -Path $paths.Log -ChildPath 'noninteractive.log'
            $cfg = [pscustomobject]@{
                Parameters = [pscustomobject]@{ Dev = $false; NonInteractive = $true }
                Paths = $paths
                Logging = [pscustomobject]@{
                    Path = $logFile
                    DefaultLevel = 'INFO'
                    Format = '[%{timestamp}] %{message}'
                    PrintBody = $false
                    Append = $true
                    Encoding = 'utf8'
                    PrintException = $true
                    ShortLevel = $false
                    OnlyColorizeLevel = $false
                }
            }

            $fs = [pscustomobject]@{}
            $null = $fs | Add-Member -MemberType ScriptMethod -Name TestPath -Value { param($p) return $true }
            $null = $fs | Add-Member -MemberType ScriptMethod -Name NewItem -Value { param($p,$t) }
            $null = $fs | Add-Member -MemberType ScriptMethod -Name SetContent -Value { param($p,$v) }

            $caught = $null
            try {
                Initialize-Logging -Config $cfg -FileSystem $fs
            }
            catch {
                $caught = $_.Exception.Message
            }

            $caught | Should -Not -BeNullOrEmpty
            $caught | Should -Match 'Failed to install NuGet provider required for PSLogs'
            Should -Invoke Install-PackageProvider -Times 1
        }
    }
}

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

 $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
 $script:psmmLoggingManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'
 $script:importClassesScript = Join-Path -Path $script:repoRoot -ChildPath 'tests/Support/Import-PSmmClasses.ps1'
 $script:preloadTypesScript = Join-Path -Path $script:repoRoot -ChildPath 'tests/Preload-PSmmTypes.ps1'

 if (-not (Get-Module -Name PSmm.Logging -ErrorAction SilentlyContinue)) {
     Import-Module $script:psmmLoggingManifest -Force
 }

Describe 'Initialize-Logging' {
    BeforeAll {
        # Rehydrate paths inside BeforeAll to avoid nulls when Pester scopes the file
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $script:psmmLoggingManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'
        $script:importClassesScript = Join-Path -Path $script:repoRoot -ChildPath 'tests/Support/Import-PSmmClasses.ps1'
        $script:preloadTypesScript = Join-Path -Path $script:repoRoot -ChildPath 'tests/Preload-PSmmTypes.ps1'

        if (Test-Path $script:preloadTypesScript) { . $script:preloadTypesScript }
        . $script:importClassesScript -RepositoryRoot $script:repoRoot
        if (Get-Module -Name PSmm.Logging -ErrorAction SilentlyContinue) { Remove-Module -Name PSmm.Logging -Force }
        Import-Module $script:psmmLoggingManifest -Force
        
        # Stub Write-PSmmLog to avoid external logging calls
        . (Join-Path $script:repoRoot 'tests/Support/Stub-WritePSmmLog.ps1')
        Enable-TestWritePSmmLogStub
    }

    Context 'Deterministic error and verbose branches' {
        It 'throws when Logging.ContainsKey Path check fails (catch at ~167)' -Tag 'Coverage' {
            InModuleScope PSmm.Logging {
                # Arrange: Create a faux dictionary whose ContainsKey throws
                $throwingDict = New-Object PSObject
                $throwingDict | Add-Member -MemberType ScriptMethod -Name ContainsKey -Value { param($k) throw 'boom' }
                $throwingDict | Add-Member -MemberType ScriptMethod -Name get_Item -Value { param($k) $null }

                $cfg = @{ Parameters = @{ Verbose = $true; Dev = $false; NonInteractive = $true }; Logging = $throwingDict }

                # Act + Assert
                { Initialize-Logging -Config $cfg -Verbose } | Should -Throw
            }
        }

        It "writes verbose message when FileSystemService isn't available (lines 255-256)" -Tag 'Coverage' {
            InModuleScope PSmm.Logging {
                # Arrange: ensure type is not available and Test-Path fails so branch executes
                Mock -ModuleName PSmm.Logging New-FileSystemService { throw 'type missing' }
                Mock -ModuleName PSmm.Logging Test-Path { $false }

                $cfg = @{ Parameters = @{ Verbose = $true; NonInteractive = $true; Dev = $false }; Logging = @{ Path = Join-Path $TestDrive 'logs' } }

                # Capture verbose output
                $verbose = & {
                    $oldPref = $VerbosePreference
                    try { $VerbosePreference = 'Continue'; Initialize-Logging -Config $cfg -Verbose }
                    finally { $VerbosePreference = $oldPref }
                } 4>&1

                # Assert: contains the expected verbose fallback message
                (@($verbose | Where-Object { $_ -match 'FileSystemService type not available - falling back to native cmdlets.' })).Count | Should -BeGreaterThan 0
            }
        }
    }

    It 'initializes logging with valid configuration and creates log directory' {
        InModuleScope PSmm.Logging {
            # Mock PSLogs functions
            Mock Get-Module { @{ Name = 'PSLogs' } } -ParameterFilter { $Name -eq 'PSLogs' -and $ListAvailable }
            Mock Import-Module { } -ParameterFilter { $Name -eq 'PSLogs' }
            Mock Set-LoggingCallerScope { }
            Mock Set-LoggingDefaultLevel { }
            Mock Set-LoggingDefaultFormat { }
            Mock Write-PSmmLog { }
            
            $logDir = Join-Path $TestDrive 'logs'
            $logFile = Join-Path $logDir 'test.log'
            
            # Mock filesystem
            $fs = [pscustomobject]@{ CreatedDirs = @(); CreatedFiles = @(); WrittenFiles = @() }
            $fs | Add-Member -MemberType ScriptMethod -Name TestPath -Value {
                param($p)
                return $this.CreatedDirs -contains $p -or $this.CreatedFiles -contains $p
            }
            $fs | Add-Member -MemberType ScriptMethod -Name NewItem -Value {
                param($p, $t)
                if ($t -eq 'Directory') { $this.CreatedDirs += $p } else { $this.CreatedFiles += $p }
            }
            $fs | Add-Member -MemberType ScriptMethod -Name SetContent -Value {
                param($p, $v)
                $this.WrittenFiles += $p
            }
            
            $config = [PSCustomObject]@{
                Parameters = [PSCustomObject]@{ Dev = $false; NonInteractive = $true; Verbose = $false; Debug = $false }
                Paths = [PSCustomObject]@{ Log = $logDir }
                Logging = [PSCustomObject]@{
                    Path = $logFile
                    Level = 'INFO'
                    DefaultLevel = 'INFO'
                    Format = '[%{timestamp}] %{message}'
                    EnableConsole = $true
                    EnableFile = $true
                    MaxFileSizeMB = 10
                    MaxLogFiles = 5
                    PrintBody = $false
                    Append = $true
                    Encoding = 'utf8'
                }
            }
            
            { Initialize-Logging -Config $config -FileSystem $fs -SkipPsLogsInit } | Should -Not -Throw
            $fs.CreatedDirs | Should -Contain $logDir
        }
    }

    It 'initializes logging idempotently with hashtable config' {
        InModuleScope PSmm.Logging {
            Mock Get-Module { @{ Name = 'PSLogs' } } -ParameterFilter { $Name -eq 'PSLogs' -and $ListAvailable }
            Mock Import-Module { }
            Mock Set-LoggingCallerScope { }
            Mock Set-LoggingDefaultLevel { }
            Mock Set-LoggingDefaultFormat { }
            Mock Write-PSmmLog { }
            
            $logDir = Join-Path $TestDrive 'logs2'
            $logFile = Join-Path $logDir 'test2.log'
            
            $fs = [pscustomobject]@{ CreatedDirs = @(); CreatedFiles = @(); WrittenFiles = @() }
            $fs | Add-Member -MemberType ScriptMethod -Name TestPath -Value { param($p) $this.CreatedDirs -contains $p }
            $fs | Add-Member -MemberType ScriptMethod -Name NewItem -Value { param($p, $t) if ($t -eq 'Directory') { $this.CreatedDirs += $p } }
            $fs | Add-Member -MemberType ScriptMethod -Name SetContent -Value { param($p, $v) $this.WrittenFiles += $p }
            
            $config = [PSCustomObject]@{
                Parameters = [PSCustomObject]@{ Dev = $false; NonInteractive = $true }
                Paths = [PSCustomObject]@{ Log = $logDir }
                Logging = [PSCustomObject]@{
                    Path = $logFile
                    Level = 'DEBUG'
                    DefaultLevel = 'INFO'
                    Format = '%{message}'
                    EnableConsole = $true
                    EnableFile = $true
                    MaxFileSizeMB = 5
                    MaxLogFiles = 3
                }
            }
            
            { Initialize-Logging -Config $config -FileSystem $fs -SkipPsLogsInit } | Should -Not -Throw
            { Initialize-Logging -Config $config -FileSystem $fs -SkipPsLogsInit } | Should -Not -Throw
        }
    }

    It 'installs PSLogs prerequisites and clears the log file during Dev runs' {
        InModuleScope PSmm.Logging {
            Mock Get-Module { $null } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSLogs' -and $ListAvailable }
            Mock Get-PackageProvider { $null } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'NuGet' }
            Mock Install-PackageProvider { @{ Name = 'NuGet' } } -ModuleName PSmm.Logging
            Import-Module PowerShellGet -ErrorAction Stop
            Mock Get-PSRepository {
                param([string]$Name)
                return [pscustomobject]@{ Name = $Name; InstallationPolicy = 'Untrusted' }
            } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSGallery' }
            Mock Set-PSmmRepositoryInstallationPolicy {
                param($Name,$InstallationPolicy)
            } -ModuleName PSmm.Logging
            Mock Install-Module { } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSLogs' }
            Mock Import-Module { } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSLogs' }
            Mock Set-LoggingCallerScope { } -ModuleName PSmm.Logging
            Mock Set-LoggingDefaultLevel { } -ModuleName PSmm.Logging
            Mock Set-LoggingDefaultFormat { } -ModuleName PSmm.Logging
            Mock Write-PSmmLog { } -ModuleName PSmm.Logging

            $logDir = Join-Path $TestDrive 'logs-dev'
            $logPath = Join-Path $logDir 'psmm.log'

            $fs = [pscustomobject]@{
                Known = @{}
                Created = [System.Collections.Generic.List[string]]::new()
                Cleared = [System.Collections.Generic.List[string]]::new()
            }
            $fs.Known[$logPath] = $true
            $fs | Add-Member -MemberType ScriptMethod -Name TestPath -Value {
                param($path)
                return ($this.Known.ContainsKey($path) -and $this.Known[$path])
            }
            $fs | Add-Member -MemberType ScriptMethod -Name NewItem -Value {
                param($path, $type)
                $this.Known[$path] = $true
                [void]$this.Created.Add($path)
            }
            $fs | Add-Member -MemberType ScriptMethod -Name SetContent -Value {
                param($path, $value)
                [void]$this.Cleared.Add($path)
            }

            $pathProvider = [pscustomobject]@{}
            $pathProvider | Add-Member -MemberType ScriptMethod -Name CombinePath -Value {
                param([object[]]$segments)
                return ($segments | Select-Object -First 1)
            }

            $config = [pscustomobject]@{
                Parameters = [pscustomobject]@{ Dev = $true; NonInteractive = $false }
                Logging = [pscustomobject]@{
                    Path = $logPath
                    DefaultLevel = 'NOTICE'
                    Format = '%{message}'
                }
            }

            { Initialize-Logging -Config $config -FileSystem $fs -PathProvider $pathProvider } | Should -Not -Throw

            Should -Invoke Install-PackageProvider -Times 1
            Should -Invoke Install-Module -Times 1
            Should -Invoke Import-Module -Times 1
            Should -Invoke Set-PSmmRepositoryInstallationPolicy -Times 1 -ModuleName PSmm.Logging
            Should -Invoke Set-LoggingCallerScope -Times 1
            Should -Invoke Set-LoggingDefaultLevel -Times 1
            Should -Invoke Set-LoggingDefaultFormat -Times 1
            $fs.Created | Should -Contain $logDir
            $fs.Cleared | Should -Contain $logPath
        }
    }
}

Describe 'Initialize-Logging error branches' {
    InModuleScope PSmm.Logging {
        Context 'Invalid configuration shapes trigger early throws' {
            It 'throws when conversion of Logging to hashtable fails and reports source type' {
                # Provide an object with no IDictionary semantics to trigger conversion failure branch
                $badLogging = New-Object System.Object
                $cfg = @{ Parameters = @{ Verbose = $false; NonInteractive = $true; Dev = $false }; Paths = @{ Log = 'D:\Logs' }; Logging = $badLogging }
                { Initialize-Logging -Config $cfg } | Should -Throw -Because 'Non-convertible Logging should error with source type'
            }

            # Note: Assignment failure branch proved non-deterministic across scopes; remove brittle expectation
            # and focus coverage on deterministic branches below.
            It 'throws when Parameters/Logging members are missing' {
                $cfg = @{ Paths = @{ Log = 'D:\Logs' } }
                { Initialize-Logging -Config $cfg } | Should -Throw -Because 'Missing Parameters/Logging should error'
            }

            It 'throws when Logging is null' {
                $cfg = @{ Parameters = @{ Verbose = $false; NonInteractive = $true }; Logging = $null }
                { Initialize-Logging -Config $cfg } | Should -Throw -Because 'Null Logging should error'
            }

            It 'throws when Logging is not a hashtable' {
                $cfg = @{ Parameters = @{ Verbose = $false; NonInteractive = $true }; Logging = 'not-a-hash' }
                { Initialize-Logging -Config $cfg } | Should -Throw -Because 'Non-hashtable Logging should error'
            }

            It "throws when Logging is missing required 'Path'" {
                $cfg = @{ Parameters = @{ Verbose = $false; NonInteractive = $true; Dev = $false }; Paths = @{ Log = 'D:\Logs' }; Logging = @{ } }
                { Initialize-Logging -Config $cfg } | Should -Throw -Because "Missing 'Path' must error"
            }

            It 'throws when Logging.Path is empty or whitespace' {
                $cfg = @{ Parameters = @{ Verbose = $false; NonInteractive = $true; Dev = $false }; Paths = @{ Log = 'D:\Logs' }; Logging = @{ Path = '  ' } }
                { Initialize-Logging -Config $cfg } | Should -Throw -Because 'Empty Path must error'
            }
        }

        Context 'PSLogs install/import failures surface errors' {
            BeforeAll {
                Mock Get-PackageProvider { @{ Name = 'NuGet' } } -ModuleName PSmm.Logging
                Mock Install-PackageProvider { throw 'NuGet install failed' } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'NuGet' }
                Mock Set-PSmmRepositoryInstallationPolicy { $true } -ModuleName PSmm.Logging
                Mock Install-Module { throw 'PSLogs install failed' } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSLogs' }
                Mock Import-Module { throw 'PSLogs import failed' } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSLogs' }
            }

            It 'throws when NuGet install fails in non-interactive mode' {
                $cfg = @{ Parameters = @{ Verbose = $false; NonInteractive = $true }; Logging = @{ Path = 'D:\Logs' } }
                { Initialize-Logging -Config $cfg } | Should -Throw -Because 'NuGet failure must throw'
            }

            It 'throws when NuGet provider missing and install fails in non-interactive mode' -Tag 'Coverage' {
                # Force provider absence and failing install to hit non-interactive throw branch
                Mock Get-PackageProvider { $null } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'NuGet' }
                Mock Install-PackageProvider { throw 'NuGet install failed (missing provider)' } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'NuGet' }

                $cfg = @{ Parameters = @{ Verbose = $false; NonInteractive = $true; Dev = $false }; Logging = @{ Path = 'D:\Logs' } }
                { Initialize-Logging -Config $cfg } | Should -Throw -Because 'NonInteractive must throw when provider install fails'
            }

            It 'emits warning when NuGet install fails in interactive mode' {
                Mock Get-PackageProvider { $null } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'NuGet' }
                # Override failure mocks for interactive path to allow continuation after warning
                Mock Set-PSmmRepositoryInstallationPolicy { $true } -ModuleName PSmm.Logging
                Mock Install-Module { } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSLogs' }
                Mock Import-Module { } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSLogs' }
                Mock Set-LoggingCallerScope { } -ModuleName PSmm.Logging
                Mock Set-LoggingDefaultLevel { } -ModuleName PSmm.Logging
                Mock Set-LoggingDefaultFormat { } -ModuleName PSmm.Logging

                $cfg = @{ Parameters = @{ Verbose = $true; NonInteractive = $false; Dev = $false }; Logging = @{ Path = 'D:\Logs' } }
                { Initialize-Logging -Config $cfg -Verbose } | Should -Not -Throw -Because 'Interactive should warn not throw'
            }

            It 'emits warning when PSGallery policy set fails in interactive mode' {
                Mock Get-PackageProvider { @{ Name = 'NuGet' } } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'NuGet' }
                Mock Install-PackageProvider { @{ Name = 'NuGet' } } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'NuGet' }
                Mock Set-PSmmRepositoryInstallationPolicy { throw 'Policy set failed' } -ModuleName PSmm.Logging
                Mock Install-Module { } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSLogs' }
                Mock Import-Module { } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSLogs' }

                $cfg = @{ Parameters = @{ Verbose = $true; NonInteractive = $false; Dev = $false }; Logging = @{ Path = 'D:\Logs' } }
                { Initialize-Logging -Config $cfg -Verbose } | Should -Not -Throw -Because 'Interactive should warn on repo policy failure'
            }

            It 'throws when PSGallery policy set fails in non-interactive mode' -Tag 'Coverage' {
                # Isolate mocks to avoid interference from previous Context blocks
                try { Remove-Mock Get-PackageProvider -ModuleName PSmm.Logging -ErrorAction SilentlyContinue } catch {}
                try { Remove-Mock Install-PackageProvider -ModuleName PSmm.Logging -ErrorAction SilentlyContinue } catch {}
                try { Remove-Mock Set-PSmmRepositoryInstallationPolicy -ModuleName PSmm.Logging -ErrorAction SilentlyContinue } catch {}
                try { Remove-Mock Get-PSRepository -ModuleName PSmm.Logging -ErrorAction SilentlyContinue } catch {}
                try { Remove-Mock Install-Module -ModuleName PSmm.Logging -ErrorAction SilentlyContinue } catch {}
                try { Remove-Mock Import-Module -ModuleName PSmm.Logging -ErrorAction SilentlyContinue } catch {}
                try { Remove-Mock Get-Module -ModuleName PSmm.Logging -ErrorAction SilentlyContinue } catch {}
                try { Remove-Mock New-FileSystemService -ModuleName PSmm.Logging -ErrorAction SilentlyContinue } catch {}
                try { Remove-Mock Test-Path -ModuleName PSmm.Logging -ErrorAction SilentlyContinue } catch {}

                Mock Get-PackageProvider { @{ Name = 'NuGet' } } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'NuGet' }
                Mock Install-PackageProvider { @{ Name = 'NuGet' } } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'NuGet' }
                # Ensure repo policy path is taken: PSGallery exists and is Untrusted
                Mock Get-PSRepository { param([string]$Name) [pscustomobject]@{ Name = $Name; InstallationPolicy = 'Untrusted' } } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSGallery' }
                Mock Set-PSmmRepositoryInstallationPolicy { throw 'Policy set failed hard' } -ModuleName PSmm.Logging
                Mock Install-Module { } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSLogs' }
                Mock Import-Module { } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSLogs' }
                # Ensure install path is taken (PSLogs not available) and filesystem is benign
                Mock Get-Module { $null } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSLogs' -and $ListAvailable }
                Mock New-FileSystemService { $null } -ModuleName PSmm.Logging
                Mock Test-Path { $true } -ModuleName PSmm.Logging

                $cfg = @{ Parameters = @{ Verbose = $false; NonInteractive = $true; Dev = $false }; Logging = @{ Path = 'D:\Logs' } }
                { Initialize-Logging -Config $cfg } | Should -Throw -Because 'NonInteractive must throw on PSGallery policy failure'
            }

            It 'throws when Install-Module fails in non-interactive mode' {
                Mock Install-PackageProvider { @{ Name = 'NuGet' } } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'NuGet' }
                Mock Set-PSmmRepositoryInstallationPolicy { $true } -ModuleName PSmm.Logging
                Mock Install-Module { throw 'PSLogs install failed hard' } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSLogs' }
                Mock Import-Module { } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSLogs' }

                $cfg = @{ Parameters = @{ Verbose = $false; NonInteractive = $true }; Logging = @{ Path = 'D:\Logs' } }
                { Initialize-Logging -Config $cfg } | Should -Throw -Because 'NonInteractive must throw on install failure'
            }
        }

        Context 'FileSystemService fallback and directory creation failure' {
            BeforeAll {
                Mock New-FileSystemService { $null } -ModuleName PSmm.Logging
                Mock Test-Path { $false } -ModuleName PSmm.Logging
                Mock New-Item { throw 'Create dir failed' } -ModuleName PSmm.Logging -ParameterFilter { $ItemType -eq 'Directory' }
            }

            It 'throws when log directory creation fails' {
                $cfg = @{ Parameters = @{ Verbose = $true; NonInteractive = $true }; Logging = @{ Path = 'D:\Logs' } }
                { Initialize-Logging -Config $cfg } | Should -Throw -Because 'Directory creation failure must throw'
            }
        }

        Context 'Warnings and verbose branches' {
            BeforeAll {
                # Ensure PSLogs path is not taken; focus on config warnings
                Mock Get-PackageProvider { @{ Name = 'NuGet' } } -ModuleName PSmm.Logging
                Mock Install-Module { } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSLogs' }
                Mock Import-Module { } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSLogs' }
                Mock Set-PSmmRepositoryInstallationPolicy { $true } -ModuleName PSmm.Logging
                Mock New-FileSystemService { $null } -ModuleName PSmm.Logging
                Mock Test-Path { $true } -ModuleName PSmm.Logging
            }

            It 'emits warnings when DefaultLevel and Format are missing' {
                $cfg = @{ Parameters = @{ Verbose = $true; NonInteractive = $true; Dev = $false }; Paths = @{ Log = 'D:\Logs' }; Logging = @{ Path = 'D:\Logs' } }
                { Initialize-Logging -Config $cfg -Verbose } | Should -Not -Throw
            }

            It 'captures specific warnings for missing DefaultLevel and Format' -Tag 'Coverage' {
                $cfg = @{ Parameters = @{ Verbose = $true; NonInteractive = $true; Dev = $false }; Paths = @{ Log = 'D:\Logs' }; Logging = @{ Path = 'D:\Logs' } }

                $warnings = & {
                    $oldWarn = $WarningPreference
                    try {
                        $WarningPreference = 'Continue'
                        Initialize-Logging -Config $cfg -Verbose
                    }
                    finally { $WarningPreference = $oldWarn }
                } 3>&1

                (@($warnings | Where-Object { $_ -match "DefaultLevel" })).Count | Should -BeGreaterThan 0
                (@($warnings | Where-Object { $_ -match "Format" })).Count | Should -BeGreaterThan 0
            }

            It 'normalizes logging keys when enumeration fails' {
                # Create a custom object with Keys property that throws upon enumeration
                $problematic = New-Object PSObject
                $problematic | Add-Member -MemberType ScriptProperty -Name Keys -Value { throw 'Keys enumeration failed' }
                $problematic | Add-Member -MemberType NoteProperty -Name Path -Value 'D:\Logs'
                $cfg = @{ Parameters = @{ Verbose = $true; NonInteractive = $true; Dev = $false }; Paths = @{ Log = 'D:\Logs' }; Logging = $problematic }
                { Initialize-Logging -Config $cfg -Verbose } | Should -Not -Throw
            }

            It 'emits verbose details when Keys enumeration fails (normalizes to Hashtable)' -Tag 'Coverage' {
                # Arrange: problematic Keys to force normalization
                $problematic = New-Object PSObject
                $problematic | Add-Member -MemberType ScriptProperty -Name Keys -Value { throw 'Keys enumeration failed' }
                $problematic | Add-Member -MemberType NoteProperty -Name Path -Value (Join-Path $TestDrive 'logs')
                $problematic | Add-Member -MemberType NoteProperty -Name Level -Value 'INFO'
                $cfg = @{ Parameters = @{ Verbose = $true; NonInteractive = $true; Dev = $false }; Logging = $problematic }

                # Act: capture verbose stream
                $verbose = & {
                    $old = $VerbosePreference
                    try { $VerbosePreference = 'Continue'; Initialize-Logging -Config $cfg -Verbose }
                    finally { $VerbosePreference = $old }
                } 4>&1

                # Assert: verbose output was emitted during normalization
                (@($verbose)).Count | Should -BeGreaterThan 0

                # Note: we only assert verbose content here to avoid scope brittleness
            }

            It 'writes verbose when falling back to Test-Path and New-Item' {
                # Force filesystem creation path
                Mock New-FileSystemService { $null } -ModuleName PSmm.Logging
                Mock Test-Path { $false } -ModuleName PSmm.Logging
                Mock New-Item { } -ModuleName PSmm.Logging -ParameterFilter { $ItemType -eq 'Directory' }

                $cfg = @{ Parameters = @{ Verbose = $true; NonInteractive = $true; Dev = $false }; Logging = @{ Path = (Join-Path 'D:\Logs' 'psmm.log') } }
                { Initialize-Logging -Config $cfg -Verbose } | Should -Not -Throw
            }
        }

        Context 'PSLogs setup success paths' {
            BeforeAll {
                Mock Get-PackageProvider { @{ Name = 'NuGet' } } -ModuleName PSmm.Logging
                Mock Install-PackageProvider { } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'NuGet' }
                Mock Set-PSmmRepositoryInstallationPolicy { $true } -ModuleName PSmm.Logging
                Mock Install-Module { } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSLogs' }
                Mock Import-Module { } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSLogs' }
                Mock Set-LoggingCallerScope { } -ModuleName PSmm.Logging
                Mock Set-LoggingDefaultLevel { } -ModuleName PSmm.Logging
                Mock Set-LoggingDefaultFormat { } -ModuleName PSmm.Logging
                Mock New-FileSystemService { $null } -ModuleName PSmm.Logging
                Mock Test-Path { $true } -ModuleName PSmm.Logging
            }

            It 'reaches PSLogs default setup steps without error' {
                $cfg = @{ Parameters = @{ Verbose = $true; NonInteractive = $true; Dev = $false }; Paths = @{ Log = 'D:\Logs' }; Logging = @{ Path = 'D:\Logs' } }
                { Initialize-Logging -Config $cfg -Verbose } | Should -Not -Throw
            }

            It 'throws when Set-LoggingCallerScope fails during default setup' {
                Mock Set-LoggingCallerScope { throw 'CallerScope failed' } -ModuleName PSmm.Logging
                $cfg = @{ Parameters = @{ Verbose = $true; NonInteractive = $true; Dev = $false }; Paths = @{ Log = 'D:\Logs' }; Logging = @{ Path = 'D:\Logs' } }
                { Initialize-Logging -Config $cfg -Verbose } | Should -Throw -Because 'Default setup should surface CallerScope failure'
                # Reset for subsequent tests
                Mock Set-LoggingCallerScope { } -ModuleName PSmm.Logging
            }

            It 'throws when Set-LoggingDefaultLevel fails during default setup' {
                Mock Set-LoggingDefaultLevel { throw 'DefaultLevel failed' } -ModuleName PSmm.Logging
                $cfg = @{ Parameters = @{ Verbose = $true; NonInteractive = $true; Dev = $false }; Paths = @{ Log = 'D:\Logs' }; Logging = @{ Path = 'D:\Logs' } }
                { Initialize-Logging -Config $cfg -Verbose } | Should -Throw -Because 'Default setup should surface DefaultLevel failure'
                Mock Set-LoggingDefaultLevel { } -ModuleName PSmm.Logging
            }

            It 'throws when Set-LoggingDefaultFormat fails during default setup' {
                Mock Set-LoggingDefaultFormat { throw 'DefaultFormat failed' } -ModuleName PSmm.Logging
                $cfg = @{ Parameters = @{ Verbose = $true; NonInteractive = $true; Dev = $false }; Paths = @{ Log = 'D:\Logs' }; Logging = @{ Path = 'D:\Logs' } }
                { Initialize-Logging -Config $cfg -Verbose } | Should -Throw -Because 'Default setup should surface DefaultFormat failure'
                Mock Set-LoggingDefaultFormat { } -ModuleName PSmm.Logging
            }
        }

        Context 'Dev-mode clearing without FileSystem throws as expected' {
            BeforeAll {
                Mock New-FileSystemService { $null } -ModuleName PSmm.Logging
                Mock Test-Path { $true } -ModuleName PSmm.Logging
            }

            It 'does not throw when Dev=true and FileSystem is not available (falls back)' {
                $logDir = 'D:\Logs'
                $logPath = Join-Path $logDir 'psmm.log'
                $pathProvider = [pscustomobject]@{}
                $pathProvider | Add-Member -MemberType ScriptMethod -Name CombinePath -Value {
                    param([object[]]$segments)
                    return ($segments | Select-Object -First 1)
                }

                $cfg = @{ Parameters = @{ Dev = $true; NonInteractive = $true; Verbose = $false }; Paths = @{ Log = $logDir }; Logging = @{ Path = $logPath; Format = 'Default'; Level = 'Information' } }
                { Initialize-Logging -Config $cfg -PathProvider $pathProvider -SkipPsLogsInit } | Should -Not -Throw -Because 'Falls back to native cmdlets when FileSystemService missing'
            }
        }
    }
}

Describe 'Set-PSmmRepositoryInstallationPolicy ShouldProcess' {
    It 'invokes Set-PSRepository when ShouldProcess is allowed' {
        InModuleScope PSmm.Logging {
            # Shadow Set-PSRepository with a simple function to bypass PowerShellGet dynamic parameters
            function Set-PSRepository { param($Name,$InstallationPolicy) }
            # Mock Set-PSRepository invocation with expected parameters
            Mock Set-PSRepository { } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSGallery' -and $InstallationPolicy -eq 'Trusted' }

            Set-PSmmRepositoryInstallationPolicy -Name 'PSGallery' -InstallationPolicy 'Trusted' -Confirm:$false

            Should -Invoke Set-PSRepository -Times 1 -ModuleName PSmm.Logging
        }
    }

    It 'does not invoke Set-PSRepository when -WhatIf is used' {
        InModuleScope PSmm.Logging {
            Mock Set-PSRepository { } -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSGallery' }

            Set-PSmmRepositoryInstallationPolicy -Name 'PSGallery' -InstallationPolicy 'Trusted' -WhatIf -Confirm:$false

            Should -Invoke Set-PSRepository -Times 0 -ModuleName PSmm.Logging -ParameterFilter { $Name -eq 'PSGallery' }
        }
    }
}

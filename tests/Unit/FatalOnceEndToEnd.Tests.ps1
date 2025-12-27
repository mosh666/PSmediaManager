#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Fatal once semantics (end-to-end)' {
    BeforeAll {
        $script:repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
        $modulesRoot = Join-Path -Path $script:repoRoot -ChildPath 'src\Modules'

        $script:oldTestMode = $env:MEDIA_MANAGER_TEST_MODE
        $env:MEDIA_MANAGER_TEST_MODE = '1'

        # Loader-first: import PSmm first (classes), then set ServiceContainer global, then import Logging.
        $psmmManifest = Join-Path -Path (Join-Path -Path $modulesRoot -ChildPath 'PSmm') -ChildPath 'PSmm.psd1'
        Import-Module -Name $psmmManifest -Force -Global -ErrorAction Stop
        $script:psmmModule = Get-Module -Name PSmm -ErrorAction Stop

        $script:container = $script:psmmModule.NewBoundScriptBlock({ [ServiceContainer]::new() }).InvokeReturnAsIs()
        $script:container.RegisterSingleton('FileSystem', $script:psmmModule.NewBoundScriptBlock({ [FileSystemService]::new() }).InvokeReturnAsIs())
        $script:container.RegisterSingleton('Environment', $script:psmmModule.NewBoundScriptBlock({ [EnvironmentService]::new() }).InvokeReturnAsIs())
        $script:container.RegisterSingleton('Process', $script:psmmModule.NewBoundScriptBlock({ [ProcessService]::new() }).InvokeReturnAsIs())
        $script:container.RegisterSingleton('PathProvider', $script:psmmModule.NewBoundScriptBlock({ [PathProvider]::new() }).InvokeReturnAsIs())

        # Avoid calling PowerShell class constructors with arguments in tests.
        # Class definitions are cached per session and can cause constructor overload mismatches
        # when the PSmm module has already been imported by other tests.
        $httpStub = [pscustomobject]@{}
        $httpStub | Add-Member -MemberType ScriptMethod -Name InvokeRequest -Value {
            param([string]$uri, [hashtable]$headers)
            return $null
        } -Force
        $httpStub | Add-Member -MemberType ScriptMethod -Name DownloadFile -Value {
            param([string]$uri, [string]$outFile)
            return
        } -Force
        $httpStub | Add-Member -MemberType ScriptMethod -Name InvokeRestMethod -Value {
            param([string]$uri, [string]$method, [hashtable]$headers, [object]$body)
            return $null
        } -Force
        $script:container.RegisterSingleton('Http', $httpStub)
        $script:container.RegisterSingleton('Crypto', $script:psmmModule.NewBoundScriptBlock({ [CryptoService]::new() }).InvokeReturnAsIs())

        # Replace the fatal service with a spy that always throws and counts invocations.
        # Use a PSCustomObject + ScriptMethod to avoid PowerShell class compilation issues in editors.
        $script:fatalSpy = [pscustomobject]@{ CallCount = 0 }
        $script:fatalSpy | Add-Member -MemberType ScriptMethod -Name InvokeFatal -Value {
            param(
                [string]$Context,
                [string]$Message,
                [object]$ErrorObject,
                [int]$ExitCode,
                [bool]$NonInteractive
            )
            $this.CallCount++
            $ctx = if ([string]::IsNullOrWhiteSpace($Context)) { 'Fatal' } else { $Context }
            $msg = if ([string]::IsNullOrWhiteSpace($Message)) { 'A fatal error occurred.' } else { $Message }
            $code = if ($ExitCode -le 0) { 1 } else { $ExitCode }

            # Create the fatal exception inside the PSmm module scope (types are defined there).
            $ex = $script:psmmModule.NewBoundScriptBlock({
                param(
                    [string]$Message,
                    [string]$Context,
                    [int]$ExitCode,
                    [bool]$NonInteractive
                )
                [PSmmFatalException]::new($Message, $Context, $ExitCode, $NonInteractive)
            }).InvokeReturnAsIs($msg, $ctx, $code, $NonInteractive)
            throw $ex
        } -Force
        $script:container.RegisterSingleton('FatalErrorUi', $script:fatalSpy)

        $psmmLoggingManifest = Join-Path -Path (Join-Path -Path $modulesRoot -ChildPath 'PSmm.Logging') -ChildPath 'PSmm.Logging.psd1'
        Import-Module -Name $psmmLoggingManifest -Force -Global -ErrorAction Stop
    }

    AfterAll {
        if ($null -eq $script:oldTestMode) {
            Remove-Item Env:\MEDIA_MANAGER_TEST_MODE -ErrorAction SilentlyContinue
        }
        else {
            $env:MEDIA_MANAGER_TEST_MODE = $script:oldTestMode
        }

    }

    It 'invokes fatal exactly once when first-run setup is cancelled' {
        # Build a minimal AppConfiguration in test mode (runtime root under TEMP).
        $bound = @{ NonInteractive = $true }
        $config = $script:psmmModule.NewBoundScriptBlock({
            param(
                [string] $repoRoot,
                [object] $container
            )

            $params = [RuntimeParameters]::new()
            $params.NonInteractive = $true

            $builder = ([AppConfigurationBuilder]::new()).WithRootPath($repoRoot).WithParameters($params)
            $builder = $builder.WithServices(
                $container.Resolve('FileSystem'),
                $container.Resolve('Environment'),
                $container.Resolve('PathProvider'),
                $container.Resolve('Process')
            ).InitializeDirectories()

            return $builder.GetConfig()
        }).InvokeReturnAsIs($script:repoRoot, $script:container)

        # Ensure the vault file does not exist so first-run setup path is taken.
        $vaultPath = [string]$config.Paths.App.Vault
        $dbPath = $script:container.Resolve('PathProvider').CombinePath(@($vaultPath, 'PSmm_System.kdbx'))
        if ($script:container.Resolve('FileSystem').TestPath($dbPath)) {
            try { Remove-Item -LiteralPath $dbPath -Force -ErrorAction Stop }
            catch { }
        }

        # Force the first-run setup flow to fail (cancelled).
        Mock -CommandName Invoke-FirstRunSetup -ModuleName PSmm -MockWith { return $false }

        { Invoke-PSmm -Config $config -FatalErrorUi $script:fatalSpy -FileSystem ($script:container.Resolve('FileSystem')) -Environment ($script:container.Resolve('Environment')) -PathProvider ($script:container.Resolve('PathProvider')) -Process ($script:container.Resolve('Process')) -Http ($script:container.Resolve('Http')) -Crypto ($script:container.Resolve('Crypto')) -Verbose:$false } | Should -Throw
        $script:fatalSpy.CallCount | Should -Be 1
    }
}

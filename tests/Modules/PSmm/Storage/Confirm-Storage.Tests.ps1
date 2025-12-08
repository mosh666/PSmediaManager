#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Confirm-Storage' {
    BeforeAll {
        try {
            # Set test mode flag to prevent UpdateStatus() from calling Get-PSDrive
            $env:MEDIA_MANAGER_TEST_MODE = '1'
            # Use shared test helpers to preload classes, stubs, and common setup
            $repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
            $helperPath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\Support\Import-AllTestHelpers.ps1')
            . $helperPath.Path -RepositoryRoot $repoRoot
            # Enable logging stub BEFORE importing target functions so calls bind correctly
            $stubPath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\Support\Stub-WritePSmmLog.ps1')
            . $stubPath.Path
            Enable-TestWritePSmmLogStub
            # Dot-source target functions (3 levels up from tests/Modules/PSmm/Storage)
            $confirmPath = Resolve-Path -Path (Join-Path -Path $repoRoot -ChildPath 'src\Modules\PSmm\Public\Storage\Confirm-Storage.ps1')
            . $confirmPath.Path
            $getPath = Resolve-Path -Path (Join-Path -Path $repoRoot -ChildPath 'src\Modules\PSmm\Public\Storage\Get-StorageDrive.ps1')
            . $getPath.Path
            # Ensure Write-PSmmLog is available for tests
            if (-not (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue)) {
                function Write-PSmmLog { param([string]$Level,[string]$Message,[string]$Body,[System.Management.Automation.ErrorRecord]$ErrorRecord,[string]$Context,[switch]$Console,[switch]$File) }
            }
        }
        catch {
            Write-Host "BeforeAll error (Confirm-Storage): $($_.Exception.Message)" -ForegroundColor Red
            throw
        }
    }

    AfterAll {
        $stubEnabled = Get-Variable -Name TestWritePSmmLog_Enabled -Scope Global -ErrorAction SilentlyContinue
        if ($stubEnabled -and $stubEnabled.Value) { Disable-TestWritePSmmLogStub }
        # Preserve MEDIA_MANAGER_TEST_MODE for other tests - don't delete it
        # It was set by Invoke-Pester.ps1 and should remain for the entire test suite
    }

    It 'updates Master drive letter when drive is found' {
        # Build typed AppConfiguration with StorageGroupConfig and StorageDeviceConfig
        $config = [AppConfiguration]::new()
        $config.Storage = New-Object 'System.Collections.Generic.Dictionary[string, StorageGroupConfig]'
        $sg = [StorageGroupConfig]::new()
        $sg.Master = [StorageDriveConfig]::new()
        $sg.Master.Label = 'MASTER'
        $sg.Master.SerialNumber = 'SN123'
        $sg.Master.DriveLetter = ''
        $sg.Backups = New-Object 'System.Collections.Generic.Dictionary[string, StorageDriveConfig]'
        $config.Storage.Add('1', $sg)

        # Mock Get-StorageDrive to return a matching drive
        $drive = [pscustomobject]@{ Label='MASTER'; DriveLetter='E:'; SerialNumber='SN123' }
        Mock Get-StorageDrive { @($drive) }

        Confirm-Storage -Config $config -Verbose

        $config.Storage['1'].Master.DriveLetter | Should -Be 'E:'
        $config.Storage['1'].Master.IsAvailable | Should -BeTrue
    }

    It 'marks Backup optional missing without error and clears fields' {
        # Build typed AppConfiguration with optional backup
        $config = [AppConfiguration]::new()
        $config.Storage = New-Object 'System.Collections.Generic.Dictionary[string, StorageGroupConfig]'
        $sg = [StorageGroupConfig]::new()
        $sg.Master = [StorageDriveConfig]::new()
        $sg.Master.Label = 'MASTER'
        $sg.Master.SerialNumber = 'SN000'
        $sg.Master.DriveLetter = ''
        $sg.Backups = New-Object 'System.Collections.Generic.Dictionary[string, StorageDriveConfig]'
        $bk1 = [StorageDriveConfig]::new()
        $bk1.Label = 'BK1'
        $bk1.SerialNumber = 'SN999'
        # Optional flag not present on StorageDriveConfig; emulate optional backup by leaving Empty DriveLetter
        $bk1.DriveLetter = ''
        $sg.Backups.Add('1', $bk1)
        $config.Storage.Add('1', $sg)

        # Master present, backups not found
        $drive = [pscustomobject]@{ Label='MASTER'; DriveLetter='D:'; SerialNumber='SN000' }
        Mock Get-StorageDrive { @($drive) }

        Confirm-Storage -Config $config -Verbose

        # Optional backup should be unavailable and cleared
        $bk = $config.Storage['1'].Backups['1']
        $bk.IsAvailable | Should -BeFalse
        [string]::IsNullOrWhiteSpace($bk.DriveLetter) | Should -BeTrue
    }
}

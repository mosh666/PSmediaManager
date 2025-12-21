<#
.SYNOPSIS
    ExifTool
#>

Set-StrictMode -Version Latest

if (-not (Get-Command -Name Get-PSmmPluginsConfigMemberValue -ErrorAction SilentlyContinue)) {
    $configHelpersPath = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..') -ChildPath 'ConfigMemberAccessHelpers.ps1'
    if (Test-Path -Path $configHelpersPath) {
        . $configHelpersPath
    }
}

#region ########## PRIVATE ##########

function Get-CurrentVersion-ExifTool {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        $ServiceContainer
    )

    # Resolve FileSystem from ServiceContainer if available
    $FileSystem = $null
    if ($null -ne $ServiceContainer) {
        try {
            $FileSystem = $ServiceContainer.Resolve('FileSystem')
        }
        catch {
            Write-Verbose "Failed to resolve FileSystem from ServiceContainer: $_"
        }
    }

    $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'ExifTool' }

    if ($FileSystem) {
        $InstallPath = @($FileSystem.GetChildItem($Paths.Root, "$pluginName*", 'Directory')) | Select-Object -First 1
    }
    else {
        $InstallPath = Get-ChildItem -Path $Paths.Root -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$pluginName*" }
    }

    if ($InstallPath) {
        $commandPath = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'CommandPath')
        $command = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Command')
        $bin = Join-Path -Path $InstallPath -ChildPath $commandPath -AdditionalChildPath $command
        $CurrentVersion = (& $bin -ver)
        return $CurrentVersion
    }
    else {
        return ''
    }
}

function Get-LatestUrlFromUrl-ExifTool {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        $ServiceContainer
    )
    $null = $Paths, $ServiceContainer
    $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'ExifTool' }
    $versionUrl = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'VersionUrl')
    $baseUri = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'BaseUri')

    $LatestVersion = Invoke-RestMethod -Uri $versionUrl
    $LatestVersion = '{0:N2}' -f $LatestVersion
    $LatestVersion = $LatestVersion -replace ',', '.'
    $LatestInstaller = "exiftool-$($LatestVersion)_64.zip"

    $state = Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'State'
    if ($null -eq $state) {
        $state = @{}
        Set-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'State' -Value $state
    }
    Set-PSmmPluginsConfigMemberValue -Object $state -Name 'LatestVersion' -Value $LatestVersion
    Set-PSmmPluginsConfigMemberValue -Object $state -Name 'LatestInstaller' -Value $LatestInstaller

    $Url = $baseUri + '/' + $LatestInstaller

    return $Url
}

function Invoke-Installer-ExifTool {
    param (
        [hashtable]$Plugin,
        [hashtable]$Paths,
        [string]$InstallerPath,
        [Parameter(Mandatory)]
        $ServiceContainer
    )

    try {
        # Resolve FileSystem from ServiceContainer if available
        if ($null -ne $ServiceContainer) {
            try {
                $null = $ServiceContainer.Resolve('FileSystem')
            }
            catch {
                Write-Verbose "Failed to resolve FileSystem from ServiceContainer: $_"
            }
        }

        $ExtractPath = $Paths.Root
        Expand-Archive -Path $InstallerPath -DestinationPath $ExtractPath -Force

        # Find the extracted exiftool directory
        $ExiftoolDir = Get-ChildItem -Path $ExtractPath -Directory -Filter "exiftool-*_64" -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($ExiftoolDir) {
            # Find and rename the executable file (handles both formats: exiftool(-k).exe and exiftool.exe)
            $ExeFile = Get-ChildItem -Path $ExiftoolDir.FullName -Filter "exiftool*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1

            if ($ExeFile -and $ExeFile.Name -ne 'exiftool.exe') {
                Rename-Item -Path $ExeFile.FullName -NewName 'exiftool.exe' -Force -ErrorAction Stop
            }

            $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
            $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
            if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'ExifTool' }
            Write-PSmmLog -Level SUCCESS -Context "Install $pluginName" -Message "Installation completed for $($InstallerPath)" -Console -File
        }
        else {
            throw "ExifTool directory not found after extraction"
        }
    }
    catch {
        $pn = 'ExifTool'
        try {
            $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
            $pnCandidate = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
            if (-not [string]::IsNullOrWhiteSpace($pnCandidate)) { $pn = $pnCandidate }
        }
        catch {
            Write-Verbose "Install ExifTool: failed to get plugin name from config: $($_.Exception.Message)"
        }
        Write-PSmmLog -Level ERROR -Context "Install $pn" -Message "Installation failed for $($InstallerPath)" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########

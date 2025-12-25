<#
.SYNOPSIS
    7-Zip
#>

Set-StrictMode -Version Latest

if (-not (Get-Command -Name Get-PSmmPluginsConfigMemberValue -ErrorAction SilentlyContinue)) {
    throw "Get-PSmmPluginsConfigMemberValue is not available. Ensure PSmm.Plugins is imported before loading plugin definitions."
}

#region ########## PRIVATE ##########

function Get-CurrentVersion-7z {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $FileSystem
    )

    $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = '7-Zip' }

    $command = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Command')
    if ([string]::IsNullOrWhiteSpace($command)) { return '' }

    $CurrentVersion = @($FileSystem.GetChildItem($Paths.Root, $command, 'File', $true)) | Select-Object -First 1

    if ($CurrentVersion) {
        return $CurrentVersion.VersionInfo.FileVersion
    }
    else {
        return ''
    }
}

function Invoke-Installer-7z {
    param (
        [hashtable]$Plugin,
        [hashtable]$Paths,
        [string]$InstallerPath,
        $Process,
        $FileSystem,
        $Environment,
        $PathProvider
    )
    $null = $FileSystem, $Environment, $PathProvider
    $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = '7-Zip' }

    try {
        $ExtractPath = Join-Path -Path $Paths.Root -ChildPath (Split-Path $InstallerPath -LeafBase)
        if ($null -eq $Process) {
            throw [System.InvalidOperationException]::new('Process service is required to install 7-Zip')
        }

        $result = $Process.StartProcess($InstallerPath, @('/S', "/D=$($ExtractPath)\"))
        if ($result -and -not $result.Success) {
            throw [System.Exception]::new("Installer exited with code $($result.ExitCode). StdErr: $($result.StdErr)")
        }
        Write-PSmmLog -Level SUCCESS -Context "Install $pluginName" -Message "Installation completed for $($InstallerPath)" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Install $pluginName" -Message "Installation failed for $($InstallerPath)" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########

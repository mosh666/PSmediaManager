<#
.SYNOPSIS
    Git-LFS
#>

Set-StrictMode -Version Latest

if (-not (Get-Command -Name Get-PSmmPluginsConfigMemberValue -ErrorAction SilentlyContinue)) {
    throw "Get-PSmmPluginsConfigMemberValue is not available. Ensure PSmm.Plugins is imported before loading plugin definitions."
}

#region ########## PRIVATE ##########

function Get-CurrentVersion-Git-LFS {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $FileSystem
    )

    $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'Git-LFS' }

    $CurrentVersion = @($FileSystem.GetChildItem($Paths.Root, "$pluginName*", 'Directory')) | Select-Object -First 1

    if ($CurrentVersion) {
        return 'v' + $CurrentVersion.BaseName.Split('-')[2]
    }
    else {
        return ''
    }
}

function Invoke-Installer-Git-LFS {
    param (
        [hashtable]$Plugin,
        [hashtable]$Paths,
        [string]$InstallerPath,
        $Process,
        $FileSystem,
        $Environment,
        $PathProvider
    )
    $null = $Process, $Environment, $PathProvider
    $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'Git-LFS' }

    try {
        $ExtractPath = $Paths.Root
        if ($null -eq $FileSystem) {
            throw [System.InvalidOperationException]::new('FileSystem service is required to extract Git-LFS zip')
        }

        $FileSystem.ExtractZip($InstallerPath, $ExtractPath, $true)
        Write-PSmmLog -Level SUCCESS -Context "Install $pluginName" -Message "Installation completed for $($InstallerPath)" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Install $pluginName" -Message "Installation failed for $($InstallerPath)" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########

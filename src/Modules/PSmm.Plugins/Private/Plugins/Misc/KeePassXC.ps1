<#
.SYNOPSIS
    KeePassXC
#>

Set-StrictMode -Version Latest

if (-not (Get-Command -Name Get-PSmmPluginsConfigMemberValue -ErrorAction SilentlyContinue)) {
    throw "Get-PSmmPluginsConfigMemberValue is not available. Ensure PSmm.Plugins is imported before loading plugin definitions."
}

#region ########## PRIVATE ##########

function Get-CurrentVersion-KeePassXC {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $FileSystem,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Process
    )

    $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'KeePassXC' }

    $InstallPath = @($FileSystem.GetChildItem($Paths.Root, "$pluginName*", 'Directory')) | Select-Object -First 1

    if ($InstallPath) {
        $commandPath = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'CommandPath')
        $command = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Command')
        $bin = Join-Path -Path $InstallPath -ChildPath $commandPath -AdditionalChildPath $command
        $result = $Process.StartProcess($bin, @('--version'))
        if ($result -and -not $result.Success) {
            throw [System.Exception]::new("Failed to execute $bin (--version). ExitCode=$($result.ExitCode)")
        }

        return ([string]$result.StdOut).Trim()
    }
    else {
        return ''
    }
}

function Invoke-Installer-KeePassXC {
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
    try {
        $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
        $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
        if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'KeePassXC' }
        $ExtractPath = $Paths.Root
        if ($null -eq $FileSystem) {
            throw [System.InvalidOperationException]::new('FileSystem service is required to extract KeePassXC zip')
        }

        $FileSystem.ExtractZip($InstallerPath, $ExtractPath, $true)
        Write-PSmmLog -Level SUCCESS -Context "Install $pluginName" -Message "Installation completed for $($InstallerPath)" -Console -File
    }
    catch {
        $pn = 'KeePassXC'
        try {
            $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
            $pnCandidate = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
            if (-not [string]::IsNullOrWhiteSpace($pnCandidate)) { $pn = $pnCandidate }
        }
        catch {
            Write-Verbose "Invoke-Installer-KeePassXC: failed to resolve plugin name: $($_.Exception.Message)"
        }
        Write-PSmmLog -Level ERROR -Context "Install $pn" -Message "Installation failed for $($InstallerPath)" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########

<#
.SYNOPSIS
    GitVersion
#>

Set-StrictMode -Version Latest

if (-not (Get-Command -Name Get-PSmmPluginsConfigMemberValue -ErrorAction SilentlyContinue)) {
    throw "Get-PSmmPluginsConfigMemberValue is not available. Ensure PSmm.Plugins is imported before loading plugin definitions."
}

#region ########## PRIVATE ##########

function Get-CurrentVersion-GitVersion {
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
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'GitVersion' }

    $InstallPath = @($FileSystem.GetChildItem($Paths.Root, "$pluginName*", 'Directory')) | Select-Object -First 1

    if ($InstallPath) {
        $commandPath = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'CommandPath')
        $command = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Command')
        if ([string]::IsNullOrWhiteSpace($commandPath) -or [string]::IsNullOrWhiteSpace($command)) {
            return ''
        }

        $bin = Join-Path -Path $InstallPath -ChildPath $commandPath -AdditionalChildPath $command
        $result = $Process.StartProcess($bin, @('-version'))
        if ($result -and -not $result.Success) {
            throw [System.Exception]::new("Failed to execute $bin (-version). ExitCode=$($result.ExitCode)")
        }

        $text = ([string]$result.StdOut).Trim()
        return $text.Split('+')[0]
    }
    else {
        return ''
    }
}

#endregion ########## PRIVATE ##########

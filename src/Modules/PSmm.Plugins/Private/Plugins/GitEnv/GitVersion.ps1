<#
.SYNOPSIS
    GitVersion
#>

Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function Get-CurrentVersion-GitVersion {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths
    )
    if ($InstallPath = Get-ChildItem -Path $Paths.Root -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($Plugin.Config.Name)*" }) {
        $bin = Join-Path -Path $InstallPath -ChildPath $Plugin.Config.CommandPath -AdditionalChildPath $Plugin.Config.Command
        $CurrentVersion = (& $bin -version)
        return $CurrentVersion.Split('+')[0]
    }
    else {
        return ''
    }
}

#endregion ########## PRIVATE ##########

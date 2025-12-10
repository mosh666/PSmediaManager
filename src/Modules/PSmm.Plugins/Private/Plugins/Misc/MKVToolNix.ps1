<#
.SYNOPSIS
    MKVToolNix
#>

Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function Get-CurrentVersion-MKVToolNix {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        $ServiceContainer
    )

    # Resolve FileSystem from ServiceContainer if available
    $FileSystem = $null
    if ($null -ne $ServiceContainer -and ($ServiceContainer.PSObject.Methods.Name -contains 'Resolve')) {
        try {
            $FileSystem = $ServiceContainer.Resolve('FileSystem')
        }
        catch {
            Write-Verbose "Failed to resolve FileSystem from ServiceContainer: $_"
        }
    }

    if ($FileSystem) {
        $InstallPath = @($FileSystem.GetChildItem($Paths.Root, "$($Plugin.Config.Name)*", 'Directory')) | Select-Object -First 1
    }
    else {
        $InstallPath = Get-ChildItem -Path $Paths.Root -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($Plugin.Config.Name)*" }
    }

    if ($InstallPath) {
        $bin = Join-Path -Path $InstallPath -ChildPath $Plugin.Config.CommandPath -AdditionalChildPath $Plugin.Config.Command
        $CurrentVersion = (& $bin --version)
        return $CurrentVersion.Split(' ')[1].Substring(1)
    }
    else {
        return ''
    }
}

function Get-LatestUrlFromUrl-MKVToolNix {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        $ServiceContainer
    )
    $null = $Paths, $ServiceContainer
    $Response = Invoke-WebRequest -Uri $Plugin.Config.VersionUrl
    # Get the latest version
    if ($Response.Links) {
        # Extract version numbers from the links
        $Versions = $Response.Links | Where-Object { $_.href -match '(\d+\.\d+)/$' } | ForEach-Object { $matches[1] } | Sort-Object { [version]$_ } -Descending
        # Ensure versions were found
        if ($Versions.Count -gt 0) {
            $LatestVersion = $Versions[0]
        }
        else {
            Write-Error 'No valid versions found.'
            exit
        }
    }
    # Ensure State exists
    if (-not $Plugin.Config.ContainsKey('State') -or $null -eq $Plugin.Config.State) { $Plugin.Config.State = @{} }
    # Use correctly-cased variable name
    $LatestInstaller = "$(($Plugin.Config.Name))-64-bit-$LatestVersion.7z"
    $Plugin.Config.State.LatestVersion = $LatestVersion
    $Plugin.Config.State.LatestInstaller = $LatestInstaller
    $Url = $Plugin.Config.VersionUrl + $LatestVersion + '/' + $LatestInstaller
    return $Url
}

function Invoke-Installer-MKVToolNix {
    param (
        [hashtable]$Plugin,
        [hashtable]$Paths,
        [string]$InstallerPath,
        $ServiceContainer
    )

    # Resolve Process and FileSystem from ServiceContainer if available
    $Process = $null
    $FileSystem = $null
    if ($null -ne $ServiceContainer -and ($ServiceContainer.PSObject.Methods.Name -contains 'Resolve')) {
        try {
            $Process = $ServiceContainer.Resolve('Process')
            $FileSystem = $ServiceContainer.Resolve('FileSystem')
        }
        catch {
            Write-Verbose "Failed to resolve services from ServiceContainer: $_"
        }
    }

    try {
        $ExtractPath = $Paths.Root

        # Ensure extraction directory exists
        if ($FileSystem -and -not $FileSystem.TestPath($ExtractPath)) {
            $FileSystem.NewItem($ExtractPath, 'Directory')
        }
        elseif (-not $FileSystem -and -not (Test-Path $ExtractPath)) {
            New-Item -Path $ExtractPath -ItemType Directory -Force | Out-Null
        }

        # Use 7z.exe to extract the archive
        if ($Process) {
            $sevenZipCmd = Resolve-PluginCommandPath -Paths $Paths -CommandName '7z' -DefaultCommand '7z' -FileSystem $FileSystem -Process $Process
        }
        else {
            $sevenZipCmd = '7z'
        }

        # Extract archive
        $result = if ($Process) {
            $Process.InvokeCommand($sevenZipCmd, @('x', $InstallerPath, "-o$ExtractPath", '-y'))
        }
        else {
            & $sevenZipCmd x $InstallerPath "-o$ExtractPath" -y
        }

        if ($Process -and -not $result.Success) {
            $ex = [System.Exception]::new("7z extraction failed with exit code: $($result.ExitCode)")
            throw $ex
        }

        Write-PSmmLog -Level SUCCESS -Context "Install $($Plugin.Config.Name)" -Message "Installation completed for $($InstallerPath)" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Install $($Plugin.Config.Name)" -Message "Installation failed for $($InstallerPath)" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########

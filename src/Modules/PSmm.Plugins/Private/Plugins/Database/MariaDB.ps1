<#
.SYNOPSIS
    MariaDB
#>

Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function Get-CurrentVersion-MariaDB {
    param(
        [hashtable]$Plugin
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
        $CurrentVersion = @($FileSystem.GetChildItem($Paths.Root, "$($Plugin.Config.Name)*", 'Directory')) | Select-Object -First 1
    }
    else {
        $CurrentVersion = Get-ChildItem -Path $Paths.Root -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($Plugin.Config.Name)*" }
    }

    if ($CurrentVersion) {
        return $CurrentVersion.BaseName.Split('-')[1]
    }
    else {
        return ''
    }
}

function Get-LatestUrlFromUrl-MariaDB {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        $ServiceContainer
    )
    $null = $Paths, $ServiceContainer
    $MajorReleases = Invoke-RestMethod -Uri $Plugin.Config.VersionUrl
    $LatestMajorReleaseId = $MajorReleases.major_releases | Where-Object release_status -EQ 'Stable' | Where-Object release_support_type -EQ 'Long Term Support' | Sort-Object -Property release_id -Descending | Select-Object -First 1 -ExpandProperty release_id
    $PointReleases = Invoke-RestMethod -Uri ("$($Plugin.Config.VersionUrl)$LatestMajorReleaseId/")
    $LatestPointReleaseId = ($PointReleases.releases | Get-Member -MemberType NoteProperty | Sort-Object -Descending | Select-Object -First 1).Name
    $Plugin.Config.State.LatestVersion = $LatestPointReleaseId
    $Files = Invoke-RestMethod -Uri "$($Plugin.Config.VersionUrl)$latestPointReleaseId/"
    $File = $Files.release_data.$LatestPointReleaseId.files | Where-Object { $_.file_name -like '*winx64.zip' } | Select-Object -First 1
    $Plugin.Config.State.LatestInstaller = $File.file_name
    $Url = $File.file_download_url
    return $Url
}

function Invoke-Installer-MariaDB {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Plugin,

        [Parameter(Mandatory)]
        [hashtable]$Paths,

        [Parameter(Mandatory)]
        [string]$InstallerPath,

        $ServiceContainer
    )

    # Resolve optional services for IO and process execution
    $FileSystem = $null
    $Process = $null
    if ($null -ne $ServiceContainer -and ($ServiceContainer.PSObject.Methods.Name -contains 'Resolve')) {
        try {
            $FileSystem = $ServiceContainer.Resolve('FileSystem')
        }
        catch {
            Write-Verbose "Failed to resolve FileSystem from ServiceContainer: $_"
        }

        try {
            $Process = $ServiceContainer.Resolve('Process')
        }
        catch {
            Write-Verbose "Failed to resolve Process from ServiceContainer: $_"
        }
    }

    $destinationRoot = $Paths.Root

    try {
        if ($FileSystem) {
            if (-not $FileSystem.TestPath($destinationRoot)) {
                $FileSystem.NewItem($destinationRoot, 'Directory') | Out-Null
            }
        }
        elseif (-not (Test-Path -LiteralPath $destinationRoot)) {
            New-Item -Path $destinationRoot -ItemType Directory -Force | Out-Null
        }

        $targetVersion = $null
        if ($Plugin.Config.PSObject.Properties.Name -contains 'Version' -and $Plugin.Config.Version) {
            $targetVersion = $Plugin.Config.Version
        }
        elseif ($Plugin.Config.PSObject.Properties.Name -contains 'State' -and $Plugin.Config.State -and $Plugin.Config.State.LatestVersion) {
            $targetVersion = $Plugin.Config.State.LatestVersion
        }
        else {
            $targetVersion = (Split-Path -Path $InstallerPath -LeafBase) -replace '^mariadb-', ''
        }

        $currentVersion = Get-CurrentVersion-MariaDB -Plugin $Plugin
        if ($currentVersion -and $targetVersion -and $currentVersion -eq $targetVersion) {
            Write-PSmmLog -Level INFO -Context "Install $($Plugin.Config.Name)" -Message "MariaDB $targetVersion already installed" -Console -File
            return
        }

        Write-PSmmLog -Level INFO -Context "Install $($Plugin.Config.Name)" -Message "Installing MariaDB $targetVersion from $InstallerPath" -Console -File

        $extracted = $false

        if ($Process) {
            try {
                $sevenZipCmd = Resolve-PluginCommandPath -Paths $Paths -CommandName '7z' -DefaultCommand '7z' -FileSystem $FileSystem -Process $Process
                $result = $Process.InvokeCommand($sevenZipCmd, @('x', $InstallerPath, "-o$destinationRoot", '-y'))

                if ($result -and -not $result.Success) {
                    throw [System.Exception]::new("7z extraction failed with exit code $($result.ExitCode)")
                }

                $extracted = $true
            }
            catch {
                Write-Verbose "7z extraction attempt failed or 7z not available: $_"
            }
        }

        if (-not $extracted) {
            Expand-Archive -Path $InstallerPath -DestinationPath $destinationRoot -Force
            $extracted = $true
        }

        Write-PSmmLog -Level SUCCESS -Context "Install $($Plugin.Config.Name)" -Message "Installation completed for $InstallerPath" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Install $($Plugin.Config.Name)" -Message "Failed to install from $InstallerPath" -ErrorRecord $_ -Console -File
        throw
    }
}

#endregion ########## PRIVATE ##########

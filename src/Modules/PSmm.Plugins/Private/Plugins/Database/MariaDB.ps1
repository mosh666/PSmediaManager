<#
.SYNOPSIS
    MariaDB
#>

Set-StrictMode -Version Latest

if (-not (Get-Command -Name Get-PSmmPluginsConfigMemberValue -ErrorAction SilentlyContinue)) {
    throw "Get-PSmmPluginsConfigMemberValue is not available. Ensure PSmm.Plugins is imported before loading plugin definitions."
}

#region ########## PRIVATE ##########

function Get-CurrentVersion-MariaDB {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $FileSystem
    )

    $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'MariaDB' }

    $CurrentVersion = @($FileSystem.GetChildItem($Paths.Root, "$pluginName*", 'Directory')) | Select-Object -First 1

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
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Http,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Crypto,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $FileSystem,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Environment,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $PathProvider,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Process
    )
    $null = $Paths, $Http, $Crypto, $FileSystem, $Environment, $PathProvider, $Process

    $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
    $versionUrl = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'VersionUrl')
    if ([string]::IsNullOrWhiteSpace($versionUrl)) {
        throw [System.InvalidOperationException]::new('Plugin config is missing VersionUrl')
    }

    $MajorReleases = $Http.InvokeRestMethod($versionUrl, 'GET', $null, $null)
    $LatestMajorReleaseId = $MajorReleases.major_releases | Where-Object release_status -EQ 'Stable' | Where-Object release_support_type -EQ 'Long Term Support' | Sort-Object -Property release_id -Descending | Select-Object -First 1 -ExpandProperty release_id
    $PointReleases = $Http.InvokeRestMethod("$versionUrl$LatestMajorReleaseId/", 'GET', $null, $null)
    $LatestPointReleaseId = ($PointReleases.releases | Get-Member -MemberType NoteProperty | Sort-Object -Descending | Select-Object -First 1).Name

    $state = Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'State'
    if ($null -eq $state) {
        $state = @{}
        Set-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'State' -Value $state
    }

    Set-PSmmPluginsConfigMemberValue -Object $state -Name 'LatestVersion' -Value $LatestPointReleaseId

    $Files = $Http.InvokeRestMethod("$versionUrl$latestPointReleaseId/", 'GET', $null, $null)
    $File = $Files.release_data.$LatestPointReleaseId.files | Where-Object { $_.file_name -like '*winx64.zip' } | Select-Object -First 1
    Set-PSmmPluginsConfigMemberValue -Object $state -Name 'LatestInstaller' -Value $File.file_name
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

        $Process,
        $FileSystem,
        $Environment,
        $PathProvider
    )
    $null = $Environment, $PathProvider

    $destinationRoot = $Paths.Root

    $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'MariaDB' }

    try {
        if ($FileSystem) {
            if (-not $FileSystem.TestPath($destinationRoot)) {
                $FileSystem.NewItem($destinationRoot, 'Directory') | Out-Null
            }
        }
        elseif (-not (Test-Path -LiteralPath $destinationRoot)) {
            New-Item -Path $destinationRoot -ItemType Directory -Force | Out-Null
        }

        $targetVersion = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Version')
        if ([string]::IsNullOrWhiteSpace($targetVersion)) {
            $state = Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'State'
            $targetVersion = [string](Get-PSmmPluginsConfigMemberValue -Object $state -Name 'LatestVersion')
        }

        if ([string]::IsNullOrWhiteSpace($targetVersion)) {
            $targetVersion = (Split-Path -Path $InstallerPath -LeafBase) -replace '^mariadb-', ''
        }

        $currentVersion = Get-CurrentVersion-MariaDB -Plugin $Plugin -Paths $Paths -FileSystem $FileSystem
        if ($currentVersion -and $targetVersion -and $currentVersion -eq $targetVersion) {
            Write-PSmmLog -Level INFO -Context "Install $pluginName" -Message "MariaDB $targetVersion already installed" -Console -File
            return
        }

        Write-PSmmLog -Level INFO -Context "Install $pluginName" -Message "Installing MariaDB $targetVersion from $InstallerPath" -Console -File

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
            if ($null -eq $FileSystem) {
                throw [System.InvalidOperationException]::new('FileSystem service is required to extract MariaDB zip')
            }

            $FileSystem.ExtractZip($InstallerPath, $destinationRoot, $true)
            $extracted = $true
        }

        Write-PSmmLog -Level SUCCESS -Context "Install $pluginName" -Message "Installation completed for $InstallerPath" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Install $pluginName" -Message "Failed to install from $InstallerPath" -ErrorRecord $_ -Console -File
        throw
    }
}


#endregion ########## PRIVATE ##########

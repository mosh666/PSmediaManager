<#
.SYNOPSIS
    MariaDB
#>

Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function Get-ConfigMemberValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    if ($Object -is [System.Collections.IDictionary]) {
        try {
            if ($Object.ContainsKey($Name)) { return $Object[$Name] }
        }
        catch { }

        try {
            if ($Object.Contains($Name)) { return $Object[$Name] }
        }
        catch { }

        try {
            foreach ($k in $Object.Keys) {
                if ($k -eq $Name) { return $Object[$k] }
            }
        }
        catch { }

        return $null
    }

    try {
        $p = $Object.PSObject.Properties[$Name]
        if ($null -ne $p) { return $p.Value }
    }
    catch { }

    return $null
}

function Set-ConfigMemberValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Object) {
        return
    }

    if ($Object -is [System.Collections.IDictionary]) {
        $Object[$Name] = $Value
        return
    }

    try {
        $Object.$Name = $Value
        return
    }
    catch { }

    try {
        if ($null -eq $Object.PSObject.Properties[$Name]) {
            $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
        }
        else {
            $Object.PSObject.Properties[$Name].Value = $Value
        }
    }
    catch { }
}

function Get-CurrentVersion-MariaDB {
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

    $pluginConfig = Get-ConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'MariaDB' }

    if ($FileSystem) {
        $CurrentVersion = @($FileSystem.GetChildItem($Paths.Root, "$pluginName*", 'Directory')) | Select-Object -First 1
    }
    else {
        $CurrentVersion = Get-ChildItem -Path $Paths.Root -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$pluginName*" }
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

    $pluginConfig = Get-ConfigMemberValue -Object $Plugin -Name 'Config'
    $versionUrl = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'VersionUrl')
    if ([string]::IsNullOrWhiteSpace($versionUrl)) {
        throw [System.InvalidOperationException]::new('Plugin config is missing VersionUrl')
    }

    $MajorReleases = Invoke-RestMethod -Uri $versionUrl
    $LatestMajorReleaseId = $MajorReleases.major_releases | Where-Object release_status -EQ 'Stable' | Where-Object release_support_type -EQ 'Long Term Support' | Sort-Object -Property release_id -Descending | Select-Object -First 1 -ExpandProperty release_id
    $PointReleases = Invoke-RestMethod -Uri ("$versionUrl$LatestMajorReleaseId/")
    $LatestPointReleaseId = ($PointReleases.releases | Get-Member -MemberType NoteProperty | Sort-Object -Descending | Select-Object -First 1).Name

    $state = Get-ConfigMemberValue -Object $pluginConfig -Name 'State'
    if ($null -eq $state) {
        $state = @{}
        Set-ConfigMemberValue -Object $pluginConfig -Name 'State' -Value $state
    }

    Set-ConfigMemberValue -Object $state -Name 'LatestVersion' -Value $LatestPointReleaseId

    $Files = Invoke-RestMethod -Uri "$versionUrl$latestPointReleaseId/"
    $File = $Files.release_data.$LatestPointReleaseId.files | Where-Object { $_.file_name -like '*winx64.zip' } | Select-Object -First 1
    Set-ConfigMemberValue -Object $state -Name 'LatestInstaller' -Value $File.file_name
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

    $pluginConfig = Get-ConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'Name')
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

        $targetVersion = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'Version')
        if ([string]::IsNullOrWhiteSpace($targetVersion)) {
            $state = Get-ConfigMemberValue -Object $pluginConfig -Name 'State'
            $targetVersion = [string](Get-ConfigMemberValue -Object $state -Name 'LatestVersion')
        }

        if ([string]::IsNullOrWhiteSpace($targetVersion)) {
            $targetVersion = (Split-Path -Path $InstallerPath -LeafBase) -replace '^mariadb-', ''
        }

        $currentVersion = Get-CurrentVersion-MariaDB -Plugin $Plugin -Paths $Paths -ServiceContainer $ServiceContainer
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
            Expand-Archive -Path $InstallerPath -DestinationPath $destinationRoot -Force
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

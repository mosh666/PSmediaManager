<#
.SYNOPSIS
    digiKam
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

function Get-CurrentVersion-digiKam {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        $ServiceContainer
    )

    # Resolve FileSystem from ServiceContainer if available, otherwise create fallback
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
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'digiKam' }

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

function Get-LatestUrlFromUrl-digiKam {
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

    $Response = Invoke-WebRequest -Uri $versionUrl
    $VersionPattern = '(\d+\.\d+\.\d+)/'
    $Match = [regex]::Matches($Response.Content, $VersionPattern)
    $LatestVersion = ($Match | ForEach-Object { $_.Groups[1].Value }) | Sort-Object -Descending | Select-Object -First 1

    $DownloadPageUrl = "$versionUrl$LatestVersion/"
    $Response = Invoke-WebRequest -Uri "$($DownloadPageUrl)"
    $LatestInstaller = [regex]::Match($Response.Content, '(digiKam-\d+\.\d+\.\d+-Qt6-Win64.exe)').Groups[1].Value

    $state = Get-ConfigMemberValue -Object $pluginConfig -Name 'State'
    if ($null -eq $state) {
        $state = @{}
        Set-ConfigMemberValue -Object $pluginConfig -Name 'State' -Value $state
    }

    Set-ConfigMemberValue -Object $state -Name 'LatestVersion' -Value $LatestVersion
    Set-ConfigMemberValue -Object $state -Name 'LatestInstaller' -Value $LatestInstaller
    $Url = $DownloadPageUrl + $LatestInstaller
    return $Url
}

function Invoke-Installer-digiKam {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [hashtable]$Plugin,

        [Parameter(Mandatory)]
        [hashtable]$Paths,

        [Parameter(Mandatory)]
        [string]$InstallerPath,

        $ServiceContainer
    )

    # Resolve optional services
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

    $pluginConfig = Get-ConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'digiKam' }

    try {
        $extractPath = Join-Path -Path $Paths.Root -ChildPath (Split-Path $InstallerPath -LeafBase)

        if ($FileSystem) {
            if (-not $FileSystem.TestPath($extractPath)) {
                $FileSystem.NewItem($extractPath, 'Directory') | Out-Null
            }
        }
        elseif (-not (Test-Path -LiteralPath $extractPath)) {
            New-Item -Path $extractPath -ItemType Directory -Force | Out-Null
        }

        $sevenZipCmd = $null
        if ($Process) {
            try {
                $sevenZipCmd = Resolve-PluginCommandPath -Paths $Paths -CommandName '7z' -DefaultCommand '7z' -FileSystem $FileSystem -Process $Process
            }
            catch {
                Write-Verbose "Unable to resolve 7z via Process service: $_"
            }
        }

        if (-not $sevenZipCmd) {
            $sevenZipCmd = (Get-Command -Name '7z' -ErrorAction SilentlyContinue)?.Source
        }

        if (-not $sevenZipCmd) {
            throw [System.InvalidOperationException]::new('7z command is required to extract digiKam installer but was not found')
        }

        $arguments = @('x', $InstallerPath, "-o$extractPath", '-y')

        if ($Process) {
            $result = $Process.InvokeCommand($sevenZipCmd, $arguments)
            if ($result -and -not $result.Success) {
                throw [System.Exception]::new("7z extraction failed with exit code $($result.ExitCode)")
            }
        }
        else {
            $nativeResult = & $sevenZipCmd @('x', $InstallerPath, "-o$extractPath", '-y')
            if ($LASTEXITCODE -ne 0) {
                throw [System.Exception]::new("7z extraction failed with exit code $LASTEXITCODE. Output: $nativeResult")
            }
        }

        Write-PSmmLog -Level SUCCESS -Context "Install $pluginName" -Message "Installation completed for $InstallerPath" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Install $pluginName" -Message "Installation failed for $InstallerPath" -ErrorRecord $_ -Console -File
        throw
    }
}

#endregion ########## PRIVATE ##########

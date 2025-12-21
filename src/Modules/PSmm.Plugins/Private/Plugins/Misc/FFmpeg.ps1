<#
.SYNOPSIS
    FFmpeg
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
        catch {
            Write-Verbose "Get-ConfigMemberValue: IDictionary.ContainsKey failed: $($_.Exception.Message)"
        }

        try {
            if ($Object.Contains($Name)) { return $Object[$Name] }
        }
        catch {
            Write-Verbose "Get-ConfigMemberValue: IDictionary.Contains failed: $($_.Exception.Message)"
        }

        try {
            foreach ($k in $Object.Keys) {
                if ($k -eq $Name) { return $Object[$k] }
            }
        }
        catch {
            Write-Verbose "Get-ConfigMemberValue: IDictionary.Keys iteration failed: $($_.Exception.Message)"
        }

        return $null
    }

    try {
        $p = $Object.PSObject.Properties[$Name]
        if ($null -ne $p) { return $p.Value }
    }
    catch {
        Write-Verbose "Get-ConfigMemberValue: PSObject property lookup failed: $($_.Exception.Message)"
    }

    return $null
}

function Set-ConfigMemberValue {
    [CmdletBinding(SupportsShouldProcess = $true)]
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
        if (-not $PSCmdlet.ShouldProcess("$Name", 'Set config value')) {
            return
        }
        $Object[$Name] = $Value
        return
    }

    try {
        if (-not $PSCmdlet.ShouldProcess("$Name", 'Set config value')) {
            return
        }
        $Object.$Name = $Value
        return
    }
    catch {
        Write-Verbose "Set-ConfigMemberValue: direct assignment failed: $($_.Exception.Message)"
    }

    try {
        if (-not $PSCmdlet.ShouldProcess("$Name", 'Set config value')) {
            return
        }
        if ($null -eq $Object.PSObject.Properties[$Name]) {
            $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
        }
        else {
            $Object.PSObject.Properties[$Name].Value = $Value
        }
    }
    catch {
        Write-Verbose "Set-ConfigMemberValue: PSObject property set failed: $($_.Exception.Message)"
    }
}

function Get-CurrentVersion-ffmpeg {
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
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'FFmpeg' }

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

function Get-LatestUrlFromUrl-ffmpeg {
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
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'FFmpeg' }
    $versionUrl = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'VersionUrl')

    Invoke-RestMethod -Uri $versionUrl -OutFile $Paths._Temp

    if ($FileSystem) {
        $tempFiles = @($FileSystem.GetChildItem($Paths._Temp, "$pluginName*.7z", 'File'))
        $latestFile = $tempFiles | Select-Object -First 1
        $LatestInstaller = $latestFile.Name
    }
    else {
        $LatestInstaller = Split-Path -Path (Get-ChildItem -Path $Paths._Temp -Name "$pluginName*.7z") -Leaf
    }

    $LatestVersion = $LatestInstaller.Split('-')[1]
    $state = Get-ConfigMemberValue -Object $pluginConfig -Name 'State'
    if ($null -eq $state) {
        $state = @{}
        Set-ConfigMemberValue -Object $pluginConfig -Name 'State' -Value $state
    }
    Set-ConfigMemberValue -Object $state -Name 'LatestVersion' -Value $LatestVersion
    Set-ConfigMemberValue -Object $state -Name 'LatestInstaller' -Value $LatestInstaller

    $Url = $versionUrl
    return $Url
}

function Get-Installer-ffmpeg {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Http', Justification = 'Parameter reserved for future HTTP-based downloads')]
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
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'FFmpeg' }
    $pattern = "$pluginName*.7z"
    if ($FileSystem) {
        $filesToRemove = @($FileSystem.GetChildItem($Paths._Downloads, $pattern, 'File'))
        foreach ($file in $filesToRemove) {
            $FileSystem.RemoveItem($file.FullName, $false)
        }
    }
    else {
        Get-ChildItem -Path "$($Paths._Downloads)\$pattern" -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
    Move-Item -Path "$($Paths._Temp)\$pattern" -Destination $Paths._Downloads -Force

    $state = Get-ConfigMemberValue -Object $pluginConfig -Name 'State'
    $latestInstaller = [string](Get-ConfigMemberValue -Object $state -Name 'LatestInstaller')
    $InstallerPath = Join-Path -Path $Paths._Downloads -ChildPath $latestInstaller
    return $InstallerPath
}

function Invoke-Installer-ffmpeg {
    param (
        [hashtable]$Plugin,
        [hashtable]$Paths,
        [string]$InstallerPath,
        $Process,
        $FileSystem
    )
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

        $pluginConfig = Get-ConfigMemberValue -Object $Plugin -Name 'Config'
        $pluginName = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'Name')
        if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'FFmpeg' }
        Write-PSmmLog -Level SUCCESS -Context "Install $pluginName" -Message "Installation completed for $($InstallerPath)" -Console -File
    }
    catch {
        $pn = 'FFmpeg'
        try {
            $pluginConfig = Get-ConfigMemberValue -Object $Plugin -Name 'Config'
            $pnCandidate = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'Name')
            if (-not [string]::IsNullOrWhiteSpace($pnCandidate)) { $pn = $pnCandidate }
        }
        catch {
            Write-Verbose "Install FFmpeg: failed to get plugin name from config: $($_.Exception.Message)"
        }
        Write-PSmmLog -Level ERROR -Context "Install $pn" -Message "Installation failed for $($InstallerPath)" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########

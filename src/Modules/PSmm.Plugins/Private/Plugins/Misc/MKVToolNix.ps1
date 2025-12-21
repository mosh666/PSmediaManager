<#
.SYNOPSIS
    MKVToolNix
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
        if ($PSCmdlet.ShouldProcess($Name, 'Set config member value')) {
            $Object[$Name] = $Value
        }
        return
    }

    try {
        if ($PSCmdlet.ShouldProcess($Name, 'Set config member value')) {
            $Object.$Name = $Value
        }
        return
    }
    catch {
        Write-Verbose "Set-ConfigMemberValue: direct property assignment failed: $($_.Exception.Message)"
    }

    try {
        if ($PSCmdlet.ShouldProcess($Name, 'Set config member value')) {
            if ($null -eq $Object.PSObject.Properties[$Name]) {
                $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
            }
            else {
                $Object.PSObject.Properties[$Name].Value = $Value
            }
        }
    }
    catch {
        Write-Verbose "Set-ConfigMemberValue: PSObject NoteProperty add/set failed: $($_.Exception.Message)"
    }
}

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

    $pluginConfig = Get-ConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'MKVToolNix' }

    if ($FileSystem) {
        $InstallPath = @($FileSystem.GetChildItem($Paths.Root, "$pluginName*", 'Directory')) | Select-Object -First 1
    }
    else {
        $InstallPath = Get-ChildItem -Path $Paths.Root -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$pluginName*" }
    }

    if ($InstallPath) {
        $commandPath = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'CommandPath')
        $command = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'Command')
        $bin = Join-Path -Path $InstallPath -ChildPath $commandPath -AdditionalChildPath $command
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
    $pluginConfig = Get-ConfigMemberValue -Object $Plugin -Name 'Config'
    $versionUrl = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'VersionUrl')
    $Response = Invoke-WebRequest -Uri $versionUrl
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
    $state = Get-ConfigMemberValue -Object $pluginConfig -Name 'State'
    if ($null -eq $state) {
        $state = @{}
        Set-ConfigMemberValue -Object $pluginConfig -Name 'State' -Value $state
    }

    $pluginName = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'MKVToolNix' }
    # Use correctly-cased variable name
    $LatestInstaller = "$pluginName-64-bit-$LatestVersion.7z"
    Set-ConfigMemberValue -Object $state -Name 'LatestVersion' -Value $LatestVersion
    Set-ConfigMemberValue -Object $state -Name 'LatestInstaller' -Value $LatestInstaller
    $Url = $versionUrl + $LatestVersion + '/' + $LatestInstaller
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
        $pluginConfig = Get-ConfigMemberValue -Object $Plugin -Name 'Config'
        $pluginName = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'Name')
        if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'MKVToolNix' }
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

        Write-PSmmLog -Level SUCCESS -Context "Install $pluginName" -Message "Installation completed for $($InstallerPath)" -Console -File
    }
    catch {
        $pn = 'MKVToolNix'
        try {
            $pluginConfig = Get-ConfigMemberValue -Object $Plugin -Name 'Config'
            $pnCandidate = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'Name')
            if (-not [string]::IsNullOrWhiteSpace($pnCandidate)) { $pn = $pnCandidate }
        }
        catch {
            Write-Verbose "Invoke-Installer-MKVToolNix: failed to resolve plugin name: $($_.Exception.Message)"
        }
        Write-PSmmLog -Level ERROR -Context "Install $pn" -Message "Installation failed for $($InstallerPath)" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########

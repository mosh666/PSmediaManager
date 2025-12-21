<#
.SYNOPSIS
    GitVersion
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

function Get-CurrentVersion-GitVersion {
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
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'GitVersion' }

    if ($FileSystem) {
        $InstallPath = @($FileSystem.GetChildItem($Paths.Root, "$pluginName*", 'Directory')) | Select-Object -First 1
    }
    else {
        $InstallPath = Get-ChildItem -Path $Paths.Root -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$pluginName*" }
    }

    if ($InstallPath) {
        $commandPath = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'CommandPath')
        $command = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'Command')
        if ([string]::IsNullOrWhiteSpace($commandPath) -or [string]::IsNullOrWhiteSpace($command)) {
            return ''
        }

        $bin = Join-Path -Path $InstallPath -ChildPath $commandPath -AdditionalChildPath $command
        $CurrentVersion = (& $bin -version)
        return $CurrentVersion.Split('+')[0]
    }
    else {
        return ''
    }
}

#endregion ########## PRIVATE ##########

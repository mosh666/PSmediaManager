#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Get-KeePassCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AppConfiguration]$Config,
        [Parameter(Mandatory)]$Http,
        [Parameter(Mandatory)]$Crypto,
        [Parameter(Mandatory)]$FileSystem,
        [Parameter(Mandatory)]$Process
    )

    # Attempt to derive vault path from configuration
    $vaultPath = $null
    try {
        if ($Config -and ($Config.PSObject.Properties.Name -contains 'Paths')) {
            $paths = $Config.Paths
            if ($paths -and ($paths.PSObject.Properties.Name -contains 'App')) {
                $appPaths = $paths.App
                if ($appPaths -and ($appPaths.PSObject.Properties.Name -contains 'Vault')) {
                    $vaultPath = $appPaths.Vault
                }
            }
        }
    }
    catch {
        Write-Error -Message "Failed deriving vault path from config: $($_.Exception.Message)" -Category InvalidData
    }

    if (-not $vaultPath -or [string]::IsNullOrWhiteSpace($vaultPath)) {
        try {
            if ($Config -and ($Config.PSObject.Properties.Name -contains 'Paths')) {
                $rootPath = $Config.Paths.Root
                if ($rootPath) { $vaultPath = Join-Path -Path $rootPath -ChildPath 'Vault' }
            }
        }
        catch {
            Write-Error -Message "Failed deriving default vault path from config: $($_.Exception.Message)" -Category InvalidData
        }
    }

    if (-not $vaultPath) {
        # Fallback: relative Vault directory from repo root (assumes standard layout)
        $vaultPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Vault')
    }

    # First resolution attempt
    $resolution = Resolve-KeePassCliCommand -VaultPath $vaultPath
    if ($resolution.Command) {
        return $resolution.Command
    }

    # Install attempt when missing
    try {
        Write-PSmmLog -Level NOTICE -Context 'Get-KeePassCli' -Message 'KeePassXC CLI not found, attempting installation.'
    }
    catch {
        Write-Error -Message "Failed to write notice log for KeePassXC installation attempt: $($_.Exception.Message)" -Category NotSpecified
    }

    try {
        $null = Install-KeePassXC -Config $Config -Http $Http -Crypto $Crypto -FileSystem $FileSystem -Process $Process
    }
    catch {
        # Swallow installer errors; final resolution will determine outcome
        Write-PSmmLog -Level WARNING -Context 'Get-KeePassCli' -Message "KeePassXC installation attempt encountered issues: $($_.Exception.Message)"
    }

    # Second resolution attempt
    $postResolution = Resolve-KeePassCliCommand -VaultPath $vaultPath
    if ($postResolution.Command) {
        Write-PSmmLog -Level INFO -Context 'Get-KeePassCli' -Message 'KeePassXC CLI resolved after installation.'
        return $postResolution.Command
    }

    throw 'keepassxc-cli.exe is still missing after installation attempt.'
}

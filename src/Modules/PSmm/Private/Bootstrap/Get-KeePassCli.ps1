#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Get-KeePassCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AppConfiguration]$Config,
        [Parameter(Mandatory)]$Http,
        [Parameter(Mandatory)]$Crypto,
        [Parameter(Mandatory)]$FileSystem,
        [Parameter(Mandatory)]$Environment,
        [Parameter(Mandatory)]$PathProvider,
        [Parameter(Mandatory)]$Process
    )

    # Resolve vault path using standard resolution order: Config > Environment > Error
    $vaultPath = $null

    # 1. Try to get from configuration (Config.Paths.App.Vault)
    try {
        if ($Config -and ($Config.PSObject.Properties.Name -contains 'Paths')) {
            $paths = $Config.Paths
            if ($paths -and ($paths.PSObject.Properties.Name -contains 'App')) {
                $appPaths = $paths.App
                if ($appPaths -and ($appPaths.PSObject.Properties.Name -contains 'Vault')) {
                    $vaultPath = $appPaths.Vault
                    Write-Verbose "[Get-KeePassCli] Resolved VaultPath from Config.Paths.App.Vault: $vaultPath"
                }
            }
        }
    }
    catch {
        Write-Verbose "[Get-KeePassCli] Failed to resolve vault path from config: $($_.Exception.Message)"
    }

    # 2. Try environment variable if not found in config
    if (-not $vaultPath -or [string]::IsNullOrWhiteSpace($vaultPath)) {
        if ($Environment -and $Environment.GetVariable) {
            $envVaultPath = $Environment.GetVariable('PSMM_VAULT_PATH')
            if (-not [string]::IsNullOrWhiteSpace($envVaultPath)) {
                $vaultPath = $envVaultPath
                Write-Verbose "[Get-KeePassCli] Resolved VaultPath from PSMM_VAULT_PATH environment: $vaultPath"
            }
        }
    }

    # 3. Error if vault path cannot be resolved
    if (-not $vaultPath -or [string]::IsNullOrWhiteSpace($vaultPath)) {
        throw "Unable to resolve vault path. Ensure Config.Paths.App.Vault is set or PSMM_VAULT_PATH environment variable is defined."
    }

    # First resolution attempt
    $resolution = Resolve-KeePassCliCommand -VaultPath $vaultPath -FileSystem $FileSystem -Environment $Environment -PathProvider $PathProvider -Process $Process
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
        $null = Install-KeePassXC -Config $Config -Http $Http -Crypto $Crypto `
            -FileSystem $FileSystem -Environment $Environment -PathProvider $PathProvider -Process $Process
    }
    catch {
        # Swallow installer errors; final resolution will determine outcome
        Write-PSmmLog -Level WARNING -Context 'Get-KeePassCli' -Message "KeePassXC installation attempt encountered issues: $($_.Exception.Message)"
    }

    # Second resolution attempt
    $postResolution = Resolve-KeePassCliCommand -VaultPath $vaultPath -FileSystem $FileSystem -Environment $Environment -PathProvider $PathProvider -Process $Process
    if ($postResolution.Command) {
        Write-PSmmLog -Level INFO -Context 'Get-KeePassCli' -Message 'KeePassXC CLI resolved after installation.'
        return $postResolution.Command
    }

    throw 'keepassxc-cli.exe is still missing after installation attempt.'
}

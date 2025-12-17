#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Get-KeePassCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)]$Http,
        [Parameter(Mandatory)]$Crypto,
        [Parameter(Mandatory)]$FileSystem,
        [Parameter(Mandatory)]$Environment,
        [Parameter(Mandatory)]$PathProvider,
        [Parameter(Mandatory)]$Process
    )

    function Get-ConfigMemberValue {
        [CmdletBinding()]
        param(
            [Parameter()][AllowNull()][object]$Object,
            [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name
        )

        if ($null -eq $Object) {
            return $null
        }

        if ($Object -is [System.Collections.IDictionary]) {
            try { if ($Object.ContainsKey($Name)) { return $Object[$Name] } } catch { }
            try { if ($Object.Contains($Name)) { return $Object[$Name] } } catch { }
            try {
                foreach ($k in $Object.Keys) {
                    if ($k -eq $Name) { return $Object[$k] }
                }
            }
            catch { }
            return $null
        }

        $p = $Object.PSObject.Properties[$Name]
        if ($null -ne $p) {
            return $p.Value
        }

        return $null
    }

    function Get-ConfigNestedValue {
        [CmdletBinding()]
        param(
            [Parameter()][AllowNull()][object]$Object,
            [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$Path
        )

        $current = $Object
        foreach ($segment in $Path) {
            $current = Get-ConfigMemberValue -Object $current -Name $segment
            if ($null -eq $current) {
                return $null
            }
        }

        return $current
    }

    # Resolve vault path using standard resolution order: Config > Environment > Error
    $vaultPath = $null

    # 1. Try to get from configuration (Config.Paths.App.Vault)
    $vaultPath = Get-ConfigNestedValue -Object $Config -Path @('Paths','App','Vault')
    if (-not [string]::IsNullOrWhiteSpace($vaultPath)) {
        Write-Verbose "[Get-KeePassCli] Resolved VaultPath from Config.Paths.App.Vault: $vaultPath"
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

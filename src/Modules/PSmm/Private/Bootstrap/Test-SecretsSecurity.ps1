<#
.SYNOPSIS
    Validates security of KeePassXC vault in PSmediaManager.

.DESCRIPTION
    Performs comprehensive security checks on the KeePassXC vault to ensure:
    - KeePass database exists and is accessible
    - keepassxc-cli is available in PATH
    - Vault directory has appropriate permissions
    - No secrets are accidentally exposed in logs or configuration exports

.PARAMETER Config
    The AppConfiguration object containing vault paths.

.EXAMPLE
    Test-SecretsSecurity -Config $appConfig
    Performs security validation on KeePassXC vault using AppConfiguration.

.EXAMPLE
    Test-SecretsSecurity -Run $Run
    (Legacy) Performs security validation using hashtable configuration.

.OUTPUTS
    Boolean - Returns $true if all security checks pass, $false otherwise.

.NOTES
    This function is called during bootstrap to ensure credential security.
    Only validates KeePassXC-based secret storage.
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function Test-ConfigurationExports {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Validates multiple configuration exports; plural noun is intentional')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$ExportPath,

        [Parameter()]
        [object]$FileSystem
    )

    try {
        if ($null -eq $FileSystem) {
            throw [ValidationException]::new('FileSystem service is required for configuration export validation', 'FileSystem', $null)
        }

        if ([string]::IsNullOrWhiteSpace($exportPath)) {
            Write-Verbose 'No configuration export path specified; skipping export validation.'
            return $true
        }

        if (-not $FileSystem.TestPath($exportPath)) {
            Write-Verbose "Safe configuration export not found: $exportPath (skip check)"
            return $true
        }

        # Read as raw text to scan for accidental secrets
        $content = $FileSystem.GetContent($exportPath)
        if ([string]::IsNullOrWhiteSpace($content)) {
            return $true
        }

        $issues = @()

        # 1) Detect GitHub token patterns (ghp_, gho_, ghu_, ghs_, ghr_ + 36+ chars)
        if ($content -match '(ghp_|gho_|ghu_|ghs_|ghr_)[A-Za-z0-9]{20,}') {
            $issues += 'Possible GitHub token pattern found in exported configuration.'
        }

        # 2) Detect common secret keys with unmasked values (simple heuristic)
        $secretKeyPatterns = 'Token', 'Password', 'Secret', 'ApiKey', 'Credential', 'Pwd'
        foreach ($key in $secretKeyPatterns) {
            # Match lines like <key> = 'value' (or "value") where value is not masked as ********
            $quotedKey = [regex]::Escape($key)
            $regex = '(?im)^\s*' + $quotedKey + '\s*=\s*[''"](?!\*{6,})[^''"]{6,}[''"]'
            if ([regex]::IsMatch($content, $regex)) {
                $issues += "Unmasked secret-like value for key '${key}'."
            }
        }

        if ($issues.Count -gt 0) {
            foreach ($issue in $issues) { Write-Warning "Config export check: $issue" }
            return $false
        }

        Write-Verbose '✓ Configuration export appears sanitized.'
        return $true
    }
    catch {
        Write-Verbose "Failed to validate configuration exports: $_"
        return $false
    }
}

function Test-SecretsSecurity {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config,

        [Parameter()]
        [object]$FileSystem
    )

    try {
        Write-Verbose 'Starting security validation for KeePassXC vault...'

        if (-not (Get-Command -Name Get-PSmmConfigNestedValue -ErrorAction SilentlyContinue)) {
            $helperPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Get-PSmmConfigNestedValue.ps1'
            if (Test-Path -LiteralPath $helperPath) {
                . $helperPath
            }
        }

        $vaultPath = Get-PSmmConfigNestedValue -Object $Config -Path @('Paths','App','Vault') -Default $null
        if ([string]::IsNullOrWhiteSpace($vaultPath)) {
            Write-Warning 'Unable to resolve vault path (Config.Paths.App.Vault).'
            return $false
        }

        if ($null -eq $FileSystem) {
            throw [ValidationException]::new('FileSystem service is required for secrets security validation', 'FileSystem', $null)
        }

        $allChecksPassed = $true

        # Ensure vault directory exists
        if (-not $FileSystem.TestPath($vaultPath)) {
            Write-Verbose "Vault directory does not exist yet: $vaultPath"
            Write-Warning "KeePass vault not initialized. Use Initialize-SystemVault to set up secret storage."
            return $false
        }

        # Test 1: Check if KeePass database exists
        $dbPath = Join-Path $vaultPath 'PSmm_System.kdbx'
        if (-not $FileSystem.TestPath($dbPath)) {
            Write-Warning "KeePass database not found: $dbPath"
            Write-Warning "Use Initialize-SystemVault to create the KeePass database."
            $allChecksPassed = $false
        }
        else {
            Write-Verbose "✓ KeePass database exists: $dbPath"
        }

        # Test 2: Check if keepassxc-cli is available
        $cliCheck = Get-Command 'keepassxc-cli.exe' -ErrorAction SilentlyContinue
        if (-not $cliCheck) {
            Write-Warning "keepassxc-cli.exe not found in PATH"
            Write-Warning "KeePassXC must be installed for secret management to work."
            $allChecksPassed = $false
        }
        else {
            Write-Verbose "✓ keepassxc-cli.exe is available in PATH"
        }

        # Test 3: Check vault directory permissions
        Test-VaultPermissions -VaultPath $vaultPath -FileSystem $FileSystem

        # Test 4: Verify no secrets in configuration exports
        $logRoot = Get-PSmmConfigNestedValue -Object $Config -Path @('Paths','Log') -Default $null

        $internalName = Get-PSmmConfigMemberValue -Object $Config -Name 'InternalName' -Default $null

        if (-not [string]::IsNullOrWhiteSpace($logRoot) -and -not [string]::IsNullOrWhiteSpace($internalName)) {
            $exportPath = Join-Path -Path $logRoot -ChildPath "$internalName`Run.psd1"
            Test-ConfigurationExports -ExportPath $exportPath -FileSystem $FileSystem
        }
        else {
            Write-Verbose 'Skipping configuration export check: missing Paths.Log or InternalName.'
        }

        if ($allChecksPassed) {
            Write-Verbose '✓ All security checks passed'
            Write-PSmmLog -Level SUCCESS -Context 'Security Check' `
                -Message 'Vault security validation passed' -File
        }
        else {
            Write-PSmmLog -Level WARNING -Context 'Security Check' `
                -Message 'Some security issues detected - review warnings above' -Console -File
        }

        return $allChecksPassed
    }
    catch {
        Write-PSmmLog -Level ERROR -Context 'Security Check' `
            -Message "Security validation failed: $_" -ErrorRecord $_ -Console -File
        return $false
    }
}

<#
.SYNOPSIS
    Tests vault directory permissions for security issues.

.PARAMETER VaultPath
    Path to the vault directory to test.

.PARAMETER FileSystem
    File system service (injectable for testing).
#>
function Test-VaultPermissions {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Function tests multiple permission settings')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$VaultPath,

        [Parameter()]
        [object]$FileSystem
    )

    try {
        if ($null -eq $FileSystem) {
            throw [ValidationException]::new('FileSystem service is required for vault permission validation', 'FileSystem', $null)
        }

        if (-not $FileSystem.TestPath($VaultPath)) {
            Write-Verbose "Vault directory does not exist: $VaultPath"
            return
        }

        # Get ACL from vault directory
        $acl = Get-Acl -Path $VaultPath -ErrorAction Stop
        $owner = $acl.Owner

        Write-Verbose "Vault owner: $owner"

        # Check if directory is readable by Everyone or Users groups (potential security issue)
        $everyoneAccess = $acl.Access | Where-Object {
            $_.IdentityReference -match '(Everyone|Users|Authenticated Users)' -and
            $_.FileSystemRights -match 'Read'
        }

        if ($everyoneAccess) {
            Write-Warning "Security Notice: Vault directory may be readable by other users"
            Write-Verbose "Consider restricting permissions to current user only"
        }
        else {
            Write-Verbose "✓ Vault directory permissions appear secure"
        }
    }
    catch {
        Write-Verbose "Could not check vault permissions: $_"
    }
}

#endregion ########## PRIVATE ##########

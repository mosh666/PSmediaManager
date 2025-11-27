<#
.SYNOPSIS
    Performs automated first-run setup for PSmediaManager.

.DESCRIPTION
    Handles initial setup tasks including:
    - Creating the KeePassXC vault if it doesn't exist
    - Prompting for required secrets (GitHub token)
    - Saving secrets to the vault
    - Configuring storage drives

    This function is called automatically when the vault is missing,
    providing a seamless first-run experience.

.PARAMETER Config
    The AppConfiguration object containing application settings and paths.
    Must be fully initialized with proper path structure.

.PARAMETER NonInteractive
    If specified, skips interactive prompts and returns false if setup is needed.
    Useful for automated/headless scenarios.

.EXAMPLE
    Invoke-FirstRunSetup -Config $appConfig

    Performs first-run setup with prompts for required information.

.NOTES
    Function Name: Invoke-FirstRunSetup
    Requires: PowerShell 7.5.4 or higher
    Dependencies: Initialize-SystemVault, Save-SystemSecret, KeePassXC
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Invoke-FirstRunSetup {
    [CmdletBinding()]
    [OutputType([bool],[string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AppConfiguration]$Config,

        [Parameter()]
        [switch]$NonInteractive
    )

    try {
                # Extract paths from config
        $VaultPath = $Config.Paths.App.Vault
        $dbPath = Join-Path $VaultPath 'PSmm_System.kdbx'
        $tokenCachePath = Join-Path $VaultPath '.pending_setup.cache'

        # Check if vault already exists
        if (Test-Path $dbPath) {
            Write-Verbose "Vault already exists at: $dbPath"
            # Clean up any pending cache
            if (Test-Path $tokenCachePath) {
                Remove-Item $tokenCachePath -Force -ErrorAction SilentlyContinue
            }
            return $true
        }

        # Check for cached token from previous setup attempt FIRST
        $token = $null
        $hasToken = $false

        if (Test-Path $tokenCachePath) {
            Write-PSmmHost ""
            Write-PSmmHost "Found cached setup data from previous attempt..." -ForegroundColor Cyan
            try {
                $cacheData = Get-Content -Path $tokenCachePath -Raw | ConvertFrom-Json
                $encryptedToken = $cacheData.Token
                $token = $encryptedToken | ConvertTo-SecureString

                # Verify the token
                $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($token)
                $plainToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

                $hasToken = -not [string]::IsNullOrWhiteSpace($plainToken)

                if ($hasToken) {
                    Write-PSmmHost "✓ Cached token loaded successfully" -ForegroundColor Green
                    Write-PSmmHost "  Continuing setup with cached credentials..." -ForegroundColor Gray
                    Write-PSmmHost ""
                }
                else {
                    Write-Warning "Cached token was empty or invalid"
                }
            }
            catch {
                Write-Warning "Failed to load cached token: $_"
                $hasToken = $false
            }
        }

        Write-PSmmHost ""
        Write-PSmmHost "╔════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        if (-not $hasToken) {
            Write-PSmmHost "║                  First-Run Setup: PSmediaManager                   ║" -ForegroundColor Cyan
        }
        else {
            Write-PSmmHost "║              Resuming Setup: PSmediaManager (Step 2/2)             ║" -ForegroundColor Cyan
        }
        Write-PSmmHost "╚════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-PSmmHost ""

        if (-not $hasToken) {
            Write-PSmmHost "Welcome! It looks like this is your first time running PSmediaManager." -ForegroundColor Yellow
            Write-PSmmHost "I'll help you set up the secure vault for storing secrets." -ForegroundColor Yellow
            Write-PSmmHost ""
        }
        else {
            Write-PSmmHost "KeePassXC is now installed. Completing vault setup..." -ForegroundColor Yellow
            Write-PSmmHost "Using your GitHub token from the previous setup step." -ForegroundColor Green
            Write-PSmmHost ""
        }

        if ($NonInteractive) {
            Write-Warning "Running in non-interactive mode. Cannot perform first-run setup."
            return $false
        }

        # Prompt to proceed (skip if resuming with cached token)
        if (-not $hasToken) {
            Write-PSmmHost "Setup will:" -ForegroundColor Cyan
            Write-PSmmHost "  1. Collect your GitHub Personal Access Token" -ForegroundColor Gray
            Write-PSmmHost "  2. Install KeePassXC (if not already installed)" -ForegroundColor Gray
            Write-PSmmHost "  3. Create a secure KeePassXC vault at: $VaultPath" -ForegroundColor Gray
            Write-PSmmHost "  4. Store the token securely in the vault" -ForegroundColor Gray
            Write-PSmmHost "  5. Configure your storage drives" -ForegroundColor Gray
            Write-PSmmHost ""

            $response = Read-Host "Ready to proceed? (Y/n)"
            if ($response -and $response -notmatch '^[Yy]') {
                Write-PSmmHost ""
                Write-PSmmHost "❌ Setup cancelled by user." -ForegroundColor Red
                Write-PSmmHost ""
                Write-PSmmHost "The application cannot run without the vault setup." -ForegroundColor Yellow
                Write-PSmmHost "Please run the setup again when you're ready." -ForegroundColor Yellow
                Write-PSmmHost ""
                return $false
            }
        }
        else {
            Write-PSmmHost "Next steps:" -ForegroundColor Cyan
            Write-PSmmHost "  • Create a vault master password" -ForegroundColor Gray
            Write-PSmmHost "  • Save your GitHub token to the vault" -ForegroundColor Gray
            Write-PSmmHost "  • Configure your storage drives" -ForegroundColor Gray
            Write-PSmmHost ""

            $response = Read-Host "Continue with vault creation? (Y/n)"
            if ($response -and $response -notmatch '^[Yy]') {
                Write-PSmmHost ""
                Write-PSmmHost "❌ Setup cancelled by user." -ForegroundColor Red
                return $false
            }
        }

            Write-PSmmHost ""
            Write-PSmmHost "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
            Write-PSmmHost "Step 1: GitHub Personal Access Token" -ForegroundColor Cyan
            Write-PSmmHost "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
            Write-PSmmHost ""

        # Only prompt for token if we don't already have one cached
        if (-not $hasToken) {
            Write-PSmmHost "The GitHub token is used for:" -ForegroundColor Yellow
            Write-PSmmHost "  • Downloading plugins and updates from GitHub releases" -ForegroundColor Gray
            Write-PSmmHost "  • Avoiding API rate limits" -ForegroundColor Gray
            Write-PSmmHost "  • Accessing private repositories (if configured)" -ForegroundColor Gray
            Write-PSmmHost ""
            Write-PSmmHost "To create a token:" -ForegroundColor Cyan
            Write-PSmmHost "  1. Go to: https://github.com/settings/tokens" -ForegroundColor Gray
            Write-PSmmHost "  2. Click 'Generate new token (classic)'" -ForegroundColor Gray
            Write-PSmmHost "  3. Give it a name (e.g., 'PSmm')" -ForegroundColor Gray
            Write-PSmmHost "  4. Select scopes: 'repo' (or just 'public_repo' for public repos only)" -ForegroundColor Gray
            Write-PSmmHost "  5. Generate and copy the token" -ForegroundColor Gray
            Write-PSmmHost ""
            Write-PSmmHost "Note: You can press Enter to skip and add it later." -ForegroundColor DarkYellow
            Write-PSmmHost ""

            # Prompt for GitHub token
            $token = Read-Host "Enter your GitHub Personal Access Token" -AsSecureString

            # Check if token was provided
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($token)
            $plainToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

            $hasToken = -not [string]::IsNullOrWhiteSpace($plainToken)

            if (-not $hasToken) {
                Write-PSmmHost ""
                Write-PSmmHost "⚠ No token provided." -ForegroundColor Yellow
            }
        }
        else {
            Write-PSmmHost "✓ Using cached token from previous setup attempt" -ForegroundColor Green
        }

        # Check if KeePassXC is available
            Write-PSmmHost ""
            Write-PSmmHost "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
            Write-PSmmHost "Step 2: KeePassXC Setup" -ForegroundColor Cyan
            Write-PSmmHost "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
            Write-PSmmHost ""

        $cliResolution = Resolve-KeePassCliCommand -VaultPath $Config.Paths.App.Vault
        $cliCheck = if ($cliResolution -and $cliResolution.Command) { $cliResolution.Command } else { $null }
        if (-not $cliCheck) {
            Write-PSmmHost "❌ KeePassXC not found!" -ForegroundColor Red
            Write-PSmmHost ""

            # Cache the token securely if provided
            if ($hasToken) {
                Write-PSmmHost "Caching your token securely..." -ForegroundColor Cyan
                try {
                    # Ensure vault directory exists
                    if (-not (Test-Path $VaultPath)) {
                        New-Item -ItemType Directory -Path $VaultPath -Force | Out-Null
                    }

                    # Store encrypted token using DPAPI
                    $encryptedToken = $token | ConvertFrom-SecureString
                    $cacheData = @{
                        Token = $encryptedToken
                        Timestamp = Get-Date -Format 'o'
                    }
                    $cacheData | ConvertTo-Json | Set-Content -Path $tokenCachePath -Force
                    Write-PSmmHost "✓ Token cached securely" -ForegroundColor Green
                }
                catch {
                    Write-Warning "Failed to cache token: $_"
                }
            }

            Write-PSmmHost ""
            Write-PSmmHost "KeePassXC will now be installed automatically..." -ForegroundColor Yellow
            Write-PSmmHost ""
            Write-PSmmHost "The application will continue with plugin installation." -ForegroundColor Cyan
            Write-PSmmHost "Once KeePassXC is installed, the vault setup will complete automatically." -ForegroundColor Cyan
            Write-PSmmHost ""

            # Return a special status to indicate pending setup
            return 'PendingKeePassXC'
        }

        Write-PSmmHost "✓ KeePassXC found" -ForegroundColor Green
        Write-PSmmHost ""

        Write-PSmmHost ""
        Write-PSmmHost "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-PSmmHost "Step 3: Creating KeePassXC Vault" -ForegroundColor Cyan
        Write-PSmmHost "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-PSmmHost ""

        # Initialize the vault
        $vaultCreated = Initialize-SystemVault -VaultPath $Config.Paths.App.Vault -ErrorAction Stop

        if (-not $vaultCreated) {
            Write-PSmmHost "❌ Failed to create vault" -ForegroundColor Red
            return $false
        }

        # Save the token if we have one
        if ($hasToken) {
            Write-PSmmHost ""
            Write-PSmmHost "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
            Write-PSmmHost "Step 4: Saving GitHub Token to Vault" -ForegroundColor Cyan
            Write-PSmmHost "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
            Write-PSmmHost ""
            Write-PSmmHost "Saving GitHub token to vault..." -ForegroundColor Cyan
            Write-PSmmHost ""
            Write-PSmmHost "NOTE: You'll be prompted for your vault master password." -ForegroundColor Yellow
            Write-PSmmHost "      (This is the password you just created)" -ForegroundColor Yellow
            Write-PSmmHost ""

            $metadata = @{
                Created = (Get-Date -Format 'yyyy-MM-dd')
                Purpose = 'PSmediaManager plugin downloads and updates'
                Scope = 'repo or public_repo'
            }

            $saved = Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue $token -Metadata $metadata -VaultPath $Config.Paths.App.Vault -ErrorAction Stop

            if ($saved) {
                Write-PSmmHost "✓ Token saved successfully" -ForegroundColor Green

                # Clean up cached token
                if (Test-Path $tokenCachePath) {
                    Remove-Item $tokenCachePath -Force -ErrorAction SilentlyContinue
                }
            }
            else {
                    Write-PSmmHost "⚠ Token saved but with warnings. Check the output above." -ForegroundColor Yellow
            }
        }
        else {
            Write-PSmmHost ""
            Write-PSmmHost "⚠ No GitHub token configured. You can add it later using:" -ForegroundColor Yellow
            Write-PSmmHost "   Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue `$token" -ForegroundColor Gray
        }

        Write-PSmmHost ""
        Write-PSmmHost "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-PSmmHost "Step 5: Storage Configuration" -ForegroundColor Cyan
        Write-PSmmHost "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-PSmmHost ""
        Write-PSmmHost "Finally, let's configure your storage drives." -ForegroundColor Yellow
        Write-PSmmHost "PSmediaManager needs to know which drives to use for media storage." -ForegroundColor Gray
        Write-PSmmHost ""

        # Get drive root and check if storage config already exists
        $driveRoot = [System.IO.Path]::GetPathRoot($Config.Paths.App.Vault)
        $storagePath = Join-Path -Path $driveRoot -ChildPath 'PSmm.Config\PSmm.Storage.psd1'
        
        if (-not (Test-Path -Path $storagePath)) {
            Write-PSmmHost "Starting storage wizard..." -ForegroundColor Cyan
            Write-PSmmHost ""
            
            try {
                $wizardResult = Invoke-StorageWizard -Config $Config -DriveRoot $driveRoot -NonInteractive:$false
                if (-not $wizardResult) {
                    Write-PSmmHost ""
                    Write-PSmmHost "⚠ Storage configuration skipped or cancelled." -ForegroundColor Yellow
                    Write-PSmmHost "   You can configure storage later using: Invoke-ManageStorage" -ForegroundColor Gray
                }
                else {
                    Write-PSmmHost ""
                    Write-PSmmHost "✓ Storage configuration saved" -ForegroundColor Green
                }
            }
            catch {
                Write-Warning "Storage configuration failed: $_"
                Write-PSmmHost "   You can configure storage later using: Invoke-ManageStorage" -ForegroundColor Gray
            }
        }
        else {
            Write-PSmmHost "✓ Storage configuration already exists at: $storagePath" -ForegroundColor Green
        }

        Write-PSmmHost ""
        Write-PSmmHost "╔════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-PSmmHost "║                  ✓ Setup Complete!                                 ║" -ForegroundColor Green
        Write-PSmmHost "╚════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-PSmmHost ""
        Write-PSmmHost "Your vault is ready at: $dbPath" -ForegroundColor Gray
        Write-PSmmHost ""
        Write-PSmmHost "Important reminders:" -ForegroundColor Cyan
        Write-PSmmHost "  • Remember your master password - it's needed to access secrets" -ForegroundColor Yellow
        if ($hasToken) {
            Write-PSmmHost "  • Your GitHub token is stored securely in the vault" -ForegroundColor Green
        }
        Write-PSmmHost "  • You can add more secrets using: Save-SystemSecret" -ForegroundColor Gray
        Write-PSmmHost ""
        Write-PSmmHost "Press any key to continue..." -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        Write-PSmmHost ""

        # Clear any cached vault master password after successful setup completes
        try { $script:_VaultMasterPasswordCache = $null }
        catch {
            Write-Verbose "Failed to clear cached vault master password: $_"
        }

        return $true
    }
    catch {
        $errorMessage = "First-run setup failed: $_"

        if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
            Write-PSmmLog -Level ERROR -Context 'Invoke-FirstRunSetup' `
                -Message $errorMessage -ErrorRecord $_ -Console -File
        }

        Write-Error $errorMessage
        # Ensure cache is cleared on failure as well
        try { $script:_VaultMasterPasswordCache = $null }
        catch {
            Write-Verbose "Failed to clear cached vault master password: $_"
        }
        return $false
    }
}

<#
.SYNOPSIS
    Performs automated first-run setup for PSmediaManager.

.DESCRIPTION
    Handles initial setup tasks including:
    - Creating the KeePassXC vault if it doesn't exist
    - Prompting for required secrets (GitHub token)
    - Saving secrets to the vault
    
    This function is called automatically when the vault is missing,
    providing a seamless first-run experience.

.PARAMETER VaultPath
    Path to the vault directory. Defaults to the application vault path.

.PARAMETER NonInteractive
    If specified, skips interactive prompts and returns false if setup is needed.
    Useful for automated/headless scenarios.

.EXAMPLE
    Invoke-FirstRunSetup -VaultPath 'D:\PSmediaManager\Vault'
    
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
    [OutputType([bool])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultPath = 'd:\PSmm.Vault',

        [Parameter()]
        [switch]$NonInteractive
    )

    try {
                # Validate parameters
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
            Write-Host ""
            Write-Host "Found cached setup data from previous attempt..." -ForegroundColor Cyan
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
                    Write-Host "✓ Cached token loaded successfully" -ForegroundColor Green
                    Write-Host "  Continuing setup with cached credentials..." -ForegroundColor Gray
                    Write-Host ""
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

        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        if (-not $hasToken) {
            Write-Host "║                  First-Run Setup: PSmediaManager                   ║" -ForegroundColor Cyan
        }
        else {
            Write-Host "║              Resuming Setup: PSmediaManager (Step 2/2)             ║" -ForegroundColor Cyan
        }
        Write-Host "╚════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        
        if (-not $hasToken) {
            Write-Host "Welcome! It looks like this is your first time running PSmediaManager." -ForegroundColor Yellow
            Write-Host "I'll help you set up the secure vault for storing secrets." -ForegroundColor Yellow
            Write-Host ""
        }
        else {
            Write-Host "KeePassXC is now installed. Completing vault setup..." -ForegroundColor Yellow
            Write-Host "Using your GitHub token from the previous setup step." -ForegroundColor Green
            Write-Host ""
        }

        if ($NonInteractive) {
            Write-Warning "Running in non-interactive mode. Cannot perform first-run setup."
            return $false
        }

        # Prompt to proceed (skip if resuming with cached token)
        if (-not $hasToken) {
            Write-Host "Setup will:" -ForegroundColor Cyan
            Write-Host "  1. Collect your GitHub Personal Access Token" -ForegroundColor Gray
            Write-Host "  2. Install KeePassXC (if not already installed)" -ForegroundColor Gray
            Write-Host "  3. Create a secure KeePassXC vault at: $VaultPath" -ForegroundColor Gray
            Write-Host "  4. Store the token securely in the vault" -ForegroundColor Gray
            Write-Host ""
            
            $response = Read-Host "Ready to proceed? (Y/n)"
            if ($response -and $response -notmatch '^[Yy]') {
                Write-Host ""
                Write-Host "❌ Setup cancelled by user." -ForegroundColor Red
                Write-Host ""
                Write-Host "The application cannot run without the vault setup." -ForegroundColor Yellow
                Write-Host "Please run the setup again when you're ready." -ForegroundColor Yellow
                Write-Host ""
                return $false
            }
        }
        else {
            Write-Host "Next steps:" -ForegroundColor Cyan
            Write-Host "  • Create a vault master password" -ForegroundColor Gray
            Write-Host "  • Save your GitHub token to the vault" -ForegroundColor Gray
            Write-Host ""
            
            $response = Read-Host "Continue with vault creation? (Y/n)"
            if ($response -and $response -notmatch '^[Yy]') {
                Write-Host ""
                Write-Host "❌ Setup cancelled by user." -ForegroundColor Red
                return $false
            }
        }

        Write-Host ""
        Write-Host "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host "Step 1: GitHub Personal Access Token" -ForegroundColor Cyan
        Write-Host "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host ""
        
        # Only prompt for token if we don't already have one cached
        if (-not $hasToken) {
            Write-Host "The GitHub token is used for:" -ForegroundColor Yellow
            Write-Host "  • Downloading plugins and updates from GitHub releases" -ForegroundColor Gray
            Write-Host "  • Avoiding API rate limits" -ForegroundColor Gray
            Write-Host "  • Accessing private repositories (if configured)" -ForegroundColor Gray
            Write-Host ""
            Write-Host "To create a token:" -ForegroundColor Cyan
            Write-Host "  1. Go to: https://github.com/settings/tokens" -ForegroundColor Gray
            Write-Host "  2. Click 'Generate new token (classic)'" -ForegroundColor Gray
            Write-Host "  3. Give it a name (e.g., 'PSmm')" -ForegroundColor Gray
            Write-Host "  4. Select scopes: 'repo' (or just 'public_repo' for public repos only)" -ForegroundColor Gray
            Write-Host "  5. Generate and copy the token" -ForegroundColor Gray
            Write-Host ""
            Write-Host "Note: You can press Enter to skip and add it later." -ForegroundColor DarkYellow
            Write-Host ""

            # Prompt for GitHub token
            $token = Read-Host "Enter your GitHub Personal Access Token" -AsSecureString
            
            # Check if token was provided
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($token)
            $plainToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            
            $hasToken = -not [string]::IsNullOrWhiteSpace($plainToken)
            
            if (-not $hasToken) {
                Write-Host ""
                Write-Host "⚠ No token provided." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "✓ Using cached token from previous setup attempt" -ForegroundColor Green
        }

        # Check if KeePassXC is available
        Write-Host ""
        Write-Host "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host "Step 2: KeePassXC Setup" -ForegroundColor Cyan
        Write-Host "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host ""
        
        $cliResolution = Resolve-KeePassCliCommand -VaultPath $VaultPath
        $cliCheck = if ($cliResolution -and $cliResolution.Command) { $cliResolution.Command } else { $null }
        if (-not $cliCheck) {
            Write-Host "❌ KeePassXC not found!" -ForegroundColor Red
            Write-Host ""
            
            # Cache the token securely if provided
            if ($hasToken) {
                Write-Host "Caching your token securely..." -ForegroundColor Cyan
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
                    Write-Host "✓ Token cached securely" -ForegroundColor Green
                }
                catch {
                    Write-Warning "Failed to cache token: $_"
                }
            }
            
            Write-Host ""
            Write-Host "KeePassXC will now be installed automatically..." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "The application will continue with plugin installation." -ForegroundColor Cyan
            Write-Host "Once KeePassXC is installed, the vault setup will complete automatically." -ForegroundColor Cyan
            Write-Host ""
            
            # Return a special status to indicate pending setup
            return 'PendingKeePassXC'
        }

        Write-Host "✓ KeePassXC found" -ForegroundColor Green
        Write-Host ""

        Write-Host ""
        Write-Host "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host "Step 3: Creating KeePassXC Vault" -ForegroundColor Cyan
        Write-Host "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host ""

        # Initialize the vault
        $vaultCreated = Initialize-SystemVault -VaultPath $VaultPath -ErrorAction Stop
        
        if (-not $vaultCreated) {
            Write-Host "❌ Failed to create vault" -ForegroundColor Red
            return $false
        }

        # Save the token if we have one
        if ($hasToken) {
            Write-Host ""
            Write-Host "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
            Write-Host "Step 4: Saving GitHub Token to Vault" -ForegroundColor Cyan
            Write-Host "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "Saving GitHub token to vault..." -ForegroundColor Cyan
            Write-Host ""
            Write-Host "NOTE: You'll be prompted for your vault master password." -ForegroundColor Yellow
            Write-Host "      (This is the password you just created)" -ForegroundColor Yellow
            Write-Host ""
            
            $metadata = @{
                Created = (Get-Date -Format 'yyyy-MM-dd')
                Purpose = 'PSmediaManager plugin downloads and updates'
                Scope = 'repo or public_repo'
            }

            $saved = Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue $token -Metadata $metadata -VaultPath $VaultPath -ErrorAction Stop
            
            if ($saved) {
                Write-Host "✓ Token saved successfully" -ForegroundColor Green
                
                # Clean up cached token
                if (Test-Path $tokenCachePath) {
                    Remove-Item $tokenCachePath -Force -ErrorAction SilentlyContinue
                }
            }
            else {
                Write-Host "⚠ Token saved but with warnings. Check the output above." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host ""
            Write-Host "⚠ No GitHub token configured. You can add it later using:" -ForegroundColor Yellow
            Write-Host "   Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue `$token" -ForegroundColor Gray
        }
        
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║                  ✓ Setup Complete!                                 ║" -ForegroundColor Green
        Write-Host "╚════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host ""
        Write-Host "Your vault is ready at: $dbPath" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Important reminders:" -ForegroundColor Cyan
        Write-Host "  • Remember your master password - it's needed to access secrets" -ForegroundColor Yellow
        if ($hasToken) {
            Write-Host "  • Your GitHub token is stored securely in the vault" -ForegroundColor Green
        }
        Write-Host "  • You can add more secrets using: Save-SystemSecret" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Press any key to continue..." -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        Write-Host ""
        
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

#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'

Write-PSmmHost "Loading exception classes..." -ForegroundColor Cyan
. ./src/Modules/PSmm/Classes/Exceptions.ps1
Write-PSmmHost "✓ Exception classes loaded" -ForegroundColor Green

Write-PSmmHost "Loading bootstrap services..." -ForegroundColor Cyan
. ./src/Core/BootstrapServices.ps1
Write-PSmmHost "✓ Bootstrap services loaded" -ForegroundColor Green

# Instantiate early services
Write-PSmmHost "Instantiating early services..." -ForegroundColor Cyan
try {
    [void][FileSystemService]::new()
    [void][PathProviderService]::new()
    Write-PSmmHost "✓ Early services instantiated" -ForegroundColor Green
} catch {
    Write-PSmmHost "✗ Failed to instantiate early services:" -ForegroundColor Red
    Write-PSmmHost $_ -ForegroundColor Red
    exit 1
}

Write-PSmmHost "Loading modules..." -ForegroundColor Cyan
Set-Location src
try {
    # Try to load the PSmm module
    Import-Module ./Modules/PSmm/PSmm.psd1 -Force -ErrorAction Stop
    Write-PSmmHost "✓ PSmm module loaded" -ForegroundColor Green
} catch {
    Write-PSmmHost "✗ Failed to load PSmm module:" -ForegroundColor Red
    Write-PSmmHost $_ -ForegroundColor Red
    exit 1
}

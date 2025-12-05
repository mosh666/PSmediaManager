#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'

Write-Host "Loading exception classes..." -ForegroundColor Cyan
. ./src/Modules/PSmm/Classes/Exceptions.ps1
Write-Host "✓ Exception classes loaded" -ForegroundColor Green

Write-Host "Loading bootstrap services..." -ForegroundColor Cyan
. ./src/Core/BootstrapServices.ps1
Write-Host "✓ Bootstrap services loaded" -ForegroundColor Green

# Instantiate early services
Write-Host "Instantiating early services..." -ForegroundColor Cyan
try {
    [void][FileSystemService]::new()
    [void][PathProviderService]::new()
    Write-Host "✓ Early services instantiated" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to instantiate early services:" -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
    exit 1
}

Write-Host "Loading modules..." -ForegroundColor Cyan
Set-Location src
try {
    # Try to load the PSmm module
    Import-Module ./Modules/PSmm/PSmm.psd1 -Force -ErrorAction Stop
    Write-Host "✓ PSmm module loaded" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to load PSmm module:" -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
    exit 1
}

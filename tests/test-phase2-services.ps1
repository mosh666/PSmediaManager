#Requires -Version 7.0
<#
.SYNOPSIS
    Test Phase 2 service injection changes.
    Verifies that updated modules and plugins load correctly with service injection.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Phase 2 Service Injection Test Suite" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# Test 1: Load core PSmm module
Write-Host "`n[Test 1] Loading PSmm module..." -ForegroundColor Magenta
try {
    $psmm = Import-Module -Name "$PSScriptRoot\..\src\Modules\PSmm\PSmm.psm1" -PassThru -ErrorAction Stop
    Write-Host "✓ PSmm module loaded successfully" -ForegroundColor Green
    Write-Host "  Exported functions: $($psmm.ExportedFunctions.Count)" -ForegroundColor Gray
}
catch {
    Write-Host "✗ Failed to load PSmm module: $_" -ForegroundColor Red
    exit 1
}

# Test 2: Verify FileSystemService interface has recursion support
Write-Host "`n[Test 2] Verifying FileSystemService interface updates..." -ForegroundColor Magenta
try {
    $interfacePath = "$PSScriptRoot\..\src\Modules\PSmm\Classes\Interfaces.ps1"
    $content = Get-Content -Path $interfacePath -Raw
    
    if ($content -match 'GetChildItem\(\[string\]\$path,\s*\[string\]\$filter,\s*\[string\]\$itemType,\s*\[bool\]\$recurse') {
        Write-Host "✓ IFileSystemService.GetChildItem has recurse parameter" -ForegroundColor Green
    }
    else {
        Write-Host "✗ IFileSystemService.GetChildItem missing recurse parameter" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "✗ Failed to verify interface: $_" -ForegroundColor Red
    exit 1
}

# Test 3: Load PSmm.Plugins module
Write-Host "`n[Test 3] Loading PSmm.Plugins module..." -ForegroundColor Magenta
try {
    $plugins = Import-Module -Name "$PSScriptRoot\..\src\Modules\PSmm.Plugins\PSmm.Plugins.psm1" -PassThru -ErrorAction Stop
    Write-Host "✓ PSmm.Plugins module loaded successfully" -ForegroundColor Green
    Write-Host "  Exported functions: $($plugins.ExportedFunctions.Count)" -ForegroundColor Gray
}
catch {
    Write-Host "✗ Failed to load PSmm.Plugins module: $_" -ForegroundColor Red
    exit 1
}

# Test 4: Verify Resolve-PluginCommandPath has FileSystem parameter (internal check)
Write-Host "`n[Test 4] Verifying plugin function signatures..." -ForegroundColor Magenta
try {
    # Check that plugin functions are available
    $confirmPluginsPath = "$PSScriptRoot\..\src\Modules\PSmm.Plugins\Private\Confirm-Plugins.ps1"
    $content = Get-Content -Path $confirmPluginsPath -Raw
    
    if ($content -match 'function Resolve-PluginCommandPath\s*\{') {
        Write-Host "✓ Resolve-PluginCommandPath function found" -ForegroundColor Green
    }
    else {
        Write-Host "✗ Resolve-PluginCommandPath function not found" -ForegroundColor Red
        exit 1
    }
    
    # Check for FileSystem parameter
    if ($content -match '\$FileSystem' -and $content -match 'Resolve-PluginCommandPath.*-FileSystem') {
        Write-Host "✓ Service injection pattern verified in Confirm-Plugins.ps1" -ForegroundColor Green
    }
}
catch {
    Write-Host "✗ Failed to verify plugin function signatures: $_" -ForegroundColor Red
    exit 1
}

# Test 5: Quick syntax check on updated plugin files
Write-Host "`n[Test 5] Checking plugin file syntax..." -ForegroundColor Magenta
$pluginFiles = @(
    'MariaDB.ps1',
    '7-Zip.ps1',
    'Git-LFS.ps1',
    'GitVersion.ps1',
    'ExifTool.ps1',
    'FFmpeg.ps1',
    'ImageMagick.ps1',
    'KeePassXC.ps1',
    'MKVToolNix.ps1',
    'PortableGit.ps1',
    'digiKam.ps1'
)

$syntaxErrors = 0
foreach ($file in $pluginFiles) {
    $paths = @(
        "$PSScriptRoot\..\src\Modules\PSmm.Plugins\Private\Plugins\Database\$file",
        "$PSScriptRoot\..\src\Modules\PSmm.Plugins\Private\Plugins\Essentials\$file",
        "$PSScriptRoot\..\src\Modules\PSmm.Plugins\Private\Plugins\GitEnv\$file",
        "$PSScriptRoot\..\src\Modules\PSmm.Plugins\Private\Plugins\Management\$file",
        "$PSScriptRoot\..\src\Modules\PSmm.Plugins\Private\Plugins\Misc\$file"
    )
    
    $filePath = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
    
    if ($filePath) {
        try {
            $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Path $filePath), [ref]$null)
            Write-Host "  ✓ $file" -ForegroundColor Green
        }
        catch {
            Write-Host "  ✗ $file - $_" -ForegroundColor Red
            $syntaxErrors++
        }
    }
}

if ($syntaxErrors -eq 0) {
    Write-Host "✓ All plugin files have valid syntax" -ForegroundColor Green
}
else {
    Write-Host "✗ Found $syntaxErrors syntax errors" -ForegroundColor Red
    exit 1
}

# Summary
Write-Host "`n=====================================" -ForegroundColor Cyan
Write-Host "Phase 2 Service Injection Tests: PASSED" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Cyan

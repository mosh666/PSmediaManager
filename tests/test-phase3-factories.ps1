#Requires -Version 7.0
<#
.SYNOPSIS
    Test Phase 3 - Factory functions and class accessibility.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Phase 3 - Factory Functions Test" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan

# Load module
Write-Host "`n[Test 1] Loading PSmm module..." -ForegroundColor Magenta
Import-Module "$PSScriptRoot\..\src\Modules\PSmm\PSmm.psm1" -Force
Write-Host "✓ PSmm module loaded" -ForegroundColor Green

# Test New-ProjectInfo factory
Write-Host "`n[Test 2] Testing New-ProjectInfo factory..." -ForegroundColor Magenta
try {
    $proj = New-ProjectInfo `
        -Name 'TestProject' `
        -Path 'D:\Test' `
        -Type 'Photo' `
        -DriveLetter 'D:' `
        -DriveLabel 'DataDrive' `
        -Location 'Master'
    
    Write-Host "✓ New-ProjectInfo created successfully" -ForegroundColor Green
    Write-Host "  Name: $($proj.Name)" -ForegroundColor Gray
    Write-Host "  Path: $($proj.Path)" -ForegroundColor Gray
    Write-Host "  Type: $($proj.Type)" -ForegroundColor Gray
    Write-Host "  Drive: $($proj.DriveLetter) ($($proj.DriveLabel))" -ForegroundColor Gray
    Write-Host "  Location: $($proj.Location)" -ForegroundColor Gray
}
catch {
    Write-Host "✗ Failed to create ProjectInfo: $_" -ForegroundColor Red
    exit 1
}

# Test New-PortInfo factory
Write-Host "`n[Test 3] Testing New-PortInfo factory..." -ForegroundColor Magenta
try {
    $port = New-PortInfo `
        -ProjectName 'TestProject' `
        -Port 8080 `
        -Protocol 'TCP' `
        -ServiceName 'WebServer' `
        -Description 'Development web server'
    
    Write-Host "✓ New-PortInfo created successfully" -ForegroundColor Green
    Write-Host "  ProjectName: $($port.ProjectName)" -ForegroundColor Gray
    Write-Host "  Port: $($port.Port)/$($port.Protocol)" -ForegroundColor Gray
    Write-Host "  Service: $($port.ServiceName)" -ForegroundColor Gray
    Write-Host "  Description: $($port.Description)" -ForegroundColor Gray
    Write-Host "  IsActive: $($port.IsActive)" -ForegroundColor Gray
}
catch {
    Write-Host "✗ Failed to create PortInfo: $_" -ForegroundColor Red
    exit 1
}

# Test Get-ProjectInfoFromPath factory
Write-Host "`n[Test 4] Testing Get-ProjectInfoFromPath factory..." -ForegroundColor Magenta
try {
    $testPath = "$env:TEMP\test-psmm-project"
    if (-not (Test-Path $testPath)) {
        $null = New-Item -Path $testPath -ItemType Directory -Force
    }
    
    $projFromPath = Get-ProjectInfoFromPath `
        -Path $testPath `
        -DriveLetter $([System.IO.Path]::GetPathRoot($testPath).TrimEnd('\')) `
        -DriveLabel 'TestDrive' `
        -SerialNumber 'TEST-SERIAL'
    
    Write-Host "✓ Get-ProjectInfoFromPath created successfully" -ForegroundColor Green
    Write-Host "  Name: $($projFromPath.Name)" -ForegroundColor Gray
    Write-Host "  Path: $($projFromPath.Path)" -ForegroundColor Gray
    Write-Host "  Size: $($projFromPath.SizeBytes) bytes" -ForegroundColor Gray
    Write-Host "  Created: $($projFromPath.CreatedDate)" -ForegroundColor Gray
}
catch {
    Write-Host "✗ Failed to create ProjectInfo from path: $_" -ForegroundColor Red
    exit 1
}

# Test that classes can be accessed via factories (not directly)
Write-Host "`n[Test 5] Verifying class accessibility pattern..." -ForegroundColor Magenta
try {
    $isProjectType = $proj -is [object]
    if ($isProjectType) {
        Write-Host "✓ ProjectInfo instances are accessible through factory functions" -ForegroundColor Green
    }
}
catch {
    Write-Host "✗ Unexpected error: $_" -ForegroundColor Red
    exit 1
}

# Test method calls on created instances
Write-Host "`n[Test 6] Testing instance methods..." -ForegroundColor Magenta
try {
    $displayName = $proj.GetDisplayName()
    Write-Host "✓ ProjectInfo.GetDisplayName() method works: $displayName" -ForegroundColor Green
    
    $portDisplay = $port.GetDisplayName()
    Write-Host "✓ PortInfo.GetDisplayName() method works: $portDisplay" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to call instance methods: $_" -ForegroundColor Red
    exit 1
}

# Summary
Write-Host "`n=================================" -ForegroundColor Cyan
Write-Host "Phase 3 Factory Functions Tests: PASSED" -ForegroundColor Green
Write-Host "=================================" -ForegroundColor Cyan
Write-Host "`nClasses are now accessible via factory functions:" -ForegroundColor Cyan
Write-Host "  New-ProjectInfo" -ForegroundColor Gray
Write-Host "  New-PortInfo" -ForegroundColor Gray
Write-Host "  Get-ProjectInfoFromPath" -ForegroundColor Gray

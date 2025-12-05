#!/usr/bin/env pwsh
using namespace System
using namespace System.Net
using namespace Microsoft.Management.Infrastructure

Write-Host "Testing standard .NET exception constructors..." -ForegroundColor Cyan

try {
    Write-Host "  Testing WebException(msg, Exception)" -ForegroundColor Cyan
    $ex = [WebException]::new("test", [System.Exception]::new("inner"))
    Write-Host "  ✓ WebException works" -ForegroundColor Green
} catch {
    Write-Host "  ✗ WebException failed: $_" -ForegroundColor Red
}

try {
    Write-Host "  Testing CimException(msg, Exception)" -ForegroundColor Cyan
    $ex = [CimException]::new("test", [System.Exception]::new("inner"))
    Write-Host "  ✓ CimException works" -ForegroundColor Green
} catch {
    Write-Host "  ✗ CimException failed: $_" -ForegroundColor Red
}

try {
    Write-Host "  Testing ArgumentException(msg, string)" -ForegroundColor Cyan
    $ex = [ArgumentException]::new("test", "paramname")
    Write-Host "  ✓ ArgumentException works" -ForegroundColor Green
} catch {
    Write-Host "  ✗ ArgumentException failed: $_" -ForegroundColor Red
}

try {
    Write-Host "  Testing InvalidOperationException(msg, Exception)" -ForegroundColor Cyan
    $ex = [InvalidOperationException]::new("test", [System.Exception]::new("inner"))
    Write-Host "  ✓ InvalidOperationException works" -ForegroundColor Green
} catch {
    Write-Host "  ✗ InvalidOperationException failed: $_" -ForegroundColor Red
}

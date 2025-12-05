#!/usr/bin/env pwsh
using namespace System
using namespace System.Net
using namespace Microsoft.Management.Infrastructure

Write-PSmmHost "Testing standard .NET exception constructors..." -ForegroundColor Cyan

try {
    Write-PSmmHost "  Testing WebException(msg, Exception)" -ForegroundColor Cyan
    [void][WebException]::new("test", [System.Exception]::new("inner"))
    Write-PSmmHost "  ✓ WebException works" -ForegroundColor Green
} catch {
    Write-PSmmHost "  ✗ WebException failed: $_" -ForegroundColor Red
}

try {
    Write-PSmmHost "  Testing CimException(msg, Exception)" -ForegroundColor Cyan
    [void][CimException]::new("test", [System.Exception]::new("inner"))
    Write-PSmmHost "  ✓ CimException works" -ForegroundColor Green
} catch {
    Write-PSmmHost "  ✗ CimException failed: $_" -ForegroundColor Red
}

try {
    Write-PSmmHost "  Testing ArgumentException(msg, string)" -ForegroundColor Cyan
    [void][ArgumentException]::new("test", "paramname")
    Write-PSmmHost "  ✓ ArgumentException works" -ForegroundColor Green
} catch {
    Write-PSmmHost "  ✗ ArgumentException failed: $_" -ForegroundColor Red
}

try {
    Write-PSmmHost "  Testing InvalidOperationException(msg, Exception)" -ForegroundColor Cyan
    [void][InvalidOperationException]::new("test", [System.Exception]::new("inner"))
    Write-PSmmHost "  ✓ InvalidOperationException works" -ForegroundColor Green
} catch {
    Write-PSmmHost "  ✗ InvalidOperationException failed: $_" -ForegroundColor Red
}

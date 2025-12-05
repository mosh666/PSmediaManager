#!/usr/bin/env pwsh
Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

# Load exception classes
. ./src/Modules/PSmm/Classes/Exceptions.ps1

# Test all 3-arg exception constructors
try {
    Write-Host 'Testing ConfigurationException(msg, path, Exception)' -ForegroundColor Cyan
    [void][ConfigurationException]::new('test', 'path', $([System.Exception]::new('inner')))
    Write-Host '✓ ConfigurationException works' -ForegroundColor Green
} catch {
    Write-Host '✗ ConfigurationException failed: ' $_ -ForegroundColor Red
}

try {
    Write-Host 'Testing PluginRequirementException(msg, name, Exception)' -ForegroundColor Cyan
    [void][PluginRequirementException]::new('test', 'plugin', $([System.Exception]::new('inner')))
    Write-Host '✓ PluginRequirementException works' -ForegroundColor Green
} catch {
    Write-Host '✗ PluginRequirementException failed: ' $_ -ForegroundColor Red
}

try {
    Write-Host 'Testing LoggingException(msg, path, Exception)' -ForegroundColor Cyan
    [void][LoggingException]::new('test', 'path', $([System.Exception]::new('inner')))
    Write-Host '✓ LoggingException works' -ForegroundColor Green
} catch {
    Write-Host '✗ LoggingException failed: ' $_ -ForegroundColor Red
}

try {
    Write-Host 'Testing ModuleLoadException(msg, name, Exception)' -ForegroundColor Cyan
    [void][ModuleLoadException]::new('test', 'module', $([System.Exception]::new('inner')))
    Write-Host '✓ ModuleLoadException works' -ForegroundColor Green
} catch {
    Write-Host '✗ ModuleLoadException failed: ' $_ -ForegroundColor Red
}

try {
    Write-Host 'Testing ProcessException(msg, name, Exception)' -ForegroundColor Cyan
    [void][ProcessException]::new('test', 'process', $([System.Exception]::new('inner')))
    Write-Host '✓ ProcessException works' -ForegroundColor Green
} catch {
    Write-Host '✗ ProcessException failed: ' $_ -ForegroundColor Red
}

try {
    Write-Host 'Testing ValidationException(msg, name, value)' -ForegroundColor Cyan
    [void][ValidationException]::new('test', 'prop', 'value')
    Write-Host '✓ ValidationException works' -ForegroundColor Green
} catch {
    Write-Host '✗ ValidationException failed: ' $_ -ForegroundColor Red
}

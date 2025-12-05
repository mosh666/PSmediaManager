#!/usr/bin/env pwsh
Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

# Load exception classes
. ./src/Modules/PSmm/Classes/Exceptions.ps1

# Test all 3-arg exception constructors
try {
    Write-PSmmHost 'Testing ConfigurationException(msg, path, Exception)' -ForegroundColor Cyan
    [void][ConfigurationException]::new('test', 'path', $([System.Exception]::new('inner')))
    Write-PSmmHost '✓ ConfigurationException works' -ForegroundColor Green
} catch {
    Write-PSmmHost '✗ ConfigurationException failed: ' $_ -ForegroundColor Red
}

try {
    Write-PSmmHost 'Testing PluginRequirementException(msg, name, Exception)' -ForegroundColor Cyan
    [void][PluginRequirementException]::new('test', 'plugin', $([System.Exception]::new('inner')))
    Write-PSmmHost '✓ PluginRequirementException works' -ForegroundColor Green
} catch {
    Write-PSmmHost '✗ PluginRequirementException failed: ' $_ -ForegroundColor Red
}

try {
    Write-PSmmHost 'Testing LoggingException(msg, path, Exception)' -ForegroundColor Cyan
    [void][LoggingException]::new('test', 'path', $([System.Exception]::new('inner')))
    Write-PSmmHost '✓ LoggingException works' -ForegroundColor Green
} catch {
    Write-PSmmHost '✗ LoggingException failed: ' $_ -ForegroundColor Red
}

try {
    Write-PSmmHost 'Testing ModuleLoadException(msg, name, Exception)' -ForegroundColor Cyan
    [void][ModuleLoadException]::new('test', 'module', $([System.Exception]::new('inner')))
    Write-PSmmHost '✓ ModuleLoadException works' -ForegroundColor Green
} catch {
    Write-PSmmHost '✗ ModuleLoadException failed: ' $_ -ForegroundColor Red
}

try {
    Write-PSmmHost 'Testing ProcessException(msg, name, Exception)' -ForegroundColor Cyan
    [void][ProcessException]::new('test', 'process', $([System.Exception]::new('inner')))
    Write-PSmmHost '✓ ProcessException works' -ForegroundColor Green
} catch {
    Write-PSmmHost '✗ ProcessException failed: ' $_ -ForegroundColor Red
}

try {
    Write-PSmmHost 'Testing ValidationException(msg, name, value)' -ForegroundColor Cyan
    [void][ValidationException]::new('test', 'prop', 'value')
    Write-PSmmHost '✓ ValidationException works' -ForegroundColor Green
} catch {
    Write-PSmmHost '✗ ValidationException failed: ' $_ -ForegroundColor Red
}

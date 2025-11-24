#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Preload PSmm class/type definitions in a deterministic order so analyzers
# can resolve types at parse time. This script is intended to be dot-sourced
# by analysis or CI runners before invoking PSScriptAnalyzer.

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$classesBase = Join-Path -Path $repoRoot -ChildPath 'src\Modules\PSmm\Classes'

if (-not (Test-Path -Path $classesBase)) {
    Write-Verbose "Preload: classes path not found: $classesBase"
    return
}

Write-Verbose "Preload: dot-sourcing PSmm types from $classesBase"

# Interfaces and exceptions
$interfaces = Join-Path $classesBase 'Interfaces.ps1'
if (Test-Path $interfaces) { . $interfaces }

$exceptions = Join-Path $classesBase 'Exceptions.ps1'
if (Test-Path $exceptions) { . $exceptions }

# Core configuration types and builder
$appConfig = Join-Path $classesBase 'AppConfiguration.ps1'
if (Test-Path $appConfig) { . $appConfig }

$appBuilder = Join-Path $classesBase 'AppConfigurationBuilder.ps1'
if (Test-Path $appBuilder) { . $appBuilder }

# Service implementations
$servicesDir = Join-Path $classesBase 'Services'
if (Test-Path $servicesDir) {
    $serviceFiles = @( 'CimService.ps1','CryptoService.ps1','EnvironmentService.ps1','FileSystemService.ps1','GitService.ps1','HttpService.ps1','ProcessService.ps1' )
    foreach ($name in $serviceFiles) {
        $path = Join-Path $servicesDir $name
        if (Test-Path $path) { . $path }
    }
}

Write-Verbose "Preload: complete"

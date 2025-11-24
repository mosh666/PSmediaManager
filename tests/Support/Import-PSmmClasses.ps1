#Requires -Version 7.5.4
param(
    [string]$RepositoryRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
)

Set-StrictMode -Version Latest

$classesRoot = Join-Path -Path $RepositoryRoot -ChildPath 'src/Modules/PSmm/Classes'

$needsImport = $false
try {
    $null = [AppConfigurationBuilder]
}
catch {
    $needsImport = $true
}

if (-not $needsImport) {
    return
}

$classFiles = @(
    'Interfaces.ps1'
    'Exceptions.ps1'
    'Services/FileSystemService.ps1'
    'Services/EnvironmentService.ps1'
    'Services/HttpService.ps1'
    'Services/ProcessService.ps1'
    'Services/CimService.ps1'
    'Services/GitService.ps1'
    'Services/CryptoService.ps1'
    'AppConfiguration.ps1'
    'AppConfigurationBuilder.ps1'
    # Dependency injection moved/removed; no DependencyInjection.ps1 to import
)

foreach ($relativePath in $classFiles) {
    $classPath = Join-Path -Path $classesRoot -ChildPath $relativePath
    if (-not (Test-Path -Path $classPath)) {
        throw "Required PSmm class file not found: $relativePath"
    }

    . $classPath
}

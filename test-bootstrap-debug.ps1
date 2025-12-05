#!/usr/bin/env pwsh
#requires -Version 7.5.4

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

# Load classes
. 'd:\PSmediaManager\src\Modules\PSmm\Classes\Interfaces.ps1'
Write-Host "✓ Interfaces loaded"

. 'd:\PSmediaManager\src\Modules\PSmm\Classes\Exceptions.ps1'
Write-Host "✓ Exceptions loaded"

. 'd:\PSmediaManager\src\Core\BootstrapServices.ps1'
Write-Host "✓ BootstrapServices loaded"

. 'd:\PSmediaManager\src\Modules\PSmm\Classes\Services\FileSystemService.ps1'
. 'd:\PSmediaManager\src\Modules\PSmm\Classes\Services\EnvironmentService.ps1'
. 'd:\PSmediaManager\src\Modules\PSmm\Classes\Services\HttpService.ps1'
. 'd:\PSmediaManager\src\Modules\PSmm\Classes\Services\CimService.ps1'
. 'd:\PSmediaManager\src\Modules\PSmm\Classes\Services\GitService.ps1'
. 'd:\PSmediaManager\src\Modules\PSmm\Classes\Services\ProcessService.ps1'
. 'd:\PSmediaManager\src\Modules\PSmm\Classes\Services\CryptoService.ps1'
. 'd:\PSmediaManager\src\Modules\PSmm\Classes\Services\StorageService.ps1'
Write-Host "✓ Services loaded"

. 'd:\PSmediaManager\src\Modules\PSmm\Classes\AppConfiguration.ps1'
Write-Host "✓ AppConfiguration loaded"

. 'd:\PSmediaManager\src\Modules\PSmm\Classes\AppConfigurationBuilder.ps1'
Write-Host "✓ AppConfigurationBuilder loaded"

# Now try the actual bootstrap steps
try {
    Write-Host "`nTesting AppConfigurationBuilder instantiation..."
    $configBuilder = [AppConfigurationBuilder]::new('D:\PSmediaManager')
    Write-Host "✓ AppConfigurationBuilder created"
    
    Write-Host "`nTesting WithRootPath..."
    $configBuilder = $configBuilder.WithRootPath('D:\PSmediaManager')
    Write-Host "✓ WithRootPath succeeded"
    
    Write-Host "`nTesting WithParameters..."
    $params = [RuntimeParameters]::new(@{})
    $configBuilder = $configBuilder.WithParameters($params)
    Write-Host "✓ WithParameters succeeded"
    
    Write-Host "`nTesting WithVersion..."
    $configBuilder = $configBuilder.WithVersion([version]'1.0.0')
    Write-Host "✓ WithVersion succeeded"
    
    Write-Host "`nTesting InitializeDirectories..."
    # Create mock services first
    $mockFileSystem = [FileSystemService]::new()
    $mockEnvironment = [EnvironmentService]::new()
    $mockPathProvider = $configBuilder.GetConfig().Paths  # Use the paths as provider
    $mockProcess = [ProcessService]::new()
    
    $configBuilder = $configBuilder.WithServices($mockFileSystem, $mockEnvironment, $mockPathProvider, $mockProcess).InitializeDirectories()
    Write-Host "✓ InitializeDirectories succeeded"
    
    Write-Host "`n✓ All bootstrap steps successful!"
}
catch {
    Write-Host -ForegroundColor Red "`n✗ Error: $($_.Exception.GetType().FullName)"
    Write-Host -ForegroundColor Red "Message: $($_.Exception.Message)"
    Write-Host -ForegroundColor Red "At line: $($_.InvocationInfo.ScriptLineNumber)"
    if($_.Exception.InnerException) {
        Write-Host -ForegroundColor Red "Inner: $($_.Exception.InnerException.Message)"
    }
    Write-Host -ForegroundColor Red "`nFull error:`n$_"
}

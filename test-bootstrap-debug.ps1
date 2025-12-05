#!/usr/bin/env pwsh
#requires -Version 7.5.4

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

# Load classes
. 'd:\PSmediaManager\src\Modules\PSmm\Classes\Interfaces.ps1'
Write-PSmmHost "✓ Interfaces loaded"

. 'd:\PSmediaManager\src\Modules\PSmm\Classes\Exceptions.ps1'
Write-PSmmHost "✓ Exceptions loaded"

. 'd:\PSmediaManager\src\Core\BootstrapServices.ps1'
Write-PSmmHost "✓ BootstrapServices loaded"

. 'd:\PSmediaManager\src\Modules\PSmm\Classes\Services\FileSystemService.ps1'
. 'd:\PSmediaManager\src\Modules\PSmm\Classes\Services\EnvironmentService.ps1'
. 'd:\PSmediaManager\src\Modules\PSmm\Classes\Services\HttpService.ps1'
. 'd:\PSmediaManager\src\Modules\PSmm\Classes\Services\CimService.ps1'
. 'd:\PSmediaManager\src\Modules\PSmm\Classes\Services\GitService.ps1'
. 'd:\PSmediaManager\src\Modules\PSmm\Classes\Services\ProcessService.ps1'
. 'd:\PSmediaManager\src\Modules\PSmm\Classes\Services\CryptoService.ps1'
. 'd:\PSmediaManager\src\Modules\PSmm\Classes\Services\StorageService.ps1'
Write-PSmmHost "✓ Services loaded"

. 'd:\PSmediaManager\src\Modules\PSmm\Classes\AppConfiguration.ps1'
Write-PSmmHost "✓ AppConfiguration loaded"

. 'd:\PSmediaManager\src\Modules\PSmm\Classes\AppConfigurationBuilder.ps1'
Write-PSmmHost "✓ AppConfigurationBuilder loaded"

# Now try the actual bootstrap steps
try {
    Write-PSmmHost "`nTesting AppConfigurationBuilder instantiation..."
    $configBuilder = [AppConfigurationBuilder]::new('D:\PSmediaManager')
    Write-PSmmHost "✓ AppConfigurationBuilder created"
    
    Write-PSmmHost "`nTesting WithRootPath..."
    $configBuilder = $configBuilder.WithRootPath('D:\PSmediaManager')
    Write-PSmmHost "✓ WithRootPath succeeded"
    
    Write-PSmmHost "`nTesting WithParameters..."
    $params = [RuntimeParameters]::new(@{})
    $configBuilder = $configBuilder.WithParameters($params)
    Write-PSmmHost "✓ WithParameters succeeded"
    
    Write-PSmmHost "`nTesting WithVersion..."
    $configBuilder = $configBuilder.WithVersion([version]'1.0.0')
    Write-PSmmHost "✓ WithVersion succeeded"
    
    Write-PSmmHost "`nTesting InitializeDirectories..."
    # Create mock services first
    $mockFileSystem = [FileSystemService]::new()
    $mockEnvironment = [EnvironmentService]::new()
    $mockPathProvider = $configBuilder.GetConfig().Paths  # Use the paths as provider
    $mockProcess = [ProcessService]::new()
    
    $configBuilder = $configBuilder.WithServices($mockFileSystem, $mockEnvironment, $mockPathProvider, $mockProcess).InitializeDirectories()
    Write-PSmmHost "✓ InitializeDirectories succeeded"
    
    Write-PSmmHost "`n✓ All bootstrap steps successful!"
}
catch {
    Write-PSmmHost -ForegroundColor Red "`n✗ Error: $($_.Exception.GetType().FullName)"
    Write-PSmmHost -ForegroundColor Red "Message: $($_.Exception.Message)"
    Write-PSmmHost -ForegroundColor Red "At line: $($_.InvocationInfo.ScriptLineNumber)"
    if($_.Exception.InnerException) {
        Write-PSmmHost -ForegroundColor Red "Inner: $($_.Exception.InnerException.Message)"
    }
    Write-PSmmHost -ForegroundColor Red "`nFull error:`n$_"
}

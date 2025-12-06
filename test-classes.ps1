Import-Module .\src\Modules\PSmm\PSmm.psd1 -Force
Write-Host "Module imported" -ForegroundColor Green
Write-Host "Testing ProjectInfo class..." -ForegroundColor Green
$proj = [ProjectInfo]::new('TestProject', 'D:\Projects\Test', 'Photo')
Write-Host "Success! Project: $($proj.GetDisplayName())" -ForegroundColor Green
Write-Host "Testing PortInfo class..." -ForegroundColor Green
$port = [PortInfo]::new('TestProject', 8080, 'TCP', 'WebServer')
Write-Host "Success! Port: $($port.GetDisplayName())" -ForegroundColor Green

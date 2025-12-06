<#
.SYNOPSIS
    Phase 10 - Configuration Validation & Security Hardening Tests

.DESCRIPTION
    Comprehensive test suite for configuration validation system:
    - Type checking and range validation
    - Path existence and accessibility validation
    - Schema validation for configuration properties
    - Security checks for sensitive data
    - Config drift detection (runtime vs. disk comparison)

.NOTES
    Requires: PowerShell 7.5.4+
    Tests: 20+ test cases
    Phase: 10 - Configuration Validation & Security Hardening
#>

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "`nPhase 10 - Configuration Validation & Security Tests" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# Setup
$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcRoot = Join-Path $testRoot '..' 'src'
$workspaceRoot = Split-Path -Parent $testRoot

# Load modules
Write-Host "`nLoading modules..." -ForegroundColor Gray
Import-Module -Name (Join-Path $srcRoot 'Modules' 'PSmm') -Force
Import-Module -Name (Join-Path $srcRoot 'Modules' 'PSmm.Logging') -Force

$testsPassed = 0
$testsFailed = 0

# ===== Test Group 1: Config Validator Instantiation =====
Write-Host "`nTest Group 1: ConfigValidator Infrastructure" -ForegroundColor Green

Write-Host "`n[1.1] ConfigValidator instantiation without FileSystem" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new()
    
    if ($null -ne $validator) {
        Write-Host "  ✓ PASS: ConfigValidator created successfully" -ForegroundColor Green
        $testsPassed++
    } else {
        throw "Validator is null"
    }
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

Write-Host "`n[1.2] ConfigValidator instantiation with FileSystem service" -ForegroundColor Yellow
try {
    $fileSystem = [FileSystemService]::new()
    $validator = [ConfigValidator]::new($fileSystem)
    
    if ($null -ne $validator) {
        Write-Host "  ✓ PASS: ConfigValidator created with FileSystem service" -ForegroundColor Green
        $testsPassed++
    } else {
        throw "Validator is null"
    }
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

# ===== Test Group 2: Schema Management =====
Write-Host "`nTest Group 2: Schema Definition and Management" -ForegroundColor Green

Write-Host "`n[2.1] Add custom schema definition" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new()
    $schema = [ConfigSchema]::new('TestProperty', 'String', $true)
    $validator.AddSchema($schema)
    
    Write-Host "  ✓ PASS: Custom schema added successfully" -ForegroundColor Green
    $testsPassed++
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

Write-Host "`n[2.2] Schema with range constraints" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new()
    $schema = [ConfigSchema]::new('Port', 'Int', $true)
    $schema.MinValue = 1024
    $schema.MaxValue = 65535
    $validator.AddSchema($schema)
    
    Write-Host "  ✓ PASS: Range-constrained schema added" -ForegroundColor Green
    $testsPassed++
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

# ===== Test Group 3: Type Validation =====
Write-Host "`nTest Group 3: Type Validation" -ForegroundColor Green

Write-Host "`n[3.1] Validate required string property" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new($false)  # Skip default schemas
    $validator.AddSchema([ConfigSchema]::new('DisplayName', 'String', $true))
    $validator.AddSchema([ConfigSchema]::new('InternalName', 'String', $true))
    
    $config = [PSCustomObject]@{
        DisplayName = 'TestApp'
        InternalName = 'testapp'
    }
    
    $issues = $validator.ValidateConfiguration($config)
    $errors = @($issues | Where-Object { $_.Severity -eq 'Error' })
    
    if ($errors.Count -eq 0) {
        Write-Host "  ✓ PASS: String properties validated (0 errors)" -ForegroundColor Green
        $testsPassed++
    } else {
        throw "Unexpected validation errors: $($errors.Count)"
    }
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

Write-Host "`n[3.2] Detect missing required property" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new($false)  # Skip default schemas
    $validator.AddSchema([ConfigSchema]::new('DisplayName', 'String', $true))
    
    $config = [PSCustomObject]@{
        InternalName = 'testapp'
        # DisplayName missing
    }
    
    $issues = $validator.ValidateConfiguration($config)
    $errors = @($issues | Where-Object { $_.Severity -eq 'Error' -and $_.Property -eq 'DisplayName' })
    
    if ($errors.Count -gt 0) {
        Write-Host "  ✓ PASS: Missing required property detected" -ForegroundColor Green
        $testsPassed++
    } else {
        throw "Missing property not detected"
    }
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

Write-Host "`n[3.3] Detect type mismatch" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new($false)  # Skip default schemas
    $schema = [ConfigSchema]::new('UI.Width', 'Int', $true)
    $validator.AddSchema($schema)
    
    $config = [PSCustomObject]@{
        UI = @{ Width = 'not-a-number' }
    }
    
    $issues = $validator.ValidateConfiguration($config)
    $typeErrors = @($issues | Where-Object { $_.Category -eq 'Type' })
    
    if ($typeErrors.Count -gt 0) {
        Write-Host "  ✓ PASS: Type mismatch detected (Expected Int, got String)" -ForegroundColor Green
        $testsPassed++
    } else {
        throw "Type mismatch not detected"
    }
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

# ===== Test Group 4: Range Validation =====
Write-Host "`nTest Group 4: Range Validation" -ForegroundColor Green

Write-Host "`n[4.1] Validate value within range" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new($false)  # Skip default schemas
    $schema = [ConfigSchema]::new('UI.Width', 'Int', $true)
    $schema.MinValue = 80
    $schema.MaxValue = 300
    $validator.AddSchema($schema)
    
    $config = [PSCustomObject]@{
        UI = @{ Width = 120 }
    }
    
    $issues = $validator.ValidateConfiguration($config)
    $rangeErrors = @($issues | Where-Object { $_.Category -eq 'Range' })
    
    if ($rangeErrors.Count -eq 0) {
        Write-Host "  ✓ PASS: Value within range validated (80 ≤ 120 ≤ 300)" -ForegroundColor Green
        $testsPassed++
    } else {
        throw "Unexpected range validation error"
    }
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

Write-Host "`n[4.2] Detect value below minimum" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new($false)  # Skip default schemas
    $schema = [ConfigSchema]::new('Port', 'Int', $true)
    $schema.MinValue = 1024
    $validator.AddSchema($schema)
    
    $config = [PSCustomObject]@{
        Port = 80
    }
    
    $issues = $validator.ValidateConfiguration($config)
    $rangeErrors = @($issues | Where-Object { $_.Category -eq 'Range' -and $_.Property -eq 'Port' })
    
    if ($rangeErrors.Count -gt 0) {
        Write-Host "  ✓ PASS: Value below minimum detected (80 < 1024)" -ForegroundColor Green
        $testsPassed++
    } else {
        throw "Minimum validation not triggered"
    }
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

Write-Host "`n[4.3] Detect value above maximum" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new($false)  # Skip default schemas
    $schema = [ConfigSchema]::new('UI.Width', 'Int', $true)
    $schema.MaxValue = 300
    $validator.AddSchema($schema)
    
    $config = [PSCustomObject]@{
        UI = @{ Width = 500 }
    }
    
    $issues = $validator.ValidateConfiguration($config)
    $rangeErrors = @($issues | Where-Object { $_.Category -eq 'Range' })
    
    if ($rangeErrors.Count -gt 0) {
        Write-Host "  ✓ PASS: Value above maximum detected (500 > 300)" -ForegroundColor Green
        $testsPassed++
    } else {
        throw "Maximum validation not triggered"
    }
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

# ===== Test Group 5: Path Validation =====
Write-Host "`nTest Group 5: Path Validation" -ForegroundColor Green

Write-Host "`n[5.1] Validate existing repository root path" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new($false)  # Skip default schemas
    $config = [PSCustomObject]@{
        Paths = @{
            Root = $workspaceRoot
            RepositoryRoot = $workspaceRoot
            Log = Join-Path $workspaceRoot 'logs'
        }
    }
    
    $issues = $validator.ValidateConfiguration($config)
    $pathErrors = @($issues | Where-Object { $_.Category -eq 'Path' -and $_.Severity -eq 'Error' })
    
    if ($pathErrors.Count -eq 0) {
        Write-Host "  ✓ PASS: Existing path validated" -ForegroundColor Green
        $testsPassed++
    } else {
        throw "Path validation failed unexpectedly: $($pathErrors[0].Message)"
    }
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

Write-Host "`n[5.2] Detect non-existent required path" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new($false)  # Skip default schemas
    $config = [PSCustomObject]@{
        Paths = @{
            RepositoryRoot = 'C:\NonExistent\Path\XYZ123'
        }
    }
    
    $issues = $validator.ValidateConfiguration($config)
    $pathErrors = @($issues | Where-Object { $_.Category -eq 'Path' -and $_.Severity -eq 'Error' })
    
    if ($pathErrors.Count -gt 0) {
        Write-Host "  ✓ PASS: Non-existent path detected" -ForegroundColor Green
        $testsPassed++
    } else {
        throw "Non-existent path not detected"
    }
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

Write-Host "`n[5.3] Warn on relative path" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new($false)  # Skip default schemas
    $config = [PSCustomObject]@{
        Paths = @{
            Root = 'relative/path'
            RepositoryRoot = $workspaceRoot
        }
    }
    
    $issues = $validator.ValidateConfiguration($config)
    $pathWarnings = @($issues | Where-Object { $_.Category -eq 'Path' -and $_.Severity -eq 'Warning' })
    
    if ($pathWarnings.Count -gt 0) {
        Write-Host "  ✓ PASS: Relative path warning generated" -ForegroundColor Green
        $testsPassed++
    } else {
        throw "Relative path warning not generated"
    }
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

# ===== Test Group 6: Security Validation =====
Write-Host "`nTest Group 6: Security Checks" -ForegroundColor Green

Write-Host "`n[6.1] Detect plaintext secrets" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new($false)  # Skip default schemas
    $config = [PSCustomObject]@{
        Secrets = @{
            GitHubToken = 'ghp_PlaintextTokenValue123'
            Password = 'supersecret'
        }
    }
    
    $issues = $validator.ValidateConfiguration($config)
    $securityWarnings = @($issues | Where-Object { $_.Category -eq 'Security' })
    
    if ($securityWarnings.Count -gt 0) {
        Write-Host "  ✓ PASS: Plaintext secrets detected ($($securityWarnings.Count) warnings)" -ForegroundColor Green
        $testsPassed++
    } else {
        throw "Plaintext secrets not detected"
    }
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

Write-Host "`n[6.2] Accept masked secrets" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new($false)  # Skip default schemas
    $config = [PSCustomObject]@{
        Secrets = @{
            GitHubToken = '********'
            Password = '****'
        }
    }
    
    $issues = $validator.ValidateConfiguration($config)
    $securityWarnings = @($issues | Where-Object { $_.Category -eq 'Security' -and $_.Property -match 'Secrets' })
    
    if ($securityWarnings.Count -eq 0) {
        Write-Host "  ✓ PASS: Masked secrets accepted" -ForegroundColor Green
        $testsPassed++
    } else {
        throw "Masked secrets flagged incorrectly"
    }
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

Write-Host "`n[6.3] Validate KeePassXC vault configuration" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new($false)  # Skip default schemas
    $config = [PSCustomObject]@{
        Vault = @{
            Database = 'C:\NonExistent\vault.kdbx'
        }
    }
    
    $issues = $validator.ValidateConfiguration($config)
    $vaultWarnings = @($issues | Where-Object { $_.Category -eq 'Security' -and $_.Property -match 'Vault' })
    
    if ($vaultWarnings.Count -gt 0) {
        Write-Host "  ✓ PASS: Missing vault database detected" -ForegroundColor Green
        $testsPassed++
    } else {
        throw "Missing vault not detected"
    }
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

# ===== Test Group 7: Config Drift Detection =====
Write-Host "`nTest Group 7: Configuration Drift Detection" -ForegroundColor Green

Write-Host "`n[7.1] Detect no drift when configs match" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new($false)  # Skip default schemas
    
    # Create temporary config file
    $tempConfig = Join-Path ([System.IO.Path]::GetTempPath()) "test-config-$(New-Guid).psd1"
    $configContent = "@{ DisplayName = 'TestApp'; Version = '1.0.0' }"
    Set-Content -Path $tempConfig -Value $configContent
    
    $runtimeConfig = @{
        DisplayName = 'TestApp'
        Version = '1.0.0'
    }
    
    $drifts = $validator.DetectDrift($runtimeConfig, $tempConfig)
    Remove-Item -Path $tempConfig -Force -ErrorAction SilentlyContinue
    
    if ($drifts.Count -eq 0) {
        Write-Host "  ✓ PASS: No drift detected when configs match" -ForegroundColor Green
        $testsPassed++
    } else {
        throw "False drift detected: $($drifts.Count) differences"
    }
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

Write-Host "`n[7.2] Detect modified property drift" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new($false)  # Skip default schemas
    
    # Create temporary config file
    $tempConfig = Join-Path ([System.IO.Path]::GetTempPath()) "test-config-$(New-Guid).psd1"
    $configContent = "@{ DisplayName = 'OldName'; Version = '1.0.0' }"
    Set-Content -Path $tempConfig -Value $configContent
    
    $runtimeConfig = @{
        DisplayName = 'NewName'  # Modified
        Version = '1.0.0'
    }
    
    $drifts = $validator.DetectDrift($runtimeConfig, $tempConfig)
    Remove-Item -Path $tempConfig -Force -ErrorAction SilentlyContinue
    
    $modifiedDrift = @($drifts | Where-Object { $_.PropertyPath -eq 'DisplayName' -and $_.DriftType -eq 'Modified' })
    
    if ($modifiedDrift.Count -gt 0) {
        Write-Host "  ✓ PASS: Modified property drift detected (OldName → NewName)" -ForegroundColor Green
        $testsPassed++
    } else {
        throw "Modified drift not detected"
    }
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

Write-Host "`n[7.3] Detect added property drift" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new($false)  # Skip default schemas
    
    # Create temporary config file
    $tempConfig = Join-Path ([System.IO.Path]::GetTempPath()) "test-config-$(New-Guid).psd1"
    $configContent = "@{ DisplayName = 'TestApp' }"
    Set-Content -Path $tempConfig -Value $configContent
    
    $runtimeConfig = @{
        DisplayName = 'TestApp'
        NewProperty = 'AddedValue'  # Added in runtime
    }
    
    $drifts = $validator.DetectDrift($runtimeConfig, $tempConfig)
    Remove-Item -Path $tempConfig -Force -ErrorAction SilentlyContinue
    
    $addedDrift = @($drifts | Where-Object { $_.DriftType -eq 'Added' })
    
    if ($addedDrift.Count -gt 0) {
        Write-Host "  ✓ PASS: Added property drift detected" -ForegroundColor Green
        $testsPassed++
    } else {
        throw "Added drift not detected"
    }
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

Write-Host "`n[7.4] Handle missing disk config file" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new($false)  # Skip default schemas
    $runtimeConfig = [PSCustomObject]@{ DisplayName = 'TestApp' }
    $nonExistentPath = 'C:\NonExistent\config.psd1'
    
    try {
        $drifts = $validator.DetectDrift($runtimeConfig, $nonExistentPath)
        throw "Should have thrown FileNotFoundException"
    }
    catch [System.IO.FileNotFoundException] {
        Write-Host "  ✓ PASS: FileNotFoundException thrown for missing config" -ForegroundColor Green
        $testsPassed++
    }
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

# ===== Test Group 8: Helper Methods =====
Write-Host "`nTest Group 8: Validator Helper Methods" -ForegroundColor Green

Write-Host "`n[8.1] GetIssuesBySeverity filter" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new($false)  # Skip default schemas
    $validator.AddSchema([ConfigSchema]::new('DisplayName', 'String', $true))  # Required property
    
    $config = [PSCustomObject]@{
        # Missing DisplayName (error), relative path (warning)
        Paths = @{ Root = 'relative/path'; RepositoryRoot = $workspaceRoot }
    }
    
    $issues = $validator.ValidateConfiguration($config)
    $errors = $validator.GetIssuesBySeverity('Error')
    $warnings = $validator.GetIssuesBySeverity('Warning')
    
    if ($errors.Count -gt 0 -and $warnings.Count -gt 0) {
        Write-Host "  ✓ PASS: Issues filtered by severity (Errors: $($errors.Count), Warnings: $($warnings.Count))" -ForegroundColor Green
        $testsPassed++
    } else {
        throw "Severity filter not working correctly"
    }
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

Write-Host "`n[8.2] HasErrors detection" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new($false)  # Skip default schemas
    $validator.AddSchema([ConfigSchema]::new('DisplayName', 'String', $true))  # Required property
    
    $config = [PSCustomObject]@{
        # Missing required DisplayName
    }
    
    $issues = $validator.ValidateConfiguration($config)
    $hasErrors = $validator.HasErrors()
    
    if ($hasErrors) {
        Write-Host "  ✓ PASS: HasErrors() detected validation errors" -ForegroundColor Green
        $testsPassed++
    } else {
        throw "HasErrors() did not detect errors"
    }
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

Write-Host "`n[8.3] Clear validation issues" -ForegroundColor Yellow
try {
    $validator = [ConfigValidator]::new($false)  # Skip default schemas
    $validator.AddSchema([ConfigSchema]::new('DisplayName', 'String', $true))  # Required property to generate error
    $config = [PSCustomObject]@{}  # Missing required property
    
    $issues1 = $validator.ValidateConfiguration($config)
    $count1 = $validator.GetIssues().Count
    
    $validator.Clear()
    $count2 = $validator.GetIssues().Count
    
    if ($count1 -gt 0 -and $count2 -eq 0) {
        Write-Host "  ✓ PASS: Issues cleared (Before: $count1, After: $count2)" -ForegroundColor Green
        $testsPassed++
    } else {
        throw "Clear() did not reset issues (Before: $count1, After: $count2)"
    }
}
catch {
    Write-Host "  ✗ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

# ===== Summary =====
$totalTests = $testsPassed + $testsFailed
Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "Phase 10 Test Results Summary" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Total Tests: $totalTests" -ForegroundColor White
Write-Host "Passed:      $testsPassed" -ForegroundColor Green
Write-Host "Failed:      $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })
Write-Host "Success Rate: $([Math]::Round(($testsPassed / $totalTests) * 100, 2))%" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Yellow' })

if ($testsFailed -eq 0) {
    Write-Host "`n✓ ALL TESTS PASSED" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`n✗ SOME TESTS FAILED" -ForegroundColor Red
    exit 1
}

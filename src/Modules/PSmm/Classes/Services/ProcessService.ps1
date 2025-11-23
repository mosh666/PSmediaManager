<#
.SYNOPSIS
    Implementation of IProcessService interface.

.DESCRIPTION
    Provides testable process execution operations.
    This service can be mocked in tests for full testability.

.NOTES
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
    Version: 1.0.0
#>

using namespace System
using namespace System.Diagnostics

<#
.SYNOPSIS
    Production implementation of process service.
#>
class ProcessService : IProcessService {
    
    <#
    .SYNOPSIS
        Starts a process and returns execution result.
    #>
    [object] StartProcess([string]$filePath, [string[]]$argumentList) {
        if ([string]::IsNullOrWhiteSpace($filePath)) {
            throw [ArgumentException]::new("File path cannot be empty", "filePath")
        }
        
        $processInfo = [ProcessStartInfo]::new()
        $processInfo.FileName = $filePath
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        
        if ($null -ne $argumentList -and $argumentList.Count -gt 0) {
            foreach ($arg in $argumentList) {
                $processInfo.ArgumentList.Add($arg)
            }
        }
        
        try {
            $process = [Process]::Start($processInfo)
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            
            return [PSCustomObject]@{
                ExitCode = $process.ExitCode
                StdOut = $stdout
                StdErr = $stderr
                Success = $process.ExitCode -eq 0
            }
        }
        catch {
            throw [InvalidOperationException]::new("Failed to start process $filePath : $_", $_.Exception)
        }
    }
    
    <#
    .SYNOPSIS
        Gets a running process by name.
    #>
    [object] GetProcess([string]$name) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw [ArgumentException]::new("Process name cannot be empty", "name")
        }
        
        $processes = Get-Process -Name $name -ErrorAction SilentlyContinue
        if ($processes) {
            return $processes[0]
        }
        
        return $null
    }
    
    <#
    .SYNOPSIS
        Tests if a command is available in PATH.
    #>
    [bool] TestCommand([string]$command) {
        if ([string]::IsNullOrWhiteSpace($command)) {
            return $false
        }
        
        $result = Get-Command -Name $command -ErrorAction SilentlyContinue
        return $null -ne $result
    }
    
    <#
    .SYNOPSIS
        Invokes a command and returns the result.
    #>
    [object] InvokeCommand([string]$command, [string[]]$arguments) {
        if ([string]::IsNullOrWhiteSpace($command)) {
            throw [ArgumentException]::new("Command cannot be empty", "command")
        }
        
        # Check if command exists
        if (-not $this.TestCommand($command)) {
            throw [InvalidOperationException]::new("Command not found: $command")
        }
        
        try {
            $output = & $command @arguments 2>&1
            $exitCode = $LASTEXITCODE
            
            return [PSCustomObject]@{
                ExitCode = $exitCode
                Output = $output
                Success = $exitCode -eq 0
            }
        }
        catch {
            throw [InvalidOperationException]::new("Failed to invoke command $command : $_", $_.Exception)
        }
    }
}

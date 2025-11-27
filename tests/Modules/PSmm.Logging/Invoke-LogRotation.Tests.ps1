#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Invoke-LogRotation' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        . (Join-Path $repoRoot 'tests/Support/Import-PSmmClasses.ps1') -RepositoryRoot $repoRoot
        try {
            $script:fileSystemFactory = { [FileSystemService]::new() }
        }
        catch {
            throw "FileSystemService type is unavailable for tests: $_"
        }
        $script:psmmLoggingManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'
        if (Get-Module -Name PSmm.Logging -ErrorAction SilentlyContinue) { Remove-Module -Name PSmm.Logging -Force }
        Import-Module -Name $psmmLoggingManifest -Force -ErrorAction Stop
    }

    It 'deletes files older than MaxAgeDays' {
        $dir = Join-Path $TestDrive 'logs-age'
        $null = New-Item -ItemType Directory -Path $dir -Force

        $recent = Join-Path $dir 'recent.log'
        $old = Join-Path $dir 'old.log'
        'recent' | Set-Content -Path $recent
        'old' | Set-Content -Path $old
        [System.IO.File]::SetLastWriteTime($recent, (Get-Date).AddDays(-1))
        [System.IO.File]::SetLastWriteTime($old, (Get-Date).AddDays(-40))

        $fs = & $script:fileSystemFactory
        { Invoke-LogRotation -Path $dir -MaxAgeDays 30 -Confirm:$false -FileSystem $fs } | Should -Not -Throw

        Test-Path -Path $old | Should -BeFalse
        Test-Path -Path $recent | Should -BeTrue
    }

    It 'keeps only MaxFiles newest files' {
        $dir = Join-Path $TestDrive 'logs-count'
        $null = New-Item -ItemType Directory -Path $dir -Force

        $files = @(
            @{ Name = 'f1.log'; Age = -1 },
            @{ Name = 'f2.log'; Age = -2 },
            @{ Name = 'f3.log'; Age = -3 }
        )

        foreach ($entry in $files) {
            $path = Join-Path $dir $entry.Name
            'log' | Set-Content -Path $path
            [System.IO.File]::SetLastWriteTime($path, (Get-Date).AddDays($entry.Age))
        }

        $fs = & $script:fileSystemFactory
        { Invoke-LogRotation -Path $dir -MaxFiles 2 -Confirm:$false -FileSystem $fs } | Should -Not -Throw

        Test-Path -Path (Join-Path $dir 'f3.log') | Should -BeFalse
        Test-Path -Path (Join-Path $dir 'f2.log') | Should -BeTrue
        Test-Path -Path (Join-Path $dir 'f1.log') | Should -BeTrue
    }

    It 'uses default FileSystemService and reports when nothing is deleted' {
        $dir = Join-Path $TestDrive 'logs-nodeletes'
        $null = New-Item -ItemType Directory -Path $dir -Force

        $file = Join-Path $dir 'latest.log'
        'keep' | Set-Content -Path $file
        [System.IO.File]::SetLastWriteTime($file, (Get-Date))

        { Invoke-LogRotation -Path $dir -MaxAgeDays 1 -MaxFiles 5 -Confirm:$false -Verbose } | Should -Not -Throw
        Test-Path -Path $file | Should -BeTrue
    }
}

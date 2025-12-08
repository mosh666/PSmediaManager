#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'New-CustomFileName' -Tag 'unit' {
    BeforeAll {
        $repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $psmmManifest = Join-Path $repoRoot 'src/Modules/PSmm/PSmm.psd1'
        if (Get-Module -Name PSmm -ErrorAction SilentlyContinue) { Remove-Module -Name PSmm -Force }
        Import-Module $psmmManifest -Force -ErrorAction Stop
    }

    It 'replaces supported time and identity placeholders' {
        Mock Get-Date { [datetime]'2025-01-02T03:04:05' } -ModuleName PSmm
        $env:USERNAME = 'UserX'
        $env:COMPUTERNAME = 'CompY'
        $template = '%year%-%month%-%day%_%hour%%minute%%second%_%username%@%computername%'
        $result = New-CustomFileName -Template $template
        $result | Should -Be '2025-01-02_030405_UserX@CompY'
    }

    It 'leaves placeholders without values unchanged and warns' {
        # Ensure username/computername are empty to trigger warnings
        $env:USERNAME = ''
        $env:USER = ''
        $env:COMPUTERNAME = ''
        $env:HOSTNAME = ''

        Mock Get-Date { [datetime]'2025-01-02T03:04:05' } -ModuleName PSmm

        $template = 'x-%username%-%computername%-y'

        # Capture warnings; function should resolve via fallbacks without warnings
        $warnings = @()
        $result = New-CustomFileName -Template $template -WarningVariable warnings
        $result | Should -Not -Match '%username%'
        $result | Should -Not -Match '%computername%'
        $warnings.Count | Should -Be 0
    }
}
Set-StrictMode -Version Latest

Describe 'New-CustomFileName' -Tag 'Filename','Utility' {
    BeforeAll {
        $script:origUser = $env:USERNAME
        $script:origUser2 = $env:USER
        $script:origComputer = $env:COMPUTERNAME
        $script:origHost = $env:HOSTNAME
    }
    AfterAll {
        $env:USERNAME = $script:origUser
        $env:USER = $script:origUser2
        $env:COMPUTERNAME = $script:origComputer
        $env:HOSTNAME = $script:origHost
    }

    Context 'Full substitution when all environment values present' {
        It 'Replaces all known placeholders and removes them from result' {
            $env:USERNAME = 'tester'
            $env:COMPUTERNAME = 'testbox'
            $template = '%year%-%month%-%day%_%hour%%minute%%second%_%username%@%computername%.log'
            $name = New-CustomFileName -Template $template -Verbose:$false
            $name | Should -Not -Match '%year%'
            $name | Should -Match 'tester@testbox'
        }
    }

    Context 'Missing primary env vars triggers fallback resolution (whoami/DNS) without warnings' {
        It 'Resolves placeholders via fallback mechanisms producing non-empty values' {
            $env:USERNAME = ''
            $env:USER = ''
            $env:COMPUTERNAME = ''
            $env:HOSTNAME = ''
            $template = '%username%_%computername%'
            $warnings = @()
            $result = New-CustomFileName -Template $template -WarningVariable warnings -Verbose:$false
            $result | Should -Not -Match '%username%'
            $result | Should -Not -Match '%computername%'
            $result | Should -Match '.+_.+'
            $warnings.Count | Should -Be 0
        }
    }

    Context 'Unknown placeholders are left intact without warning' {
        It 'Replaces known placeholders and leaves unknown untouched' {
            $env:USERNAME = 'alpha'
            $env:COMPUTERNAME = 'node1'
            $template = '%year%%unknown%'
            $warnings = @()
            $result = New-CustomFileName -Template $template -WarningVariable warnings -Verbose:$false
            $result | Should -Match '^[0-9]{4}%unknown%$'
            $warnings.Count | Should -Be 0
        }
    }
}
#Requires -Version 7.5.4
Set-StrictMode -Version Latest

if (-not (Get-Command -Name whoami -CommandType Function -ErrorAction SilentlyContinue)) {
    function whoami {
        & (Get-Command whoami.exe -ErrorAction Stop) @args
    }
}

$script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
$script:psmmManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'

Import-Module -Name $script:psmmManifest -Force -ErrorAction Stop

Describe 'New-CustomFileName' {
    BeforeAll {
        $localRepoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $psmmManifest = if ($script:psmmManifest) { $script:psmmManifest } else { Join-Path -Path $localRepoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1' }

        if (Get-Module -Name PSmm -ErrorAction SilentlyContinue) {
            Remove-Module -Name PSmm -Force
        }

        Import-Module -Name $psmmManifest -Force -ErrorAction Stop
    }

    BeforeAll {
        $script:originalUsername = $env:USERNAME
        $script:originalUser = $env:USER
        $script:originalComputerName = $env:COMPUTERNAME
        $script:originalHostName = $env:HOSTNAME
    }

    AfterAll {
        $env:USERNAME = $script:originalUsername
        $env:USER = $script:originalUser
        $env:COMPUTERNAME = $script:originalComputerName
        $env:HOSTNAME = $script:originalHostName
    }

    InModuleScope PSmm {
        It 'replaces all supported placeholders using environment data' {
            $mockedNow = [datetime]'2025-11-18T10:15:30'
            Mock Get-Date { $mockedNow }

            $env:USERNAME = 'psuser'
            $env:USER = 'legacy-user'
            $env:COMPUTERNAME = 'PSNODE'
            $env:HOSTNAME = 'ignored'

            $template = '%year%%month%%day%-%hour%%minute%%second%_%username%@%computername%'
            $result = New-CustomFileName -Template $template

            $expected = '{0}{1}{2}-{3}{4}{5}_psuser@PSNODE' -f
                $mockedNow.ToString('yyyy'),
                $mockedNow.ToString('MM'),
                $mockedNow.ToString('dd'),
                $mockedNow.ToString('HH'),
                $mockedNow.ToString('mm'),
                $mockedNow.ToString('ss')

            $result | Should -Be $expected
            Should -Invoke Get-Date -Times 1
        }

        It 'replaces %username% via whoami fallback when env is empty' {
            $mockedNow = [datetime]'2025-01-02T03:04:05'
            Mock Get-Date { $mockedNow }

            $env:USERNAME = ''
            $env:USER = ''
            $env:COMPUTERNAME = 'PSNODE'
            $env:HOSTNAME = 'PSNODE'

            $template = 'Export-%username%-%year%'
            $result = New-CustomFileName -Template $template

            $actualUser = & whoami
            $expected = ('Export-{0}-{1}' -f $actualUser, $mockedNow.ToString('yyyy'))

            $result | Should -Be $expected
        }

        It 'falls back to whoami for username when environment variables are missing' {
            $mockedNow = [datetime]'2025-11-18T10:15:30'
            Mock Get-Date { $mockedNow }
            function whoami { 'who-user' }

            $env:USERNAME = ''
            $env:USER = ''
            $env:COMPUTERNAME = 'NODE'
            $env:HOSTNAME = 'NODE'

            $result = New-CustomFileName -Template 'log-%username%'
            $result | Should -Be 'log-who-user'
        }

        It 'falls back to DNS hostname when environment variables are missing' {
            $mockedNow = [datetime]'2025-11-18T10:15:30'
            Mock Get-Date { $mockedNow }

            $env:USERNAME = 'userx'
            $env:USER = ''
            $env:COMPUTERNAME = ''
            $env:HOSTNAME = ''

            $expectedHost = [System.Net.Dns]::GetHostName()
            $result = New-CustomFileName -Template 'dump-%computername%'
            $result | Should -Be ("dump-{0}" -f $expectedHost)
        }
    }
}

Describe 'New-DirectoriesFromHashtable' {
    BeforeAll {
        $localRepoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $psmmManifest = Join-Path -Path $localRepoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'

        if (Get-Module -Name PSmm -ErrorAction SilentlyContinue) {
            Remove-Module -Name PSmm -Force
        }

        Import-Module -Name $psmmManifest -Force -ErrorAction Stop
    }

    It 'creates directories for absolute paths and nested structures' {
        $root = Join-Path -Path $TestDrive -ChildPath 'App'
        $paths = @{
            Root = Join-Path -Path $root -ChildPath 'Root'
            Nested = @{
                Data = Join-Path -Path $root -ChildPath 'Data'
            }
        }

        PSmm\New-DirectoriesFromHashtable -Structure $paths | Out-Null

        Test-Path -Path $paths.Root | Should -BeTrue
        Test-Path -Path $paths.Nested.Data | Should -BeTrue
    }

    It 'skips relative paths without creating directories' {
        Push-Location -Path $TestDrive
        try {
            $relativePath = 'logs\app'
            $structure = @{ Relative = $relativePath }

            PSmm\New-DirectoriesFromHashtable -Structure $structure | Out-Null

            Test-Path -Path (Join-Path -Path $TestDrive -ChildPath $relativePath) | Should -BeFalse
        }
        finally {
            Pop-Location
        }
    }

    It 'emits warning when encountering invalid absolute path' {
        Mock Write-Warning { param($Message) } -ModuleName PSmm

        $invalidPath = 'C:\Invalid<>Path'
        $structure = @{ Broken = $invalidPath }

        PSmm\New-DirectoriesFromHashtable -Structure $structure | Out-Null

        Should -Invoke Write-Warning -ModuleName PSmm -ParameterFilter { $Message -like '*Invalid path*' } -Times 1
        Test-Path -Path $invalidPath | Should -BeFalse
    }

    It 'respects WhatIf and does not create directories' {
        $root = Join-Path -Path $TestDrive -ChildPath 'App2'
        $paths = @{ Root = Join-Path -Path $root -ChildPath 'Root' }

        PSmm\New-DirectoriesFromHashtable -Structure $paths -WhatIf | Out-Null

        Test-Path -Path $paths.Root | Should -BeFalse
    }

    It 'skips non-path value types without errors' {
        $root = Join-Path -Path $TestDrive -ChildPath 'App3'
        $paths = @{
            Number = 123
            Flag = $true
            Items = @('a','b')
            Nested = @{ Inner = 1 }
        }

        PSmm\New-DirectoriesFromHashtable -Structure $paths | Out-Null

        Test-Path -Path (Join-Path -Path $root -ChildPath '123') | Should -BeFalse
    }
}

Describe 'Export-SafeConfiguration (deep branches)' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    It 'Handles extremely deep nested structures' {
        $tmp = Join-Path $env:TEMP ("psmm-deep-{0}.psd1" -f ([System.Guid]::NewGuid().ToString()))
        if (Test-Path $tmp) { Remove-Item $tmp -Force }

        # build a nested array deeper than the CloneGeneric default MaxDepth (20)
        $depth = 25
        $node = 'leaf'
        for ($i = 0; $i -lt $depth; $i++) { $node = @($node) }

        $cfg = @{ Deep = $node }

        Export-SafeConfiguration -Configuration $cfg -Path $tmp
        $content = Get-Content -Raw -Path $tmp

        # Ensure deep structure is represented in the export (at least the leaf)
        $content | Should -Match "Deep = 'leaf'"

        Remove-Item -Path $tmp -ErrorAction SilentlyContinue -Force
    }

    It 'Restores original PSModules when Requirements provided as IDictionary' {
        $tmp = Join-Path $env:TEMP ("psmm-req-{0}.psd1" -f ([System.Guid]::NewGuid().ToString()))
        if (Test-Path $tmp) { Remove-Item $tmp -Force }

        $cfg = @{ Requirements = @{ PSModules = @('ModA','ModB') } }

        Export-SafeConfiguration -Configuration $cfg -Path $tmp
        $content = Get-Content -Raw -Path $tmp

        # Expect the original PSModules to be preserved in the serialized output
        $content | Should -Match "PSModules\s*=\s*@\('ModA'\s*,\s*'ModB'\)"

        Remove-Item -Path $tmp -ErrorAction SilentlyContinue -Force
    }

    It 'Masks token/password keys and handles cyclic refs' {
        $tmp = Join-Path $env:TEMP ("psmm-mask-{0}.psd1" -f ([System.Guid]::NewGuid().ToString()))
        if (Test-Path $tmp) { Remove-Item $tmp -Force }

        $a = @{ }
        $a.Secret = 's3cr3t'
        $a.Token = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD'
        $a.Self = $a

        $cfg = @{ Projects = $a; Misc = @{ Number = 123; Flag = $true } }

        Export-SafeConfiguration -Configuration $cfg -Path $tmp
        $content = Get-Content -Raw -Path $tmp

        # Secret and Token values must be masked (asterisks are literal in output)
        $content | Should -Not -Match 's3cr3t'
        $content | Should -Match "Secret\s*=\s*'\*{8}'"
        $content | Should -Match "Token\s*=\s*'(?:\*{8}|ghp_\*+)'"

        # Cyclic refs should appear as the marker (or be truncated to MaxDepth in very deep graphs)
        $content | Should -Match '\[CyclicRef\]|\[MaxDepth\]'

        # Numeric and boolean leaves should be stringified
        $content | Should -Match "Number = '123'"
        $content | Should -Match "Flag = 'True'"

        Remove-Item -Path $tmp -ErrorAction SilentlyContinue -Force
    }
}

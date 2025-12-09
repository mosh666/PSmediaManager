<#
.SYNOPSIS
    PSmm requirements
#>

Set-StrictMode -Version Latest

@{
    PowerShell = @{
        VersionMinimum = '7.5.4'
        Modules = @(
            @{Name = 'Pester'; Repository = 'PSGallery' },
            @{Name = 'PSLogs'; Repository = 'PSGallery' },
            @{Name = 'PSScriptAnalyzer'; Repository = 'PSGallery' },
            @{Name = 'PSScriptTools'; Repository = 'PSGallery' }
        )
    }
}

@{
    # PSScriptAnalyzer settings tailored for PSmediaManager development.
    # Supported top-level keys: Rules, ExcludeRules, IncludeRules, IncludeDefaultRules, CustomRulePath, Severity
    IncludeDefaultRules = $true

    # Per-rule configuration: map rule name -> configuration hashtable
    Rules = @{
        'PSAvoidUsingConvertToSecureStringWithPlainText' = @{ Enable = $true; Severity = 'Error' }
        'PSAvoidUsingInvokeExpression'                    = @{ Enable = $true; Severity = 'Error' }
        'PSAvoidGlobalVars'                               = @{ Enable = $true; Severity = 'Warning' }
        'PSAvoidUsingCmdletAliases'                       = @{ Enable = $true; Severity = 'Warning' }
        'PSAvoidUsingWriteHost'                           = @{ Enable = $true; Severity = 'Warning' }
        'PSUseDeclaredVarsMoreThanAssignments'            = @{ Enable = $true; Severity = 'Warning' }
        'PSUseShouldProcess'                              = @{ Enable = $true; Severity = 'Warning' }
        'PSUseApprovedVerbs'                              = @{ Enable = $true; Severity = 'Warning' }
    }

    # Project-wide excludes (rule names)
    ExcludeRules = @(
        # 'PSAvoidTrailingWhitespace'  # enable if you want to ignore trailing-whitespace informational findings
        'TypeNotFound' # types are often defined at runtime or imported via module load; suppress parse-time noise
        'PSAvoidGlobalVars' # global service injection is an architectural pattern for dependency injection
    )
}

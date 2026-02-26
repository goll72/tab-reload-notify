#!/usr/bin/env pwsh

$settings = @{
    Rules = @{
        PSUseCompatibleSyntax = @{
            Enable = $true
            TargetVersions = @('5.1')
        }
    }
}

Invoke-ScriptAnalyzer -Path ./scripts/resources/install-win.ps1 -Settings $settings

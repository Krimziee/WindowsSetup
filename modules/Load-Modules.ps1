<#
    Loads every engine module. Dot-source this file (". .\modules\Load-Modules.ps1")
    so the functions land in the caller's scope. Used by setup.ps1 and by
    Run-Engine.ps1, so the list of modules lives in one place.
    (Ui.ps1 is loaded separately, only when the window is used.)
#>
foreach ($module in 'Common', 'Hardware', 'Preflight', 'Bloatware', 'Settings', 'Downloads', 'Apps', 'Drivers', 'Cleanup', 'Engine') {
    . (Join-Path $PSScriptRoot "$module.ps1")
}

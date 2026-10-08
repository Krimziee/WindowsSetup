<#
    The Windows Setup tab in Krimz's Toolkit. The toolkit loads this file in
    its own private module and calls the functions below; the page is the same
    one the standalone window shows (ui\Page.xaml, built by Ui.ps1).
    The log file is only started when Start setup is pressed.
#>

. (Join-Path $PSScriptRoot 'Load-Modules.ps1')
. (Join-Path $PSScriptRoot 'Ui.ps1')

function New-ToolPage {
    param([string]$Root, [hashtable]$Shell)
    $script:Setup.DryRun = [bool]$Shell.DryRun
    New-SetupPage -Root $Root -Version $script:SetupVersion -System (Get-SystemInfo) -OnBusy $Shell.SetBusy
}

function Test-ToolPageCanClose { Test-SetupCanClose }

function Close-ToolPage { Close-SetupPage }

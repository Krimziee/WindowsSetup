<#
    The Windows Setup tab in Krimz's Toolkit. The toolkit loads this file in
    its own private module and calls the functions below; the page is the same
    one the standalone window shows (ui\Page.xaml, built by Ui.ps1).
    The log file is only started when Start setup is pressed.
#>

. (Join-Path $PSScriptRoot 'Load-Modules.ps1')
. (Join-Path $PSScriptRoot 'Ui.ps1')

function Start-ToolPrefetch {
    # Reading the hardware takes a second or two (the first Windows query is slow), so the toolkit
    # starts it in the background while its window opens. New-ToolPage picks the result up.
    param([string]$Root)
    $ps = [powershell]::Create()
    [void]$ps.AddScript({ param($file) . $file; Get-SystemInfo }).AddArgument((Join-Path $Root 'modules\Hardware.ps1'))
    [pscustomobject]@{ PowerShell = $ps; Handle = $ps.BeginInvoke() }
}

function New-ToolPage {
    param([string]$Root, [hashtable]$Shell)
    $script:Setup.DryRun = [bool]$Shell.DryRun

    $system = $null
    if ($Shell.Prefetch) {
        try { $system = @($Shell.Prefetch.PowerShell.EndInvoke($Shell.Prefetch.Handle))[0] } catch { $system = $null }
        try { $Shell.Prefetch.PowerShell.Dispose() } catch { }
        $Shell.Prefetch = $null
    }
    if (-not $system) { $system = Get-SystemInfo }

    New-SetupPage -Root $Root -Version $script:SetupVersion -System $system -OnBusy $Shell.SetBusy
}

function Test-ToolPageCanClose { Test-SetupCanClose }

function Close-ToolPage { Close-SetupPage }

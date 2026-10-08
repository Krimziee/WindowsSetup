#Requires -Version 5.1
<#
    Windows Setup
    Sets up a fresh Windows install: removes bloatware, applies settings,
    installs game redistributables, apps and drivers, cleans up, then
    restarts. Windows Update is left to Windows itself.

    Opens the setup window by default.
    -Console                           Text-only version (no window)
    -Preset  Recommended | PowerUser   Console only: skips the preset menu
    -DryRun                            Shows what would happen without changing anything
#>
param(
    [ValidateSet('Recommended', 'PowerUser')] [string]$Preset,
    [switch]$DryRun,
    [switch]$Console
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # progress bars make downloads much slower in PowerShell 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Version = '0.9'

. (Join-Path $PSScriptRoot 'modules\Load-Modules.ps1')
$script:Setup.DryRun = [bool]$DryRun
Initialize-Log
Write-Log "Windows Setup $Version started (dry run: $DryRun, console: $Console)"

# ------------------------------------------------------------------
#  Window (default)
# ------------------------------------------------------------------

if (-not $Console) {
    try {
        . (Join-Path $PSScriptRoot 'modules\Ui.ps1')
        Show-SetupWindow -Root $PSScriptRoot -Version $Version -System (Get-SystemInfo)
    } catch {
        Write-Log "FATAL (window): $($_.Exception.Message)"
        Write-Log $_.ScriptStackTrace
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show("Windows Setup couldn't open its window:`n$($_.Exception.Message)`n`nDetails are in the log on your desktop.", 'Windows Setup', 'OK', 'Error') | Out-Null
    }
    return
}

# ------------------------------------------------------------------
#  Console version
# ------------------------------------------------------------------

$Host.UI.RawUI.WindowTitle = "Windows Setup $Version"

function Select-Preset {
    $presets = @(Get-Presets $PSScriptRoot)
    Write-Section 'Choose a setup'
    for ($i = 0; $i -lt $presets.Count; $i++) {
        Write-Host ('   {0}) {1,-15} {2}' -f ($i + 1), $presets[$i].Name, $presets[$i].Description)
    }
    Write-Host ''
    while ($true) {
        $answer = (Read-Host " Type a number and press Enter").Trim()
        if ($answer -match '^\d+$' -and [int]$answer -ge 1 -and [int]$answer -le $presets.Count) {
            return $presets[[int]$answer - 1].Key
        }
    }
}

function Show-Summary {
    param($Summary)
    Write-Section 'Summary'
    Write-Host ("  Done in {0} min:  " -f $Summary.Minutes) -NoNewline
    Write-Host ("{0} done  " -f $Summary.Ok)       -ForegroundColor Green    -NoNewline
    Write-Host ("{0} skipped  " -f $Summary.Skip)  -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0} warnings  " -f $Summary.Warn) -ForegroundColor Yellow   -NoNewline
    Write-Host ("{0} failed" -f $Summary.Fail)     -ForegroundColor Red
    if ($Summary.Problems) {
        Write-Host ''
        Write-Host '  Needs a look:' -ForegroundColor Yellow
        foreach ($p in $Summary.Problems) { Write-Host "   - $($p.Label): $($p.Detail)" }
    }
}

function Invoke-RestartCountdown {
    <#
        Counts down and restarts. Any key cancels. Returns $true if the PC
        is restarting.
    #>
    param([int]$Seconds = 60)

    if ($script:Setup.DryRun) {
        Write-Log '[dry run] would restart the PC'
        Write-Host ''
        Write-Host ' (dry run) The PC would restart now.' -ForegroundColor Yellow
        return $false
    }

    # Throw away keys pressed earlier so they don't cancel the countdown by accident
    while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }

    Write-Host ''
    for ($left = $Seconds; $left -gt 0; $left--) {
        Write-Host ("`r Restarting in {0,2} seconds to finish setup. Press any key to cancel. " -f $left) -ForegroundColor Cyan -NoNewline
        for ($tick = 0; $tick -lt 10; $tick++) {
            if ([Console]::KeyAvailable) {
                [void][Console]::ReadKey($true)
                Write-Host ''
                Write-Host ' Restart cancelled. Restart the PC yourself to finish setup.' -ForegroundColor Yellow
                Write-Log 'Restart cancelled by user'
                return $false
            }
            Start-Sleep -Milliseconds 100
        }
    }
    Write-Host ''
    Write-Log 'Restarting'
    Restart-Computer -Force
    return $true
}

$finished = $false
try {
    Clear-Host
    Write-Host ''
    Write-Host ' ============================================' -ForegroundColor DarkCyan
    Write-Host "   Windows Setup  $Version" -ForegroundColor White
    if ($DryRun) { Write-Host '   DRY RUN: nothing will be changed' -ForegroundColor Yellow }
    Write-Host ' ============================================' -ForegroundColor DarkCyan

    $system = Get-SystemInfo
    Show-SystemInfo $system

    if (-not $Preset) { $Preset = Select-Preset }
    $config = Import-PowerShellDataFile (Join-Path $PSScriptRoot "presets\$Preset.psd1")

    $summary = Invoke-Setup $config $system
    Show-Summary $summary
    Write-Host ''
    Write-Host " Log saved to: $($script:Setup.LogFile)" -ForegroundColor Green
    $finished = $true
}
catch {
    Write-Host ''
    Write-Host ' Setup stopped because of an error:' -ForegroundColor Red
    Write-Host " $($_.Exception.Message)" -ForegroundColor Red
    Write-Host " Details are in the log: $($script:Setup.LogFile)" -ForegroundColor Gray
    Write-Log "FATAL: $($_.Exception.Message)"
    Write-Log $_.ScriptStackTrace
}
finally {
    # Never leave background downloads running
    Stop-DownloadQueue
}

# Only restart after a complete run, so an error message stays readable
if ($finished -and $config.Finish.Restart) {
    if (Invoke-RestartCountdown $config.Finish.CountdownSeconds) { return }
}

Write-Host ''
Read-Host ' Press Enter to close' | Out-Null

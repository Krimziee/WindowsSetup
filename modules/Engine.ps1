<#
    The setup steps in order. Used by both the console version and the
    window (which runs it in the background, see Run-Engine.ps1).
#>

function Get-Presets {
    # Every .psd1 file in the presets folder is a choice for the user
    param([string]$Root)
    foreach ($file in Get-ChildItem (Join-Path $Root 'presets') -Filter *.psd1 | Sort-Object Name -Descending) {
        $config = Import-PowerShellDataFile $file.FullName
        [pscustomobject]@{ Key = $file.BaseName; Name = $config.Name; Description = $config.Description; Path = $file.FullName }
    }
}

function Invoke-Setup {
    <#
        Runs every enabled step of the preset. Errors inside a step are
        reported per item; anything that escapes stops the setup.
    #>
    param($Config, $System)

    $startedAt = Get-Date
    Write-Log "Preset: $($Config.Name)"

    Write-Section 'Getting ready'
    if (-not (Test-IsAdmin) -and -not $script:Setup.DryRun) {
        Write-Item 'Admin rights' 'Missing - start with "Start Setup.cmd"' 'Fail'
        throw 'Setup needs admin rights.'
    }
    $online = Test-Internet
    $wingetReady = $false
    if ($online) {
        Write-Item 'Internet' 'Connected' 'Ok'
        $wingetReady = Update-Winget
        if ($wingetReady) {
            Update-WingetCatalog
            # Start downloading apps now, so they download while bloatware and settings run
            Start-AppDownloads $Config
        }
    } else {
        Write-Item 'Internet' 'Not connected - online steps will be skipped' 'Warn'
    }
    New-SafetyRestorePoint
    Save-CleanupState

    if ($Config.Bloatware.Enabled) { Invoke-BloatwareRemoval $Config.Bloatware }
    if ($Config.Settings.Enabled)  { Invoke-WindowsSettings $Config.Settings $System }

    if ($Config.Redistributables.Enabled -or $Config.Apps.Enabled) {
        if ($wingetReady) {
            if ($Config.Redistributables.Enabled) { Invoke-Redistributables $Config.Redistributables }
            if ($Config.Apps.Enabled)             { Invoke-AppInstall $Config.Apps }
        } else {
            Write-Section 'Apps'
            Write-Item 'Redistributables and apps' 'Skipped: needs internet and winget' 'Warn'
        }
    }

    if ($Config.Drivers.Enabled) { Invoke-DriverSetup $Config.Drivers $System }

    # Windows Update is left to Windows itself; it handles updates best on its own schedule
    if ($Config.Cleanup.Enabled) { Invoke-Cleanup $Config.Cleanup $System $startedAt }

    $summary = Get-SetupSummary $startedAt
    Write-Log ("Summary: {0} ok, {1} skipped, {2} warnings, {3} failed" -f $summary.Ok, $summary.Skip, $summary.Warn, $summary.Fail)
    $summary
}

function Get-SetupSummary {
    param([datetime]$StartedAt)
    $results = $script:Setup.Results
    $count = { param($s) @($results | Where-Object Status -eq $s).Count }
    [pscustomobject]@{
        Minutes  = [math]::Round(((Get-Date) - $StartedAt).TotalMinutes, 1)
        Ok       = & $count 'Ok'
        Skip     = & $count 'Skip'
        Warn     = & $count 'Warn'
        Fail     = & $count 'Fail'
        Problems = @($results | Where-Object { $_.Status -in 'Warn', 'Fail' })
    }
}

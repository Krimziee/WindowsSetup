<#
    Runs the setup engine in the background for the window (UI).
    The window starts this script in a separate runspace (a second
    PowerShell inside the same program) and reads progress from UiQueue.
#>
param(
    [string]$Root,
    [hashtable]$Config,
    $System,
    [string]$LogFile,
    [bool]$DryRun,
    $UiQueue
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

. (Join-Path $Root 'modules\Load-Modules.ps1')
$script:Setup.LogFile = $LogFile
$script:Setup.DryRun  = $DryRun
$script:Setup.UiQueue = $UiQueue

try {
    $summary = Invoke-Setup $Config $System
    $UiQueue.Enqueue([pscustomobject]@{ Type = 'Done'; Summary = $summary })
}
catch {
    Write-Log "FATAL: $($_.Exception.Message)"
    Write-Log $_.ScriptStackTrace
    $UiQueue.Enqueue([pscustomobject]@{ Type = 'Error'; Value = $_.Exception.Message })
}
finally {
    # Never leave background downloads running
    Stop-DownloadQueue
}

<#
    Common helpers used by every module: logging, on-screen output,
    result tracking, dry-run support and registry writes.
#>

$script:SetupVersion = '0.9'   # shown in the window and the log

$script:Setup = @{
    IsAdmin = $null
    DryRun  = $false
    LogFile = $null
    Results = New-Object System.Collections.Generic.List[object]
    # When the window (UI) is used, progress goes into this queue instead of
    # the console; the window reads it a few times per second.
    UiQueue = $null
}

# ------------------------------------------------------------------
#  Logging and output
# ------------------------------------------------------------------

function Send-UiEvent {
    param([string]$Type, [string]$Label = '', [string]$Value = '', [string]$Status = '')
    $script:Setup.UiQueue.Enqueue([pscustomobject]@{ Type = $Type; Label = $Label; Value = $Value; Status = $Status })
}

function Initialize-Log {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $script:Setup.LogFile = Join-Path $desktop ("WindowsSetup-log-{0:yyyy-MM-dd_HH-mm}.txt" -f (Get-Date))
}

function Write-Log {
    param([string]$Message)
    if (-not $script:Setup.LogFile) { return }
    try { Add-Content -Path $script:Setup.LogFile -Value ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message) } catch { }
}

function Write-Section {
    param([string]$Title)
    Write-Log "== $Title =="
    if ($script:Setup.UiQueue) { Send-UiEvent 'Section' $Title; return }
    Write-Host ''
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host (' ' + ('-' * $Title.Length)) -ForegroundColor DarkCyan
}

function Write-Item {
    <#
        Prints one line of progress. Every status except 'Info' is also
        recorded so the summary at the end can count it.
    #>
    param(
        [string]$Label,
        [string]$Value = '',
        [ValidateSet('Ok', 'Skip', 'Warn', 'Fail', 'Info')] [string]$Status = 'Info'
    )
    $Value = ($Value -replace '\s+', ' ').Trim()   # error messages often end with line breaks
    if ($script:Setup.DryRun -and $Status -eq 'Ok') { $Value = "$Value (dry run)" }
    $tag, $color = switch ($Status) {
        'Ok'   { '[ OK ]', 'Green' }
        'Skip' { '[SKIP]', 'DarkGray' }
        'Warn' { '[WARN]', 'Yellow' }
        'Fail' { '[FAIL]', 'Red' }
        'Info' { '[ -- ]', 'Gray' }
    }
    Write-Log "$tag $Label $Value"
    if ($script:Setup.UiQueue) {
        Send-UiEvent 'Item' $Label $Value $Status
    } else {
        # `r returns to the start of the line, so this overwrites a Write-Pending line
        Write-Host "`r  $tag " -ForegroundColor $color -NoNewline
        Write-Host ('{0,-42} ' -f $Label) -NoNewline
        Write-Host ('{0,-30}' -f $Value) -ForegroundColor White
    }

    if ($Status -ne 'Info') {
        $script:Setup.Results.Add([pscustomobject]@{ Label = $Label; Status = $Status; Detail = $Value })
    }

    # Progress lines are printed often during every step, which makes this a
    # handy moment to start the next background download (see Downloads.ps1)
    if ($script:Downloads) { Step-DownloadQueue }
}

function Write-Pending {
    # Shows "working on it" for a slow item; the next Write-Item replaces the line
    param([string]$Label, [string]$Value = 'working...')
    if ($script:Setup.UiQueue) { Send-UiEvent 'Pending' $Label $Value; return }
    # Must not be longer than the space Write-Item clears, or leftovers stay on screen
    if ($Value.Length -gt 30) { $Value = $Value.Substring(0, 27) + '...' }
    Write-Host "`r  [ .. ] " -ForegroundColor Cyan -NoNewline
    Write-Host ('{0,-42} ' -f $Label) -NoNewline
    Write-Host ('{0,-30}' -f $Value) -ForegroundColor Gray -NoNewline
}

# ------------------------------------------------------------------
#  Making changes
# ------------------------------------------------------------------

function Invoke-Change {
    <#
        Runs a change, or only logs it when running in dry-run mode.
        Every module makes its changes through this function.
    #>
    param(
        [string]$Description,
        [scriptblock]$Action
    )
    if ($script:Setup.DryRun) {
        Write-Log "[dry run] would $Description"
        return
    }
    Write-Log "Doing: $Description"
    & $Action
}

function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [ValidateSet('DWord', 'QWord', 'String', 'ExpandString', 'Binary', 'MultiString')] [string]$Type = 'DWord'
    )
    Invoke-Change "set $Path\$Name = $Value" {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    }
}

function Invoke-WithDefaultUserHive {
    <#
        Temporarily loads the registry of the "Default" user profile, the
        template Windows copies for every NEW user account. The script block
        receives the registry path to use (e.g. Registry::HKEY_USERS\...).
    #>
    param([scriptblock]$Action)

    $hiveFile = Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT'
    $mount    = 'HKU\WindowsSetup_Default'
    $root     = 'Registry::HKEY_USERS\WindowsSetup_Default'

    if ($script:Setup.DryRun) { & $Action $root; return }
    if (-not (Test-Path $hiveFile)) { return }

    & reg.exe load $mount $hiveFile 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not load the default user profile.' }
    try {
        & $Action $root
    }
    finally {
        # Windows can't unload the hive while PowerShell still holds a handle to it
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        for ($i = 0; $i -lt 5; $i++) {
            & reg.exe unload $mount 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { break }
            Start-Sleep -Milliseconds 500
        }
    }
}

# ------------------------------------------------------------------
#  Misc
# ------------------------------------------------------------------

function Test-IsAdmin {
    # Checked once; admin rights can't change while the script runs
    if ($null -eq $script:Setup.IsAdmin) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $script:Setup.IsAdmin = (New-Object Security.Principal.WindowsPrincipal $identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    $script:Setup.IsAdmin
}

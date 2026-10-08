<#
    Windows settings. Every setting lives in one catalog below with an Id,
    a friendly name and the code that applies it. Presets just list the
    Ids they want, so the UI can later show the same catalog as checkboxes.

    Only    = 'Win11'   setting only exists on Windows 11
              'Desktop' only applied on desktops (not laptops)
    Last    = $true     applied at the very end (after apps are installed)
#>

$script:AdvancedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$script:CdmKey      = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'

function Set-MouseAccelerationOff {
    # Applies immediately (no sign-out needed) and saves it to the registry
    if (-not ('WindowsSetup.Mouse' -as [type])) {
        Add-Type -Namespace WindowsSetup -Name Mouse -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern bool SystemParametersInfo(uint action, uint param, int[] values, uint winIni);
'@
    }
    Invoke-Change 'turn off mouse acceleration' {
        # SPI_SETMOUSE = 4, values = threshold1, threshold2, speed; 3 = save + broadcast
        if (-not [WindowsSetup.Mouse]::SystemParametersInfo(4, 0, [int[]](0, 0, 0), 3)) {
            throw 'Windows refused the mouse setting.'
        }
    }
}

function Add-DesktopApi {
    if ('WindowsSetup.Desktop' -as [type]) { return }
    Add-Type -Namespace WindowsSetup -Name Desktop -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool SystemParametersInfo(uint action, uint param, string value, uint winIni);
[DllImport("user32.dll", SetLastError = true)]
public static extern bool SetSysColors(int count, int[] elements, int[] colors);
'@
}

function Set-SolidBackground {
    # Removes the wallpaper and shows a plain color instead (applies immediately)
    param([int]$Red, [int]$Green, [int]$Blue)

    Set-RegistryValue 'HKCU:\Control Panel\Colors' 'Background' "$Red $Green $Blue" 'String'
    Set-RegistryValue 'HKCU:\Control Panel\Desktop' 'WallPaper' '' 'String'
    # 1 = "Solid color" in Settings > Personalization > Background
    Set-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers' 'BackgroundType' 1

    Invoke-Change 'apply the solid background now' {
        Add-DesktopApi
        # COLOR_DESKTOP = 1; Windows stores colors as 0x00BBGGRR
        [void][WindowsSetup.Desktop]::SetSysColors(1, [int[]]@(1), [int[]]@($Red + ($Green -shl 8) + ($Blue -shl 16)))
        # SPI_SETDESKWALLPAPER = 20, empty = no picture; 3 = save + tell other programs
        if (-not [WindowsSetup.Desktop]::SystemParametersInfo(20, 0, '', 3)) { throw 'Windows refused to remove the wallpaper.' }
    }
}

function Clear-TaskbarPins {
    <#
        Unpins everything from the taskbar. Pins are stored in the Taskband
        registry key plus a folder of shortcuts; Explorer must be closed while
        they are removed, or it writes them back.
    #>
    $taskband = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband'
    $pinned   = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
    Invoke-Change 'unpin all taskbar apps' {
        Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 2
        Remove-Item $taskband -Recurse -Force -ErrorAction SilentlyContinue
        Get-ChildItem $pinned -Filter *.lnk -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    }
}

function Set-HighPerformancePowerPlan {
    $highPerf = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    Invoke-Change 'switch to the High performance power plan' {
        $plans = powercfg /list | Out-String
        if ($plans -notmatch $highPerf) {
            # Some PCs hide the plan; adding a copy of it makes it available
            $copy = powercfg /duplicatescheme $highPerf | Out-String
            if ($copy -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') { $highPerf = $Matches[1] }
        }
        powercfg /setactive $highPerf
        if ($LASTEXITCODE -ne 0) { throw 'powercfg could not switch the plan.' }
    }
}

function Add-KeyboardLanguage {
    param([string]$Tag)
    Invoke-Change "add keyboard language $Tag" {
        $list = Get-WinUserLanguageList
        if ($list.LanguageTag -notcontains $Tag) {
            # Added at the end, so the display language stays the same.
            # Windows still prints a generic "display language changed" warning; hide it.
            $list.Add($Tag)
            Set-WinUserLanguageList $list -Force -WarningAction SilentlyContinue
        }
    }
}

$script:SettingsCatalog = @(
    # ---- Look -------------------------------------------------------
    @{ Id = 'DarkMode'; Name = 'Dark mode'; Category = 'Look'; Apply = {
        $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        Set-RegistryValue $key 'AppsUseLightTheme' 0
        Set-RegistryValue $key 'SystemUsesLightTheme' 0 } }

    @{ Id = 'DarkSolidBackground'; Name = 'Plain dark background'; Category = 'Look'; Apply = {
        Set-SolidBackground 0 0 0 } }

    @{ Id = 'ThisPcOnDesktop'; Name = '"This PC" icon on desktop'; Category = 'Look'; Apply = {
        Set-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel' '{20D04FE0-3AEA-1069-A2D8-08002B30309D}' 0 } }

    @{ Id = 'ClassicContextMenu'; Name = 'Full right-click menu'; Category = 'Look'; Only = 'Win11'; Apply = {
        Set-RegistryValue 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' '(default)' '' 'String' } }

    # ---- Taskbar and Start -----------------------------------------
    @{ Id = 'TaskbarLeft'; Name = 'Taskbar icons on the left'; Category = 'Taskbar'; Only = 'Win11'; Apply = {
        Set-RegistryValue $script:AdvancedKey 'TaskbarAl' 0 } }

    @{ Id = 'HideWidgets'; Name = 'Hide Widgets'; Category = 'Taskbar'; Only = 'Win11'; Apply = {
        # Windows blocks scripts from the normal switch, so the policy is used instead
        Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0 } }

    @{ Id = 'UnpinTaskbarApps'; Name = 'Unpin all taskbar apps'; Category = 'Taskbar'; Last = $true; Apply = {
        Clear-TaskbarPins } }

    @{ Id = 'HideTaskView'; Name = 'Hide Task View button'; Category = 'Taskbar'; Apply = {
        Set-RegistryValue $script:AdvancedKey 'ShowTaskViewButton' 0 } }

    @{ Id = 'SearchIconOnly'; Name = 'Search as icon only'; Category = 'Taskbar'; Apply = {
        Set-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 1 } }

    @{ Id = 'NeverCombine'; Name = 'Never combine taskbar buttons'; Category = 'Taskbar'; Apply = {
        Set-RegistryValue $script:AdvancedKey 'TaskbarGlomLevel' 2 } }

    @{ Id = 'StartNoRecentFiles'; Name = 'No recent files in Start'; Category = 'Taskbar'; Apply = {
        Set-RegistryValue $script:AdvancedKey 'Start_TrackDocs' 0 } }

    @{ Id = 'StartNoRecommendations'; Name = 'No tips or app promos in Start'; Category = 'Taskbar'; Only = 'Win11'; Apply = {
        Set-RegistryValue $script:AdvancedKey 'Start_IrisRecommendations' 0 } }

    # ---- File Explorer ---------------------------------------------
    @{ Id = 'ShowFileExtensions'; Name = 'Show file extensions'; Category = 'Explorer'; Apply = {
        Set-RegistryValue $script:AdvancedKey 'HideFileExt' 0 } }

    @{ Id = 'ShowHiddenFiles'; Name = 'Show hidden files'; Category = 'Explorer'; Apply = {
        Set-RegistryValue $script:AdvancedKey 'Hidden' 1 } }

    @{ Id = 'QuickAccessPrivacy'; Name = 'No recent/frequent files in Quick Access'; Category = 'Explorer'; Apply = {
        $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
        Set-RegistryValue $key 'ShowRecent' 0
        Set-RegistryValue $key 'ShowFrequent' 0
        Set-RegistryValue $key 'ShowCloudFilesInQuickAccess' 0 } }

    @{ Id = 'LongPaths'; Name = 'Allow long file paths'; Category = 'Explorer'; Apply = {
        Set-RegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1 } }

    # ---- Mouse and gaming ------------------------------------------
    @{ Id = 'MouseAccelerationOff'; Name = 'Mouse acceleration off'; Category = 'Gaming'; Apply = {
        Set-MouseAccelerationOff } }

    @{ Id = 'WindowedGameOptimizationsOff'; Name = 'Windowed game optimizations and VRR off'; Category = 'Gaming'; Apply = {
        Set-RegistryValue 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings' 'SwapEffectUpgradeEnable=0;VRROptimizeEnable=0;' 'String' } }

    @{ Id = 'ControllerGameBarOff'; Name = 'Controller button doesn''t open Game Bar'; Category = 'Gaming'; Apply = {
        Set-RegistryValue 'HKCU:\Software\Microsoft\GameBar' 'UseNexusForGameBarEnabled' 0 } }

    # ---- Privacy and notifications ---------------------------------
    @{ Id = 'AdsOff'; Name = 'Advertising ID and tailored ads off'; Category = 'Privacy'; Apply = {
        Set-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
        Set-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
        Set-RegistryValue 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1 } }

    @{ Id = 'DiagnosticsRequiredOnly'; Name = 'Send only required diagnostic data'; Category = 'Privacy'; Apply = {
        Set-RegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 1 } }

    @{ Id = 'SettingsSuggestionsOff'; Name = 'No suggestions in Settings'; Category = 'Privacy'; Apply = {
        foreach ($n in '338393', '353694', '353696') { Set-RegistryValue $script:CdmKey "SubscribedContent-$($n)Enabled" 0 } } }

    @{ Id = 'NotificationsOff'; Name = 'All notifications off'; Category = 'Privacy'; Apply = {
        Set-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' 0 } }

    # ---- System ----------------------------------------------------
    @{ Id = 'HighPerformance'; Name = 'High performance power plan'; Category = 'System'; Only = 'Desktop'; Apply = {
        Set-HighPerformancePowerPlan } }

    @{ Id = 'ScreenOff10NeverSleep'; Name = 'Screen off after 10 min, never sleep'; Category = 'System'; Only = 'Desktop'; Apply = {
        Invoke-Change 'set screen and sleep timeouts' {
            powercfg /change monitor-timeout-ac 10
            powercfg /change standby-timeout-ac 0 } } }

    @{ Id = 'FastStartupOff'; Name = 'Fast Startup off'; Category = 'System'; Apply = {
        Set-RegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0 } }

    @{ Id = 'StorageSenseOn'; Name = 'Storage Sense on'; Category = 'System'; Apply = {
        Set-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01' 1 } }

    @{ Id = 'NoDriversFromWindowsUpdate'; Name = 'No drivers from Windows Update'; Category = 'System'; Only = 'Desktop'; Apply = {
        Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'ExcludeWUDriversInQualityUpdate' 1 } }

    # ---- Region ----------------------------------------------------
    @{ Id = 'TimeZoneJordan'; Name = 'Time zone: Jordan'; Category = 'Region'; Apply = {
        Invoke-Change 'set time zone to Jordan' { Set-TimeZone -Id 'Jordan Standard Time' } } }

    @{ Id = 'KeyboardArabic'; Name = 'Add Arabic (Jordan) keyboard'; Category = 'Region'; Apply = {
        Add-KeyboardLanguage 'ar-JO' } }
)

# What each setting does, in plain words. Shown when hovering over a setting in the window.
$script:SettingInfo = @{
    DarkMode                     = 'Switches Windows and apps to dark colors. Easier on the eyes, especially at night.'
    DarkSolidBackground          = 'Replaces the desktop wallpaper with plain black.'
    ThisPcOnDesktop              = 'Puts a "This PC" icon on the desktop for quick access to your drives.'
    ClassicContextMenu           = 'Right-clicking shows the full menu straight away, instead of the short Windows 11 menu with "Show more options".'
    TaskbarLeft                  = 'Moves the Start button and taskbar icons to the left, like Windows 10.'
    HideWidgets                  = 'Turns off the Widgets panel (news, weather, stocks) on the taskbar.'
    UnpinTaskbarApps             = 'Removes every pinned app from the taskbar. Done at the very end, so installers can''t pin themselves again.'
    HideTaskView                 = 'Hides the Task View button. Win + Tab still opens Task View.'
    SearchIconOnly               = 'Shows search as a small icon instead of a wide search box, leaving more room on the taskbar.'
    NeverCombine                 = 'Every open window gets its own taskbar button with its title, instead of being stacked under one icon.'
    StartNoRecentFiles           = 'Start stops listing the files you opened recently.'
    StartNoRecommendations       = 'Removes tips, app suggestions and promotions from the Start menu.'
    ShowFileExtensions           = 'Shows file endings like .exe or .pdf, which makes fake files such as "photo.jpg.exe" easy to spot.'
    ShowHiddenFiles              = 'Shows hidden files and folders in File Explorer. Protected Windows system files stay hidden.'
    QuickAccessPrivacy           = 'File Explorer''s Home page stops listing recently and frequently used files.'
    LongPaths                    = 'Lets programs use file paths longer than 260 characters, avoiding rare "path too long" errors.'
    MouseAccelerationOff         = 'Turns off "Enhance pointer precision": the same hand movement always moves the cursor the same distance. Preferred for gaming.'
    WindowedGameOptimizationsOff = 'Turns off Windows'' own tweaks for games in windowed mode and its variable refresh rate override, which make some games stutter.'
    ControllerGameBarOff         = 'Pressing the Xbox button on a controller no longer opens Game Bar.'
    AdsOff                       = 'Turns off the advertising ID, ads based on your diagnostic data, and websites reading your language list.'
    DiagnosticsRequiredOnly      = 'Windows sends Microsoft only the basic diagnostic data it requires, not the optional extra data.'
    SettingsSuggestionsOff       = 'Removes suggested content and promotions from the Settings app.'
    NotificationsOff             = 'Turns off all pop-up notifications from Windows and apps, including message alerts from apps like Discord.'
    HighPerformance              = 'Keeps the processor ready for full speed instead of saving power. Uses a bit more electricity. Desktops only.'
    ScreenOff10NeverSleep        = 'The screen turns off after 10 minutes without use, but the PC never goes to sleep, so downloads keep running. Desktops only.'
    FastStartupOff               = 'Shut down really shuts down. Fast Startup can cause driver and dual-boot problems; turning it off makes startup a few seconds slower.'
    StorageSenseOn               = 'Windows automatically deletes temporary files and old Recycle Bin items when disk space runs low.'
    NoDriversFromWindowsUpdate   = 'Windows Update stops installing drivers; graphics and chipset drivers come from AMD, NVIDIA or Intel instead.'
    TimeZoneJordan               = 'Sets the clock to Jordan time (UTC+3).'
    KeyboardArabic               = 'Adds an Arabic keyboard next to English. Switch between them with Win + Space.'
}

function Restart-Explorer {
    # Explorer only re-reads most taskbar/Explorer settings when it restarts
    Invoke-Change 'restart File Explorer' {
        Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 3
        # Windows normally restarts it by itself; start it if it didn't
        if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    }
}

$script:LastSettings = @()   # settings held back until the end (see Invoke-LastSettings)

function Invoke-Setting {
    param($Setting, $System)
    if ($Setting.Only -eq 'Win11' -and -not $System.Windows.IsWin11) {
        Write-Item $Setting.Name 'Not available on Windows 10' 'Skip'
        return
    }
    if ($Setting.Only -eq 'Desktop' -and $System.IsLaptop) {
        Write-Item $Setting.Name 'Skipped on laptops' 'Skip'
        return
    }
    try {
        & $Setting.Apply
        Write-Item $Setting.Name 'Done' 'Ok'
    } catch {
        Write-Log "Setting $($Setting.Id) failed: $($_.Exception.Message)"
        Write-Item $Setting.Name "Couldn't apply: $($_.Exception.Message)" 'Fail'
    }
}

function Invoke-WindowsSettings {
    param($Config, $System)

    Write-Section 'Windows settings'

    foreach ($id in $Config.Apply) {
        $setting = $script:SettingsCatalog | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if (-not $setting) {
            Write-Log "Unknown setting id in preset: $id"
            continue
        }
        if ($setting.Last) {
            $script:LastSettings += $setting
            continue
        }
        Invoke-Setting $setting $System
    }

    Restart-Explorer
    Write-Item 'File Explorer' 'Restarted to apply changes' 'Info'
}

function Invoke-LastSettings {
    # Settings that must come after the app installs (installers can undo them)
    param($System)
    foreach ($setting in $script:LastSettings) { Invoke-Setting $setting $System }
}

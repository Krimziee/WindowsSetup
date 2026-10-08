# Power user preset: the full app list and advanced tweaks.
@{
    Name        = 'Power user'
    Description = 'Full app list and advanced tweaks'

    Bloatware = @{
        Enabled        = $true
        RemoveOneDrive = $true
        Apps = @(
            @{ Id = 'Clipchamp.Clipchamp';                    Name = 'Clipchamp' }
            @{ Id = 'Microsoft.BingNews';                     Name = 'News' }
            @{ Id = 'Microsoft.BingWeather';                  Name = 'Weather' }
            @{ Id = 'Microsoft.BingSearch';                   Name = 'Bing Search' }
            @{ Id = 'Microsoft.MicrosoftSolitaireCollection'; Name = 'Solitaire' }
            @{ Id = 'Microsoft.Todos';                        Name = 'To Do' }
            @{ Id = 'Microsoft.MicrosoftStickyNotes';         Name = 'Sticky Notes' }
            @{ Id = 'Microsoft.MicrosoftOfficeHub';           Name = 'Microsoft 365 hub' }
            @{ Id = 'Microsoft.Copilot';                      Name = 'Copilot' }
            @{ Id = 'MicrosoftCorporationII.MicrosoftFamily'; Name = 'Family' }
            @{ Id = 'Microsoft.WindowsCamera';                Name = 'Camera' }
            @{ Id = 'Microsoft.WindowsMaps';                  Name = 'Maps' }
            @{ Id = 'Microsoft.GamingApp';                    Name = 'Xbox app' }
            @{ Id = 'Microsoft.ZuneMusic';                    Name = 'Media Player' }
            @{ Id = 'Microsoft.ZuneVideo';                    Name = 'Movies & TV' }
            @{ Id = 'MSTeams';                                Name = 'Teams (personal)' }
            @{ Id = 'Microsoft.PowerAutomateDesktop';         Name = 'Power Automate' }
            @{ Id = 'Microsoft.Windows.DevHome';              Name = 'Dev Home' }
            @{ Id = 'MicrosoftWindows.Client.WebExperience';  Name = 'Widgets' }
            @{ Id = 'MicrosoftCorporationII.QuickAssist';     Name = 'Quick Assist' }
            @{ Id = 'Microsoft.WindowsAlarms';                Name = 'Alarms & Clock' }
        )
        # Classic programs, removed with their own uninstaller
        ClassicApps = @(
            @{ DisplayName = 'Copilot'; Name = 'Copilot (desktop app)'; SilentArgs = '--force-uninstall' }
        )
    }

    Redistributables = @{
        Enabled  = $true
        Packages = @(
            @{ Id = 'Microsoft.VCRedist.2005.x86';        Name = 'Visual C++ 2005 (x86)' }
            @{ Id = 'Microsoft.VCRedist.2005.x64';        Name = 'Visual C++ 2005 (x64)' }
            @{ Id = 'Microsoft.VCRedist.2008.x86';        Name = 'Visual C++ 2008 (x86)' }
            @{ Id = 'Microsoft.VCRedist.2008.x64';        Name = 'Visual C++ 2008 (x64)' }
            @{ Id = 'Microsoft.VCRedist.2010.x86';        Name = 'Visual C++ 2010 (x86)' }
            @{ Id = 'Microsoft.VCRedist.2010.x64';        Name = 'Visual C++ 2010 (x64)' }
            @{ Id = 'Microsoft.VCRedist.2012.x86';        Name = 'Visual C++ 2012 (x86)' }
            @{ Id = 'Microsoft.VCRedist.2012.x64';        Name = 'Visual C++ 2012 (x64)' }
            @{ Id = 'Microsoft.VCRedist.2013.x86';        Name = 'Visual C++ 2013 (x86)' }
            @{ Id = 'Microsoft.VCRedist.2013.x64';        Name = 'Visual C++ 2013 (x64)' }
            @{ Id = 'Microsoft.VCRedist.2015+.x86';       Name = 'Visual C++ 2015-2022 (x86)' }
            @{ Id = 'Microsoft.VCRedist.2015+.x64';       Name = 'Visual C++ 2015-2022 (x64)' }
            @{ Id = 'Microsoft.DirectX';                  Name = 'DirectX (June 2010)' }
            @{ Id = 'Microsoft.DotNet.DesktopRuntime.6';  Name = '.NET Desktop Runtime 6' }
            @{ Id = 'Microsoft.DotNet.DesktopRuntime.8';  Name = '.NET Desktop Runtime 8' }
            @{ Id = 'Microsoft.DotNet.DesktopRuntime.9';  Name = '.NET Desktop Runtime 9' }
            @{ Id = 'Microsoft.DotNet.DesktopRuntime.10'; Name = '.NET Desktop Runtime 10' }
            @{ Id = 'Microsoft.XNARedist';                Name = 'XNA Framework 4.0' }
            @{ Id = 'CreativeTechnology.OpenAL';          Name = 'OpenAL' }
        )
    }

    # AsUser   = installer refuses to run with admin rights
    # Location = installer refuses to run silently without a target folder
    Apps = @{
        Enabled = $true
        Groups = @(
            @{ Name = 'Game launchers'; Packages = @(
                @{ Id = 'Valve.Steam';                  Name = 'Steam' }
                @{ Id = 'EpicGames.EpicGamesLauncher';  Name = 'Epic Games Launcher' }
                @{ Id = 'Blizzard.BattleNet';           Name = 'Battle.net'; Location = 'C:\Program Files (x86)\Battle.net' }
                @{ Id = 'ElectronicArts.EADesktop';     Name = 'EA app' }
                @{ Id = 'Ubisoft.Connect';              Name = 'Ubisoft Connect' }
                @{ Id = 'RiotGames.Valorant.EU';        Name = 'Riot Client (Valorant)' }
            ) }
            @{ Name = 'Everyday'; Packages = @(
                @{ Id = 'Google.Chrome';                Name = 'Google Chrome' }
                @{ Id = 'Discord.Discord';              Name = 'Discord' }
                @{ Id = 'Spotify.Spotify';              Name = 'Spotify'; AsUser = $true }
                @{ Id = 'Stremio.Stremio.Beta';         Name = 'Stremio 5' }
            ) }
            @{ Name = 'Utilities'; Packages = @(
                @{ Id = '7zip.7zip';                    Name = '7-Zip' }
                @{ Id = 'Notepad++.Notepad++';          Name = 'Notepad++' }
                @{ Id = 'Adobe.Acrobat.Reader.64-bit';  Name = 'Adobe Acrobat Reader' }
                @{ Id = 'VideoLAN.VLC';                 Name = 'VLC' }
                @{ Id = 'CodecGuide.K-LiteCodecPack.Mega'; Name = 'K-Lite Codec Pack Mega' }
                @{ Id = 'HandBrake.HandBrake';          Name = 'HandBrake' }
                @{ Id = 'IrfanSkiljan.IrfanView';       Name = 'IrfanView' }
                @{ Id = 'Proton.ProtonPass';            Name = 'Proton Pass' }
                @{ Id = 'Proton.ProtonAuthenticator';   Name = 'Proton Authenticator' }
                @{ Id = 'Google.GoogleDrive';           Name = 'Google Drive' }
                @{ Id = 'qBittorrent.qBittorrent';      Name = 'qBittorrent' }
                @{ Id = 'Mozilla.Thunderbird';          Name = 'Thunderbird' }
            ) }
            @{ Name = 'Hardware tools'; Packages = @(
                @{ Id = 'Guru3D.Afterburner';           Name = 'MSI Afterburner' }
                @{ Id = 'Guru3D.RTSS';                  Name = 'RivaTuner Statistics Server' }
                @{ Id = 'SteelSeries.GG';               Name = 'SteelSeries GG' }
            ) }
        )
    }

    # Ids come from the catalog in modules\Settings.ps1
    Settings = @{
        Enabled = $true
        Apply = @(
            'DarkMode', 'DarkSolidBackground', 'ThisPcOnDesktop', 'ClassicContextMenu'
            'TaskbarLeft', 'UnpinTaskbarApps', 'HideWidgets', 'HideTaskView', 'SearchIconOnly', 'NeverCombine'
            'StartNoRecentFiles', 'StartNoRecommendations'
            'ShowHiddenFiles', 'QuickAccessPrivacy', 'LongPaths'
            'MouseAccelerationOff', 'WindowedGameOptimizationsOff', 'ControllerGameBarOff'
            'AdsOff', 'DiagnosticsRequiredOnly', 'SettingsSuggestionsOff', 'NotificationsOff'
            'HighPerformance', 'ScreenOff10NeverSleep', 'FastStartupOff', 'StorageSenseOn', 'NoDriversFromWindowsUpdate'
            'TimeZoneJordan', 'KeyboardArabic'
        )
    }

    Drivers       = @{ Enabled = $true }
    Cleanup = @{
        Enabled                   = $true
        RemoveNewDesktopShortcuts = $false   # keep the shortcuts installers put on the desktop
        DisableNewStartupApps     = $true    # apps installed now won't start with Windows
        KeepStartupApps           = @('GoogleDriveFS', 'SteelSeriesGG')   # ...except these (startup entry names)
        RemoveSetupCopy           = $true    # delete C:\WindowsSetup after the restart
    }

    Finish = @{
        Restart          = $true
        CountdownSeconds = 60
    }
}
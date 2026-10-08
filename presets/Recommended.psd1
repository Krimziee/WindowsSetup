# Recommended preset: safe defaults for anyone (friends, family).
# Keeps apps some people rely on, like OneDrive, Camera and Alarms.
@{
    Name        = 'Recommended'
    Description = 'Safe defaults for anyone'

    Bloatware = @{
        Enabled        = $true
        RemoveOneDrive = $false
        Apps = @(
            @{ Id = 'Clipchamp.Clipchamp';                    Name = 'Clipchamp' }
            @{ Id = 'Microsoft.BingNews';                     Name = 'News' }
            @{ Id = 'Microsoft.BingWeather';                  Name = 'Weather' }
            @{ Id = 'Microsoft.BingSearch';                   Name = 'Bing Search' }
            @{ Id = 'Microsoft.MicrosoftSolitaireCollection'; Name = 'Solitaire' }
            @{ Id = 'Microsoft.MicrosoftOfficeHub';           Name = 'Microsoft 365 hub' }
            @{ Id = 'Microsoft.Copilot';                      Name = 'Copilot' }
            @{ Id = 'MicrosoftCorporationII.MicrosoftFamily'; Name = 'Family' }
            @{ Id = 'Microsoft.PowerAutomateDesktop';         Name = 'Power Automate' }
            @{ Id = 'Microsoft.Windows.DevHome';              Name = 'Dev Home' }
            @{ Id = 'MicrosoftCorporationII.QuickAssist';     Name = 'Quick Assist' }
        )
        # Classic programs, removed with their own uninstaller
        ClassicApps = @(
            @{ DisplayName = 'Copilot'; Name = 'Copilot (desktop app)'; SilentArgs = '--force-uninstall' }
        )
    }

    # Games need these, so friends get the full set too
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

    # A small set of essentials; more can be picked in Custom mode.
    # Group names match the Power user preset, so in Custom mode each app sits next to similar ones.
    Apps = @{
        Enabled = $true
        Groups = @(
            @{ Name = 'Game launchers'; Packages = @(
                @{ Id = 'Valve.Steam';           Name = 'Steam' }
            ) }
            @{ Name = 'Everyday'; Packages = @(
                @{ Id = 'Google.Chrome';         Name = 'Google Chrome' }
                @{ Id = 'Discord.Discord';       Name = 'Discord' }
            ) }
            @{ Name = 'Utilities'; Packages = @(
                @{ Id = '7zip.7zip';             Name = '7-Zip' }
                @{ Id = 'VideoLAN.VLC';          Name = 'VLC' }
                @{ Id = 'Adobe.Acrobat.Reader.64-bit'; Name = 'Adobe Acrobat Reader' }
            ) }
        )
    }

    # Only settings almost everyone is happy with. Ids come from modules\Settings.ps1
    Settings = @{
        Enabled = $true
        Apply = @(
            'ShowFileExtensions'
            'StartNoRecommendations'
            'AdsOff', 'SettingsSuggestionsOff'
            'LongPaths'
        )
    }

    Drivers       = @{ Enabled = $true }
    Cleanup = @{
        Enabled                   = $true
        RemoveNewDesktopShortcuts = $false   # friends may like their desktop icons
        DisableNewStartupApps     = $false   # friends decide for themselves
        RemoveSetupCopy           = $true
    }

    Finish = @{
        Restart          = $true
        CountdownSeconds = 60
    }
}
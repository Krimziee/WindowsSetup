# Approximate download size (MB) of each package, used for the estimate in
# the window. Measured from the publishers' servers on 2026-10-08; starter
# installers that download more while installing (Battle.net, EA app,
# Bitwarden) use the full amount. Unknown packages count as 50 MB.
@{
    # Game redistributables
    'Microsoft.VCRedist.2005.x86'        = 2.6
    'Microsoft.VCRedist.2005.x64'        = 3
    'Microsoft.VCRedist.2008.x86'        = 4.3
    'Microsoft.VCRedist.2008.x64'        = 5
    'Microsoft.VCRedist.2010.x86'        = 8.6
    'Microsoft.VCRedist.2010.x64'        = 9.8
    'Microsoft.VCRedist.2012.x86'        = 6.3
    'Microsoft.VCRedist.2012.x64'        = 6.9
    'Microsoft.VCRedist.2013.x86'        = 6.2
    'Microsoft.VCRedist.2013.x64'        = 6.9
    'Microsoft.VCRedist.2015+.x86'       = 6.6
    'Microsoft.VCRedist.2015+.x64'       = 17.9
    'Microsoft.DirectX'                  = 55.7
    'Microsoft.DotNet.DesktopRuntime.6'  = 54.7
    'Microsoft.DotNet.DesktopRuntime.8'  = 56
    'Microsoft.DotNet.DesktopRuntime.9'  = 58
    'Microsoft.DotNet.DesktopRuntime.10' = 57.3
    'Microsoft.XNARedist'                = 6.7
    'CreativeTechnology.OpenAL'          = 0.6

    # Game launchers
    'Valve.Steam'                        = 2.3      # updates itself (~400 MB) the first time it opens
    'EpicGames.EpicGamesLauncher'        = 252
    'Blizzard.BattleNet'                 = 200      # small starter that downloads the rest
    'ElectronicArts.EADesktop'           = 300      # small starter that downloads the rest
    'Ubisoft.Connect'                    = 252
    'RiotGames.Valorant.EU'              = 72       # Riot Client only; games download later
    'GOG.Galaxy'                         = 326.4

    # Everyday
    'Google.Chrome'                      = 161.8
    'Discord.Discord'                    = 139.3
    'Spotify.Spotify'                    = 149.6
    'Stremio.Stremio.Beta'               = 69.8
    'Mozilla.Firefox'                    = 89.1
    'Brave.Brave'                        = 159.5
    'Telegram.TelegramDesktop'           = 53.1
    '9NKSQGP7F2NH'                       = 60       # WhatsApp (Microsoft Store)

    # Utilities
    '7zip.7zip'                          = 1.9
    'Notepad++.Notepad++'                = 7.5
    'Adobe.Acrobat.Reader.64-bit'        = 824.9
    'VideoLAN.VLC'                       = 60.5
    'CodecGuide.K-LiteCodecPack.Mega'    = 65.4
    'HandBrake.HandBrake'                = 24.2
    'IrfanSkiljan.IrfanView'             = 4.3
    'Proton.ProtonPass'                  = 151.3
    'Proton.ProtonAuthenticator'         = 16.6
    'Google.GoogleDrive'                 = 279.2
    'qBittorrent.qBittorrent'            = 35
    'Mozilla.Thunderbird'                = 80
    'Bitwarden.Bitwarden'                = 100      # small starter that downloads the rest
    'Dropbox.Dropbox'                    = 289.7
    'AnyDesk.AnyDesk'                    = 8.2
    'Microsoft.VisualStudioCode'         = 233.1
    'RARLab.WinRAR'                      = 3.6

    # Hardware tools
    'Guru3D.Afterburner'                 = 40.5
    'Guru3D.RTSS'                        = 17.2
    'SteelSeries.GG'                     = 413.3
    'CrystalDewWorld.CrystalDiskInfo'    = 6
}

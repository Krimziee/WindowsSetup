# Extra apps offered in Custom mode only, always unticked by default.
# Presets never include these. Group names match the preset groups, so
# each app shows up next to similar apps (a missing group is added).
# Source = 'msstore' installs from the Microsoft Store instead of winget's catalog.
@{
    Groups = @(
        @{ Name = 'Game launchers'; Packages = @(
            @{ Id = 'GOG.Galaxy';               Name = 'GOG Galaxy' }
        ) }
        @{ Name = 'Everyday'; Packages = @(
            @{ Id = 'Mozilla.Firefox';          Name = 'Firefox' }
            @{ Id = 'Brave.Brave';              Name = 'Brave' }
            @{ Id = 'Telegram.TelegramDesktop'; Name = 'Telegram' }
            @{ Id = '9NKSQGP7F2NH';             Name = 'WhatsApp'; Source = 'msstore' }
        ) }
        @{ Name = 'Utilities'; Packages = @(
            @{ Id = 'Bitwarden.Bitwarden';        Name = 'Bitwarden' }
            @{ Id = 'Dropbox.Dropbox';            Name = 'Dropbox' }
            @{ Id = 'AnyDesk.AnyDesk';            Name = 'AnyDesk' }
            @{ Id = 'Microsoft.VisualStudioCode'; Name = 'VS Code' }
            @{ Id = 'RARLab.WinRAR';              Name = 'WinRAR' }
        ) }
        @{ Name = 'Hardware tools'; Packages = @(
            @{ Id = 'CrystalDewWorld.CrystalDiskInfo'; Name = 'CrystalDiskInfo' }
        ) }
    )
}

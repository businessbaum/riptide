//@ pragma IconTheme Adwaita
//@ pragma UseQApplication

// riptide's desktop shell in the style of macOS.
// Every visible part is its own file; Quickshell reloads on every save.
//
//   Config.qml         settings.json + theme.json (live)
//   Apps.qml           running apps, launching, activating (via Hyprland)
//   Wallpaper.qml      desktop background
//   MenuBar.qml        menu bar with Apple menu, app name, status, clock
//   Dock.qml           dock on every screen
//   Spotlight.qml      ⌘Space app search
//   Notifications.qml  notification server + banners
//   Osd.qml            volume display

import QtQuick
import Quickshell

ShellRoot {
    Variants {
        model: Quickshell.screens

        Scope {
            id: perScreen
            required property var modelData

            Wallpaper {
                screen: perScreen.modelData
            }
            MenuBar {
                screen: perScreen.modelData
            }
            Dock {
                screen: perScreen.modelData
            }
        }
    }

    Spotlight {}
    Notifications {}
    Osd {}
    ConfirmDialog {}
}

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
//   Launchpad.qml      all apps as a grid (dock)
//   Clipboard.qml      SUPER+V clipboard history (cliphist)
//   Switcher.qml       ⌘Tab / ⌥Tab panel (logic in Hyprland)
//   ControlCenter.qml  + NotificationCenter.qml: panels from the menu bar
//   Notifications.qml  notification server + banners
//   Osd.qml            volume display
//   PolkitDialog.qml   password dialog for administrator rights

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
    Launchpad {}
    Clipboard {}
    Switcher {}
    Notifications {}
    Osd {}
    ConfirmDialog {}
    PolkitDialog {}
}

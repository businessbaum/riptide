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
//   BannerWindow.qml   everything at the top right (Banners.qml: notifications, system messages)
//   BluetoothBanners   "AirPods · Verbunden" when a Bluetooth device connects
//   Osd.qml            volume display
//   PolkitDialog.qml   password dialog for administrator rights
//   ShareDialog.qml    what an app may see when sharing the screen
//   AboutWindow.qml    "Über diesen Computer" (Apple menu)
//   Riptide.qml        the connection to the session's system services (riptide-session)
//   Privacy.qml        app permissions: asks, remembers (docs/os-plan.md)

import QtQuick
import Quickshell

ShellRoot {
    // Services that must run from the start (singletons start on first use otherwise).
    // This is the main shell: it asks the questions apps have (Riptide role "shell").
    readonly property var services: [Privacy]
    Component.onCompleted: Riptide.role = "shell"

    // No "Config reloaded" toast on every save; a failed reload becomes a notification
    Connections {
        target: Quickshell
        function onReloadCompleted() {
            Quickshell.inhibitReloadPopup();
        }
        function onReloadFailed(error) {
            Quickshell.inhibitReloadPopup();
            Notify.error("Fehler in der Shell-Konfiguration", error);
        }
    }

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
    BannerWindow {}
    BluetoothBanners {}
    Osd {}
    ConfirmDialog {}
    ShareDialog {}
    PolkitDialog {}
    AboutWindow {}
}

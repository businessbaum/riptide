//@ pragma IconTheme Adwaita
//@ pragma UseQApplication

// riptide's desktop shell in the style of macOS.
// Every visible part is its own file; Quickshell reloads on every save.
//
//   Config.qml         settings.json + theme.json (live)
//   Apps.qml           running apps, launching, activating (via Hyprland)
//   Wallpaper.qml      desktop background (WallpaperImage.qml: the picture itself)
//   LockScreen.qml     the lock screen, at boot the login (Lock.qml, LoginScreen.qml: the window)
//   MenuBar.qml        menu bar with Apple menu, app name, status, clock
//   Dock.qml           dock on every screen
//   Spotlight.qml      ⌘Space app search
//   Launchpad.qml      all apps as a grid (dock)
//   Clipboard.qml      SUPER+V clipboard history (cliphist)
//   EmojiPicker.qml    ⌃⌘Space emoji & symbols
//   Switcher.qml       ⌘Tab / ⌥Tab panel (logic in Hyprland)
//   MissionControl.qml ⌃↑ Mission Control, ⌃↓ App Exposé; HotCorners.qml: active corners
//   ControlCenter.qml  + NotificationCenter.qml: panels from the menu bar
//   BannerWindow.qml   everything at the top right (Banners.qml: notifications, system messages)
//   BluetoothBanners   "AirPods · Verbunden" when a Bluetooth device connects (UsbBanners: USB)
//   Osd.qml            volume display
//   PolkitDialog.qml   password dialog for administrator rights
//   ShareDialog.qml    what an app may see when sharing the screen
//   AboutWindow.qml    "Über diesen Computer" (Apple menu); AppInfoWindow: "Über „App“" (app menu)
//   ForceQuitWindow    "Sofort beenden" (⌥⌘⎋); HyprDialogs.qml: Hyprland's questions in our look
//   Riptide.qml        the connection to the session's system services (riptide-session)
//   Privacy.qml        app permissions: asks, remembers (docs/os-plan.md)

import QtQuick
import Quickshell

ShellRoot {
    // Services that must run from the start (singletons start on first use otherwise).
    // This is the main shell: it asks the questions apps have (Riptide role "shell").
    readonly property var services: [Privacy, HyprDialogs, Updates, NightShift, Brightness, Session, Microphone, Drives, Tools, AutoAppearance, SystemSounds]
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

    // the wallpaper, always (the lock screen shows the same one)
    Variants {
        model: Quickshell.screens
        Wallpaper {
            required property var modelData
            screen: modelData
        }
    }

    // the lock screen – at boot also the login (Lock.qml)
    LockScreen {}

    // Everything that can be touched: when the session starts locked (the login at boot)
    // only once Hyprland has confirmed the lock – created under it, never before it
    LazyLoader {
        active: Lock.desktopAllowed

        Scope {
            Variants {
                model: Quickshell.screens

                Scope {
                    id: perScreen
                    required property var modelData

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
            EmojiPicker {}
            Switcher {}
            MissionControl {}
            HotCorners {}
            BannerWindow {}
            BluetoothBanners {}
            UsbBanners {}
            Osd {}
            ConfirmDialog {}
            ShareDialog {}
            PolkitDialog {}
            AboutWindow {}
            AppInfoWindow {}
            ForceQuitWindow {}
        }
    }
}

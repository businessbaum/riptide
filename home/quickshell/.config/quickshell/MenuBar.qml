import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Wayland

// The menu bar at the top of every screen:
//   left:  Apple menu, name of the active app
//   right: apps in the background (tray), volume, control centre,
//          date and time (opens the notification centre)
PanelWindow {
    id: bar

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property string activeAppId: Hyprland.activeToplevel?.wayland?.appId ?? ""

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "menubar"
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: 30
    exclusiveZone: implicitHeight
    color: "transparent"

    PwObjectTracker {
        objects: [bar.sink]
    }

    // Open the menus from outside, e.g.  qs ipc call menubar-DP-1 controlCenter
    IpcHandler {
        target: "menubar-" + (bar.screen?.name ?? "")
        function appleMenu(): void {
            appleMenu.toggle();
        }
        function controlCenter(): void {
            controlCenter.toggle();
        }
        function notificationCenter(): void {
            notificationCenter.toggle();
        }
    }

    // "Computer wachhalten" (control centre): no lock, screens stay on
    IdleInhibitor {
        window: bar
        enabled: Session.keepAwake
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Rectangle {
        anchors.fill: parent
        color: Config.menubar
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 8
        height: parent.height

        BarButton {
            id: logo
            text: "" // Apple logo (Symbols Nerd Font)
            symbol: true
            active: appleMenu.visible
            onClicked: appleMenu.toggle()
        }

        BarButton {
            text: bar.activeAppId !== "" ? Apps.name(Apps.keyForAppId(bar.activeAppId)) : "Finder"
            bold: true
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 8
        height: parent.height

        // Apps running in the background (Discord, Claude, …)
        Repeater {
            model: SystemTray.items
            TrayItem {
                required property var modelData
                item: modelData
                barWindow: bar
            }
        }

        BarButton {
            visible: Session.keepAwake
            text: "\uf0f4" // cup: the computer is kept awake
            symbol: true
            onClicked: Session.keepAwake = false
        }

        BarButton {
            readonly property var audio: bar.sink?.audio
            visible: audio !== undefined && audio !== null
            symbol: true
            // speaker muted / low / high
            text: !audio ? "" : audio.muted ? "" : audio.volume < 0.4 ? "" : ""
            onClicked: audio.muted = !audio.muted
            onScrolled: delta => audio.volume = Math.max(0, Math.min(1, audio.volume + (delta > 0 ? 0.05 : -0.05)))
        }

        BarButton {
            id: controlButton
            text: "\uf1de" // control centre (sliders)
            symbol: true
            active: controlCenter.visible
            onClicked: controlCenter.toggle()
        }

        BarButton {
            id: clockButton
            text: clock.date.toLocaleString(Qt.locale("de_DE"), "ddd d. MMM  HH:mm")
            active: notificationCenter.visible
            onClicked: notificationCenter.toggle()
        }
    }

    ControlCenter {
        id: controlCenter
        anchorItem: controlButton
        keepOpenFor: [bar]
    }

    NotificationCenter {
        id: notificationCenter
        anchorItem: clockButton
        keepOpenFor: [bar]
    }

    MenuPopup {
        id: appleMenu
        anchorItem: logo
        keepOpenFor: [bar]
        items: [
            { text: "Über diesen Computer", action: () => Quickshell.execDetached([Quickshell.shellPath("scripts/about.sh")]) },
            { separator: true },
            { text: "Systemeinstellungen …", action: () => Quickshell.execDetached(["uwsm", "app", "--", "org.riptide.SystemSettings.desktop"]) },
            { separator: true },
            { text: "Neustart …", action: () => Confirm.ask("Möchtest du den Computer jetzt neu starten?", "", "Neustart", () => Session.end("reboot")) },
            { text: "Ausschalten …", action: () => Confirm.ask("Möchtest du den Computer jetzt ausschalten?", "", "Ausschalten", () => Session.end("poweroff")) },
            { separator: true },
            { text: "Bildschirm sperren", action: () => Quickshell.execDetached(["sh", "-c", "pidof hyprlock || hyprlock"]) },
            { text: "Abmelden …", action: () => Confirm.ask("Möchtest du dich wirklich abmelden?", "Alle Programme werden beendet.", "Abmelden", () => Session.end("logout")) }
        ]
    }
}

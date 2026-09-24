import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Wayland

// The menu bar at the top of every screen:
//   left:  Apple menu, name of the active app
//   right: volume, date and time
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
            text: clock.date.toLocaleString(Qt.locale("de_DE"), "ddd d. MMM  HH:mm")
        }
    }

    MenuPopup {
        id: appleMenu
        anchorItem: logo
        keepOpenFor: [bar]
        items: [
            { text: "Über diesen Computer", action: () => Quickshell.execDetached([Quickshell.shellPath("scripts/about.sh")]) },
            { separator: true },
            { text: "Systemeinstellungen …", enabled: false },
            { separator: true },
            { text: "Neustart …", action: () => Confirm.ask("Möchtest du den Computer jetzt neu starten?", "", "Neustart", () => Quickshell.execDetached(["systemctl", "reboot"])) },
            { text: "Ausschalten …", action: () => Confirm.ask("Möchtest du den Computer jetzt ausschalten?", "", "Ausschalten", () => Quickshell.execDetached(["systemctl", "poweroff"])) },
            { separator: true },
            { text: "Bildschirm sperren", action: () => Quickshell.execDetached(["sh", "-c", "pidof hyprlock || hyprlock"]) },
            { text: "Abmelden …", action: () => Confirm.ask("Möchtest du dich wirklich abmelden?", "Alle Programme werden beendet.", "Abmelden", () => Quickshell.execDetached(["uwsm", "stop"])) }
        ]
    }
}

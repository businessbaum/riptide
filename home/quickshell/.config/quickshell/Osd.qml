import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Wayland

// Volume display: appears for a moment whenever the volume or mute state of the
// default output changes (keys, menu bar, any app), on the active screen – and the
// brightness when its keys change it (Brightness.qml).
Scope {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink?.audio
    property bool shown: false
    property string kind: "volume" // or "brightness"

    PwObjectTracker {
        objects: [root.sink]
    }

    // Like on a Mac: when Bluetooth headphones connect, the sound switches to them.
    // (Only new Bluetooth outputs; switching back happens by itself when they disconnect.)
    property var knownSinks: ({})
    property bool sinksReady: false
    readonly property var bluetoothSinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream
        && (n.properties?.["device.api"] === "bluez5" || (n.name ?? "").startsWith("bluez_output")))
    onBluetoothSinksChanged: {
        const known = Object.assign({}, knownSinks);
        for (const n of bluetoothSinks) {
            if (!known[n.id] && sinksReady)
                Pipewire.preferredDefaultAudioSink = n; // BluetoothBanners shows the connection
            known[n.id] = true;
        }
        knownSinks = known;
    }
    Timer {
        // outputs present at start are not "new"
        running: true
        interval: 3000
        onTriggered: root.sinksReady = true
    }

    // Ignore the values the sink reports while it connects
    property bool armed: false
    Timer {
        running: root.audio !== null && root.audio !== undefined
        interval: 1500
        onTriggered: root.armed = true
    }

    Connections {
        target: root.audio ?? null
        ignoreUnknownSignals: true
        function onVolumeChanged() {
            root.flash();
        }
        function onMutedChanged() {
            root.flash();
        }
    }
    Connections {
        target: Brightness
        function onStepped() {
            root.kind = "brightness";
            root.shown = true;
            hideTimer.restart();
        }
    }

    function flash() {
        if (!armed)
            return;
        kind = "volume";
        shown = true;
        hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: root.shown = false
    }

    PanelWindow {
        visible: root.shown
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "osd"
        exclusionMode: ExclusionMode.Ignore
        anchors.bottom: true
        margins.bottom: 140
        implicitWidth: 260
        implicitHeight: 48
        color: "transparent"
        mask: Region {}

        Glass {
            anchors.fill: parent
            radius: height / 2

            Text {
                id: speaker
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                text: root.kind === "brightness" ? "\u{f00df}" : root.audio?.muted ? "" : ""
                font.family: Config.fontSymbols
                font.pixelSize: 18
                color: Config.text
            }

            Rectangle {
                anchors.left: speaker.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                height: 6
                radius: 3
                color: Config.tile

                Rectangle {
                    width: parent.width * (root.kind === "brightness" ? Brightness.average / 100
                        : Math.min(1, root.audio?.muted ? 0 : (root.audio?.volume ?? 0)))
                    height: parent.height
                    radius: 3
                    color: Config.text
                    Behavior on width {
                        NumberAnimation { duration: 90 }
                    }
                }
            }
        }
    }
}

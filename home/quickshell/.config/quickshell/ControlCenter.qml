import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

// Control centre (icon next to the clock), laid out like macOS:
//   network, Bluetooth | appearance, do not disturb
//   sound slider, now playing
MenuBarPopup {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    // the adapter that is not blocked (see settings/BluetoothPage.qml)
    readonly property var adapter: Bluetooth.adapters.values.find(a => a.state !== BluetoothAdapterState.Blocked) ?? Bluetooth.defaultAdapter
    readonly property var wired: Networking.devices.values.find(d => d.type === DeviceType.Wired && d.connected) ?? null
    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wifiNetwork: wifi?.networks.values.find(n => n.connected) ?? null
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    readonly property var btConnected: adapter?.devices.values.filter(d => d.connected) ?? []

    implicitWidth: 330
    implicitHeight: content.implicitHeight + 24

    PwObjectTracker {
        objects: [root.sink]
    }

    Column {
        id: content
        x: 12
        y: 12
        width: parent.width - 24
        spacing: 10

        Row {
            width: parent.width
            spacing: 10

            // Network + Bluetooth
            Rectangle {
                width: (parent.width - 10) / 2
                height: 112
                radius: Config.radiusTile
                color: Config.tile
                border.color: Config.border

                Column {
                    x: 10
                    y: 10
                    width: parent.width - 20
                    spacing: 4

                    ControlTile {
                        width: parent.width
                        icon: root.wired ? String.fromCodePoint(0xf0200) : "\uf1eb" // ethernet / wifi
                        title: root.wired ? "Netzwerk" : "WLAN"
                        on: root.wired !== null || (Networking.wifiEnabled && root.wifiNetwork !== null)
                        status: root.wired ? "Ethernet verbunden"
                              : !Networking.wifiEnabled ? "Aus"
                              : root.wifiNetwork?.name ?? "Nicht verbunden"
                        available: root.wired !== null || root.wifi !== null
                        onToggled: if (!root.wired) Networking.wifiEnabled = !Networking.wifiEnabled
                    }
                    ControlTile {
                        width: parent.width
                        icon: "" // bluetooth
                        title: "Bluetooth"
                        available: root.adapter !== null
                        on: root.adapter?.enabled ?? false
                        status: !root.adapter ? "Nicht verfügbar"
                              : !root.adapter.enabled ? "Aus"
                              : root.btConnected.length > 0 ? root.btConnected.map(d => d.name).join(", ") : "Ein"
                        onToggled: root.adapter.enabled = !root.adapter.enabled
                    }
                }
            }

            // Appearance + do not disturb
            Column {
                width: (parent.width - 10) / 2
                spacing: 10

                Rectangle {
                    width: parent.width
                    height: 51
                    radius: Config.radiusTile
                    color: Config.tile
                    border.color: Config.border

                    ControlTile {
                        x: 10
                        width: parent.width - 20
                        anchors.verticalCenter: parent.verticalCenter
                        icon: Config.dark ? "" : "" // moon / sun
                        title: "Darstellung"
                        status: Config.dark ? "Dunkel" : "Hell"
                        on: Config.dark
                        onToggled: Config.updateSettings(s => {
                            s.appearance = s.appearance ?? {};
                            s.appearance.mode = Config.dark ? "light" : "dark";
                        })
                    }
                }
                Rectangle {
                    width: parent.width
                    height: 51
                    radius: Config.radiusTile
                    color: Config.tile
                    border.color: Config.border

                    ControlTile {
                        x: 10
                        width: parent.width - 20
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "" // moon
                        title: "Nicht stören"
                        status: NotificationStore.doNotDisturb ? "Ein" : "Aus"
                        on: NotificationStore.doNotDisturb
                        onToggled: NotificationStore.setDoNotDisturb(!NotificationStore.doNotDisturb)
                    }
                }
            }
        }

        // Keep awake
        Rectangle {
            width: parent.width
            height: 51
            radius: Config.radiusTile
            color: Config.tile
            border.color: Config.border

            ControlTile {
                x: 10
                width: parent.width - 20
                anchors.verticalCenter: parent.verticalCenter
                icon: "\uf0f4" // cup
                title: "Computer wachhalten"
                status: Session.keepAwake ? "Keine Sperre, Bildschirme bleiben an" : "Aus"
                on: Session.keepAwake
                onToggled: Session.keepAwake = !Session.keepAwake
            }
        }

        // Sound
        Rectangle {
            width: parent.width
            height: 64
            radius: Config.radiusTile
            color: Config.tile
            border.color: Config.border
            visible: root.sink?.audio !== undefined && root.sink?.audio !== null

            Column {
                x: 12
                y: 10
                width: parent.width - 24
                spacing: 8

                Text {
                    text: "Ton"
                    font.family: Config.fontSans
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: Config.text
                }
                Slider {
                    width: parent.width
                    icon: root.sink?.audio?.muted ? "" : ""
                    value: root.sink?.audio?.muted ? 0 : (root.sink?.audio?.volume ?? 0)
                    onMoved: v => {
                        root.sink.audio.muted = false;
                        root.sink.audio.volume = v;
                    }
                }
            }
        }

        // Now playing
        Rectangle {
            width: parent.width
            height: 64
            radius: Config.radiusTile
            color: Config.tile
            border.color: Config.border
            visible: root.player !== null

            Image {
                id: art
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                height: 44
                source: root.player?.trackArtUrl ?? ""
                fillMode: Image.PreserveAspectCrop
                visible: status === Image.Ready
            }
            Column {
                anchors.left: art.visible ? art.right : parent.left
                anchors.leftMargin: 12
                anchors.right: controls.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    text: root.player?.trackTitle || root.player?.identity || ""
                    elide: Text.ElideRight
                    font.family: Config.fontSans
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: Config.text
                }
                Text {
                    width: parent.width
                    text: root.player?.trackArtist ?? ""
                    elide: Text.ElideRight
                    font.family: Config.fontSans
                    font.pixelSize: 11
                    color: Config.textSecondary
                }
            }
            Row {
                id: controls
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14

                Repeater {
                    model: [
                        { glyph: "", run: () => root.player.previous(), ok: root.player?.canGoPrevious },
                        { glyph: root.player?.isPlaying ? "" : "", run: () => root.player.togglePlaying(), ok: root.player?.canTogglePlaying },
                        { glyph: "", run: () => root.player.next(), ok: root.player?.canGoNext }
                    ]
                    Text {
                        required property var modelData
                        text: modelData.glyph
                        opacity: modelData.ok ? 1 : 0.35
                        font.family: Config.fontSymbols
                        font.pixelSize: 15
                        color: Config.text
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            enabled: parent.modelData.ok === true
                            onClicked: parent.modelData.run()
                        }
                    }
                }
            }
        }
    }
}

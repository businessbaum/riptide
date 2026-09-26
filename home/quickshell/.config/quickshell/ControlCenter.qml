import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

// Control centre (icon next to the clock), laid out like macOS:
//   network, Bluetooth | appearance, do not disturb
//   keep awake, energy mode, screens (brightness, Night Shift), sound slider, now playing
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
                        status: NotificationStore.dndReason
                        on: NotificationStore.doNotDisturb
                        onToggled: NotificationStore.setDoNotDisturb(!NotificationStore.doNotDisturb)
                    }
                }
            }
        }

        // Keep awake | energy mode (power-profiles-daemon; a click unfolds its three modes)
        Item {
            id: energyBox
            property bool unfolded: false
            readonly property var modes: [
                { profile: PowerProfile.PowerSaver, name: "Energiesparen", glyph: "\u{f032a}" },   // leaf
                { profile: PowerProfile.Balanced, name: "Automatisch", glyph: "\u{f029a}" },      // gauge
                { profile: PowerProfile.Performance, name: "Hohe Leistung", glyph: "\u{f0241}" }  // fire
            ]
            readonly property var current: modes.find(m => m.profile === PowerProfiles.profile) ?? modes[1]
            width: parent.width
            height: 51 + (unfolded ? modesRow.height + 10 : 0)

            Row {
                width: parent.width
                spacing: 10

                Rectangle {
                    width: (parent.width - 10) / 2
                    height: 51
                    radius: Config.radiusTile
                    color: Config.tile
                    border.color: Config.border
                    ControlTile {
                        x: 10
                        width: parent.width - 20
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "\uf0f4" // cup
                        title: "Wachhalten"
                        status: Session.keepAwake ? "Keine Sperre" : "Aus"
                        on: Session.keepAwake
                        onToggled: Session.keepAwake = !Session.keepAwake
                    }
                }
                Rectangle {
                    width: (parent.width - 10) / 2
                    height: 51
                    radius: Config.radiusTile
                    color: Config.tile
                    border.color: Config.border
                    ControlTile {
                        x: 10
                        width: parent.width - 20
                        anchors.verticalCenter: parent.verticalCenter
                        icon: energyBox.current.glyph
                        title: "Energiemodus"
                        status: energyBox.current.name
                        on: PowerProfiles.profile !== PowerProfile.Balanced
                        onToggled: energyBox.unfolded = !energyBox.unfolded
                    }
                }
            }
            Row {
                id: modesRow
                visible: energyBox.unfolded
                y: 61
                width: parent.width
                spacing: 6
                Repeater {
                    model: energyBox.modes
                    Rectangle {
                        required property var modelData
                        width: (parent.width - 12) / 3
                        height: 32
                        radius: 9
                        color: PowerProfiles.profile === modelData.profile ? Config.accent
                            : modeMouse.containsMouse ? Config.hover : Config.tile
                        border.color: Config.border
                        Text {
                            anchors.centerIn: parent
                            text: modelData.name
                            font.family: Config.fontSans
                            font.pixelSize: 11
                            color: PowerProfiles.profile === modelData.profile ? "white" : Config.text
                        }
                        MouseArea {
                            id: modeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                PowerProfiles.profile = modelData.profile;
                                energyBox.unfolded = false;
                            }
                        }
                    }
                }
            }
        }

        // Screens: one slider for all; unfolded, one per screen (DDC, Brightness.qml) –
        // and Night Shift
        Rectangle {
            id: screensBox
            property bool unfolded: false
            width: parent.width
            height: screensColumn.implicitHeight + 20
            radius: Config.radiusTile
            color: Config.tile
            border.color: Config.border
            Behavior on height {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            // "BenQ EX2710Q", with left/right when two look alike
            function label(d) {
                const same = Brightness.displays.filter(o => o.model === d.model).length > 1;
                if (!same)
                    return d.model;
                const x = s => Quickshell.screens.find(q => q.name === s)?.x ?? 0;
                const others = Brightness.displays.filter(o => o.model === d.model && o.name !== d.name);
                return d.model + (others.every(o => x(o.name) > x(d.name)) ? " – links"
                    : others.every(o => x(o.name) < x(d.name)) ? " – rechts" : " – " + d.name);
            }

            Column {
                id: screensColumn
                x: 12
                y: 10
                width: parent.width - 24
                spacing: 8

                Item {
                    width: parent.width
                    height: screensTitle.implicitHeight
                    Text {
                        id: screensTitle
                        text: Brightness.displays.length > 1 ? "Bildschirme" : "Bildschirm"
                        font.family: Config.fontSans
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Config.text
                    }
                    // unfold: one slider per screen
                    Text {
                        visible: Brightness.displays.length > 1
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: screensBox.unfolded ? "\u{f0143}" : "\u{f0140}" // chevron up / down
                        font.family: Config.fontSymbols
                        font.pixelSize: 16
                        color: unfold.containsMouse ? Config.text : Config.textSecondary
                        MouseArea {
                            id: unfold
                            anchors.fill: parent
                            anchors.margins: -8
                            hoverEnabled: true
                            onClicked: screensBox.unfolded = !screensBox.unfolded
                        }
                    }
                }
                Slider {
                    visible: Brightness.available && !screensBox.unfolded
                    width: parent.width
                    icon: "\u{f00df}" // sun
                    from: 0
                    to: 100
                    value: Brightness.average
                    onMoved: v => Brightness.setAll(v)
                }
                Repeater {
                    model: screensBox.unfolded ? Brightness.displays : []
                    Column {
                        required property var modelData
                        width: screensColumn.width
                        spacing: 4
                        Text {
                            text: screensBox.label(modelData)
                            font.family: Config.fontSans
                            font.pixelSize: 11
                            color: Config.textSecondary
                        }
                        Slider {
                            width: parent.width
                            icon: "\u{f00df}"
                            from: 0
                            to: 100
                            value: modelData.value
                            onMoved: v => Brightness.set(modelData.name, v)
                        }
                    }
                }
                Text {
                    visible: !Brightness.available
                    text: "Die Helligkeit lässt sich an diesen Bildschirmen nicht einstellen."
                    width: parent.width
                    wrapMode: Text.Wrap
                    font.family: Config.fontSans
                    font.pixelSize: 11
                    color: Config.textSecondary
                }
                ControlTile {
                    width: parent.width
                    icon: "\u{f0594}" // moon and stars
                    title: "Night Shift"
                    status: NightShift.active
                        ? (NightShift.override?.on ? "An bis " + Qt.formatTime(new Date(NightShift.override.until), "H:mm") + " Uhr"
                            : "An bis " + Math.floor(NightShift.to) + " Uhr")
                        : NightShift.schedule ? "Ab " + Math.floor(NightShift.from) + " Uhr" : "Aus"
                    on: NightShift.active
                    onToggled: NightShift.toggle()
                }
            }
        }

        // Sound
        Rectangle {
            width: parent.width
            height: 66
            radius: Config.radiusTile
            color: Config.tile
            border.color: Config.border
            visible: root.sink?.audio !== undefined && root.sink?.audio !== null

            Column {
                x: 12
                y: 10
                width: parent.width - 24
                spacing: 8

                Item {
                    width: parent.width
                    height: soundTitle.implicitHeight
                    Text {
                        id: soundTitle
                        text: "Ton"
                        font.family: Config.fontSans
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Config.text
                    }
                    // the microphone for all apps (Microphone.qml)
                    Rectangle {
                        visible: Microphone.available
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: micLabel.implicitWidth + 22
                        height: 20
                        radius: 10
                        color: Microphone.muted ? "#ff453a" : micMouse.containsMouse ? Config.hover : "transparent"
                        border.color: Microphone.muted ? "transparent" : Config.border
                        Text {
                            id: micLabel
                            anchors.centerIn: parent
                            text: (Microphone.muted ? "\u{f036d}" : "\u{f036c}") + "  " + (Microphone.muted ? "Mikrofon aus" : "Mikrofon")
                            font.family: Config.fontSans
                            font.pixelSize: 11
                            color: Microphone.muted ? "white" : Config.textSecondary
                        }
                        MouseArea {
                            id: micMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: Microphone.toggle()
                        }
                    }
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

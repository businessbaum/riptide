import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

// Control centre (icon next to the clock), laid out like macOS:
//   Wi-Fi, Bluetooth (their networks / known devices unfold below) | appearance, do not disturb
//   keep awake, energy mode, screens (brightness, Night Shift), sound slider, tools, now playing
MenuBarPopup {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var adapter: BtDevices.adapter
    readonly property var wired: Networking.devices.values.find(d => d.type === DeviceType.Wired && d.connected) ?? null
    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wifiNetwork: wifi?.networks.values.find(n => n.connected) ?? null
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    readonly property var btConnected: BtDevices.known.filter(d => d.connected)

    // the list unfolded below the tiles: "wifi", "bluetooth" or none – one at a time
    property string unfolded: ""
    function unfold(what) {
        unfolded = unfolded === what ? "" : what;
    }
    onVisibleChanged: if (!visible) unfolded = ""
    // Wi-Fi searches only while its networks are shown
    readonly property bool showingWifi: unfolded === "wifi"
    onShowingWifiChanged: Wifi.watch(showingWifi)

    function openSettings(page) {
        close();
        Quickshell.execDetached([Quickshell.shellPath("scripts/system-settings.sh"), page]);
    }

    implicitWidth: 330
    panelHeight: content.implicitHeight + 24

    // open with the Wi-Fi networks or the Bluetooth devices unfolded (menu bar IPC "wifi",
    // "bluetooth")
    function showList(what) {
        if (!visible)
            open();
        unfolded = what === "wifi" && root.wifi === null ? "" : what;
    }

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

                    // Wi-Fi: the circle switches it, the rest shows the networks; without a
                    // Wi-Fi card only the cable
                    ControlTile {
                        width: parent.width
                        icon: root.wifi ? "\uf1eb" : String.fromCodePoint(0xf0200) // wifi / ethernet
                        title: root.wifi ? "WLAN" : "Netzwerk"
                        on: root.wifi ? Networking.wifiEnabled : root.wired !== null
                        status: root.wifiNetwork?.name
                            ?? (root.wired ? "Ethernet" : root.wifi && !Networking.wifiEnabled ? "Aus" : "Nicht verbunden")
                        available: root.wired !== null || root.wifi !== null
                        unfolds: root.wifi !== null
                        unfolded: root.unfolded === "wifi"
                        onToggled: if (root.wifi) Networking.wifiEnabled = !Networking.wifiEnabled
                        onUnfold: root.unfold("wifi")
                    }
                    ControlTile {
                        width: parent.width
                        icon: "" // bluetooth
                        title: "Bluetooth"
                        available: root.adapter !== null
                        on: root.adapter?.enabled ?? false
                        status: !root.adapter ? "Nicht verfügbar"
                              : !root.adapter.enabled ? "Aus"
                              : root.btConnected.length > 0 ? root.btConnected.map(d => BtDevices.nameOf(d) || d.name).join(", ") : "Ein"
                        unfolds: root.adapter !== null
                        unfolded: root.unfolded === "bluetooth"
                        onToggled: root.adapter.enabled = !root.adapter.enabled
                        onUnfold: root.unfold("bluetooth")
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

        // Wi-Fi networks, unfolded from the tile above: a click joins one (a new protected one
        // asks for its password in the system dialog, Wifi.qml)
        ControlList {
            visible: root.unfolded === "wifi"
            width: parent.width
            title: "WLAN"
            switchedOn: Networking.wifiEnabled
            onSwitched: on => Networking.wifiEnabled = on
            emptyText: !Networking.wifiEnabled ? "WLAN ist aus."
                : Wifi.networks.length > 0 ? ""
                : Wifi.searchedLong ? "Keine Netzwerke gefunden. Ist die WLAN-Antenne am Computer angeschlossen?"
                : "Suche nach Netzwerken …"
            settingsText: "WLAN-Einstellungen …"
            onOpenSettings: root.openSettings("network")
            Repeater {
                model: Networking.wifiEnabled ? Wifi.networks.slice(0, 8) : []
                ControlListRow {
                    required property var modelData
                    glyph: Wifi.glyph(modelData)
                    active: modelData.connected
                    hoverable: !modelData.connected
                    title: modelData.name
                    status: modelData.stateChanging ? "Verbinde …" : modelData.connected ? "\uf00c" : ""
                    statusIsGlyph: !modelData.stateChanging
                    onClicked: {
                        const n = modelData;
                        // the password dialog comes up in the middle of the screen
                        if (!n.connected && !n.known && !Wifi.isOpen(n))
                            root.close();
                        Wifi.join(n);
                    }
                }
            }
        }

        // Bluetooth: the known devices – connect one, or disconnect a connected one (BtDevices.qml)
        ControlList {
            visible: root.unfolded === "bluetooth"
            width: parent.width
            title: "Bluetooth"
            switchedOn: root.adapter?.enabled ?? false
            onSwitched: on => root.adapter.enabled = on
            emptyText: !(root.adapter?.enabled ?? false) ? "Bluetooth ist aus."
                : BtDevices.known.length === 0 ? "Noch keine Geräte gekoppelt – das geht in den Bluetooth-Einstellungen." : ""
            settingsText: "Bluetooth-Einstellungen …"
            onOpenSettings: root.openSettings("bluetooth")
            Repeater {
                model: (root.adapter?.enabled ?? false) ? BtDevices.known : []
                ControlListRow {
                    required property var modelData
                    glyph: BtDevices.glyph(modelData)
                    active: modelData.connected
                    hoverable: false
                    title: BtDevices.nameOf(modelData) || "Unbekanntes Gerät"
                    detail: !modelData.connected ? ""
                        : modelData.batteryAvailable ? `Verbunden · Batterie ${Math.round(modelData.battery * 100)} %` : "Verbunden"
                    button: BtDevices.busy(modelData) ? "…" : modelData.connected ? "Trennen" : "Verbinden"
                    onButtonClicked: BtDevices.toggle(modelData)
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
            clip: true
            Behavior on height {
                NumberAnimation { duration: Config.reduceMotion ? 0 : 220; easing.type: Easing.OutCubic }
            }

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
            clip: true
            Behavior on height {
                NumberAnimation { duration: Config.reduceMotion ? 0 : 220; easing.type: Easing.OutCubic }
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
                // (by count: a list as model would rebuild the sliders on every value while dragging)
                Repeater {
                    model: screensBox.unfolded ? Brightness.displays.length : 0
                    Column {
                        required property int index
                        readonly property var modelData: Brightness.displays[index] ?? ({})
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
                    // (switched on by hand before the schedule starts: the schedule then keeps it on)
                    status: NightShift.active
                        ? (NightShift.override?.on && !NightShift.schedule
                            ? "An bis " + Qt.formatTime(new Date(NightShift.override.until), "H:mm") + " Uhr"
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

        // Tools: screenshot, colour, emoji (the panel closes first, so they see the screen)
        Row {
            width: parent.width
            spacing: 10
            Repeater {
                model: [
                    { glyph: "\u{f0104}", name: "Bildschirmfoto", run: () => Tools.screenshot("area") },
                    { glyph: "\u{f020a}", name: "Farbpipette", run: () => Tools.pickColour() },
                    { glyph: "\u{f0785}", name: "Emoji", run: () => Quickshell.execDetached(["qs", "ipc", "call", "emoji", "toggle"]) }
                ]
                Rectangle {
                    required property var modelData
                    width: (parent.width - 20) / 3
                    height: 62
                    radius: Config.radiusTile
                    color: toolMouse.containsMouse ? Config.hover : Config.tile
                    border.color: Config.border
                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.glyph
                            font.family: Config.fontSymbols
                            font.pixelSize: 18
                            color: Config.text
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.name
                            font.family: Config.fontSans
                            font.pixelSize: 11
                            color: Config.textSecondary
                        }
                    }
                    MouseArea {
                        id: toolMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.close();
                            // a moment for the panel to go away
                            toolDelay.run = modelData.run;
                            toolDelay.restart();
                        }
                    }
                }
            }
            Timer {
                id: toolDelay
                property var run: null
                interval: 250
                onTriggered: run?.()
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

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Sound menu (speaker in the menu bar), laid out like the one of macOS:
//   overall volume · the output (headphones, screen, speakers) · every app that is
//   playing right now with its own volume. Click an app's icon to mute it.
MenuBarPopup {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var outputs: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isSink && n.isStream && n.audio)

    // Streams of one app together (Discord plays several). A sandboxed app's streams are
    // named by the service (Privacy.streams), else by what the stream says about itself
    function keyOf(node) {
        const p = node.properties ?? {};
        return Privacy.appOfStream(node) || p["application.process.binary"] || p["application.name"] || node.name;
    }
    readonly property var apps: {
        const groups = {};
        for (const s of streams) {
            const key = keyOf(s);
            (groups[key] = groups[key] ?? []).push(s);
        }
        return Object.keys(groups).sort().map(key => ({ key: key, streams: groups[key] }));
    }
    // The app behind a program name ("Discord" → discord.desktop)
    function entryOf(key) {
        return Apps.entryById(key) ?? Apps.entryById(key.toLowerCase()) ?? Apps.entryForAppId(key)
            ?? Apps.entryForAppId(key.toLowerCase()) ?? null;
    }
    function appName(group) {
        return entryOf(group.key)?.name ?? group.streams[0].properties?.["application.name"] ?? group.key;
    }

    // A short name and a symbol for an output
    function outputName(node) {
        const text = node.description || node.nickname || node.name;
        const inBrackets = text.match(/\[(.+)\]/); // "… (HDMI) [BenQ EX2710Q]" → the screen
        return inBrackets ? inBrackets[1] : text;
    }
    function outputGlyph(node) {
        const p = node.properties ?? {};
        const text = (node.description + " " + node.name).toLowerCase();
        if (p["device.api"] === "bluez5" || /headset|headphone|blackshark|airpods|kopfhörer/.test(text))
            return "\u{f02cb}"; // headphones
        if (/hdmi|displayport/.test(text))
            return "\u{f0379}"; // screen
        return "\u{f04c3}"; // speaker
    }

    PwObjectTracker {
        objects: [root.sink].concat(root.outputs).concat(root.streams)
    }

    implicitWidth: 340
    panelHeight: content.implicitHeight + 28

    component Heading: Text {
        font.family: Config.fontSans
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: Config.textSecondary
    }
    component Line: Rectangle {
        width: parent.width
        height: 1
        color: Config.border
    }

    Column {
        id: content
        x: 14
        y: 14
        width: parent.width - 28
        spacing: 12

        Text {
            text: "Ton"
            font.family: Config.fontSans
            font.pixelSize: 14
            font.weight: Font.Bold
            color: Config.text
        }
        Slider {
            width: parent.width
            icon: root.sink?.audio?.muted ? "" : ""
            percent: true
            value: root.sink?.audio?.muted ? 0 : (root.sink?.audio?.volume ?? 0)
            onMoved: v => {
                root.sink.audio.muted = false;
                root.sink.audio.volume = v;
            }
        }

        Line {}

        Heading {
            text: "Ausgabe"
        }
        Column {
            width: parent.width
            spacing: 2
            Repeater {
                model: root.outputs
                Rectangle {
                    id: output
                    required property var modelData
                    readonly property bool current: modelData === root.sink
                    width: parent.width
                    height: 38
                    radius: 8
                    color: outputMouse.containsMouse ? Config.hover : "transparent"

                    GlyphTile {
                        id: deviceIcon
                        x: 6
                        anchors.verticalCenter: parent.verticalCenter
                        size: 26
                        radius: 13
                        glyph: root.outputGlyph(output.modelData)
                        color: output.current ? Config.accent : Config.tile
                    }
                    Text {
                        anchors.left: deviceIcon.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.outputName(output.modelData)
                        elide: Text.ElideRight
                        font.family: Config.fontSans
                        font.pixelSize: 13
                        font.weight: output.current ? Font.DemiBold : Font.Normal
                        color: Config.text
                    }
                    MouseArea {
                        id: outputMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: Pipewire.preferredDefaultAudioSink = output.modelData
                    }
                }
            }
        }

        Line {}

        Heading {
            text: "Apps"
        }
        Text {
            visible: root.apps.length === 0
            text: "Gerade spielt keine App Ton ab."
            font.family: Config.fontSans
            font.pixelSize: 12
            color: Config.textSecondary
        }
        Repeater {
            model: root.apps
            Item {
                id: app
                required property var modelData
                readonly property var first: modelData.streams[0]
                readonly property bool muted: modelData.streams.every(s => s.audio?.muted)
                readonly property real volume: muted ? 0 : Math.min(1, first?.audio?.volume ?? 0)
                width: content.width
                height: 50

                AppIcon {
                    id: icon
                    anchors.verticalCenter: parent.verticalCenter
                    size: 34
                    entry: root.entryOf(app.modelData.key)
                    appId: app.modelData.key.toLowerCase()
                    opacity: app.muted ? 0.35 : 1
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const mute = !app.muted;
                            for (const s of app.modelData.streams)
                                s.audio.muted = mute;
                        }
                    }
                }
                Text {
                    anchors.left: icon.right
                    anchors.leftMargin: 10
                    anchors.right: level.left
                    anchors.rightMargin: 8
                    y: 6
                    text: root.appName(app.modelData)
                    elide: Text.ElideRight
                    font.family: Config.fontSans
                    font.pixelSize: 13
                    color: Config.text
                }
                Text {
                    id: level
                    anchors.right: parent.right
                    y: 6
                    text: app.muted ? "stumm" : Math.round(app.volume * 100) + " %"
                    font.family: Config.fontSans
                    font.pixelSize: 12
                    font.features: { "tnum": 1 }
                    color: Config.textSecondary
                }
                Slider {
                    anchors.left: icon.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    value: app.volume
                    onMoved: v => {
                        for (const s of app.modelData.streams) {
                            s.audio.muted = false;
                            s.audio.volume = v;
                        }
                    }
                }
            }
        }
    }
}

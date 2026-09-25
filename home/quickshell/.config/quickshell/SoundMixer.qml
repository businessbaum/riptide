import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Sound menu (speaker in the menu bar): overall volume, the output to use, and every app
// that is playing right now with its own volume – click an app's icon to mute it.
MenuBarPopup {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var outputs: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isSink && n.isStream && n.audio)

    // Streams of one app together (Discord plays several)
    function keyOf(node) {
        const p = node.properties ?? {};
        return p["application.process.binary"] || p["application.name"] || node.name;
    }
    readonly property var apps: {
        const groups = {};
        for (const s of streams) {
            const key = keyOf(s);
            (groups[key] = groups[key] ?? []).push(s);
        }
        return Object.keys(groups).sort().map(key => ({ key: key, streams: groups[key] }));
    }
    function appName(group) {
        const entry = Apps.entryForAppId(group.key);
        return entry?.name ?? group.streams[0].properties?.["application.name"] ?? group.key;
    }

    PwObjectTracker {
        objects: [root.sink].concat(root.outputs).concat(root.streams)
    }

    implicitWidth: 330
    implicitHeight: content.implicitHeight + 24

    Column {
        id: content
        x: 12
        y: 12
        width: parent.width - 24
        spacing: 10

        Text {
            text: "Ton"
            font.family: Config.fontSans
            font.pixelSize: 15
            font.weight: Font.Bold
            color: Config.text
        }

        Slider {
            width: parent.width
            icon: root.sink?.audio?.muted ? "\uf026" : "\uf028"
            value: root.sink?.audio?.muted ? 0 : (root.sink?.audio?.volume ?? 0)
            onMoved: v => {
                root.sink.audio.muted = false;
                root.sink.audio.volume = v;
            }
        }

        // Outputs
        Text {
            text: "Ausgabe"
            font.family: Config.fontSans
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: Config.textSecondary
        }
        Column {
            width: parent.width
            Repeater {
                model: root.outputs
                Rectangle {
                    id: output
                    required property var modelData
                    readonly property bool current: modelData === root.sink
                    width: parent.width
                    height: 30
                    radius: 6
                    color: outputMouse.containsMouse ? Config.hover : "transparent"
                    Text {
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        text: output.current ? "\uf00c" : "" // check mark
                        font.family: Config.fontSymbols
                        font.pixelSize: 12
                        color: Config.accent
                    }
                    Text {
                        x: 30
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 38
                        text: output.modelData.description || output.modelData.nickname || output.modelData.name
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

        // Apps
        Text {
            text: "Apps"
            font.family: Config.fontSans
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: Config.textSecondary
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
                width: content.width
                height: 44

                AppIcon {
                    id: icon
                    anchors.verticalCenter: parent.verticalCenter
                    size: 30
                    entry: Apps.entryForAppId(app.modelData.key)
                    appId: app.modelData.key
                    opacity: app.muted ? 0.4 : 1
                    MouseArea {
                        anchors.fill: parent
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
                    anchors.right: parent.right
                    y: 2
                    text: root.appName(app.modelData) + (app.muted ? " · stumm" : "")
                    elide: Text.ElideRight
                    font.family: Config.fontSans
                    font.pixelSize: 12
                    color: Config.text
                }
                Slider {
                    anchors.left: icon.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    trackHeight: 14
                    value: app.first?.audio?.volume ?? 0
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

import QtQuick
import Quickshell

// Menu bar: which app is using the microphone (orange), the camera (green) or sees the
// screen (purple) right now, like the dots of macOS. Only while a stream really runs
// (an active PipeWire link). Click: who it is; the settings are one click away.
Item {
    id: root

    property var barWindow

    // who uses what: MediaUse.qml
    readonly property var microphone: MediaUse.microphone
    readonly property var camera: MediaUse.camera
    readonly property var screen: MediaUse.screen

    readonly property var kinds: [
        { key: "microphone", users: microphone, glyph: "\u{f036c}", colour: "#ff9f0a", label: "Mikrofon" },
        { key: "camera", users: camera, glyph: "\u{f0100}", colour: "#30d158", label: "Kamera" },
        { key: "screen", users: screen, glyph: "\u{f0379}", colour: "#bf5af2", label: "Bildschirm" }
    ].filter(k => k.users.length > 0)

    visible: kinds.length > 0
    implicitWidth: visible ? dots.implicitWidth + 16 : 0
    implicitHeight: parent ? parent.height : 30

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 3
        anchors.bottomMargin: 3
        radius: 5
        color: panel.visible || mouse.containsMouse ? Config.hover : "transparent"
    }

    Row {
        id: dots
        anchors.centerIn: parent
        spacing: 4
        Repeater {
            model: root.kinds
            GlyphTile {
                required property var modelData
                size: 18
                radius: 9
                glyph: modelData.glyph
                color: modelData.colour
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: panel.toggle()
    }

    MenuBarPopup {
        id: panel
        anchorItem: root
        implicitWidth: 300
        panelHeight: list.implicitHeight + 24

        Column {
            id: list
            x: 12
            y: 12
            width: parent.width - 24
            spacing: 8

            Repeater {
                model: root.kinds
                Column {
                    id: kind
                    required property var modelData
                    width: list.width
                    spacing: 4
                    Text {
                        text: kind.modelData.label + " wird verwendet von"
                        font.family: Config.fontSans
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Config.textSecondary
                    }
                    Repeater {
                        model: kind.modelData.users
                        Row {
                            required property var modelData
                            spacing: 8
                            AppIcon {
                                size: 24
                                entry: Apps.entryForAppId(parent.modelData)
                                appId: parent.modelData
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Apps.entryForAppId(parent.modelData)?.name ?? parent.modelData
                                font.family: Config.fontSans
                                font.pixelSize: 13
                                color: Config.text
                            }
                        }
                    }
                }
            }
            Text {
                text: "Datenschutz & Sicherheit …"
                font.family: Config.fontSans
                font.pixelSize: 12
                color: settingsMouse.containsMouse ? Config.text : Config.accent
                MouseArea {
                    id: settingsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        panel.close();
                        Quickshell.execDetached([Quickshell.shellPath("scripts/system-settings.sh"), "privacy"]);
                    }
                }
            }
        }
    }
}

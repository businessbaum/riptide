import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Menu bar: which app is using the microphone (orange), the camera (green) or sees the
// screen (purple) right now, like the dots of macOS. Only while a stream really runs
// (an active PipeWire link). Click: who it is; the settings are one click away.
Item {
    id: root

    property var barWindow

    // (state and properties are only known for what is tracked)
    PwObjectTracker {
        objects: {
            const list = [];
            for (const g of Pipewire.linkGroups.values)
                list.push(g, g.source, g.target);
            return list.filter(o => o);
        }
    }
    readonly property var active: Pipewire.linkGroups.values.filter(g => g.state === PwLinkState.Active && g.source && g.target)
    function classOf(node) {
        return node?.properties?.["media.class"] ?? "";
    }
    function appOf(node) {
        const p = node?.properties ?? {};
        const app = Privacy.appOfStream(node); // sandboxed apps: named by the service
        return (app && Apps.name(app)) || p["application.process.binary"] || p["application.name"] || node?.name || "?";
    }
    function usersOf(test) {
        const names = [];
        for (const g of active) {
            if (test(g.source, g.target) && !names.includes(appOf(g.target)))
                names.push(appOf(g.target));
        }
        return names;
    }
    readonly property var microphone: usersOf((s, t) => classOf(t) === "Stream/Input/Audio" && classOf(s).startsWith("Audio/Source"))
    readonly property var camera: usersOf((s, t) => classOf(t) === "Stream/Input/Video" && classOf(s) === "Video/Source" && !(s.name ?? "").startsWith("xdg-desktop-portal"))
    readonly property var screen: usersOf((s, t) => classOf(t) === "Stream/Input/Video" && (s.name ?? "").startsWith("xdg-desktop-portal"))

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
        keepOpenFor: root.barWindow ? [root.barWindow] : []
        implicitWidth: 300
        implicitHeight: list.implicitHeight + 24

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

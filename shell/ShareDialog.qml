import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// Screen sharing: what an app may see (instead of Hyprland's picker). The session service
// sends "share" after the app's permission "screen" is given (riptide-share-picker asked
// it on behalf of the portal); the choice goes back as screen.picked. Screens and windows
// are shown as previews. Only a click shares – Enter never does; Esc cancels.
Scope {
    id: root

    property var queue: [] // [{ pick, app, windows }] – the first one is on screen
    readonly property var current: queue.length > 0 ? queue[0] : null
    property string tab: "screens"
    property string selection: ""

    function answer(value) {
        if (!current)
            return;
        Riptide.call("screen.picked", { pick: current.pick, selection: value || null });
        queue = queue.slice(1);
        selection = "";
        tab = "screens";
    }

    Connections {
        target: Riptide
        function onEvent(message) {
            if (message.event === "share")
                root.queue = root.queue.concat([message]);
            else if (message.event === "share-cancelled")
                root.queue = root.queue.filter(q => q.pick !== message.pick);
        }
    }

    // From a script (tests): qs ipc call share cancel – sharing always takes a click
    IpcHandler {
        target: "share"
        function cancel(): void {
            root.answer(null);
        }
    }

    // The window of a list entry among the shell's toplevels (for its preview)
    function toplevelOf(w) {
        return ToplevelManager.toplevels.values.find(t => t.appId === w.app && t.title === w.title) ?? null;
    }

    PanelWindow {
        visible: root.current !== null
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "confirm"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        implicitWidth: 760
        implicitHeight: box.implicitHeight

        onVisibleChanged: if (visible) box.forceActiveFocus()

        Glass {
            id: box
            anchors.fill: parent
            implicitHeight: content.implicitHeight + 40
            focus: true
            Keys.onEscapePressed: root.answer(null)

            Column {
                id: content
                x: 20
                y: 20
                width: parent.width - 40
                spacing: 14

                Row {
                    spacing: 14
                    AppIcon {
                        visible: (root.current?.app ?? "") !== ""
                        size: 48
                        entry: visible ? Apps.entryById(root.current.app) : null
                        appId: root.current?.app ?? ""
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Text {
                            text: (root.current?.app ?? "") !== ""
                                ? `„${Apps.name(root.current.app)}“ möchte deinen Bildschirm teilen.`
                                : "Ein Programm möchte deinen Bildschirm teilen."
                            font.family: Config.fontSans
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            color: Config.text
                        }
                        Text {
                            text: "Wähle aus, was die App sehen darf. Nur das wird übertragen, solange die Freigabe läuft."
                            font.family: Config.fontSans
                            font.pixelSize: 12
                            color: Config.textSecondary
                        }
                    }
                }

                // Bildschirme | Fenster
                Row {
                    spacing: 6
                    Repeater {
                        model: [{ key: "screens", text: "Bildschirme" }, { key: "windows", text: "Fenster" }]
                        DialogButton {
                            required property var modelData
                            width: 120
                            text: modelData.text
                            primary: root.tab === modelData.key
                            onClicked: {
                                root.tab = modelData.key;
                                root.selection = "";
                            }
                        }
                    }
                }

                Flickable {
                    width: parent.width
                    height: 330
                    clip: true
                    contentHeight: grid.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    Grid {
                        id: grid
                        width: parent.width
                        columns: 3
                        spacing: 12

                        Repeater {
                            model: root.current === null ? []
                                : root.tab === "screens" ? Quickshell.screens.map(s => ({ key: "screen:" + s.name, screen: s, title: s.model || s.name }))
                                : root.current.windows.map(w => ({ key: "window:" + w.id, window: w, title: w.title, app: w.app }))

                            Rectangle {
                                id: tile
                                required property var modelData
                                readonly property bool chosen: root.selection === modelData.key
                                width: (grid.width - 24) / 3
                                height: 150
                                radius: Config.radiusTile
                                color: chosen ? Config.hover : Config.tile
                                border.width: chosen ? 2 : 1
                                border.color: chosen ? Config.accent : Config.border

                                ScreencopyView {
                                    id: preview
                                    x: 8
                                    y: 8
                                    width: parent.width - 16
                                    height: parent.height - 40
                                    live: false
                                    captureSource: tile.modelData.screen ?? root.toplevelOf(tile.modelData.window)
                                    Component.onCompleted: captureFrame()
                                }
                                AppIcon {
                                    visible: tile.modelData.window !== undefined && !preview.hasContent
                                    anchors.centerIn: preview
                                    size: 48
                                    appId: tile.modelData.app ?? ""
                                }
                                Text {
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 9
                                    x: 10
                                    width: parent.width - 20
                                    text: tile.modelData.title
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                    font.family: Config.fontSans
                                    font.pixelSize: 12
                                    color: Config.text
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.selection = tile.modelData.key
                                    onDoubleClicked: root.answer(tile.modelData.key)
                                }
                            }
                        }
                    }
                }

                Row {
                    anchors.right: parent.right
                    spacing: 8
                    DialogButton {
                        width: 130
                        text: "Abbrechen"
                        onClicked: root.answer(null)
                    }
                    DialogButton {
                        width: 130
                        text: "Teilen"
                        primary: true
                        enabled: root.selection !== ""
                        opacity: enabled ? 1 : 0.4
                        onClicked: root.answer(root.selection)
                    }
                }
            }
        }
    }
}

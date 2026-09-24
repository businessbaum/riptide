import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland

// ⌘Space: search apps by name, description or keywords and start them.
//   ↑/↓ choose, Enter starts, Esc or a click outside closes.
// Opened by Hyprland via:  qs ipc call spotlight toggle
PanelWindow {
    id: root

    property string query: ""
    property int selected: 0

    readonly property var results: {
        const q = query.trim().toLowerCase();
        if (q === "")
            return [];
        const scored = [];
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay)
                continue;
            const name = e.name.toLowerCase();
            let score = 0;
            if (name.startsWith(q)) score = 100;
            else if (name.split(/[\s-]/).some(w => w.startsWith(q))) score = 80;
            else if (name.includes(q)) score = 60;
            else if ((e.genericName ?? "").toLowerCase().includes(q)) score = 40;
            else if ((e.keywords ?? "").toString().toLowerCase().includes(q)) score = 30;
            else if ((e.comment ?? "").toLowerCase().includes(q)) score = 10;
            if (score > 0)
                scored.push({ entry: e, score: score - name.length / 100 });
        }
        scored.sort((a, b) => b.score - a.score);
        return scored.slice(0, 8).map(s => s.entry);
    }

    function show() {
        query = "";
        selected = 0;
        visible = true;
        grab.active = true;
        input.forceActiveFocus();
    }
    function hide() {
        grab.active = false;
        visible = false;
    }
    function launch(entry) {
        hide();
        if (entry)
            Apps.launch(entry);
    }

    IpcHandler {
        target: "spotlight"
        function toggle(): void {
            root.visible ? root.hide() : root.show();
        }
    }

    HyprlandFocusGrab {
        id: grab
        windows: [root]
        onCleared: root.hide()
    }

    visible: false
    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "spotlight"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors.top: true
    margins.top: Math.round((screen?.height ?? 1440) * 0.22)
    implicitWidth: 680
    implicitHeight: panel.height
    color: "transparent"

    Rectangle {
        id: panel
        width: parent.width
        height: 56 + (root.results.length > 0 ? list.height + 9 : 0)
        radius: Config.radiusPanel
        color: Config.glassMenu
        border.color: Config.border

        // Search field
        Item {
            id: field
            width: parent.width
            height: 56

            Text {
                id: glass
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: "" // magnifying glass
                font.family: Config.fontSymbols
                font.pixelSize: 20
                color: Config.textSecondary
            }

            TextInput {
                id: input
                anchors.left: glass.right
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                font.family: Config.fontSans
                font.pixelSize: 24
                color: Config.text
                selectionColor: Config.accent
                clip: true
                onTextChanged: {
                    root.query = text;
                    root.selected = 0;
                }
                Keys.onEscapePressed: root.hide()
                Keys.onReturnPressed: root.launch(root.results[root.selected])
                Keys.onEnterPressed: root.launch(root.results[root.selected])
                Keys.onUpPressed: root.selected = Math.max(0, root.selected - 1)
                Keys.onDownPressed: root.selected = Math.min(root.results.length - 1, root.selected + 1)
                Keys.onTabPressed: root.selected = (root.selected + 1) % Math.max(1, root.results.length)

                Text {
                    visible: input.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Spotlight-Suche"
                    font: input.font
                    color: Config.textSecondary
                }
            }
        }

        Rectangle {
            visible: root.results.length > 0
            anchors.top: field.bottom
            width: parent.width
            height: 1
            color: Config.border
        }

        Column {
            id: list
            anchors.top: field.bottom
            anchors.topMargin: 5
            x: 6
            width: parent.width - 12

            Repeater {
                model: root.results

                Rectangle {
                    id: result
                    required property var modelData
                    required property int index
                    width: list.width
                    height: 40
                    radius: 8
                    color: index === root.selected ? Config.accent : "transparent"

                    IconImage {
                        id: resultIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: 28
                        source: Apps.icon(result.modelData, "")
                        asynchronous: true
                    }
                    Text {
                        anchors.left: resultIcon.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: result.modelData.name
                            + (result.modelData.genericName ? "  <font color='" + (result.index === root.selected ? "#ccffffff" : Config.textSecondary) + "'>– " + result.modelData.genericName + "</font>" : "")
                        textFormat: Text.StyledText
                        font.family: Config.fontSans
                        font.pixelSize: 15
                        color: result.index === root.selected ? "white" : Config.text
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: root.selected = result.index
                        onClicked: root.launch(result.modelData)
                    }
                }
            }
        }
    }
}

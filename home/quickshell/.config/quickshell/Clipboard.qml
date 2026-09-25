import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// Clipboard history (SUPER+V), like Windows: pick an earlier copied item, it is copied
// again and pasted into the active window. The history itself is recorded by cliphist
// (started by Hyprland, autostart.lua).
//   Type to filter, ↑/↓ choose, Enter pastes, Entf removes an item, Esc closes.
PanelWindow {
    id: root

    property var items: []        // [{ line, id, text }] newest first
    property string query: ""
    property int selected: 0

    readonly property var shown: {
        const q = query.toLowerCase();
        return q === "" ? items : items.filter(i => i.text.toLowerCase().includes(q));
    }

    function show() {
        query = "";
        input.text = "";
        selected = 0;
        list.running = true;
        visible = true;
        grab.active = true;
        input.forceActiveFocus();
    }
    function hide() {
        grab.active = false;
        visible = false;
    }

    // "[[ binary data 120 KiB png 800x600 ]]" → "Bild · 800×600 · 120 KiB"
    function describe(text) {
        const m = /^\[\[ binary data (.+?) (\w+) (\d+)x(\d+) \]\]$/.exec(text);
        return m ? `Bild · ${m[3]}×${m[4]} · ${m[1]}` : text;
    }

    function paste(item) {
        hide();
        if (!item)
            return;
        // Copy again, give the keyboard back to the window, then ⌃V into it
        Quickshell.execDetached(["sh", "-c",
            "printf '%s' \"$1\" | cliphist decode | wl-copy && sleep 0.15 && " +
            "hyprctl dispatch 'hl.dsp.send_shortcut({ mods = \"CTRL\", key = \"v\" })' >/dev/null",
            "sh", item.line]);
    }

    function remove(item) {
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | cliphist delete", "sh", item.line]);
        items = items.filter(i => i !== item);
        selected = Math.min(selected, shown.length - 1);
    }

    Process {
        id: list
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: root.items = text.split("\n").filter(l => l !== "").map(l => {
                const tab = l.indexOf("\t");
                return { line: l, id: l.slice(0, tab), text: root.describe(l.slice(tab + 1)) };
            })
        }
    }

    IpcHandler {
        target: "clipboard"
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
    WlrLayershell.namespace: "clipboard"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 520
    implicitHeight: 470
    color: "transparent"

    Glass {
        anchors.fill: parent

        Text {
            id: title
            x: 18
            y: 14
            text: "Zwischenablage"
            font.family: Config.fontSans
            font.pixelSize: 15
            font.weight: Font.Bold
            color: Config.text
        }

        Rectangle {
            id: field
            anchors.top: title.bottom
            anchors.topMargin: 10
            x: 14
            width: parent.width - 28
            height: 30
            radius: 8
            color: Config.tile
            border.color: Config.border

            TextInput {
                id: input
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                font.family: Config.fontSans
                font.pixelSize: 13
                color: Config.text
                clip: true
                onTextChanged: {
                    root.query = text;
                    root.selected = 0;
                }
                Keys.onEscapePressed: root.hide()
                Keys.onReturnPressed: root.paste(root.shown[root.selected])
                Keys.onEnterPressed: root.paste(root.shown[root.selected])
                Keys.onUpPressed: root.selected = Math.max(0, root.selected - 1)
                Keys.onDownPressed: root.selected = Math.min(root.shown.length - 1, root.selected + 1)
                Keys.onDeletePressed: if (root.shown[root.selected]) root.remove(root.shown[root.selected])

                Text {
                    visible: input.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Suchen"
                    font: input.font
                    color: Config.textSecondary
                }
            }
        }

        Text {
            visible: root.shown.length === 0
            anchors.centerIn: parent
            text: root.items.length === 0 ? "Noch nichts kopiert" : "Keine Treffer"
            font.family: Config.fontSans
            font.pixelSize: 13
            color: Config.textSecondary
        }

        ListView {
            id: entries
            anchors.top: field.bottom
            anchors.topMargin: 8
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            x: 8
            width: parent.width - 16
            clip: true
            model: root.shown
            currentIndex: root.selected
            highlightMoveDuration: 0

            FastScroll {
                view: entries
            }

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                width: entries.width
                height: 34
                radius: 7
                color: index === root.selected ? Config.accent : "transparent"

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 10
                    width: parent.width - 20
                    text: row.modelData.text.replace(/\s+/g, " ")
                    elide: Text.ElideRight
                    font.family: Config.fontSans
                    font.pixelSize: 13
                    font.italic: row.modelData.text.startsWith("Bild ·")
                    color: row.index === root.selected ? "white" : Config.text
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: root.selected = row.index
                    onClicked: root.paste(row.modelData)
                }
            }
        }
    }
}

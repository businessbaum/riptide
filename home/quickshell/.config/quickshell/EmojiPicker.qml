import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// "Emoji & Symbole" (⌃⌘Space), like on a Mac: search by name (German with python-emoji),
// the last used first; Enter or a click types it into the app in front (copied, then ⌃V –
// like the clipboard history). Arrow keys move, Esc closes.
// Data: scripts/emoji-data.py → ~/.cache/riptide/emoji.json. Also: qs ipc call emoji toggle
PanelWindow {
    id: root

    property var all: []
    property var recent: []
    property string query: ""
    property int selected: 0
    readonly property int columns: 10

    readonly property var shown: {
        const q = query.trim().toLowerCase();
        if (q === "") {
            const first = recent.map(e => all.find(a => a.e === e)).filter(a => a);
            return first.concat(all.filter(a => !recent.includes(a.e)));
        }
        const words = q.split(/\s+/);
        return all.filter(a => words.every(w => a.n.toLowerCase().includes(w) || a.k.includes(w))).slice(0, 300);
    }
    readonly property var current: shown[selected] ?? null

    // (re)written once per start: German names appear once python-emoji is installed
    Process {
        running: true
        command: ["python3", Quickshell.shellPath("scripts/emoji-data.py")]
        onExited: data.reload()
    }
    FileView {
        id: data
        path: Quickshell.env("HOME") + "/.cache/riptide/emoji.json"
        onLoaded: {
            try {
                root.all = JSON.parse(text());
            } catch (e) {}
        }
    }
    FileView {
        id: recentFile
        path: Quickshell.env("HOME") + "/.local/state/macos/emoji-recent.json"
        printErrors: false // (there is none until the first emoji is chosen)
        onLoaded: {
            try {
                root.recent = JSON.parse(text());
            } catch (e) {}
        }
    }

    function show() {
        query = "";
        input.text = "";
        selected = 0;
        visible = true;
        grab.active = true;
        input.forceActiveFocus();
    }
    function hide() {
        grab.active = false;
        visible = false;
    }
    function insert(item) {
        hide();
        if (!item)
            return;
        recent = [item.e].concat(recent.filter(e => e !== item.e)).slice(0, 20);
        recentFile.setText(JSON.stringify(recent));
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy && sleep 0.15 && "
            + "hyprctl dispatch 'hl.dsp.send_shortcut({ mods = \"CTRL\", key = \"v\" })' >/dev/null", "sh", item.e]);
    }

    IpcHandler {
        target: "emoji"
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
    WlrLayershell.namespace: "emoji"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors.top: true
    margins.top: Math.round((screen?.height ?? 1440) * 0.22)
    implicitWidth: panel.width
    implicitHeight: panel.height
    color: "transparent"

    Glass {
        id: panel
        width: root.columns * 44 + 24
        height: 400

        // search field
        Rectangle {
            id: field
            x: 12
            y: 12
            width: parent.width - 24
            height: 32
            radius: 8
            color: Config.tile
            border.color: Config.border

            Text {
                id: glass
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                font.family: Config.fontSymbols
                font.pixelSize: 13
                color: Config.textSecondary
            }
            TextInput {
                id: input
                anchors.left: glass.right
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                font.family: Config.fontSans
                font.pixelSize: 14
                color: Config.text
                clip: true
                onTextChanged: {
                    root.query = text;
                    root.selected = 0;
                    grid.positionViewAtBeginning();
                }
                Keys.onEscapePressed: root.hide()
                Keys.onReturnPressed: root.insert(root.current)
                Keys.onEnterPressed: root.insert(root.current)
                Keys.onLeftPressed: root.selected = Math.max(0, root.selected - 1)
                Keys.onRightPressed: root.selected = Math.min(root.shown.length - 1, root.selected + 1)
                Keys.onUpPressed: root.selected = Math.max(0, root.selected - root.columns)
                Keys.onDownPressed: root.selected = Math.min(root.shown.length - 1, root.selected + root.columns)

                Text {
                    visible: input.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Emoji und Symbole suchen"
                    font: input.font
                    color: Config.textSecondary
                }
            }
        }

        GridView {
            id: grid
            x: 12
            anchors.top: field.bottom
            anchors.topMargin: 8
            anchors.bottom: footer.top
            width: parent.width - 24
            cellWidth: 44
            cellHeight: 44
            clip: true
            model: root.shown
            currentIndex: root.selected
            boundsBehavior: Flickable.StopAtBounds
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)

            delegate: Rectangle {
                id: cell
                required property var modelData
                required property int index
                width: 42
                height: 42
                radius: 8
                color: index === root.selected ? Config.accent : cellMouse.containsMouse ? Config.hover : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: cell.modelData.e
                    font.family: cell.modelData.g === "Symbole" ? Config.fontSans : "Noto Color Emoji"
                    font.pixelSize: cell.modelData.g === "Symbole" ? 20 : 26
                    color: cell.index === root.selected ? "white" : Config.text
                }
                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: root.selected = cell.index
                    onClicked: root.insert(cell.modelData)
                }
            }
        }

        // the name of the chosen one
        Text {
            id: footer
            x: 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            width: parent.width - 32
            height: 18
            elide: Text.ElideRight
            text: root.shown.length === 0 ? "Nichts gefunden" : (root.current?.n ?? "")
            font.family: Config.fontSans
            font.pixelSize: 12
            color: Config.textSecondary
        }
    }
}

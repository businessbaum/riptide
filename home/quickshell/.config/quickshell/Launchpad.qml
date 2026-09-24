import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland

// Launchpad: every app as a grid over the blurred desktop, with a search field.
// Opens from the dock (pinned item "launchpad") or  qs ipc call launchpad toggle.
// Esc, a click on the background or starting an app closes it.
PanelWindow {
    id: root

    property string query: ""

    readonly property var apps: {
        const q = query.trim().toLowerCase();
        return DesktopEntries.applications.values
            .filter(e => !e.noDisplay && (q === "" || e.name.toLowerCase().includes(q)
                || (e.genericName ?? "").toLowerCase().includes(q)))
            .sort((a, b) => a.name.localeCompare(b.name, "de"));
    }

    function show() {
        query = "";
        search.text = "";
        visible = true;
        search.forceActiveFocus();
    }
    function hide() {
        visible = false;
    }
    function launch(entry) {
        hide();
        Apps.launch(entry);
    }

    IpcHandler {
        target: "launchpad"
        function toggle(): void {
            root.visible ? root.hide() : root.show();
        }
    }

    visible: false
    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "launchpad"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: Config.dark ? "#66000000" : "#40ffffff"

    MouseArea {
        anchors.fill: parent
        onClicked: root.hide()
    }

    // Search field on top, like on a Mac
    Rectangle {
        id: field
        anchors.horizontalCenter: parent.horizontalCenter
        y: 70
        width: 260
        height: 30
        radius: 8
        color: Config.tile
        border.color: Config.border

        Text {
            id: glass
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            font.family: Config.fontSymbols
            font.pixelSize: 12
            color: Config.textSecondary
        }
        TextInput {
            id: search
            anchors.left: glass.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            font.family: Config.fontSans
            font.pixelSize: 14
            color: Config.text
            clip: true
            onTextChanged: root.query = text
            Keys.onEscapePressed: root.hide()
            Keys.onReturnPressed: if (root.apps.length > 0) root.launch(root.apps[0])

            Text {
                visible: search.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: "Suchen"
                font: search.font
                color: Config.textSecondary
            }
        }
    }

    GridView {
        id: grid
        anchors.top: field.bottom
        anchors.topMargin: 50
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 110
        anchors.horizontalCenter: parent.horizontalCenter
        readonly property int columns: 7
        width: columns * cellWidth
        cellWidth: 170
        cellHeight: 150
        clip: true
        model: root.apps

        delegate: Item {
            id: cell
            required property var modelData
            width: grid.cellWidth
            height: grid.cellHeight

            IconImage {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                implicitSize: 88
                source: Apps.icon(cell.modelData, "")
                asynchronous: true
                scale: cellMouse.pressed ? 0.92 : 1
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 104
                width: parent.width - 16
                horizontalAlignment: Text.AlignHCenter
                text: cell.modelData.name
                elide: Text.ElideRight
                font.family: Config.fontSans
                font.pixelSize: 13
                color: Config.dark ? "white" : "#1d1d1f"
                style: Text.Raised
                styleColor: Config.dark ? "#60000000" : "#40ffffff"
            }
            MouseArea {
                id: cellMouse
                anchors.fill: parent
                onClicked: root.launch(cell.modelData)
            }
        }
    }
}

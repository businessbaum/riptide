import QtQuick
import Quickshell
import Quickshell.Hyprland

// A macOS-style menu: translucent panel, rows highlight in the accent colour.
//   items: [{ text, enabled?, action }, { separator: true }, …]
// Opens at `anchorItem`; clicking anywhere else closes it.
PopupWindow {
    id: root

    property var items: []
    property Item anchorItem
    property int anchorEdges: Edges.Bottom | Edges.Left
    property int openTowards: Edges.Bottom | Edges.Right
    property int offset: 4
    // Windows whose clicks do not close the menu (e.g. the bar with the button that opens it)
    property var keepOpenFor: []

    anchor.item: anchorItem
    anchor.edges: anchorEdges
    anchor.gravity: openTowards
    anchor.margins.top: (openTowards & Edges.Bottom) ? offset : 0
    anchor.margins.bottom: (openTowards & Edges.Top) ? offset : 0

    visible: false
    color: "transparent"
    implicitWidth: Math.max(230, list.implicitWidth + 12)
    implicitHeight: list.implicitHeight + 12

    function open() {
        visible = true;
        grab.active = true;
    }
    function close() {
        grab.active = false;
        visible = false;
    }
    function toggle() {
        visible ? close() : open();
    }

    HyprlandFocusGrab {
        id: grab
        windows: [root].concat(root.keepOpenFor)
        onCleared: root.close()
    }

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: Config.glassMenu
        border.color: Config.border
        border.width: 1

        Column {
            id: list
            x: 6
            y: 6
            width: parent.width - 12

            Repeater {
                model: root.items

                Item {
                    id: row
                    required property var modelData
                    readonly property bool separator: modelData.separator === true
                    readonly property bool enabled: !separator && modelData.enabled !== false

                    width: list.width
                    implicitWidth: label.implicitWidth + 24
                    height: separator ? 11 : 24

                    Rectangle {
                        visible: row.separator
                        anchors.verticalCenter: parent.verticalCenter
                        x: 8
                        width: parent.width - 16
                        height: 1
                        color: Config.border
                    }

                    Rectangle {
                        visible: !row.separator
                        anchors.fill: parent
                        radius: 5
                        color: mouse.containsMouse && row.enabled ? Config.accent : "transparent"
                    }

                    Text {
                        id: label
                        visible: !row.separator
                        anchors.verticalCenter: parent.verticalCenter
                        x: 12
                        text: row.modelData.text ?? ""
                        font.family: Config.fontSans
                        font.pixelSize: 13
                        color: !row.enabled ? Config.textSecondary
                             : mouse.containsMouse ? "white" : Config.text
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: row.enabled
                        onClicked: {
                            root.close();
                            row.modelData.action?.();
                        }
                    }
                }
            }
        }
    }
}

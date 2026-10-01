import QtQuick
import Quickshell
import Quickshell.Hyprland

// A macOS-style menu: translucent panel, rows highlight in the accent colour.
//   items: [{ text, hint?, enabled?, action }, { separator: true }, …]
//   (hint: the keyboard shortcut, grey on the right: "⌘Q")
// Opens at `anchorItem`; clicking anywhere else closes it.
PopupWindow {
    id: root

    // (counted while open: the menu bar and dock over a full-screen app stay, OpenMenus.qml)
    onVisibleChanged: OpenMenus.count += visible ? 1 : -1
    Component.onDestruction: if (visible) OpenMenus.count -= 1

    property var items: []
    property Item anchorItem
    property int anchorEdges: Edges.Bottom | Edges.Left
    property int openTowards: Edges.Bottom | Edges.Right
    property int offset: 4

    anchor.item: anchorItem
    anchor.edges: anchorEdges
    anchor.gravity: openTowards
    anchor.margins.top: (openTowards & Edges.Bottom) ? offset : 0
    anchor.margins.bottom: (openTowards & Edges.Top) ? offset : 0

    visible: false
    color: "transparent"
    implicitWidth: Math.max(230, list.implicitWidth + 12)
    implicitHeight: list.implicitHeight + 12

    // the screen of the menu bar it opens from: frosted glass (see MenuBarPopup)
    property var backdropScreen: null
    function open() {
        if (backdropScreen && Config.frostedMenus && anchorItem) {
            const ax = (anchorEdges & Edges.Right) ? anchorItem.width : (anchorEdges & Edges.Left) ? 0 : anchorItem.width / 2;
            const ay = (anchorEdges & Edges.Bottom) ? anchorItem.height : (anchorEdges & Edges.Top) ? 0 : anchorItem.height / 2;
            const p = anchorItem.mapToItem(null, ax, ay);
            const x = (openTowards & Edges.Left) ? p.x - implicitWidth : (openTowards & Edges.Right) ? p.x : p.x - implicitWidth / 2;
            const y = (openTowards & Edges.Top) ? p.y - implicitHeight - offset : p.y + offset;
            menuGlass.backdropPos = Qt.point(x, y);
            menuGlass.capture();
            showLater.restart();
        } else {
            visible = true;
            grab.active = true;
        }
    }
    Timer {
        id: showLater
        interval: 40
        onTriggered: {
            root.visible = true;
            grab.active = true;
        }
    }
    // Rule for every menu and panel: a click anywhere else closes it. A click on the item
    // that opened it closes it too – and must not open it again right away
    property double closedAt: 0
    function close() {
        if (visible)
            closedAt = Date.now();
        showLater.stop();
        grab.active = false;
        visible = false;
    }
    function toggle() {
        if (visible || showLater.running)
            close();
        else if (Date.now() - closedAt > 300)
            open();
    }

    HyprlandFocusGrab {
        id: grab
        windows: [root]
        onCleared: root.close()
    }

    Glass {
        id: menuGlass
        anchors.fill: parent
        radius: 10
        border.width: 1
        backdropScreen: root.backdropScreen

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
                    implicitWidth: label.implicitWidth + 24 + (hintLabel.text !== "" ? hintLabel.implicitWidth + 28 : 0)
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
                    Text {
                        id: hintLabel
                        visible: !row.separator && text !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        text: row.modelData.hint ?? ""
                        font.family: Config.fontSans
                        font.pixelSize: 13
                        color: mouse.containsMouse && row.enabled ? "white" : Config.textSecondary
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

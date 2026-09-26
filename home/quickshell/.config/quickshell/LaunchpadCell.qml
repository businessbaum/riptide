import QtQuick

// One tile of Launchpad (Launchpad.qml), in the grid and inside an open folder:
//   an app – its icon and name – or a folder – a rounded plate with small icons of its apps.
// Reports clicks, right-clicks and drags to Launchpad, which decides what they mean.
Item {
    id: root

    property var item // { kind: "app", id, entry } or { kind: "folder", index, name, entries }
    property var launchpad
    property bool inFolder: false
    property bool target: false   // something is dragged onto it: it grows, like a folder forming
    property bool lifted: false   // this is the tile being dragged: it moves with the pointer
    property bool showName: true
    property real offsetX: 0      // moved aside while another tile is dragged past
    property real offsetY: 0

    transform: Translate {
        x: root.offsetX
        y: root.offsetY
        Behavior on x {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
    }

    signal clicked
    signal menu(Item at)

    readonly property int iconSize: 88

    opacity: lifted ? 0 : 1 // (the icon under the pointer is this one, not a copy)

    // folder plate
    Rectangle {
        id: plate
        visible: root.item?.kind === "folder" || root.target
        anchors.horizontalCenter: parent.horizontalCenter
        y: 8
        width: root.iconSize
        height: root.iconSize
        radius: Math.round(root.iconSize * 0.225)
        color: Config.dark ? "#40ffffff" : "#66ffffff"
        border.color: Config.border
        scale: root.target ? 1.18 : 1
        Behavior on scale {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        Grid {
            visible: root.item?.kind === "folder"
            anchors.centerIn: parent
            columns: 3
            spacing: 5
            Repeater {
                model: root.item?.kind === "folder" ? root.item.entries.slice(0, 9) : []
                AppIcon {
                    required property var modelData
                    size: 21
                    entry: modelData
                }
            }
        }
    }

    AppIcon {
        visible: root.item?.kind === "app"
        anchors.horizontalCenter: parent.horizontalCenter
        y: 8
        size: root.iconSize
        entry: root.item?.entry ?? null
        scale: mouse.pressed && !root.lifted ? 0.92 : root.target ? 0.8 : 1
        Behavior on scale {
            NumberAnimation { duration: 120 }
        }
    }

    Text {
        visible: root.showName
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.iconSize + 16
        width: parent.width - 16
        horizontalAlignment: Text.AlignHCenter
        text: root.item?.kind === "folder" ? root.item.name : (root.item?.entry?.name ?? "")
        elide: Text.ElideRight
        font.family: Config.fontSans
        font.pixelSize: 13
        color: root.inFolder ? Config.text : (Config.dark ? "white" : "#1d1d1f")
        style: root.inFolder ? Text.Normal : Text.Raised
        styleColor: Config.dark ? "#60000000" : "#40ffffff"
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true
        property point pressAt
        property bool dragging: false

        onPressed: e => {
            pressAt = Qt.point(e.x, e.y);
            dragging = false;
        }
        onPositionChanged: e => {
            if (!pressed || !(e.buttons & Qt.LeftButton) || !root.item)
                return;
            const p = mapToItem(root.launchpad.contentItem, e.x, e.y);
            if (!dragging && Math.hypot(e.x - pressAt.x, e.y - pressAt.y) > 10) {
                dragging = true;
                root.launchpad.startDrag(root.item, root.inFolder, p);
            }
            if (dragging)
                root.launchpad.moveDrag(p);
        }
        onReleased: e => {
            if (dragging) {
                dragging = false;
                root.launchpad.endDrag();
            } else if (e.button === Qt.RightButton) {
                root.menu(root);
            } else {
                root.clicked();
            }
        }
    }
}

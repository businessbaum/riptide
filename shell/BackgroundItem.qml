import QtQuick
import Quickshell

// Icon of an app we keep in the background (Background.qml), in the menu bar next to the
// apps that put one there themselves (TrayItem.qml).
//   click:  menu with "Öffnen" (its window back, its icon back into the dock) and "Beenden"
Item {
    id: root

    required property var app  // { key, appId, entry }
    readonly property string name: app.entry?.name ?? Apps.name(app.key)

    implicitWidth: 26
    implicitHeight: parent ? parent.height : 30

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 3
        anchors.bottomMargin: 3
        radius: 5
        color: mouse.containsMouse || menu.visible ? Config.hover : "transparent"
    }

    AppIcon {
        anchors.centerIn: parent
        size: 18
        entry: root.app.entry
        appId: root.app.appId
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: menu.toggle()
    }

    MenuPopup {
        id: menu
        anchorItem: root
        items: [
            { text: `„${root.name}“ öffnen`, action: () => Background.leave(root.app.key) },
            { separator: true },
            { text: `„${root.name}“ beenden`, action: () => Background.quit(root.app.key) }
        ]
    }

    Tooltip {
        visible: mouse.containsMouse && !menu.visible
        anchors.top: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.name + " – im Hintergrund"
    }
}

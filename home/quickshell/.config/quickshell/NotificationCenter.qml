import QtQuick
import Quickshell
import Quickshell.Hyprland

// Notification centre: opens from the clock in the menu bar, lists every
// notification (newest first). Click a card to open it, × to remove it.
MenuBarPopup {
    id: root

    readonly property int screenHeight: anchorItem?.QsWindow.window?.screen?.height ?? 1440

    implicitWidth: 380
    implicitHeight: Math.min(screenHeight - 140, header.height + list.contentHeight + 24)

    Item {
        id: header
        x: 16
        y: 10
        width: parent.width - 32
        height: 32

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Mitteilungen"
            font.family: Config.fontSans
            font.pixelSize: 15
            font.weight: Font.Bold
            color: Config.text
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: NotificationStore.all.length > 0
            text: "Alle löschen"
            font.family: Config.fontSans
            font.pixelSize: 12
            color: clearMouse.containsMouse ? Config.text : Config.textSecondary
            MouseArea {
                id: clearMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: NotificationStore.clearAll()
            }
        }
    }

    Text {
        visible: NotificationStore.all.length === 0
        anchors.top: header.bottom
        anchors.topMargin: 14
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Keine Mitteilungen"
        font.family: Config.fontSans
        font.pixelSize: 13
        color: Config.textSecondary
    }

    ListView {
        id: list
        anchors.top: header.bottom
        anchors.topMargin: 6
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        x: 10
        width: parent.width - 20
        clip: true
        spacing: 2
        model: NotificationStore.all

        FastScroll {
            view: list
        }

        // Padding on the left keeps the × (top left corner of a card) visible
        delegate: Item {
            id: slot
            required property var modelData
            width: list.width
            height: card.height + 6

            NotificationCard {
                id: card
                x: 8
                y: 6
                width: parent.width - 8
                n: slot.modelData
                color: Config.tile
            }
        }
    }
}

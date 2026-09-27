import QtQuick
import Quickshell
import Quickshell.Hyprland

// Notification centre: opens from the clock in the menu bar, lists every
// notification (newest first). Click a card to open it, × to remove it.
MenuBarPopup {
    id: root


    // One app's notifications lie on top of each other, the newest in front, like on a
    // Mac: a click on the stack opens it, "Weniger" closes it again.
    property var expanded: ({})
    readonly property var rows: {
        const groups = [], at = {};
        for (const n of NotificationStore.all) {
            const key = NotificationStore.groupOf(n);
            if (at[key] === undefined) {
                at[key] = groups.length;
                groups.push({ key: key, items: [] });
            }
            groups[at[key]].items.push(n);
        }
        const out = [];
        for (const g of groups) {
            if (g.items.length === 1)
                out.push({ kind: "card", n: g.items[0], stack: 0 });
            else if (expanded[g.key]) {
                out.push({ kind: "head", key: g.key, n: g.items[0] });
                for (const n of g.items)
                    out.push({ kind: "card", n: n, stack: 0 });
            } else
                out.push({ kind: "card", n: g.items[0], stack: g.items.length - 1, key: g.key });
        }
        return out;
    }
    function setExpanded(key, on) {
        const e = Object.assign({}, expanded);
        e[key] = on;
        expanded = e;
    }

    implicitWidth: 380
    panelHeight: Math.min(screenHeight - 140, header.height + list.contentHeight + 24)

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
        model: root.rows

        FastScroll {
            view: list
        }

        // Padding on the left keeps the × (top left corner of a card) visible
        delegate: Item {
            id: slot
            required property var modelData
            readonly property bool head: modelData.kind === "head"
            readonly property int stack: modelData.stack ?? 0
            width: list.width
            height: head ? 30 : card.height + 6 + (stack > 0 ? 10 : 0)

            // an opened stack: the app's name, "Weniger", × for all of it
            Item {
                visible: slot.head
                x: 12
                width: parent.width - 16
                height: 30
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: slot.head ? NotificationStore.nameOf(slot.modelData.n) || slot.modelData.key : ""
                    font.family: Config.fontSans
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Config.text
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14
                    Text {
                        text: "Weniger"
                        font.family: Config.fontSans
                        font.pixelSize: 12
                        color: lessMouse.containsMouse ? Config.text : Config.textSecondary
                        MouseArea {
                            id: lessMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.setExpanded(slot.modelData.key, false)
                        }
                    }
                    Text {
                        text: "Löschen"
                        font.family: Config.fontSans
                        font.pixelSize: 12
                        color: groupClear.containsMouse ? Config.text : Config.textSecondary
                        MouseArea {
                            id: groupClear
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: NotificationStore.removeGroup(slot.modelData.key)
                        }
                    }
                }
            }

            // the cards behind the front one of a stack
            Repeater {
                model: slot.stack > 0 ? (slot.stack > 1 ? 2 : 1) : 0
                Rectangle {
                    required property int index
                    x: 8 + 10 * (index + 1)
                    y: 6 + card.height - 14 + 6 * (index + 1)
                    width: slot.width - 8 - 20 * (index + 1)
                    height: 20
                    radius: 12
                    color: Config.tile
                    opacity: 0.8 - 0.25 * index
                    z: -1 - index
                }
            }

            NotificationCard {
                id: card
                visible: !slot.head
                x: 8
                y: 6
                width: parent.width - 8
                n: slot.modelData.n
                stack: slot.stack
                color: Config.tile
                onOpenStack: root.setExpanded(slot.modelData.key, true)
            }
        }
    }
}

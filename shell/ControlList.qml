import QtQuick

// A list that unfolds in the control centre below its tile – the Wi-Fi networks, the
// Bluetooth devices – like on a Mac: its title with the switch, the rows (ControlListRow),
// a line when there are none, and its settings at the bottom.
Rectangle {
    id: root

    property string title: ""
    property bool switchedOn: false
    property string emptyText: ""    // shown while there are no rows ("" = nothing)
    property string settingsText: "" // "WLAN-Einstellungen …"
    default property alias rows: rowColumn.data
    signal switched(bool on)
    signal openSettings

    height: column.implicitHeight + 16
    radius: Config.radiusTile
    color: Config.tile
    border.color: Config.border

    Column {
        id: column
        x: 8
        y: 8
        width: parent.width - 16
        spacing: 2

        Item {
            width: parent.width
            height: 26
            Text {
                x: 4
                anchors.verticalCenter: parent.verticalCenter
                text: root.title
                font.family: Config.fontSans
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: Config.text
            }
            Toggle {
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                checked: root.switchedOn
                onToggled: on => root.switched(on)
            }
        }
        Column {
            id: rowColumn
            width: parent.width
            spacing: 2
        }
        Text {
            visible: root.emptyText !== ""
            x: 4
            width: parent.width - 8
            topPadding: 2
            bottomPadding: 4
            text: root.emptyText
            wrapMode: Text.Wrap
            font.family: Config.fontSans
            font.pixelSize: 11
            color: Config.textSecondary
        }
        Rectangle {
            width: parent.width
            height: 1
            color: Config.border
        }
        Rectangle {
            width: parent.width
            height: 28
            radius: 7
            color: settingsMouse.containsMouse ? Config.hover : "transparent"
            Text {
                x: 6
                anchors.verticalCenter: parent.verticalCenter
                text: root.settingsText
                font.family: Config.fontSans
                font.pixelSize: 12
                color: Config.text
            }
            MouseArea {
                id: settingsMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.openSettings()
            }
        }
    }
}

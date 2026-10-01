import QtQuick
import QtQuick.Layouts
import qs

// A titled card of rows, as on a macOS settings page. Rows go inside; lines between them.
ColumnLayout {
    id: root

    property string title: ""
    property string description: ""
    default property alias rows: list.data

    Layout.fillWidth: true
    spacing: 6

    Text {
        visible: root.title !== ""
        Layout.leftMargin: 4
        text: root.title
        font.family: Config.fontSans
        font.pixelSize: 13
        font.weight: Font.DemiBold
        color: Config.text
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: list.implicitHeight
        radius: 10
        color: Config.cardBg
        border.color: Config.border

        ColumnLayout {
            id: list
            width: parent.width
            spacing: 0
        }
    }

    Text {
        visible: root.description !== ""
        Layout.fillWidth: true
        Layout.leftMargin: 4
        text: root.description
        wrapMode: Text.Wrap
        font.family: Config.fontSans
        font.pixelSize: 11
        color: Config.textSecondary
    }
}

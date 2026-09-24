import QtQuick
import QtQuick.Layouts
import qs

// One setting: title (+ subtitle) on the left, the control on the right.
// A thin line separates it from the row above.
Item {
    id: root

    property string title: ""
    property string subtitle: ""
    property bool first: false
    default property alias control: slot.data

    Layout.fillWidth: true
    implicitHeight: Math.max(40, texts.implicitHeight + 18, slot.childrenRect.height + 14)

    Rectangle {
        visible: !root.first
        x: 12
        width: parent.width - 24
        height: 1
        color: Config.border
    }

    Column {
        id: texts
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: slot.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            width: parent.width
            text: root.title
            wrapMode: Text.Wrap
            font.family: Config.fontSans
            font.pixelSize: 13
            color: Config.text
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: root.subtitle
            wrapMode: Text.Wrap
            font.family: Config.fontSans
            font.pixelSize: 11
            color: Config.textSecondary
        }
    }

    Item {
        id: slot
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
}

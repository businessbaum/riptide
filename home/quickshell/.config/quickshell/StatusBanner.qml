import QtQuick
import Quickshell
import Quickshell.Widgets

// Short system message (Banners.show): round badge with a symbol or icon, title,
// subtitle and an optional ring on the right (e.g. battery). Click closes it.
Banner {
    id: root

    property string glyph: ""    // Nerd Font symbol …
    property string icon: ""     // … or icon name / file path
    property string title: ""
    property string subtitle: ""
    property real value: -1      // 0…1 draws the ring, < 0 none

    closable: false
    implicitWidth: 300
    implicitHeight: 64
    onClicked: leave()

    Rectangle {
        id: badge
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 40
        height: 40
        radius: 20
        color: Config.tile

        Text {
            visible: root.glyph !== ""
            anchors.centerIn: parent
            text: root.glyph
            font.family: Config.fontSymbols
            font.pixelSize: 22
            color: Config.text
        }
        IconImage {
            visible: root.glyph === "" && root.icon !== ""
            anchors.centerIn: parent
            implicitSize: 28
            source: root.icon.startsWith("/") ? "file://" + root.icon : Quickshell.iconPath(root.icon, true)
        }
    }

    Column {
        anchors.left: badge.right
        anchors.leftMargin: 12
        anchors.right: ring.visible ? ring.left : parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            width: parent.width
            text: root.title
            elide: Text.ElideRight
            font.family: Config.fontSans
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: Config.text
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: root.subtitle
            elide: Text.ElideRight
            font.family: Config.fontSans
            font.pixelSize: 12
            color: Config.textSecondary
        }
    }

    ProgressRing {
        id: ring
        visible: root.value >= 0
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: 32
        height: 32
        thickness: 3
        value: Math.max(0, root.value)
        colour: value < 0.2 ? "#ff9f0a" : "#30d158"

        Text {
            anchors.centerIn: parent
            text: Math.round(ring.value * 100)
            font.family: Config.fontSans
            font.pixelSize: 10
            font.weight: Font.DemiBold
            color: Config.text
        }
    }
}

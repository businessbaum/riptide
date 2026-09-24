import QtQuick
import Quickshell

// The Launchpad icon in the dock: a grid of coloured dots on a dark tile.
Item {
    id: root

    property int size: 64

    width: size
    height: size

    Rectangle {
        anchors.fill: parent
        anchors.margins: root.size * 0.04
        radius: width * 0.225
        gradient: Gradient {
            GradientStop { position: 0; color: "#4a4a52" }
            GradientStop { position: 1; color: "#2a2a30" }
        }
        opacity: mouse.pressed ? 0.7 : 1

        Grid {
            anchors.centerIn: parent
            columns: 3
            spacing: parent.width * 0.09
            Repeater {
                model: ["#ff5f57", "#febc2e", "#28c840", "#0a84ff", "#bf5af2", "#ff9f0a", "#64d2ff", "#ff375f", "#30d158"]
                Rectangle {
                    required property string modelData
                    width: root.size * 0.14
                    height: width
                    radius: width * 0.3
                    color: modelData
                }
            }
        }
    }

    Rectangle {
        visible: mouse.containsMouse
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: 16
        width: label.implicitWidth + 20
        height: 24
        radius: 6
        color: Config.glassMenu
        border.color: Config.border
        Text {
            id: label
            anchors.centerIn: parent
            text: "Launchpad"
            font.family: Config.fontSans
            font.pixelSize: 13
            color: Config.text
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: Quickshell.execDetached(["qs", "ipc", "call", "launchpad", "toggle"])
    }
}

import QtQuick

// Small name label, e.g. above a dock icon while hovering. Position it with anchors or x/y.
Glass {
    property alias text: label.text

    width: label.implicitWidth + 20
    height: 24
    radius: 6

    Text {
        id: label
        anchors.centerIn: parent
        font.family: Config.fontSans
        font.pixelSize: 13
        color: Config.text
    }
}

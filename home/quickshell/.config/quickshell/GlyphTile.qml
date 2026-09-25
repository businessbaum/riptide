import QtQuick

// A symbol on a coloured rounded square, like the icons in macOS System Settings.
Rectangle {
    id: root

    property string glyph: ""
    property int size: 20

    width: size
    height: size
    radius: Math.round(size / 4)
    color: "#8e8e93"

    Text {
        anchors.centerIn: parent
        text: root.glyph
        font.family: Config.fontSymbols
        font.pixelSize: Math.round(root.size * 0.55)
        color: "white"
    }
}

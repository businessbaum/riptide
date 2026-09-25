import QtQuick
import QtQuick.Layouts
import qs

// One setting: (app icon or symbol,) title (+ subtitle) on the left, the control on the
// right. A thin line separates it from the row above. With `link` the whole row opens
// something (chevron on the right, `clicked`).
Item {
    id: root

    property string title: ""
    property string subtitle: ""
    property bool first: false
    // Optional app icon in front of the title: a desktop entry, or an icon name/app id
    property var iconEntry: null
    property string iconAppId: ""
    // … or a symbol on a coloured tile
    property string glyph: ""
    property color glyphColour: "#8e8e93"
    readonly property bool hasIcon: iconEntry !== null || iconAppId !== "" || glyph !== ""
    property bool link: false
    signal clicked
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

    MouseArea {
        id: rowMouse
        visible: root.link
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
    Rectangle {
        visible: root.link && rowMouse.containsMouse
        anchors.fill: parent
        anchors.margins: 2
        radius: 8
        color: Config.hover
    }

    Item {
        id: icon
        visible: root.hasIcon
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 28
        height: 28

        AppIcon {
            visible: root.glyph === ""
            size: 28
            entry: root.iconEntry
            appId: root.iconAppId
        }
        GlyphTile {
            visible: root.glyph !== ""
            anchors.centerIn: parent
            size: 24
            glyph: root.glyph
            color: root.glyphColour
        }
    }

    Column {
        id: texts
        anchors.left: root.hasIcon ? icon.right : parent.left
        anchors.leftMargin: root.hasIcon ? 10 : 12
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

    Text {
        id: chevron
        visible: root.link
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: "\u{f0142}"
        font.family: Config.fontSymbols
        font.pixelSize: 16
        color: Config.textSecondary
    }

    Item {
        id: slot
        anchors.right: root.link ? chevron.left : parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
}

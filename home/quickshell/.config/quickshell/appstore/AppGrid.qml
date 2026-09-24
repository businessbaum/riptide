import QtQuick
import qs

// Page with a title and apps in two columns. Only visible cards are created
// (categories can hold hundreds of apps).
GridView {
    id: root

    property string title: ""
    property string subtitle: ""
    property var apps: []
    property string empty: "Keine Apps gefunden."
    signal open(var app)

    leftMargin: 24
    rightMargin: 24
    topMargin: 16
    bottomMargin: 24
    cellWidth: (width - leftMargin - rightMargin) / 2
    cellHeight: 88
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: apps

    header: Column {
        width: root.width - root.leftMargin - root.rightMargin
        bottomPadding: 14
        spacing: 2

        Text {
            text: root.title
            font.family: Config.fontSans
            font.pixelSize: 22
            font.weight: Font.Bold
            color: Config.text
        }
        Text {
            visible: root.subtitle !== ""
            text: root.subtitle
            font.family: Config.fontSans
            font.pixelSize: 12
            color: Config.textSecondary
        }
        Text {
            visible: root.apps.length === 0
            topPadding: 10
            text: Catalog.loading ? "Katalog wird geladen …" : root.empty
            font.family: Config.fontSans
            font.pixelSize: 13
            color: Config.textSecondary
        }
    }

    delegate: Item {
        id: cell
        required property var modelData
        width: root.cellWidth
        height: root.cellHeight

        AppCard {
            anchors.fill: parent
            anchors.rightMargin: 12
            anchors.bottomMargin: 4
            app: cell.modelData
            onOpen: a => root.open(a)
        }
    }
}

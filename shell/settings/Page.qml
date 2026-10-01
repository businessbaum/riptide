import QtQuick
import QtQuick.Layouts
import qs

// Scrollable content of one settings page with its title on top.
Flickable {
    id: root

    property string title: ""
    default property alias content: column.data

    contentHeight: column.implicitHeight + 40
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    FastScroll {
        view: root
    }

    ColumnLayout {
        id: column
        x: 24
        y: 16
        width: root.width - 48
        spacing: 22

        Text {
            text: root.title
            font.family: Config.fontSans
            font.pixelSize: 20
            font.weight: Font.Bold
            color: Config.text
        }
    }
}

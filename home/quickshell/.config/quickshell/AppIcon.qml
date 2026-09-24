import QtQuick
import Quickshell
import Quickshell.Widgets

// An app icon in the one shape every app gets (dock, Launchpad, Spotlight, ⌘Tab):
// a rounded square like on macOS. The app's own icon sits on a light tile, so round,
// wide or transparent icons all end up with the same outline and size.
Item {
    id: root

    property var entry: null      // desktop entry (preferred)
    property string appId: ""     // window class, used when there is no entry
    property string source: ""    // explicit icon path/URL (overrides both)
    property int size: 64

    // Our own apps already come as a rounded square: let them fill the tile
    readonly property bool fills: (entry?.id ?? appId).startsWith("org.riptide.")

    implicitWidth: size
    implicitHeight: size

    // Soft shadow below the tile
    Rectangle {
        anchors.fill: tile
        anchors.topMargin: root.size * 0.03
        anchors.bottomMargin: -root.size * 0.03
        radius: tile.radius
        color: "#000000"
        opacity: 0.22
    }

    ClippingRectangle {
        id: tile
        anchors.fill: parent
        anchors.margins: root.size * 0.04
        radius: width * 0.225
        color: "#f4f4f6"
        border.color: "#1a000000"
        border.width: 1

        Rectangle {
            anchors.fill: parent
            visible: !root.fills
            gradient: Gradient {
                GradientStop { position: 0; color: "#ffffff" }
                GradientStop { position: 1; color: "#e4e4e8" }
            }
        }

        IconImage {
            anchors.centerIn: parent
            implicitSize: root.fills ? Math.round(tile.width / 0.875) : Math.round(tile.width * 0.76)
            source: root.source !== "" ? root.source : Apps.icon(root.entry, root.appId)
            asynchronous: true
        }
    }
}

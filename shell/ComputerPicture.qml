import QtQuick

// A small picture of this computer – a display on a stand, showing the desktop picture –
// for "Über diesen Computer" and System Settings → Allgemein → Info, where a Mac shows
// a photo of itself.
Item {
    id: root

    property real size: 160 // width of the display
    readonly property string wallpaper: Config.settings.appearance?.wallpaper ?? ""

    implicitWidth: size
    implicitHeight: screen.height + neck.height + foot.height

    Rectangle {
        id: screen
        width: root.size
        height: Math.round(root.size * 0.6)
        radius: Math.round(root.size * 0.045)
        color: "#0c0c0e"
        border.color: Config.dark ? "#48484a" : "#8e8e93"

        Image {
            anchors.fill: parent
            anchors.margins: Math.max(3, Math.round(root.size * 0.025))
            source: root.wallpaper !== "" ? "file://" + root.wallpaper : ""
            sourceSize.width: root.size * 2
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
        }
        // no desktop picture: the desktop's own gradient (Wallpaper.qml)
        Rectangle {
            visible: root.wallpaper === ""
            anchors.fill: parent
            anchors.margins: Math.max(3, Math.round(root.size * 0.025))
            gradient: Gradient {
                GradientStop { position: 0.0; color: Config.dark ? "#1b2a4a" : "#8fb3e6" }
                GradientStop { position: 0.55; color: Config.dark ? "#3b2f63" : "#c4b2e8" }
                GradientStop { position: 1.0; color: Config.dark ? "#5c2a4f" : "#f0c2d4" }
            }
        }
    }
    Rectangle {
        id: neck
        anchors.top: screen.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.round(root.size * 0.16)
        height: Math.round(root.size * 0.12)
        gradient: Gradient {
            GradientStop { position: 0; color: "#8e8e93" }
            GradientStop { position: 1; color: "#c7c7cc" }
        }
    }
    Rectangle {
        id: foot
        anchors.top: neck.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.round(root.size * 0.36)
        height: Math.max(4, Math.round(root.size * 0.03))
        radius: height / 2
        color: "#aeaeb2"
    }
}

import QtQuick

// The desktop background as a picture: the image from settings.json
// (appearance.wallpaper), otherwise a soft gradient in the spirit of macOS. The desktop
// (Wallpaper.qml) and the lock screen (LockScreen.qml) show the same one – unlocking
// goes straight on into the desktop.
Item {
    id: root

    readonly property string image: Config.settings.appearance?.wallpaper ?? ""

    Rectangle {
        anchors.fill: parent
        visible: picture.status !== Image.Ready
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Config.dark ? "#1b2a4a" : "#8fb3e6" }
            GradientStop { position: 0.55; color: Config.dark ? "#3b2f63" : "#c4b2e8" }
            GradientStop { position: 1.0; color: Config.dark ? "#5c2a4f" : "#f0c2d4" }
        }
    }

    Image {
        id: picture
        anchors.fill: parent
        source: root.image !== "" ? "file://" + root.image : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
    }
}

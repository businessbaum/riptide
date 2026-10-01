import QtQuick
import QtQuick.Effects

// The desktop background as a picture: the image from settings.json
// (appearance.wallpaper), otherwise a soft gradient in the spirit of macOS. The desktop
// (Wallpaper.qml) and the lock screen (LockScreen.qml) show the same one – unlocking
// goes straight on into the desktop. `blurred`: soft and a little darker, so what lies on
// it stays readable on any picture (the lock screen's weather and month on the other screen).
Item {
    id: root

    readonly property string image: Config.settings.appearance?.wallpaper ?? ""
    property bool blurred: false

    // only without a picture (none chosen, or it cannot be read) – never while it loads:
    // a gradient flashing up before the picture looks like a wrong wallpaper
    Rectangle {
        anchors.fill: parent
        visible: root.image === "" || picture.status === Image.Error
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
        visible: !root.blurred
        source: root.image !== "" ? "file://" + root.image : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // shared: the desktop has it in memory already, so the lock screen (and Mission
        // Control) show it in their very first frame, not a moment later
        cache: true
    }
    MultiEffect {
        anchors.fill: parent
        visible: root.blurred && picture.status === Image.Ready
        source: picture
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1
        blurMax: 64
        brightness: -0.22
        saturation: -0.15
    }
}

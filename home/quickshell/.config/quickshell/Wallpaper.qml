import QtQuick
import Quickshell
import Quickshell.Wayland

// Desktop background: the image from settings.json (appearance.wallpaper),
// otherwise a soft gradient in the spirit of macOS.
PanelWindow {
    id: root

    readonly property string image: Config.settings.appearance?.wallpaper ?? ""

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "wallpaper"
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "black"

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

import QtQuick
import Quickshell
import Quickshell.Wayland

// Desktop background (WallpaperImage.qml: the image from settings.json or the gradient).
PanelWindow {
    id: root

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

    WallpaperImage {
        anchors.fill: parent
    }
}

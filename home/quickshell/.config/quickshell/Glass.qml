import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// The frosted surface every popup of the shell is made of: menus, panels, dialogs,
// banners, tooltips. Change the look here and all of them follow.
//
// Frosted like on a Mac: a popup that knows where it sits on its screen (the menus and
// panels of the menu bar) sets `backdropScreen` and `backdropPos` and calls capture()
// right before it shows: the screen behind is taken once and shown blurred under a
// lighter tint – readable over bright windows. Our own blur: the compositor's is off on
// NVIDIA. Without a backdrop (or with "Menüs mit Unschärfe" off) the glass is just tinted.
Rectangle {
    id: glass

    property var backdropScreen: null
    property point backdropPos: Qt.point(0, 0)
    readonly property bool frosted: Config.frostedMenus && backdropScreen !== null && shot.hasContent

    function capture() {
        if (backdropScreen && Config.frostedMenus)
            shot.captureFrame();
    }

    radius: Config.radiusPanel
    color: frosted ? "transparent" : Config.glassMenu
    border.color: Config.border

    // the screen behind, once
    ScreencopyView {
        id: shot
        visible: false
        width: glass.backdropScreen?.width ?? 0
        height: glass.backdropScreen?.height ?? 0
        captureSource: glass.backdropScreen
        live: false
    }
    // just the part under the glass
    ShaderEffectSource {
        id: part
        visible: false
        sourceItem: shot
        sourceRect: Qt.rect(glass.backdropPos.x, glass.backdropPos.y, glass.width, glass.height)
        width: glass.width
        height: glass.height
    }
    ClippingRectangle {
        visible: glass.frosted
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, glass.radius - 1)
        color: "transparent"
        MultiEffect {
            width: glass.width
            height: glass.height
            x: -1
            y: -1
            source: part
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1
            blurMax: 48
            saturation: 0.3
        }
        // the tint over it: lighter than plain glass, the blur does the calming
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(Config.glassMenu.r, Config.glassMenu.g, Config.glassMenu.b, Config.highContrast ? 0.94 : 0.66)
        }
    }
}

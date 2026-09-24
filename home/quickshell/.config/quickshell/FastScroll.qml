import QtQuick

// Mouse-wheel scrolling like in a browser: one notch moves 120 px, eased for 0.12 s.
// Qt's own wheel handling on lists is much slower. Touchpads scroll 1:1.
// The scroll speed from System Settings already reaches us through Hyprland.
// Put inside any Flickable / ListView / GridView:  FastScroll { view: theView }
WheelHandler {
    id: root

    required property Flickable view
    property real target: 0

    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    orientation: Qt.Vertical

    function clamp(y) {
        const top = view.originY - view.topMargin;
        const bottom = view.originY + view.contentHeight + view.bottomMargin - view.height;
        return Math.max(top, Math.min(Math.max(top, bottom), y));
    }

    onWheel: event => {
        if (event.pixelDelta.y !== 0 && event.angleDelta.y % 120 !== 0) {
            // touchpad: follow the fingers
            ease.stop();
            view.contentY = clamp(view.contentY - event.pixelDelta.y);
        } else {
            const from = ease.running ? root.target : view.contentY;
            root.target = clamp(from - event.angleDelta.y / 120 * 120);
            ease.from = view.contentY;
            ease.to = root.target;
            ease.restart();
        }
        event.accepted = true;
    }

    property NumberAnimation ease: NumberAnimation {
        target: root.view
        property: "contentY"
        duration: 120
        easing.type: Easing.OutCubic
    }
}

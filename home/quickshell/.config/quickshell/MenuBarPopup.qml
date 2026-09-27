import QtQuick
import Quickshell
import Quickshell.Hyprland

// A panel that drops down from a menu bar item – control centre, notification centre,
// sound, privacy – like the menus of the macOS menu bar: glass, opens below its item,
// closes on a click anywhere else. What goes inside is the panel's content; the panel
// sets its own size (implicitWidth / implicitHeight).
PopupWindow {
    id: root

    property Item anchorItem
    property var keepOpenFor: [] // windows whose clicks keep it open (the menu bar)
    default property alias content: surface.data
    // the screen of the menu bar it hangs from: frosted glass (the bar sits at the
    // screen's top left, so the item's place in it is its place on the screen)
    property var backdropScreen: null

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom | Edges.Right
    anchor.gravity: Edges.Bottom | Edges.Left
    anchor.margins.top: 4

    visible: false
    color: "transparent"
    implicitWidth: 330

    function open() {
        if (backdropScreen && Config.frostedMenus && anchorItem) {
            // the screen behind first, then show (else the panel would be in the picture)
            const p = anchorItem.mapToItem(null, anchorItem.width, anchorItem.height);
            surface.backdropPos = Qt.point(p.x - implicitWidth, p.y + 4);
            surface.capture();
            showLater.restart();
        } else {
            visible = true;
            grab.active = true;
        }
    }
    Timer {
        id: showLater
        interval: 40
        onTriggered: {
            root.visible = true;
            grab.active = true;
        }
    }
    function close() {
        showLater.stop();
        grab.active = false;
        visible = false;
    }
    function toggle() {
        visible || showLater.running ? close() : open();
    }

    HyprlandFocusGrab {
        id: grab
        windows: [root].concat(root.keepOpenFor)
        onCleared: root.close()
    }

    Glass {
        id: surface
        anchors.fill: parent
        backdropScreen: root.backdropScreen
    }
}

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

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom | Edges.Right
    anchor.gravity: Edges.Bottom | Edges.Left
    anchor.margins.top: 4

    visible: false
    color: "transparent"
    implicitWidth: 330

    function open() {
        visible = true;
        grab.active = true;
    }
    function close() {
        grab.active = false;
        visible = false;
    }
    function toggle() {
        visible ? close() : open();
    }

    HyprlandFocusGrab {
        id: grab
        windows: [root].concat(root.keepOpenFor)
        onCleared: root.close()
    }

    Glass {
        id: surface
        anchors.fill: parent
    }
}

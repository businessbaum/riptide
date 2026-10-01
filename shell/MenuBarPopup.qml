import QtQuick
import Quickshell
import Quickshell.Hyprland

// A panel that drops down from a menu bar item – control centre, notification centre,
// sound, privacy – like the menus of the macOS menu bar: glass, opens below its item,
// closes on a click anywhere else. What goes inside is the panel's content; the panel
// sets its width (implicitWidth) and the height of its glass (panelHeight).
// The window itself is as tall as the room below the menu bar from the start (see-through
// and click-through below the glass): when a part unfolds, only the glass grows – downwards
// and smoothly – instead of the window changing size, which made it jump up and down.
PopupWindow {
    id: root

    // (counted while open: the menu bar and dock over a full-screen app stay, OpenMenus.qml)
    onVisibleChanged: OpenMenus.count += visible ? 1 : -1
    Component.onDestruction: if (visible) OpenMenus.count -= 1

    property Item anchorItem
    default property alias content: surface.data
    // the screen of the menu bar it hangs from: frosted glass (the bar sits at the
    // screen's top left, so the item's place in it is its place on the screen)
    property var backdropScreen: null

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom | Edges.Right
    anchor.gravity: Edges.Bottom | Edges.Left
    anchor.margins.top: 4

    property real panelHeight: 100
    readonly property int screenHeight: anchorItem?.QsWindow.window?.screen?.height ?? 1440

    visible: false
    color: "transparent"
    implicitWidth: 330
    implicitHeight: screenHeight - 40
    mask: Region {
        item: surface
    }

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
    // Rule for every menu and panel: a click anywhere else closes it. A click on the item
    // that opened it closes it too – and must not open it again right away
    property double closedAt: 0
    function close() {
        if (visible)
            closedAt = Date.now();
        showLater.stop();
        grab.active = false;
        visible = false;
    }
    function toggle() {
        if (visible || showLater.running)
            close();
        else if (Date.now() - closedAt > 300)
            open();
    }

    HyprlandFocusGrab {
        id: grab
        windows: [root]
        onCleared: root.close()
    }

    Glass {
        id: surface
        width: parent.width
        height: root.panelHeight
        clip: true
        backdropScreen: root.backdropScreen
        Behavior on height {
            enabled: root.visible
            NumberAnimation { duration: Config.reduceMotion ? 0 : 220; easing.type: Easing.OutCubic }
        }
    }
}

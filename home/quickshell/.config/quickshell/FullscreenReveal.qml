import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// The menu bar and the dock over an app in full screen, like on a Mac: while an app fills
// a screen (F11), they are hidden there; pushing the pointer against that screen's top
// (menu bar) or bottom edge (dock) brings them over the app until the pointer has left
// them. The edge is noticed by riptide-wm (window_buttons.cpp: "fullscreen-edge") – nothing
// of ours lies over the app's own edge.
//   layer   for WlrLayershell.layer: above the full-screen app while it is there
//   shown   for visible
//   hold    while it must stay: the pointer on it, a menu open, an icon dragged
Scope {
    id: root

    required property var screen
    property string edge: "top" // "top" | "bottom"
    property bool hold: false

    readonly property bool fullscreen: Hyprland.monitorFor(screen)?.activeWorkspace?.hasFullscreen ?? false
    property bool revealed: false
    readonly property bool shown: !fullscreen || revealed
    readonly property int layer: fullscreen ? WlrLayer.Overlay : WlrLayer.Top

    onFullscreenChanged: revealed = false
    onHoldChanged: {
        if (hold) {
            hide.stop();
        } else if (revealed) {
            hide.interval = 700;
            hide.restart();
        }
    }
    Timer {
        id: hide
        onTriggered: if (!root.hold) root.revealed = false
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "custom" || event.data !== `fullscreen-edge>>${root.edge}>>${root.screen?.name}` || !root.fullscreen)
                return;
            root.revealed = true;
            // time to reach it from the edge (the dock's plate sits a little above it)
            hide.interval = 1500;
            if (!root.hold)
                hide.restart();
        }
    }
}

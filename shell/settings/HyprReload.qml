pragma Singleton

import QtQuick
import Quickshell

// Hyprland reads settings.json in its Lua config; after a change it has to reload.
// Collects quick changes (dragging a slider) into one reload.
Singleton {
    id: root

    property bool monitors: false

    function soon(withMonitors) {
        monitors = monitors || withMonitors === true;
        timer.restart();
    }

    Timer {
        id: timer
        interval: 200
        onTriggered: {
            Quickshell.execDetached(root.monitors ? ["hyprctl", "reload"] : ["hyprctl", "reload", "config-only"]);
            root.monitors = false;
        }
    }
}

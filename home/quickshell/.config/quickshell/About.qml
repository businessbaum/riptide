pragma Singleton

import Quickshell

// "Über diesen Computer" (AboutWindow.qml), opened from the Apple menu
Singleton {
    property bool open: false

    function show() {
        if (open) // already open: to the front
            Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ window = \"title:^Über diesen Computer$\" })"]);
        open = true;
    }
}

pragma Singleton

import Quickshell

// "Über „App“" (AppInfoWindow.qml), opened from the app menu in the menu bar
Singleton {
    property var entry: null // the app's desktop entry; null = closed

    function show(e) {
        if (entry && e && entry.id === e.id) // already open: to the front
            Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.focus({ window = "title:^Über ${e.name}$" })`]);
        entry = e;
    }
}

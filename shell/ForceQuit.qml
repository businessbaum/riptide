pragma Singleton

import Quickshell

// "Sofort beenden": the window (ForceQuitWindow.qml, ⌥⌘⎋ and the Apple menu) and ending
// an app at once, all of its processes (scripts/force-quit.sh)
Singleton {
    property bool open: false

    function show() {
        if (open) // already open: to the front
            Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ window = \"title:^Sofort beenden$\" })"]);
        open = true;
    }

    // every window class of the app
    function quit(classes) {
        for (const c of classes)
            Quickshell.execDetached([Quickshell.shellPath("scripts/force-quit.sh"), c]);
    }
}

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The lock: LockScreen.qml shows the login window over everything, Hyprland shows nothing
// else and takes no shortcuts until the password is given.
//
// At boot the session starts locked – that is the login, like on a Mac: greetd logs the
// person in (its initial session, /usr/local/lib/riptide/greeter/session-locked) and leaves
// the marker $XDG_RUNTIME_DIR/riptide/start-locked. Until the password: Hyprland without
// any shortcut (hyprland.lua), menu bar and dock only once the lock is confirmed and under
// it (shell.qml), no login items (xdg-desktop-autostart.target), no apps. After it the
// marker goes, Hyprland loads its shortcuts, the login items and the apps of the last
// session open – the desktop was there behind the login window all along.
//   qs ipc call lock now      lock the screen (⌘L, ⌃⌘Q, hot corner, hypridle)
Singleton {
    id: root

    readonly property string runtime: Quickshell.env("XDG_RUNTIME_DIR") + "/riptide"
    readonly property string marker: runtime + "/start-locked"
    property bool locked: false
    property bool secure: false   // Hyprland confirmed the lock
    property bool loggedIn: true  // the password was given this session (not yet at boot)
    readonly property bool desktopAllowed: loggedIn || secure

    // the person, for the login window: the name from /etc/passwd, else the login name
    readonly property string user: Quickshell.env("USER") ?? ""
    property string displayName: user.charAt(0).toUpperCase() + user.slice(1)

    function lock() {
        locked = true;
    }

    // LockScreen.qml, after the password (and the fade)
    function unlocked() {
        locked = false;
        if (loggedIn)
            return;
        loggedIn = true;
        // in this order: the marker first, then Hyprland reloads with its shortcuts
        Quickshell.execDetached(["sh", "-c", 'rm -f "$1" "$2"; hyprctl reload >/dev/null; '
            + "systemctl --user start xdg-desktop-autostart.target", "sh", marker, runtime + "/lock-shown"]);
    }

    onSecureChanged: {
        // for the session's watchdog (session-locked): the login window came up
        if (secure && !loggedIn)
            Quickshell.execDetached(["touch", runtime + "/lock-shown"]);
    }

    FileView {
        path: root.marker
        blockLoading: true
        printErrors: false
        onLoaded: {
            root.loggedIn = false;
            root.locked = true;
        }
    }
    FileView {
        path: "/etc/passwd"
        blockLoading: true
        onLoaded: {
            for (const line of text().split("\n")) {
                const f = line.split(":");
                const full = (f[4] ?? "").split(",")[0].trim();
                if (f[0] === root.user && full !== "")
                    root.displayName = full;
            }
        }
    }

    IpcHandler {
        target: "lock"
        function now(): void {
            root.lock();
        }
    }
}

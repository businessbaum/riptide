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

    readonly property string runtime: (Quickshell.env("XDG_RUNTIME_DIR") ?? "") + "/riptide"
    readonly property string marker: runtime + "/start-locked"
    property bool locked: false
    property bool secure: false   // Hyprland confirmed the lock
    // Fail-closed: nothing counts as logged in until it is certain that this is no locked
    // start – the marker's answer comes only after the shell is built (FileView), and in
    // that moment neither the apps of the last session nor menu bar and dock may start
    property bool loggedIn: false // the password was given, or it was a normal login
    // menu bar, dock and the rest: once allowed (logged in, or under the confirmed lock)
    // they stay – unlocking must not rebuild them
    property bool desktopAllowed: false
    onLoggedInChanged: if (loggedIn) desktopAllowed = true

    // the person, for the login window: the name from /etc/passwd, else the login name
    readonly property string user: Quickshell.env("USER") ?? ""
    property string displayName: user.charAt(0).toUpperCase() + user.slice(1)

    function lock() {
        locked = true;
    }

    // LockScreen.qml, after the password (and the fade)
    function unlocked() {
        const first = !loggedIn;
        loggedIn = true; // (before unlocking: nothing is taken down in between)
        locked = false;
        // in this order: the markers first; at boot then Hyprland reloads with its
        // shortcuts and the login items held back start (their target refuses a manual
        // start: each one, by its name as systemd's generator wrote it); then drives that
        // came in while locked are mounted (Riptide "drives.mount", drives.py)
        afterUnlock.command = ["sh", "-c", 'rm -f "$1" "$2" "$3"; [ "$4" = 1 ] || exit 0; hyprctl reload >/dev/null; '
            + 'for f in "$XDG_RUNTIME_DIR"/systemd/generator.late/xdg-desktop-autostart.target.wants/*.service; do '
            + '[ -e "$f" ] && systemctl --user start --no-block -- "${f##*/}"; done', "sh",
            runtime + "/locked", marker, runtime + "/lock-shown", first ? "1" : "0"];
        afterUnlock.running = true;
    }
    Process {
        id: afterUnlock
        onExited: Riptide.call("drives.mount", {})
    }

    // for the session service: no drives are mounted while locked (drives.py)
    onLockedChanged: {
        if (locked)
            Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && touch "$1/locked"', "sh", runtime]);
    }

    onSecureChanged: {
        if (!secure)
            return;
        desktopAllowed = true; // created under the lock
        // for the session's watchdog (session-locked): the login window came up
        if (!loggedIn)
            Quickshell.execDetached(["touch", runtime + "/lock-shown"]);
    }

    // Hyprland that crashed while locked is started again locked (start-hyprland adds
    // --locked): then this lock screen takes over at once – otherwise there would be a
    // locked screen with nothing to unlock it (allow_session_lock_restore, hyprland.lua)
    Process {
        running: true
        command: ["sh", "-c", 'for p in $(pgrep -u "$(id -u)" -x Hyprland); do tr "\\0" " " < "/proc/$p/cmdline"; done']
        stdout: StdioCollector {
            onStreamFinished: {
                if (/(^| )--locked( |$)/.test(text))
                    root.locked = true;
            }
        }
    }

    // a locked start or not (without a runtime folder: locked, never open by mistake)
    Component.onCompleted: if (!Quickshell.env("XDG_RUNTIME_DIR")) locked = true
    FileView {
        path: root.marker
        blockLoading: true
        printErrors: false
        onLoaded: root.locked = true
        onLoadFailed: {
            if (Quickshell.env("XDG_RUNTIME_DIR"))
                root.loggedIn = true; // no marker: a normal login (with the password)
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

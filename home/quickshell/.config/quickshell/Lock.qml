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
//   qs ipc call lock now      lock the screen, animated (⌘L, ⌃⌘Q, hot corner, idle)
//   qs ipc call lock instant  lock at once (hypridle before sleep)
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

    // how the lock screen comes and goes (LockScreen.qml): animated from the desktop; at
    // boot, after a crash and before sleep it simply is there
    property bool animateIn: false
    // menu bar and dock: after the login at boot they arrive once the lock screen is gone
    property bool arrived: true

    function lock() {
        if (locked)
            return;
        animateIn = true;
        locked = true;
    }
    // before sleep: at once – no half-faded screen when waking up
    function lockNow() {
        animateIn = false;
        locked = true;
    }

    // LockScreen.qml, the moment the password is right – before its animation, so that at
    // boot the apps already start loading behind it
    function passwordAccepted() {
        if (loggedIn)
            return;
        loggedIn = true;
        // in this order: the marker first, then Hyprland reloads with its shortcuts (still
        // locked: they wait), then the login items held back (their target refuses a manual
        // start: each one, by its name as systemd's generator wrote it)
        Quickshell.execDetached(["sh", "-c", 'rm -f "$1" "$2"; hyprctl reload >/dev/null; '
            + 'for f in "$XDG_RUNTIME_DIR"/systemd/generator.late/xdg-desktop-autostart.target.wants/*.service; do '
            + '[ -e "$f" ] && systemctl --user start --no-block -- "${f##*/}"; done', "sh", marker, runtime + "/lock-shown"]);
    }

    // LockScreen.qml, after its animation
    function unlocked() {
        passwordAccepted();
        locked = false;
        arrived = true;
        // drives that came in while locked are mounted now (Riptide "drives.mount", drives.py)
        afterUnlock.running = true;
    }
    Process {
        id: afterUnlock
        command: ["rm", "-f", root.runtime + "/locked"]
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
        onLoaded: {
            root.arrived = false;
            root.locked = true;
        }
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
        // hypridle before sleep (scripts/hypridle-config.py)
        function instant(): void {
            root.lockNow();
        }
    }
}

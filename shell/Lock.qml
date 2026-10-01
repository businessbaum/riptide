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
// session open – the desktop was there behind the login window all along. Like on a Mac
// the login window stays a moment longer for that, with a progress bar: until every one
// of those apps shows a window, at most 15 s (an app that never opens must not keep
// anyone out), then it fades into the finished desktop.
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

    // After the password at a locked start: the desktop is prepared under the lock
    // (LockScreen.qml shows `progress`, fades out on ready())
    property bool preparing: false
    property real progress: 0
    signal ready
    property double allOpenSince: 0
    // the login items (~/.config/autostart, without hidden ones): they open themselves,
    // the apps of the last session through Session.qml
    property var loginItems: []
    property bool loginItemsRead: false
    // the apps waited for: login items and the apps of the last session that exist
    function awaited() {
        const keys = [];
        for (const id of loginItems.concat(Session.reopenIds)) {
            const entry = Apps.entryById(id);
            if (entry && !keys.includes(entry.id))
                keys.push(entry.id);
        }
        return keys;
    }

    // the person, for the login window: the name from /etc/passwd, else the login name
    readonly property string user: Quickshell.env("USER") ?? ""
    property string displayName: user.charAt(0).toUpperCase() + user.slice(1)

    function lock() {
        locked = true;
    }

    // LockScreen.qml, after the password at a locked start: still locked, the desktop is
    // made ready behind the login window. In this order: the markers first, then Hyprland
    // reloads with its shortcuts (they work only once the lock is gone) and the login
    // items held back start (their target refuses a manual start: each one, by its name
    // as systemd's generator wrote it); the apps of the last session follow (Session.qml,
    // on loggedIn). Drives stay unmounted until the lock is gone (the marker "locked").
    function prepare() {
        if (loggedIn)
            return ready();
        loggedIn = true;
        preparing = true;
        progress = 0;
        allOpenSince = 0;
        startDesktop.running = true;
        prepareTick.start();
        prepareLimit.start();
    }
    function finishPreparing() {
        if (!preparing || (!prepareTick.running && !prepareLimit.running))
            return; // (once)
        prepareTick.stop();
        prepareLimit.stop();
        progress = 1;
        ready();
    }
    // the limit on its own, without the counting: whatever happens, after 15 s it opens
    Timer {
        id: prepareLimit
        interval: 15000
        onTriggered: {
            let waiting = "?";
            try {
                waiting = root.awaited().filter(k => Apps.windowsOf(k).length === 0).join(", ");
            } catch (e) {}
            console.warn("lock: desktop not ready after 15 s, unlocking; without a window:", waiting);
            root.finishPreparing();
        }
    }
    Process {
        id: startDesktop
        command: ["sh", "-c", 'rm -f "$1" "$2"; hyprctl reload >/dev/null; '
            + 'for f in "$XDG_RUNTIME_DIR"/systemd/generator.late/xdg-desktop-autostart.target.wants/*.service; do '
            + '[ -e "$f" ] && systemctl --user start --no-block -- "${f##*/}"; done', "sh",
            root.marker, root.runtime + "/lock-shown"]
    }
    Timer {
        id: prepareTick
        interval: 250
        repeat: true
        onTriggered: {
            const keys = root.awaited();
            const waiting = keys.filter(k => Apps.windowsOf(k).length === 0);
            const known = root.loginItemsRead && Session.reopenRead;
            root.progress = keys.length > 0 ? (keys.length - waiting.length) / keys.length : (known ? 1 : 0);
            if (!known || waiting.length > 0) {
                root.allOpenSince = 0;
                return;
            }
            // every app open: a moment more for their first picture and their place
            // (window memory), then into the desktop
            if (root.allOpenSince === 0)
                root.allOpenSince = Date.now();
            else if (Date.now() - root.allOpenSince >= 700)
                root.finishPreparing();
        }
    }

    // LockScreen.qml, after the fade: the lock goes; then drives that came in while
    // locked are mounted (Riptide "drives.mount", drives.py)
    function unlocked() {
        if (!loggedIn) { // (never without prepare(); if it happens, the desktop starts now)
            loggedIn = true;
            startDesktop.running = true;
        }
        preparing = false;
        locked = false;
        afterUnlock.command = ["rm", "-f", runtime + "/locked"];
        afterUnlock.running = true;
    }
    Process {
        id: afterUnlock
        onExited: Riptide.call("drives.mount", {})
    }
    Process {
        running: true
        command: ["sh", "-c", 'for f in "$HOME"/.config/autostart/*.desktop; do [ -f "$f" ] && ! grep -qx "Hidden=true" "$f" && basename "$f" .desktop; done; true']
        stdout: StdioCollector {
            onStreamFinished: {
                root.loginItems = text.split("\n").filter(l => l !== "");
                root.loginItemsRead = true;
            }
        }
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
    // locked when the shell restarted or reloaded: stays locked (the new lock takes over
    // the old one – unlocked, it would open the screen)
    FileView {
        path: root.runtime + "/locked"
        blockLoading: true
        printErrors: false
        onLoaded: root.locked = true
    }
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

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The one connection to the session's system services (riptide-session, see
// ~/.local/lib/desktop_shell/session.py): permissions, app sandboxes, … Every part of the
// shell and of System Settings talks to the system through here.
//
//   Riptide.call("permissions.set", { app, kind, state }, result => …)
//   signals: connected(result of hello), event(message)
//   role: "shell" for the main shell (it gets the questions apps ask), else "settings"
Singleton {
    id: root

    property string role: "settings"
    readonly property bool ready: !!socket?.connected && greeted
    property bool greeted: false

    signal hello(var result)
    signal event(var message)

    property int nextId: 1
    property var pending: ({}) // id → callback

    function call(name, params, done) {
        const id = nextId++;
        if (done)
            pending[id] = done;
        if (!socket)
            return;
        socket.write(JSON.stringify(Object.assign({ id: id, call: name }, params ?? {})) + "\n");
        socket.flush();
    }

    function greet() {
        greeted = false;
        call("hello", { role: role }, result => {
            greeted = true;
            root.hello(result);
        });
    }
    onRoleChanged: if (socket?.connected) greet()

    readonly property string socketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/riptide/session.sock"

    // The connection, made anew for every attempt (see retry)
    readonly property var socket: link.item
    LazyLoader {
        id: link
        active: true

        Socket {
            path: root.socketPath
            connected: true
            onConnectedChanged: {
                if (connected)
                    Qt.callLater(root.greet); // (link.item is set only after this)
                else
                    root.greeted = false;
            }
            onError: root.greeted = false // e.g. the service restarted: connect again (retry)
            parser: SplitParser {
                onRead: line => {
                    let message;
                    try {
                        message = JSON.parse(line);
                    } catch (e) {
                        return;
                    }
                    if (message.event) {
                        root.event(message);
                    } else if (message.id !== undefined) {
                        const done = root.pending[message.id];
                        delete root.pending[message.id];
                        if (message.error)
                            console.warn("riptide-session:", message.error);
                        else if (done)
                            done(message.result);
                    }
                }
            }
        }
    }

    // For troubleshooting:  qs ipc call riptide status
    IpcHandler {
        target: "riptide"
        function status(): string {
            return JSON.stringify({ connected: !!root.socket?.connected, greeted: root.greeted, retrying: retry.running, role: root.role });
        }
    }

    // Not connected and greeted (the service restarted or is not up yet): try again every
    // 2 s with a new socket – a socket whose peer went away may still count as connected,
    // and one that once failed to find the service (it was down) never connects again
    Timer {
        id: retry
        interval: 2000
        repeat: true
        running: !root.greeted
        onTriggered: {
            link.active = false;
            link.active = true;
        }
    }
}

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

// The login itself (greetd): who logs in, the password, what went wrong. The person who
// logged in last is chosen (on a computer of one: always that one); "Anderer Benutzer"
// types another name. After the login greetd starts the session – uwsm → Hyprland, as
// before from the text console.
Singleton {
    id: root

    readonly property string stateDir: Quickshell.env("XDG_RUNTIME_DIR") + "/riptide-greeter"
    readonly property var session: ["uwsm", "start", "-e", "-D", "Hyprland", "hyprland.desktop"]

    // people who can log in: /etc/passwd, uid 1000 and up with a real shell
    property var users: []
    property string lastUser: ""
    readonly property var chosen: users.find(u => u.name === lastUser) ?? users[0] ?? null
    property bool other: false // "Anderer Benutzer …": the name is typed
    property string otherName: ""
    readonly property string userName: other ? otherName.trim() : (chosen?.name ?? "")
    readonly property string displayName: other ? "Anderer Benutzer" : (chosen?.display ?? "")

    property bool busy: false
    property string error: ""
    property int failures: 0 // the password field shakes when it changes
    property string pending: ""

    function login(password) {
        if (busy || userName === "")
            return;
        error = "";
        if (!Greetd.available) {
            error = "Der Anmeldedienst ist nicht erreichbar.";
            return;
        }
        busy = true;
        pending = password;
        Greetd.createSession(userName);
    }

    function power(action) {
        Quickshell.execDetached(["systemctl", action]);
    }

    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                Greetd.respond(root.pending);
                root.pending = "";
            } else if (error) {
                root.error = message;
            }
        }
        function onAuthFailure(message) {
            root.busy = false;
            root.pending = "";
            root.error = "Falsches Passwort.";
            root.failures++;
        }
        function onReadyToLaunch() {
            lastUserFile.setText(root.userName + "\n");
            // tells the start script that the session follows (no text login)
            Quickshell.execDetached(["touch", root.stateDir + "/launched"]);
            Greetd.launch(root.session, [], true);
        }
        function onError(error) {
            root.busy = false;
            root.pending = "";
            root.error = "Die Anmeldung ist nicht möglich: " + error;
        }
    }

    FileView {
        path: "/etc/passwd"
        blockLoading: true
        onLoaded: {
            const list = [];
            for (const line of text().split("\n")) {
                const f = line.split(":");
                const uid = parseInt(f[2]);
                if (f.length < 7 || uid < 1000 || uid >= 60000 || /(nologin|false)$/.test(f[6]))
                    continue;
                const full = (f[4] ?? "").split(",")[0].trim();
                list.push({ name: f[0], display: full || f[0].charAt(0).toUpperCase() + f[0].slice(1) });
            }
            root.users = list;
        }
    }
    // (written by the greeter; setup-os.sh creates the folder for the user "greeter")
    FileView {
        id: lastUserFile
        path: "/var/lib/riptide/greeter/last-user"
        blockLoading: true
        printErrors: false
        atomicWrites: true
        onLoaded: root.lastUser = text().trim()
    }
}

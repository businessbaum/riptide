pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// App permissions (docs/os-plan.md): what each app may use, kept in the system's
// permission store (app-permissions). When an app wants something it was not given yet,
// request() asks – "„Discord“ möchte auf das Mikrofon zugreifen." – and stores the answer.
// The sandbox, PipeWire and the notification server act on it.
//
//   Privacy.state(app, kind)            "yes" | "no" | "ask" (not decided yet)
//   Privacy.request(app, kind, done)    ask, once at a time per app and kind; done(state)
//   Privacy.set(app, kind, state)       change it (System Settings)
//   From outside (sandbox, sound):      qs ipc call privacy request <app> <kind>
Singleton {
    id: root

    readonly property string tool: Quickshell.env("HOME") + "/.local/bin/app-permissions"

    property var kinds: ({})   // key → { label, description, question, how, applies }
    property var kindList: []  // the same in their order
    property var states: ({})  // app → { kind → state }
    property var waiting: ({}) // "app kind" → [done callbacks] while the question is open

    function state(app, kind) {
        return states[app]?.[kind] ?? "ask";
    }

    function request(app, kind, done) {
        const now = state(app, kind);
        if (now !== "ask") {
            done?.(now);
            return;
        }
        const key = `${app} ${kind}`;
        if (waiting[key]) {
            if (done)
                waiting[key].push(done);
            return;
        }
        waiting = Object.assign({}, waiting, { [key]: done ? [done] : [] });
        const k = kinds[kind];
        Confirm.request({
            app: app,
            title: `„${Apps.name(app)}“ möchte ${k?.question ?? kind}.`,
            text: (k?.applies === "restart" ? "Gilt ab dem nächsten Start der App. " : "")
                + "Du kannst das jederzeit in den Systemeinstellungen unter „Datenschutz & Sicherheit“ ändern.",
            button: "Erlauben",
            cancel: "Nicht erlauben",
            action: () => root.answered(app, kind, "yes"),
            cancelled: () => root.answered(app, kind, "no")
        });
    }

    function answered(app, kind, value) {
        set(app, kind, value);
        const key = `${app} ${kind}`;
        const callbacks = waiting[key] ?? [];
        const rest = Object.assign({}, waiting);
        delete rest[key];
        waiting = rest;
        for (const done of callbacks)
            done(value);
    }

    function set(app, kind, value) {
        states = Object.assign({}, states, { [app]: Object.assign({}, states[app], { [kind]: value }) });
        Quickshell.execDetached([tool, "set", app, kind, value]);
    }

    Process {
        command: [root.tool, "kinds"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const list = JSON.parse(text);
                    root.kindList = list;
                    const byKey = {};
                    for (const k of list)
                        byKey[k.key] = k;
                    root.kinds = byKey;
                } catch (e) {}
            }
        }
    }

    Process {
        id: load
        command: [root.tool, "list"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.states = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    // Read again whenever the store changes (System Settings, a portal, another app)
    Process {
        command: ["gdbus", "monitor", "--session", "--dest", "org.freedesktop.impl.portal.PermissionStore"]
        running: true
        stdout: SplitParser {
            onRead: reload.restart()
        }
    }
    Timer {
        id: reload
        interval: 300
        onTriggered: load.running = true
    }

    IpcHandler {
        target: "privacy"

        function request(app: string, kind: string): void {
            root.request(app, kind, null);
        }
        function state(app: string, kind: string): string {
            return root.state(app, kind);
        }
    }
}

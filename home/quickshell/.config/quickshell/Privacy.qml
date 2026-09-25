pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// App permissions (docs/os-plan.md): what each app may use. The decisions live in the
// system's permission store and come from the session service (Riptide.qml); when an app
// wants something it was not given yet, request() asks – "„Discord“ möchte auf das
// Mikrofon zugreifen." – and the answer goes back to the service. The sandbox, PipeWire
// and the notification server act on it.
//
//   Privacy.state(app, kind)            "yes" | "no" | "ask" (not decided yet)
//   Privacy.request(app, kind, done)    ask, once at a time per app and kind; done(state)
//   Privacy.set(app, kind, state)       change it (System Settings)
// The service sends the questions of the sandbox and the sound system to the shell.
Singleton {
    id: root

    property var kinds: ({})   // key → { label, description, question, how, applies, … }
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

    // A question of the portal (camera, running in the background, …), same dialog
    property var portalShown: ({}) // numbers already on screen (they come again on reconnect)
    function portalQuestion(q) {
        if (portalShown[q.pick])
            return;
        portalShown[q.pick] = true;
        Confirm.request({
            app: q.app,
            title: q.title,
            text: q.text,
            button: q.grant,
            cancel: q.deny,
            action: () => Riptide.call("access.answered", { pick: q.pick, granted: true }),
            cancelled: () => Riptide.call("access.answered", { pick: q.pick, granted: false })
        });
    }

    function set(app, kind, value) {
        states = Object.assign({}, states, { [app]: Object.assign({}, states[app], { [kind]: value }) });
        Riptide.call("permissions.set", { app: app, kind: kind, state: value });
    }

    Connections {
        target: Riptide
        function onHello(result) {
            root.kindList = result.kinds;
            const byKey = {};
            for (const k of result.kinds)
                byKey[k.key] = k;
            root.kinds = byKey;
            root.states = result.states;
        }
        function onEvent(message) {
            if (message.event === "permissions")
                root.states = message.states;
            else if (message.event === "request")
                root.request(message.app, message.kind, null);
            else if (message.event === "access")
                root.portalQuestion(message);
        }
    }

    IpcHandler {
        target: "privacy"

        function request(app: string, kind: string): void {
            Riptide.call("permissions.request", { app: app, kind: kind });
        }
        function state(app: string, kind: string): string {
            return root.state(app, kind);
        }
    }
}

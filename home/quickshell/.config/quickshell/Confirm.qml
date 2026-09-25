pragma Singleton

import Quickshell
import Quickshell.Io

// Every question the system asks goes through here, one after the other, and shows as
// the dialog in ConfirmDialog.qml – like the macOS alert "Möchtest du den Computer jetzt
// ausschalten?" or "„Discord“ möchte auf das Mikrofon zugreifen."
//
//   Confirm.ask(title, text, button, action)          confirm or cancel
//   Confirm.request({ title, text, button, cancel, app, action, cancelled })
//       cancel     label of the other button (default "Abbrechen")
//       app        desktop id: shows the app's icon above the question
//       cancelled  called for the other button and for Esc
// From a script (tests): qs ipc call confirm cancel – there is deliberately no way to
// confirm from outside; granting something always takes a click.
Singleton {
    id: root

    // Waiting questions; the first one is on screen
    property var queue: []
    readonly property var current: queue.length > 0 ? queue[0] : null
    readonly property bool open: current !== null

    function ask(title, text, button, action) {
        request({ title, text, button, action });
    }

    function request(question) {
        queue = queue.concat([question]);
    }

    function answer(ok) {
        const question = current;
        queue = queue.slice(1);
        if (ok)
            question?.action?.();
        else
            question?.cancelled?.();
    }

    IpcHandler {
        target: "confirm"

        function cancel(): void {
            if (root.open)
                root.answer(false);
        }
    }
}

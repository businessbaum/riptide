pragma Singleton

import Quickshell

// State of the confirmation dialog (ConfirmDialog.qml), like the macOS sheet
// "Möchtest du den Computer jetzt ausschalten?".
Singleton {
    property bool open: false
    property string title: ""
    property string text: ""
    property string button: ""
    property var action: null

    function ask(title_, text_, button_, action_) {
        title = title_;
        text = text_;
        button = button_;
        action = action_;
        open = true;
    }

    function answer(ok) {
        open = false;
        if (ok)
            action?.();
        action = null;
    }
}

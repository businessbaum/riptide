pragma Singleton

import QtQuick
import Quickshell

// The sounds a notification can make (freedesktop sound theme), shared by the shell
// (NotificationStore.qml plays them) and System Settings (choosing one) – without
// starting a notification server there.
Singleton {
    readonly property string dir: "/usr/share/sounds/freedesktop/stereo/"
    readonly property var list: [
        { value: "message", text: "Nachricht" }, { value: "message-new-instant", text: "Sofortnachricht" },
        { value: "bell", text: "Glocke" }, { value: "complete", text: "Fertig" },
        { value: "dialog-information", text: "Hinweis" }, { value: "none", text: "Kein Ton" }
    ]
    function play(name) {
        if (name && name !== "none")
            Quickshell.execDetached(["pw-play", dir + name + ".oga"]);
    }
}

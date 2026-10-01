pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Small tools of the system, used from the control centre and keys:
//   screenshot(kind)  like ⌘⇧3 / ⌘⇧4 (hypr/scripts/screenshot.sh: "screen" or "area")
//   pickColour()      the colour under the pointer (hyprpicker), copied as #RRGGBB
Singleton {
    id: root

    function screenshot(kind) {
        Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/screenshot.sh", kind]);
    }

    function pickColour() {
        if (!picker.running)
            picker.running = true;
    }
    Process {
        id: picker
        command: ["hyprpicker", "--autocopy", "--format=hex", "--quiet"]
        stdout: StdioCollector {
            onStreamFinished: {
                const colour = text.trim().toUpperCase();
                if (/^#[0-9A-F]{6}$/.test(colour))
                    Banners.show({ key: "colour", glyph: "\u{f020a}", title: colour, subtitle: "Farbe kopiert" });
            }
        }
    }

    IpcHandler {
        target: "tools"
        function colour(): void {
            root.pickColour();
        }
    }
}

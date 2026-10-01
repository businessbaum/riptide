pragma Singleton

import QtQuick
import Quickshell

// External drives (USB sticks, disks) as the session service sees them (drives.py): a
// banner when one is plugged in, the eject symbol in the menu bar while one is mounted
// (MenuBar.qml), ejecting it safely.
Singleton {
    id: root

    property var list: [] // [{ id, name, mount, size, fs }]

    Connections {
        target: Riptide
        function onEvent(message) {
            if (message.event !== "drives")
                return;
            root.list = message.drives;
            const added = message.drives.find(d => d.id === message.added);
            if (added)
                Banners.show({
                    key: "drive:" + added.id,
                    glyph: "\u{f02ca}",
                    title: added.name,
                    subtitle: "Verbunden · " + root.size(added.size)
                });
        }
    }

    // 64 GB, 1,8 TB (like the Finder: powers of ten)
    function size(bytes) {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let v = bytes, i = 0;
        while (v >= 1000 && i < units.length - 1) {
            v /= 1000;
            i++;
        }
        return v.toLocaleString(Qt.locale("de_DE"), "f", v < 10 && i > 0 ? 1 : 0) + " " + units[i];
    }

    function open(drive) {
        Quickshell.execDetached(["xdg-open", drive.mount]);
    }

    function eject(drive) {
        Riptide.call("drives.eject", { id: drive.id }, result => {
            if (result?.error)
                Notify.send(`„${drive.name}“ wurde nicht ausgeworfen`, result.error, false);
            else
                Banners.show({
                    key: "drive:" + drive.id,
                    glyph: "\u{f02ca}",
                    title: drive.name,
                    subtitle: "Kann jetzt entfernt werden"
                });
        });
    }
}

import QtQuick
import Quickshell
import Quickshell.Io

// "Logitech Unifying Receiver · Verbunden" at the top right when a USB device is plugged in,
// like the Bluetooth banners (BluetoothBanners.qml). Hubs stay quiet; what the device is
// comes from its interface classes (keyboard, mouse, sound, camera, phone, storage).
// Source: udev's events (udevadm monitor), whole USB devices only.
Scope {
    id: root

    // a USB interface class (ID_USB_INTERFACES ":030101:…") → symbol and kind
    function glyph(interfaces) {
        if (interfaces.includes(":030101:"))
            return "\u{f030c}"; // keyboard
        if (interfaces.includes(":030102:"))
            return "\u{f037d}"; // mouse
        const classes = interfaces.split(":").filter(c => c).map(c => c.slice(0, 2));
        const has = c => classes.includes(c);
        return has("01") ? "\u{f02cb}"   // sound
            : has("0e") ? "\u{f0567}"    // camera
            : has("06") || has("02") ? "\u{f011c}" // phone (photos, modem)
            : has("08") ? "\u{f02ca}"    // storage
            : has("07") ? "\u{f042a}"    // printer
            : has("03") ? "\u{f0297}"    // other input (game controller)
            : "\u{f0553}";               // USB
    }

    // "Logitech, Inc." + "Unifying Receiver" → "Logitech Unifying Receiver"
    function name(p) {
        const clean = s => (s ?? "").replace(/_/g, " ").replace(/\s*\[.*?\]\s*/g, " ").trim();
        const model = clean(p.ID_MODEL_FROM_DATABASE) || clean(p.ID_MODEL);
        const vendor = (clean(p.ID_VENDOR_FROM_DATABASE) || clean(p.ID_VENDOR)).replace(/,?\s*(Inc|Ltd|Co|Corp|Corporation|GmbH)\.?$/i, "").split(/[ ,]/)[0];
        if (!model)
            return vendor ? vendor + "-Gerät" : "USB-Gerät";
        return vendor && !model.toLowerCase().includes(vendor.toLowerCase()) ? vendor + " " + model : model;
    }

    // Blocks of KEY=value lines, one per event, ending with an empty line
    property var block: ({})
    function event(p) {
        if (p.ACTION !== "add" || p.DEVTYPE !== "usb_device")
            return;
        const interfaces = p.ID_USB_INTERFACES ?? "";
        if (/:09/.test(interfaces) || p.ID_USB_CLASS_FROM_DATABASE === "Hub")
            return; // a hub
        Banners.show({
            key: "usb:" + (p.DEVPATH ?? ""),
            glyph: root.glyph(interfaces),
            title: root.name(p),
            subtitle: "Verbunden"
        });
    }

    Process {
        running: true
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=usb/usb_device", "--property"]
        stdout: SplitParser {
            onRead: line => {
                if (line === "") {
                    root.event(root.block);
                    root.block = {};
                    return;
                }
                const i = line.indexOf("=");
                if (i > 0)
                    root.block[line.slice(0, i)] = line.slice(i + 1);
            }
        }
    }
}

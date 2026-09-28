pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Brightness of the screens, set in the screens themselves (DDC/CI through ddcutil – no
// dimming by the graphics card): the control centre shows one slider for all and, unfolded,
// one per screen; the brightness keys change all of them (Osd.qml shows it).
// A setting takes the screen ~0.3 s: while a slider moves, each screen gets only the
// newest value, one at a time.
//   displays  [{ name: "DP-2", bus: 7, model: "BenQ EX2710Q", value: 0–100 }]
Singleton {
    id: root

    property var displays: []
    readonly property bool available: displays.length > 0
    readonly property real average: available ? displays.reduce((s, d) => s + d.value, 0) / displays.length : 0
    signal stepped // a key changed it: the OSD shows it

    function detect() {
        detector.running = true;
    }
    Component.onCompleted: detect()
    // screens plugged in or out
    Connections {
        target: Quickshell
        function onScreensChanged() {
            redetect.restart();
        }
    }
    Timer {
        id: redetect
        interval: 3000
        onTriggered: root.detect()
    }

    // "Display 1 / I2C bus: /dev/i2c-7 / DRM connector: card2-DP-2 / Monitor: BNQ:BenQ EX2710Q:K6R…"
    // (--syslog ERROR: else every call writes its guesses about the screens to the journal;
    // written apart: "--syslog=ERROR" is not taken – tested with ddcutil 3.0.2)
    Process {
        id: detector
        command: ["ddcutil", "detect", "--brief", "--syslog", "ERROR"]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = [];
                for (const block of text.split(/\n(?=Display \d+)/)) {
                    const bus = block.match(/I2C bus:\s+\/dev\/i2c-(\d+)/);
                    const drm = block.match(/DRM connector:\s+card\d+-(\S+)/);
                    const model = block.match(/Monitor:\s+[^:]*:([^:]*):/);
                    if (bus && drm)
                        found.push({ name: drm[1], bus: +bus[1], model: model ? model[1] : drm[1], value: 100 });
                }
                root.displays = found;
                reader.next = 0;
                reader.readNext();
            }
        }
    }
    // the current values, one screen after the other
    Process {
        id: reader
        property int next: 0
        function readNext() {
            if (next >= root.displays.length)
                return;
            command = ["ddcutil", "--bus", String(root.displays[next].bus), "getvcp", "10", "--brief", "--syslog", "ERROR"];
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/VCP 10 C (\d+) (\d+)/); // current, maximum
                if (m && reader.next < root.displays.length)
                    root.update(reader.next, Math.round(100 * +m[1] / Math.max(1, +m[2])));
                reader.next++;
                reader.readNext();
            }
        }
    }

    function update(i, value) {
        const list = displays.slice();
        list[i] = Object.assign({}, list[i], { value: value });
        displays = list;
    }

    function set(name, value) {
        const i = displays.findIndex(d => d.name === name);
        if (i < 0)
            return;
        const v = Math.round(Math.max(0, Math.min(100, value)));
        update(i, v);
        writers.objectAt(i)?.push(v);
    }
    function setAll(value) {
        for (const d of displays)
            set(d.name, value);
    }
    // keys: a sixteenth of the way, like a Mac
    function step(up) {
        setAll(Math.round(average) + (up ? 6.25 : -6.25));
        stepped();
    }

    Instantiator {
        id: writers
        model: root.displays.length
        delegate: Process {
            required property int index
            property int wanted: -1
            function push(v) {
                wanted = v;
                if (!running)
                    send();
            }
            function send() {
                if (wanted < 0 || !root.displays[index])
                    return;
                command = ["ddcutil", "--bus", String(root.displays[index].bus), "setvcp", "10", String(wanted), "--noverify", "--syslog", "ERROR"];
                wanted = -1;
                running = true;
            }
            onExited: send()
        }
    }

    IpcHandler {
        target: "brightness"
        function up(): void {
            root.step(true);
        }
        function down(): void {
            root.step(false);
        }
        function get(): string {
            return JSON.stringify(root.displays);
        }
    }
}

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs

Page {
    id: page
    title: "Bildschirme"
    property var window

    // Current state straight from Hyprland (name, make, model, modes, scale)
    property var monitors: []
    Process {
        id: query
        running: true
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.monitors = JSON.parse(text);
                } catch (e) {
                    page.monitors = [];
                }
            }
        }
    }
    // Ask again after a change has been applied
    Timer {
        id: requery
        interval: 1200
        onTriggered: query.running = true
    }

    Repeater {
        model: page.monitors

        Group {
            id: group
            required property var modelData
            readonly property string name: modelData.name
            readonly property var saved: Config.settings.monitors?.[name] ?? {}
            // "2560x1440@165.00Hz" -> "2560x1440@165.00"; highest refresh first per resolution
            readonly property var modes: [...new Set((modelData.availableModes ?? []).map(m => m.replace(/Hz$/, "")))]
            readonly property string currentMode: `${modelData.width}x${modelData.height}@${Number(modelData.refreshRate).toFixed(2)}`

            function save(key, value) {
                Config.updateSettings(s => {
                    s.monitors = s.monitors ?? {};
                    s.monitors[group.name] = s.monitors[group.name] ?? {};
                    s.monitors[group.name][key] = value;
                });
                HyprReload.soon(true);
                requery.restart();
            }

            title: `${modelData.make ?? ""} ${modelData.model ?? ""}`.trim() || name
            description: `${name} · ${modelData.width} × ${modelData.height}`

            SettingRow {
                first: true
                title: "Auflösung"
                Choice {
                    window: page.window
                    options: group.modes.map(m => ({ value: m, text: m.replace("x", " × ").replace("@", "  ·  ").replace(/\.\d+$/, "") + " Hz" }))
                    current: group.saved.mode ?? group.currentMode
                    onPicked: v => group.save("mode", v)
                }
            }
            SettingRow {
                title: "Skalierung"
                subtitle: "Größere Werte machen Schrift und Bedienelemente größer"
                Choice {
                    window: page.window
                    options: [{ value: 1, text: "100 %" }, { value: 1.25, text: "125 %" }, { value: 1.5, text: "150 %" }, { value: 2, text: "200 %" }]
                    current: group.saved.scale ?? group.modelData.scale
                    onPicked: v => group.save("scale", v)
                }
            }
        }
    }
}

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

            // (make is often the maker's three-letter code: "BNQ" for "BenQ EX2710Q")
            title: `${/^[A-Z]{3}$/.test(modelData.make ?? "") ? "" : modelData.make ?? ""} ${modelData.model ?? ""}`.trim() || name
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

    // Night Shift (NightShift.qml in the shell applies it; switched by hand in the control
    // centre). Temperature: 2700 K warm … 5500 K a little.
    readonly property var nightShift: Config.settings.nightshift ?? ({})
    readonly property var nightHours: Array.from({ length: 24 }, (_, h) => ({ value: h, text: (h < 10 ? "0" : "") + h + ":00" }))
    function setNightShift(key, value) {
        Config.updateSettings(s => {
            s.nightshift = s.nightshift ?? {};
            s.nightshift[key] = value;
            if (key !== "temperature")
                s.nightshift.override = null; // a new schedule decides again
        });
    }

    Group {
        title: "Night Shift"
        description: "Macht die Farben am Abend wärmer, damit das Licht der Bildschirme weniger blendet. "
            + "Im Kontrollzentrum kannst du es jederzeit von Hand ein- und ausschalten."
        SettingRow {
            first: true
            title: "Nach Zeitplan"
            Row {
                spacing: 8
                Choice {
                    visible: page.nightShift.schedule === true
                    window: page.window
                    options: page.nightHours
                    current: page.nightShift.from ?? 22
                    onPicked: v => page.setNightShift("from", v)
                }
                Text {
                    visible: page.nightShift.schedule === true
                    anchors.verticalCenter: parent.verticalCenter
                    text: "bis"
                    font.family: Config.fontSans
                    font.pixelSize: 12
                    color: Config.textSecondary
                }
                Choice {
                    visible: page.nightShift.schedule === true
                    window: page.window
                    options: page.nightHours
                    current: page.nightShift.to ?? 7
                    onPicked: v => page.setNightShift("to", v)
                }
                Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: page.nightShift.schedule === true
                    onToggled: on => page.setNightShift("schedule", on)
                }
            }
        }
        SettingRow {
            title: "Farbtemperatur"
            subtitle: "Weniger warm ↔ Wärmer"
            Slider {
                width: 220
                // right = warmer (lower Kelvin)
                from: -5500
                to: -2700
                stepSize: 100
                value: -(page.nightShift.temperature ?? 3800)
                onMoved: v => page.setNightShift("temperature", -v)
            }
        }
    }
}

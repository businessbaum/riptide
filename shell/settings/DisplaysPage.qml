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

            title: page.monitorLabel(modelData)
            description: `${name} · ${modelData.width} × ${modelData.height}` + (modelData.description === Config.settings.displays?.main ? " · Hauptbildschirm" : "")

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

    // ---------------------------------------------------------------- main screen, lock screen
    // The main screen is kept as Hyprland's description (maker, model, serial number): the
    // connector names change between starts (MainScreen.qml in the shell uses it)

    // "BenQ EX2710Q", with left/right when two look alike (make is often the maker's
    // three-letter code: "BNQ" for "BenQ EX2710Q")
    function monitorLabel(m) {
        const base = `${/^[A-Z]{3}$/.test(m.make ?? "") ? "" : m.make ?? ""} ${m.model ?? ""}`.trim() || m.name;
        const others = monitors.filter(o => o.model === m.model && o.name !== m.name);
        if (others.length === 0)
            return base;
        return base + (others.every(o => o.x > m.x) ? " – links" : others.every(o => o.x < m.x) ? " – rechts" : " – " + m.name);
    }
    readonly property var lock: Config.settings.lockscreen ?? ({})
    function setLock(key, value) {
        Config.updateSettings(s => {
            s.lockscreen = s.lockscreen ?? {};
            s.lockscreen[key] = value;
        });
    }
    function setAside(key, on) {
        Config.updateSettings(s => {
            s.lockscreen = s.lockscreen ?? {};
            s.lockscreen.aside = s.lockscreen.aside ?? {};
            s.lockscreen.aside[key] = on;
        });
    }

    // the place for the weather: searched by name (Weather.qml, Open-Meteo)
    property var places: []
    property bool placeSearching: false
    property string placeError: ""
    function findPlace(name) {
        if (name.trim() === "" || placeSearching)
            return;
        placeSearching = true;
        placeError = "";
        Weather.search(name.trim(), list => {
            placeSearching = false;
            places = list ?? [];
            placeError = list === null ? "Keine Verbindung zum Wetterdienst." : list.length === 0 ? "Kein Ort mit diesem Namen gefunden." : "";
        });
    }

    Group {
        visible: page.monitors.length > 1
        title: "Hauptbildschirm"
        description: "Hier erscheinen beim Sperren und Anmelden das Passwortfeld und der Anmeldebildschirm."
        SettingRow {
            first: true
            title: "Hauptbildschirm"
            Choice {
                window: page.window
                options: [{ value: "", text: "Der mit dem Mauszeiger" }].concat(page.monitors.map(m => ({ value: m.description, text: page.monitorLabel(m) })))
                current: Config.settings.displays?.main ?? ""
                onPicked: v => {
                    Config.updateSettings(s => {
                        s.displays = s.displays ?? {};
                        s.displays.main = v;
                    });
                    HyprReload.soon(); // hypr/modules/greeter.lua leaves it for the login screen
                }
            }
        }
    }

    Group {
        visible: page.monitors.length > 1
        title: "Sperrbildschirm auf den anderen Bildschirmen"
        description: "Unter der Uhr, nur zum Ansehen: Solange gesperrt ist, lässt sich dort nichts bedienen."
        SettingRow {
            first: true
            glyph: "\u{f0595}"
            glyphColour: "#0a84ff"
            title: "Wetter"
            subtitle: page.lock.place ? page.lock.place.name + " · von Open-Meteo, übertragen wird nur der Ort" : "Wähle zuerst unten einen Ort"
            Toggle {
                enabled: page.lock.place !== undefined && page.lock.place !== null
                checked: enabled && page.lock.aside?.weather !== false
                onToggled: on => page.setAside("weather", on)
            }
        }
        SettingRow {
            glyph: "\u{f00ed}"
            glyphColour: "#ff453a"
            title: "Kalender"
            subtitle: "Der aktuelle Monat"
            Toggle {
                checked: page.lock.aside?.calendar !== false
                onToggled: on => page.setAside("calendar", on)
            }
        }
        SettingRow {
            glyph: "\u{f075a}"
            glyphColour: "#ff375f"
            title: "Musik"
            subtitle: "Was gerade läuft oder pausiert ist"
            Toggle {
                checked: page.lock.aside?.media !== false
                onToggled: on => page.setAside("media", on)
            }
        }
        SettingRow {
            title: "Ort fürs Wetter"
            subtitle: page.placeError !== "" ? page.placeError : "Name der Stadt, dann Suchen"
            Row {
                spacing: 8
                Field {
                    id: placeField
                    implicitWidth: 180
                    placeholder: page.lock.place?.name ?? "z. B. München"
                    onAccepted: page.findPlace(text)
                }
                DialogButton {
                    implicitWidth: 90
                    width: implicitWidth
                    text: page.placeSearching ? "Suche …" : "Suchen"
                    onClicked: page.findPlace(placeField.text)
                }
            }
        }
        Repeater {
            model: page.places
            SettingRow {
                required property var modelData
                title: modelData.name
                subtitle: modelData.region
                DialogButton {
                    implicitWidth: 90
                    width: implicitWidth
                    primary: true
                    text: "Wählen"
                    onClicked: {
                        page.setLock("place", { name: modelData.name, lat: modelData.lat, lon: modelData.lon });
                        page.places = [];
                        placeField.text = "";
                    }
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

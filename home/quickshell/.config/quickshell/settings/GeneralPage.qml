import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

// "Allgemein", like on a Mac: an overview leading to Info (what this computer is, its
// name), Datum & Uhrzeit and Sprache & Region – and on to Speicher, Anmeldeobjekte and
// the updates in the App Store.
//   From outside:  … call settings page general/about  (or general/datetime, general/language)
// Reads scripts/general.py and scripts/system-info.py. Changes go through timedatectl,
// hostnamectl and localectl: systemd asks for the password with our polkit dialog.
Page {
    id: page
    property var window
    property string selected: ""

    readonly property var subpages: ({
        about: "Info",
        datetime: "Datum & Uhrzeit",
        language: "Sprache & Region"
    })
    title: subpages[selected] ?? "Allgemein"

    // ---------------------------------------------------------------- reading

    property var info: ({})                               // general.py
    property var system: ({ name: "", system: "", rows: [] }) // system-info.py
    property var zones: []                                // [[zone, "UTC+2"], …], when changing it
    property string error: ""

    function load() {
        reader.running = true;
    }
    Component.onCompleted: {
        load();
        systemReader.running = true;
    }

    Process {
        id: reader
        command: ["python3", Quickshell.shellPath("scripts/general.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.info = JSON.parse(text);
                } catch (e) {}
            }
        }
    }
    Process {
        id: systemReader
        command: ["python3", Quickshell.shellPath("scripts/system-info.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.system = JSON.parse(text);
                } catch (e) {}
            }
        }
    }
    Process {
        id: zoneReader
        command: ["python3", Quickshell.shellPath("scripts/general.py"), "zones"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.zones = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    // ---------------------------------------------------------------- changing

    // One change at a time; its output and exit code come back together
    Process {
        id: change
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const code = (lines.pop() ?? "").replace("exit:", "");
                page.error = code === "0" ? "" : page.explain(lines.join("\n"));
                page.load();
                systemReader.running = true;
            }
        }
    }
    function run(argv) {
        error = "";
        change.command = ["sh", "-c", "\"$@\" 2>&1; echo \"exit:$?\"", "sh"].concat(argv);
        change.running = true;
    }
    function explain(text) {
        if (/access denied|not authorized|interactive authentication/i.test(text))
            return "Nicht geändert: Dafür ist dein Passwort nötig.";
        return "Nicht geändert: " + (text.trim().split("\n").pop() || "unbekannter Fehler");
    }

    function rename(name) {
        const n = name.trim().replace(/[\x00-\x1f\x7f]/g, "");
        if (n === "" || n.length > 64 || n === (info.prettyName || info.hostname))
            return;
        run(["hostnamectl", "hostname", n]);
    }

    // "27.09.2026 14:30" → timedatectl (only while not set automatically)
    function setTime(text) {
        const m = text.trim().match(/^(\d{1,2})\.(\d{1,2})\.(\d{4})\s+(\d{1,2}):(\d{2})$/);
        const two = n => String(n).padStart(2, "0");
        if (!m || +m[1] < 1 || +m[1] > 31 || +m[2] < 1 || +m[2] > 12 || +m[4] > 23 || +m[5] > 59) {
            error = "Bitte so eingeben: 27.09.2026 14:30";
            return;
        }
        run(["timedatectl", "set-time", `${m[3]}-${two(m[2])}-${two(m[1])} ${two(m[4])}:${m[5]}:00`]);
    }

    // Language (LANG) and region (formats of dates, numbers, money, measures, paper)
    readonly property var regionKeys: ["LC_TIME", "LC_NUMERIC", "LC_MONETARY", "LC_MEASUREMENT", "LC_PAPER"]
    readonly property string lang: info.locale?.LANG ?? "de_DE.UTF-8"
    readonly property string region: info.locale?.LC_TIME ?? lang
    function setLocale(language, reg) {
        const vars = ["LANG=" + language];
        if (reg !== language)
            vars.push(...regionKeys.map(k => k + "=" + reg));
        // what was set elsewhere stays (LC_COLLATE, LANGUAGE …)
        for (const [k, v] of Object.entries(info.locale ?? {}))
            if (k !== "LANG" && !regionKeys.includes(k))
                vars.push(k + "=" + v);
        run(["localectl", "set-locale"].concat(vars));
    }
    function qtLocale(name) {
        return Qt.locale(name.split(".")[0]);
    }

    // Time zones: "Europe/Berlin" → "Berlin"; a few German names find their zone
    function cityOf(zone) {
        return zone.split("/").pop().replace(/_/g, " ");
    }
    property bool pickingZone: false
    property string zoneQuery: ""
    readonly property var germanNames: ({
        "wien": "vienna", "zürich": "zurich", "rom": "rome", "moskau": "moscow", "prag": "prague",
        "warschau": "warsaw", "kopenhagen": "copenhagen", "lissabon": "lisbon", "brüssel": "brussels",
        "athen": "athens", "kairo": "cairo", "peking": "shanghai", "tokio": "tokyo", "neu-delhi": "kolkata",
        "mexiko": "mexico_city", "new york": "new_york", "los angeles": "los_angeles", "kiew": "kyiv"
    })
    readonly property var zoneMatches: {
        let q = zoneQuery.trim().toLowerCase();
        q = (germanNames[q] ?? q).replace(/ /g, "_");
        return q === "" ? [] : zones.filter(z => z[0].toLowerCase().includes(q)).slice(0, 40);
    }

    // a row with a value on the right
    component ValueRow: SettingRow {
        id: valueRow
        property string value
        Text {
            text: valueRow.value
            width: Math.min(implicitWidth, 380)
            horizontalAlignment: Text.AlignRight
            wrapMode: Text.Wrap
            font.family: Config.fontSans
            font.pixelSize: 13
            color: Config.textSecondary
        }
    }

    // ---------------------------------------------------------------- overview

    Group {
        visible: page.selected === ""
        SettingRow {
            first: true
            glyph: ""
            title: "Info"
            subtitle: page.system.name
            link: true
            onClicked: page.selected = "about"
        }
        SettingRow {
            glyph: "\u{f06b0}"
            title: "Softwareupdate"
            subtitle: "Updates für Apps und System im App Store"
            link: true
            onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/app-store.sh"), "updates"])
        }
        SettingRow {
            glyph: ""
            title: "Speicher"
            link: true
            onClicked: page.window.page = "storage"
        }
    }
    Group {
        visible: page.selected === ""
        SettingRow {
            first: true
            glyph: "\u{f0342}"
            title: "Anmeldeobjekte"
            link: true
            onClicked: page.window.page = "login"
        }
        SettingRow {
            glyph: ""
            glyphColour: "#0a84ff"
            title: "Datum & Uhrzeit"
            subtitle: page.info.timezone ? page.cityOf(page.info.timezone) + " · " + page.info.offset : ""
            link: true
            onClicked: page.selected = "datetime"
        }
        SettingRow {
            glyph: ""
            glyphColour: "#0a84ff"
            title: "Sprache & Region"
            subtitle: page.qtLocale(page.lang).nativeLanguageName
            link: true
            onClicked: page.selected = "language"
        }
    }

    // ---------------------------------------------------------------- one part

    Text {
        visible: page.selected !== ""
        text: "\u{f0141} Allgemein"
        font.family: Config.fontSans
        font.pixelSize: 13
        color: back.containsMouse ? Config.text : Config.accent
        MouseArea {
            id: back
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                page.selected = "";
                page.error = "";
            }
        }
    }
    Text {
        visible: page.error !== "" && page.selected !== ""
        Layout.fillWidth: true
        text: page.error
        wrapMode: Text.Wrap
        font.family: Config.fontSans
        font.pixelSize: 13
        color: "#ff453a"
    }

    // ---------------------------------------------------------------- Info

    Item {
        visible: page.selected === "about"
        Layout.fillWidth: true
        implicitHeight: header.implicitHeight

        Column {
            id: header
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4

            ComputerPicture {
                anchors.horizontalCenter: parent.horizontalCenter
                size: 170
            }
            Item {
                width: 1
                height: 8
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.system.name
                font.family: Config.fontSans
                font.pixelSize: 22
                font.weight: Font.DemiBold
                color: Config.text
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.system.rows.find(r => r[0] === "Computer")?.[1] ?? ""
                font.family: Config.fontSans
                font.pixelSize: 13
                color: Config.textSecondary
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.system.system
                font.family: Config.fontSans
                font.pixelSize: 13
                color: Config.textSecondary
            }
        }
    }

    Group {
        visible: page.selected === "about"
        description: !page.info.hostname ? ""
            : page.info.mdns ? "Andere Geräte im lokalen Netzwerk finden diesen Computer als „" + page.info.hostname + ".local“."
            : "Im Netzwerk heißt er „" + page.info.hostname + "“."
        SettingRow {
            first: true
            title: "Name"
            Field {
                implicitWidth: 240
                text: page.info.prettyName || page.info.hostname || ""
                input.onEditingFinished: page.rename(text)
                onCancelled: text = page.info.prettyName || page.info.hostname || ""
            }
        }
    }

    Group {
        visible: page.selected === "about"
        Repeater {
            model: page.system.rows.filter(r => r[0] !== "Computer")
            ValueRow {
                required property var modelData
                required property int index
                first: index === 0
                title: modelData[0]
                value: modelData[1]
            }
        }
    }

    Group {
        visible: page.selected === "about"
        SettingRow {
            first: true
            title: "Systembericht"
            subtitle: "Alle Angaben oben als Text – etwa für eine Frage in einem Forum"
            DialogButton {
                id: copyButton
                property bool done: false
                implicitWidth: 100
                width: implicitWidth
                text: done ? "Kopiert" : "Kopieren"
                onClicked: {
                    Quickshell.execDetached(["sh", "-c", "python3 \"$1\" --text | wl-copy", "sh",
                        Quickshell.shellPath("scripts/system-info.py")]);
                    done = true;
                    copied.restart();
                }
                Timer {
                    id: copied
                    interval: 2000
                    onTriggered: copyButton.done = false
                }
            }
        }
        SettingRow {
            title: "Fehlerberichte"
            subtitle: "Was auf diesem Computer zuletzt schiefging, an einem Ort gesammelt"
            DialogButton {
                implicitWidth: 100
                width: implicitWidth
                text: "Öffnen"
                onClicked: Quickshell.execDetached(["sh", "-c",
                    "riptide-report --quiet; xdg-open \"$HOME/.local/state/macos/reports/$(date +%F).md\""])
            }
        }
    }

    // ---------------------------------------------------------------- Datum & Uhrzeit

    Group {
        visible: page.selected === "datetime"
        SettingRow {
            first: true
            title: "Datum und Uhrzeit automatisch einstellen"
            subtitle: !page.info.ntp ? "" : page.info.synced
                ? "Mit einem Zeitserver im Internet abgeglichen" + (page.info.server ? " (" + page.info.server + ")" : "")
                : "Wird mit einem Zeitserver im Internet abgeglichen …"
            Toggle {
                checked: page.info.ntp ?? false
                enabled: page.info.canNtp ?? false
                onToggled: on => page.run(["timedatectl", "set-ntp", on ? "true" : "false"])
            }
        }
        SettingRow {
            visible: page.info.ntp === false
            title: "Datum und Uhrzeit"
            subtitle: "Eingeben, dann ⏎"
            Field {
                id: timeField
                implicitWidth: 150
                placeholder: "27.09.2026 14:30"
                onAccepted: t => page.setTime(t)
                onVisibleChanged: if (visible) text = Qt.formatDateTime(new Date(), "dd.MM.yyyy HH:mm")
            }
        }
        SettingRow {
            title: "24-Stunden-Format"
            Toggle {
                checked: Store.get("clock", "hours24", true)
                onToggled: on => Store.set("clock", "hours24", on)
            }
        }
    }

    Group {
        visible: page.selected === "datetime"
        title: "Zeitzone"
        SettingRow {
            first: true
            title: page.info.timezone ? page.cityOf(page.info.timezone) : ""
            subtitle: page.info.timezone ? page.info.timezone + " · " + page.info.offset : ""
            DialogButton {
                implicitWidth: 90
                width: implicitWidth
                text: page.pickingZone ? "Fertig" : "Ändern …"
                onClicked: {
                    page.pickingZone = !page.pickingZone;
                    if (page.pickingZone) {
                        if (page.zones.length === 0)
                            zoneReader.running = true;
                        zoneSearch.text = "";
                        zoneSearch.edit();
                    }
                }
            }
        }
        SettingRow {
            visible: page.pickingZone
            title: ""
            Field {
                id: zoneSearch
                placeholder: "Stadt suchen, z. B. Berlin"
                input.onTextChanged: page.zoneQuery = text
                onCancelled: page.pickingZone = false
            }
        }
        Repeater {
            model: page.pickingZone ? page.zoneMatches : []
            SettingRow {
                required property var modelData
                title: page.cityOf(modelData[0])
                subtitle: modelData[0] + " · " + modelData[1]
                link: true
                onClicked: {
                    page.run(["timedatectl", "set-timezone", modelData[0]]);
                    page.pickingZone = false;
                }
            }
        }
    }

    Group {
        visible: page.selected === "datetime"
        title: "Uhr in der Menüleiste"
        description: "So sieht sie aus: " + new Date().toLocaleString(Qt.locale(), Config.clockFormat)
        SettingRow {
            first: true
            title: "Wochentag anzeigen"
            Toggle {
                checked: Store.get("clock", "weekday", true)
                onToggled: on => Store.set("clock", "weekday", on)
            }
        }
        SettingRow {
            title: "Datum anzeigen"
            Toggle {
                checked: Store.get("clock", "date", true)
                onToggled: on => Store.set("clock", "date", on)
            }
        }
        SettingRow {
            title: "Sekunden anzeigen"
            Toggle {
                checked: Store.get("clock", "seconds", false)
                onToggled: on => Store.set("clock", "seconds", on)
            }
        }
    }

    Group {
        visible: page.selected === "datetime"
        description: "Windows stellt die eingebaute Uhr des Computers auf Ortszeit, Linux auf Weltzeit (UTC). "
            + "Läuft auf diesem Computer auch Windows, lass es eingeschaltet – sonst geht die Uhr nach jedem Wechsel falsch."
        SettingRow {
            first: true
            title: "Hardware-Uhr in Ortszeit"
            Toggle {
                checked: page.info.localRtc ?? false
                onToggled: on => page.run(["timedatectl", "set-local-rtc", on ? "1" : "0"])
            }
        }
    }

    // ---------------------------------------------------------------- Sprache & Region

    Group {
        visible: page.selected === "language"
        description: "Gilt für alle Apps ab der nächsten Anmeldung."
        SettingRow {
            first: true
            title: "Sprache"
            Choice {
                window: page.window
                options: (page.info.locales ?? []).map(l => ({ value: l, text: page.qtLocale(l).nativeLanguageName }))
                current: page.lang
                onPicked: v => page.setLocale(v, page.region)
            }
        }
        SettingRow {
            title: "Region"
            subtitle: "Wie Datum, Zahlen, Währung und Maße geschrieben werden"
            Choice {
                window: page.window
                options: (page.info.locales ?? []).map(l => ({ value: l, text: page.qtLocale(l).nativeTerritoryName }))
                current: page.region
                onPicked: v => page.setLocale(page.lang, v)
            }
        }
    }

    Group {
        visible: page.selected === "language"
        id: preview
        title: "So sieht es aus"
        readonly property var loc: page.qtLocale(page.region)
        readonly property date now: new Date()
        ValueRow {
            first: true
            title: "Datum"
            value: preview.now.toLocaleDateString(preview.loc, Locale.LongFormat)
        }
        ValueRow {
            title: "Kurz"
            value: preview.now.toLocaleDateString(preview.loc, Locale.ShortFormat)
                + ", " + preview.now.toLocaleTimeString(preview.loc, Locale.ShortFormat)
        }
        ValueRow {
            title: "Zahlen"
            value: Number(1234567.89).toLocaleString(preview.loc, "f", 2)
        }
        ValueRow {
            title: "Währung"
            value: Number(1234.56).toLocaleCurrencyString(preview.loc)
        }
        ValueRow {
            title: "Maße"
            value: preview.loc.measurementSystem === Locale.MetricSystem
                ? "Metrisch (Meter, Kilogramm, °C)" : "Angloamerikanisch (Fuß, Pfund, °F)"
        }
        ValueRow {
            title: "Erster Tag der Woche"
            value: Qt.locale("de_DE").dayName(preview.loc.firstDayOfWeek, Locale.LongFormat)
        }
    }
}

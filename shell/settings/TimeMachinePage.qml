import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

// "Time Machine", like on a Mac: backups to an external disk (encrypted, hourly, kept
// hourly/daily/weekly) and the hourly snapshots on this computer; earlier versions open in
// Finder. Everything through riptide-timemachine (desktop_shell/timemachine.py); the
// backup itself runs as riptide-backup.service.
Page {
    id: page
    title: "Time Machine"
    property var window

    readonly property var tm: Config.settings.timemachine ?? ({})
    property var info: ({ volume: null, mounted: false, state: {}, local: [], backups: [], exclude: [], keep: {} })
    property var volumes: []       // external drives that could take backups
    property bool choosing: false  // picking a backup disk
    property string chosenUuid: ""
    property string error: ""
    readonly property string cli: Config.bin + "riptide-timemachine"

    function load(withBackups) {
        reader.command = [page.cli, "status"].concat(withBackups ? ["--with-backups"] : []);
        reader.running = true;
    }
    Component.onCompleted: load(true)
    Process {
        id: reader
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.info = JSON.parse(text);
                } catch (e) {}
            }
        }
    }
    // progress while a backup runs
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/macos/timemachine.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const s = JSON.parse(text());
                const ended = page.info.state?.running && !s.running;
                page.info = Object.assign({}, page.info, { state: s });
                if (ended)
                    page.load(true);
            } catch (e) {}
        }
    }
    Process {
        id: volumeReader
        command: [page.cli, "volumes"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.volumes = JSON.parse(text);
                } catch (e) {
                    page.volumes = [];
                }
            }
        }
    }
    // the password goes on stdin (never on a command line others could read)
    Process {
        id: setup
        stdinEnabled: true
        property string input: ""
        onStarted: {
            write(input);
            input = "";
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try {
                    r = JSON.parse(text);
                } catch (e) {}
                page.error = r.error ?? "";
                if (r.volume) {
                    Store.set("timemachine", "volume", r.volume);
                    page.choosing = false;
                    page.chosenUuid = "";
                    page.load(true);
                }
            }
        }
    }
    function useVolume(uuid, password) {
        error = "";
        setup.command = ["sh", "-c", "read -r pw; printf '%s' \"$pw\" | \"$2\" setup \"$1\"", "sh", uuid, cli];
        setup.input = password + "\n";
        setup.running = true;
    }
    Process {
        id: action
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.error = JSON.parse(text).error ?? "";
                } catch (e) {}
                page.load(false);
            }
        }
    }
    function run(args) {
        error = "";
        action.command = [page.cli].concat(args);
        action.running = true;
    }
    function backupNow() {
        Quickshell.execDetached(["systemd-run", "--user", "--collect", "--quiet", "--unit=riptide-backup-now",
            "-p", "Nice=19", "-p", "IOSchedulingClass=idle", page.cli, "backup"]);
    }

    // "vor 5 Min.", "heute, 14:02", "12.09.2026, 09:00"
    function when(date) {
        if (!date)
            return "";
        const d = typeof date === "number" ? new Date(date * 1000) : new Date(date.replace(" ", "T"));
        const minutes = Math.round((Date.now() - d.getTime()) / 60000);
        if (minutes < 60)
            return minutes <= 1 ? "gerade eben" : `vor ${minutes} Min.`;
        if (d.toDateString() === new Date().toDateString())
            return "heute, " + Qt.formatTime(d, "HH:mm");
        return Qt.formatDateTime(d, "dd.MM.yyyy, HH:mm");
    }
    function size(bytes) {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let v = bytes ?? 0, i = 0;
        while (v >= 1000 && i < units.length - 1) {
            v /= 1000;
            i++;
        }
        return v.toLocaleString(Qt.locale("de_DE"), "f", v < 10 && i > 0 ? 1 : 0) + " " + units[i];
    }
    function setKeep(key, value) {
        Store.set("timemachine", "keep", Object.assign({}, page.tm.keep ?? {}, { [key]: value }));
    }
    readonly property var exclude: page.tm.exclude ?? page.info.exclude ?? []
    function setExclude(list) {
        Store.set("timemachine", "exclude", list);
    }
    // earlier versions, newest first: on this computer and on the backup disk
    readonly property var points: (page.info.local ?? []).map(p => Object.assign({ where: "Auf diesem Computer" }, p))
        .concat((page.info.backups ?? []).map(p => Object.assign({ where: "Auf „" + (page.info.volume?.name ?? "") + "“" }, p)))
        .sort((a, b) => b.date.localeCompare(a.date)).slice(0, 40)

    Text {
        visible: page.error !== ""
        Layout.fillWidth: true
        text: page.error
        wrapMode: Text.Wrap
        font.family: Config.fontSans
        font.pixelSize: 13
        color: "#ff453a"
    }

    // ---------------------------------------------------------------- state

    Group {
        SettingRow {
            first: true
            glyph: "\u{f02da}"
            glyphColour: page.info.state?.error ? "#ff9f0a" : "#30d158"
            title: page.info.state?.running
                ? `Sichert … ${Math.round((page.info.state.progress ?? 0) * 100)} %`
                : page.info.state?.last ? "Letzte Sicherung: " + page.when(page.info.state.last) : "Noch keine Sicherung"
            subtitle: page.info.state?.running
                ? `${page.size(page.info.state.bytesDone)} von ${page.size(page.info.state.bytesTotal)}`
                : page.info.state?.error ? page.info.state.error
                : !page.info.volume ? "Wähle ein Sicherungsvolume, damit Time Machine deine Dateien sichert."
                : page.info.mounted ? `Auf „${page.info.volume.name}“ · ${page.size(page.info.disk?.free)} frei`
                : `„${page.info.volume.name}“ ist nicht angeschlossen – gesichert wird, sobald es wieder da ist.`
            DialogButton {
                visible: page.info.volume !== null && page.info.mounted && !page.info.state?.running
                implicitWidth: 120
                width: implicitWidth
                primary: true
                text: "Jetzt sichern"
                onClicked: page.backupNow()
            }
        }
    }

    // ---------------------------------------------------------------- the backup disk

    Group {
        title: "Sicherungsvolume"
        description: "Die Sicherung ist mit deinem Passwort verschlüsselt. Ohne es kann niemand sie lesen – auch du nicht: "
            + "bewahre es gut auf. Es liegt zusätzlich im Schlüsselbund dieses Computers."
        SettingRow {
            first: true
            visible: page.info.volume !== null
            glyph: "\u{f02ca}"
            title: page.info.volume?.name ?? ""
            subtitle: page.info.mounted ? "Angeschlossen" : "Nicht angeschlossen"
            DialogButton {
                implicitWidth: 100
                width: implicitWidth
                text: "Entfernen …"
                onClicked: Confirm.ask(`„${page.info.volume.name}“ nicht mehr für Time Machine verwenden?`,
                    "Die Sicherungen darauf bleiben erhalten.", "Nicht mehr verwenden", () => {
                        page.run(["forget-volume"]);
                        Store.set("timemachine", "volume", null);
                    })
            }
        }
        SettingRow {
            first: page.info.volume === null
            visible: page.info.volume === null
            glyph: "+"
            glyphColour: Config.accent
            title: page.choosing ? "Laufwerk wählen" : "Sicherungsvolume hinzufügen …"
            link: !page.choosing
            onClicked: {
                page.choosing = true;
                volumeReader.running = true;
            }
            DialogButton {
                visible: page.choosing
                implicitWidth: 90
                width: implicitWidth
                text: "Abbrechen"
                onClicked: {
                    page.choosing = false;
                    page.chosenUuid = "";
                }
            }
        }
        SettingRow {
            visible: page.choosing && page.volumes.length === 0
            title: "Kein externes Laufwerk angeschlossen"
            subtitle: "Schließe eine Festplatte oder SSD an – sie erscheint dann hier."
            DialogButton {
                implicitWidth: 100
                width: implicitWidth
                text: "Neu laden"
                onClicked: volumeReader.running = true
            }
        }
        Repeater {
            model: page.choosing ? page.volumes : []
            SettingRow {
                required property var modelData
                glyph: "\u{f02ca}"
                title: modelData.name
                subtitle: `${page.size(modelData.size)} · ${page.size(modelData.free)} frei · ${modelData.fs}`
                DialogButton {
                    visible: page.chosenUuid !== modelData.uuid
                    implicitWidth: 100
                    width: implicitWidth
                    text: "Verwenden"
                    onClicked: page.chosenUuid = modelData.uuid
                }
            }
        }
        // the password for the chosen disk (new backup: twice)
        SettingRow {
            visible: page.chosenUuid !== ""
            title: "Passwort"
            subtitle: "Mindestens 8 Zeichen. Für eine vorhandene Sicherung: ihr Passwort."
            Row {
                spacing: 8
                Field {
                    id: pw1
                    implicitWidth: 150
                    placeholder: "Passwort"
                    input.echoMode: TextInput.Password
                }
                Field {
                    id: pw2
                    implicitWidth: 150
                    placeholder: "Wiederholen"
                    input.echoMode: TextInput.Password
                    onAccepted: useButton.clicked()
                }
                DialogButton {
                    id: useButton
                    implicitWidth: 90
                    width: implicitWidth
                    primary: true
                    text: setup.running ? "…" : "Sichern"
                    onClicked: {
                        if (pw1.text !== pw2.text) {
                            page.error = "Die Passwörter sind nicht gleich.";
                            return;
                        }
                        page.useVolume(page.chosenUuid, pw1.text);
                        pw1.text = "";
                        pw2.text = "";
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- when and how long

    Group {
        title: "Optionen"
        SettingRow {
            first: true
            title: "Automatisch sichern"
            Choice {
                window: page.window
                options: [
                    { value: "hourly", text: "Stündlich" },
                    { value: "daily", text: "Täglich" },
                    { value: "weekly", text: "Wöchentlich" },
                    { value: "manual", text: "Nur von Hand" }
                ]
                current: page.tm.schedule ?? "hourly"
                onPicked: v => Store.set("timemachine", "schedule", v)
            }
        }
        SettingRow {
            title: "Stündliche Sicherungen behalten"
            Choice {
                window: page.window
                options: [{ value: 24, text: "24 Stunden" }, { value: 48, text: "48 Stunden" }, { value: 0, text: "Keine" }]
                current: page.tm.keep?.hourly ?? 24
                onPicked: v => page.setKeep("hourly", v)
            }
        }
        SettingRow {
            title: "Tägliche Sicherungen behalten"
            Choice {
                window: page.window
                options: [{ value: 7, text: "1 Woche" }, { value: 14, text: "2 Wochen" }, { value: 31, text: "1 Monat" },
                    { value: 90, text: "3 Monate" }]
                current: page.tm.keep?.daily ?? 31
                onPicked: v => page.setKeep("daily", v)
            }
        }
        SettingRow {
            title: "Wöchentliche Sicherungen behalten"
            Choice {
                window: page.window
                options: [{ value: 12, text: "3 Monate" }, { value: 52, text: "1 Jahr" }, { value: 104, text: "2 Jahre" },
                    { value: 520, text: "Alle" }]
                current: page.tm.keep?.weekly ?? 520
                onPicked: v => page.setKeep("weekly", v)
            }
        }
    }

    Group {
        title: "Nicht sichern"
        description: "Zwischenspeicher und Papierkorb sichert Time Machine nie. Ordner, die du hier nennst, auch nicht."
        Repeater {
            model: page.exclude
            SettingRow {
                required property var modelData
                required property int index
                first: index === 0
                glyph: "\u{f024b}"
                glyphColour: "#8e8e93"
                title: modelData.replace(/^~\//, "")
                DialogButton {
                    implicitWidth: 90
                    width: implicitWidth
                    text: "Entfernen"
                    onClicked: page.setExclude(page.exclude.filter(p => p !== modelData))
                }
            }
        }
        SettingRow {
            first: page.exclude.length === 0
            title: "Ordner ausschließen"
            Row {
                spacing: 8
                Field {
                    id: excludeField
                    implicitWidth: 220
                    placeholder: "~/Downloads"
                    onAccepted: addExclude.clicked()
                }
                DialogButton {
                    id: addExclude
                    implicitWidth: 90
                    width: implicitWidth
                    text: "Hinzufügen"
                    onClicked: {
                        let p = excludeField.text.trim();
                        if (p === "")
                            return;
                        if (!p.startsWith("~/") && !p.startsWith("/"))
                            p = "~/" + p;
                        if (!page.exclude.includes(p))
                            page.setExclude(page.exclude.concat([p]));
                        excludeField.text = "";
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- earlier versions

    Group {
        title: "Frühere Versionen"
        description: "Öffne einen Zeitpunkt im Finder und kopiere, was du zurück möchtest. Auf diesem Computer: stündlich "
            + "die letzten 24 Stunden, täglich 7 Tage, wöchentlich 4 Wochen, monatlich 6 Monate."
        SettingRow {
            first: true
            visible: page.info.browsing === true
            glyph: "\u{f01ea}"
            title: "Geöffnete Sicherung schließen"
            DialogButton {
                implicitWidth: 100
                width: implicitWidth
                text: "Schließen"
                onClicked: page.run(["close"])
            }
        }
        SettingRow {
            first: page.info.browsing !== true
            visible: page.points.length === 0
            title: "Noch keine früheren Versionen"
        }
        Repeater {
            model: page.points
            SettingRow {
                required property var modelData
                required property int index
                first: index === 0 && page.info.browsing !== true
                glyph: modelData.id.startsWith("local:") ? "\u{f0322}" : "\u{f02ca}"
                glyphColour: "#8e8e93"
                title: page.when(modelData.date)
                subtitle: modelData.where + (modelData.description && modelData.description !== "timeline" ? " · " + modelData.description : "")
                DialogButton {
                    implicitWidth: 130
                    width: implicitWidth
                    text: "Im Finder öffnen"
                    onClicked: page.run(["browse", modelData.id])
                }
            }
        }
    }
}

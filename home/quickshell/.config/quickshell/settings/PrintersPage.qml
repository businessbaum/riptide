import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

// "Drucker & Scanner", like on a Mac: the printers (state, default, supplies), adding one
// that was found in the network or on USB (driverless: IPP Everywhere/AirPrint, no driver
// to install), and the scanners. One printer: its queue ("Drucker" app), a test page,
// removing it. Everything through scripts/printers.py (CUPS and Avahi).
Page {
    id: page
    property var window
    property string selected: "" // a printer's queue name; "" = the overview

    property var cups: ({ printers: [], default: "", running: true })
    readonly property var printer: cups.printers.find(p => p.name === selected) ?? null
    title: printer ? printer.info : "Drucker & Scanner"

    property bool adding: false
    property bool searching: false
    property var found: []
    property string addingUri: ""
    property string error: ""
    property var scanners: []
    property bool lookingForScanners: true

    readonly property string script: Quickshell.shellPath("scripts/printers.py")
    function parse(text, fallback) {
        try {
            return JSON.parse(text);
        } catch (e) {
            return fallback;
        }
    }

    Component.onCompleted: {
        lister.running = true;
        scannerFinder.running = true;
    }
    // printers change by themselves (jobs, ink, offline): look again now and then
    Timer {
        running: true
        repeat: true
        interval: 4000
        onTriggered: if (!lister.running) lister.running = true
    }
    Process {
        id: lister
        command: ["python3", page.script, "list"]
        stdout: StdioCollector {
            onStreamFinished: page.cups = page.parse(text, page.cups)
        }
    }
    Process {
        id: finder
        command: ["python3", page.script, "discover"]
        stdout: StdioCollector {
            onStreamFinished: {
                page.found = page.parse(text, []);
                page.searching = false;
            }
        }
    }
    function search() {
        found = [];
        searching = true;
        finder.running = true;
    }
    Process {
        id: scannerFinder
        command: ["python3", page.script, "scanners"]
        stdout: StdioCollector {
            onStreamFinished: {
                page.scanners = page.parse(text, []);
                page.lookingForScanners = false;
            }
        }
    }

    // One change at a time; an error comes back as {"error": …}
    Process {
        id: change
        property var after: null
        stdout: StdioCollector {
            onStreamFinished: {
                const r = page.parse(text, {});
                page.error = r.error ?? "";
                const done = change.after;
                change.after = null;
                done?.(r);
                lister.running = true;
            }
        }
    }
    function run(args, after) {
        error = "";
        change.after = after ?? null;
        change.command = ["python3", script].concat(args);
        change.running = true;
    }

    function addPrinter(p) {
        addingUri = p.uri;
        run(["add", p.uri, p.name, p.location], r => {
            addingUri = "";
            if (!r.error) {
                found = found.filter(f => f.uri !== p.uri);
                if (found.length === 0)
                    adding = false;
            }
        });
    }

    function stateText(p) {
        if (p.offline)
            return "Nicht erreichbar";
        const s = p.state === "printing" ? "Druckt …" : p.state === "stopped" ? "Angehalten" : "Bereit";
        return s + (p.jobs > 0 ? ` · ${p.jobs} ${p.jobs === 1 ? "Auftrag" : "Aufträge"}` : "");
    }
    function openQueue(name) {
        Quickshell.execDetached([Quickshell.shellPath("scripts/printers-app.sh"), name]);
    }

    component ValueRow: SettingRow {
        id: valueRow
        property string value
        Text {
            text: valueRow.value
            width: Math.min(implicitWidth, 360)
            horizontalAlignment: Text.AlignRight
            wrapMode: Text.WrapAnywhere
            font.family: Config.fontSans
            font.pixelSize: 13
            color: Config.textSecondary
        }
    }

    Text {
        visible: page.error !== ""
        Layout.fillWidth: true
        text: page.error
        wrapMode: Text.Wrap
        font.family: Config.fontSans
        font.pixelSize: 13
        color: "#ff453a"
    }

    // ---------------------------------------------------------------- overview

    Group {
        visible: page.selected === "" && !page.cups.running
        description: "Der Druckdienst ist noch nicht eingerichtet. Einmal im Terminal ausführen: "
            + "sudo ~/dotfiles/system/setup-os.sh – danach findet dein Computer Drucker und Scanner im Netzwerk von selbst."
    }

    Group {
        visible: page.selected === "" && page.cups.running
        title: "Drucker"

        Repeater {
            model: page.cups.printers
            SettingRow {
                required property var modelData
                required property int index
                first: index === 0
                glyph: ""
                glyphColour: modelData.offline ? "#8e8e93" : "#0a84ff"
                title: modelData.info + (modelData.default ? "  ·  Standard" : "")
                subtitle: page.stateText(modelData)
                link: true
                onClicked: page.selected = modelData.name
            }
        }
        SettingRow {
            first: page.cups.printers.length === 0
            glyph: "+"
            glyphColour: Config.accent
            title: page.adding ? (page.searching ? "Suche im Netzwerk und an USB …" : "Gefundene Drucker") : "Drucker hinzufügen …"
            link: !page.adding
            onClicked: {
                page.adding = true;
                page.search();
            }
            DialogButton {
                visible: page.adding
                implicitWidth: 90
                width: implicitWidth
                text: "Fertig"
                onClicked: page.adding = false
            }
        }
        Repeater {
            model: page.adding ? page.found : []
            SettingRow {
                required property var modelData
                glyph: modelData.kind === "usb" ? "\u{f0553}" : ""
                title: modelData.name
                subtitle: [modelData.model !== modelData.name ? modelData.model : "", modelData.location,
                    modelData.kind === "usb" ? "USB" : "Netzwerk"].filter(s => s).join(" · ")
                DialogButton {
                    implicitWidth: 120
                    width: implicitWidth
                    primary: page.addingUri === ""
                    text: page.addingUri === modelData.uri ? "Wird eingerichtet …" : "Hinzufügen"
                    onClicked: if (page.addingUri === "") page.addPrinter(modelData)
                }
            }
        }
        SettingRow {
            visible: page.adding && !page.searching && page.found.length === 0
            title: "Keine neuen Drucker gefunden"
            subtitle: "Ist der Drucker eingeschaltet und im selben Netzwerk (WLAN oder Kabel)?"
            DialogButton {
                implicitWidth: 120
                width: implicitWidth
                text: "Erneut suchen"
                onClicked: page.search()
            }
        }
    }

    Group {
        visible: page.selected === ""
        title: "Scanner"
        description: page.scanners.length === 0 && !page.lookingForScanners
            ? "Keine Scanner gefunden. Scanner im Netzwerk – auch die in Multifunktionsdruckern – erscheinen hier von selbst."
            : ""
        SettingRow {
            first: true
            visible: page.lookingForScanners
            title: "Suche nach Scannern …"
        }
        Repeater {
            model: page.scanners
            SettingRow {
                required property var modelData
                required property int index
                first: index === 0
                glyph: "\u{f06ab}"
                title: modelData.name
                subtitle: modelData.device.split(":")[0] === "airscan" ? "Netzwerk" : modelData.device.split(":")[0]
                DialogButton {
                    implicitWidth: 100
                    width: implicitWidth
                    text: "Scannen …"
                    onClicked: Quickshell.execDetached(["uwsm", "app", "--", "org.gnome.SimpleScan.desktop"])
                }
            }
        }
    }

    // ---------------------------------------------------------------- one printer

    Text {
        visible: page.selected !== ""
        text: "\u{f0141} Drucker & Scanner"
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

    Group {
        visible: page.printer !== null
        ValueRow {
            first: true
            title: "Status"
            value: page.printer ? page.stateText(page.printer) + (page.printer.message ? " – " + page.printer.message : "") : ""
        }
        SettingRow {
            title: "Standarddrucker"
            subtitle: "Apps schlagen ihn beim Drucken zuerst vor"
            Toggle {
                checked: page.printer?.default ?? false
                enabled: !(page.printer?.default ?? true)
                onToggled: on => on && page.run(["default", page.selected])
            }
        }
        SettingRow {
            title: "Druckerwarteliste öffnen …"
            link: true
            onClicked: page.openQueue(page.selected)
        }
    }

    Group {
        visible: (page.printer?.supplies.length ?? 0) > 0
        title: "Füllstände"
        Repeater {
            model: page.printer?.supplies ?? []
            SettingRow {
                required property var modelData
                required property int index
                first: index === 0
                title: modelData.name
                Row {
                    spacing: 10
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 160
                        height: 8
                        radius: 4
                        color: Config.hover
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(100, modelData.level)) / 100
                            height: parent.height
                            radius: 4
                            color: "#" + modelData.colour
                        }
                    }
                    Text {
                        width: 40
                        horizontalAlignment: Text.AlignRight
                        text: modelData.level < 0 ? "?" : modelData.level + " %"
                        font.family: Config.fontSans
                        font.pixelSize: 12
                        color: modelData.level >= 0 && modelData.level < 15 ? "#ff9f0a" : Config.textSecondary
                    }
                }
            }
        }
    }

    Group {
        visible: page.printer !== null
        title: "Details"
        ValueRow {
            first: true
            title: "Modell"
            value: page.printer?.model ?? ""
        }
        ValueRow {
            visible: (page.printer?.location ?? "") !== ""
            title: "Standort"
            value: page.printer?.location ?? ""
        }
        ValueRow {
            title: "Adresse"
            value: page.printer?.uri ?? ""
        }
    }

    Group {
        visible: page.printer !== null
        SettingRow {
            first: true
            title: "Testseite drucken"
            DialogButton {
                implicitWidth: 100
                width: implicitWidth
                text: "Drucken"
                onClicked: page.run(["test", page.selected])
            }
        }
        SettingRow {
            title: "Drucker entfernen"
            subtitle: "Aufträge in seiner Warteliste werden abgebrochen"
            DialogButton {
                implicitWidth: 100
                width: implicitWidth
                text: "Entfernen …"
                onClicked: {
                    const p = page.printer;
                    Confirm.ask(`Möchtest du „${p.info}“ entfernen?`, "Du kannst ihn jederzeit wieder hinzufügen.",
                        "Entfernen", () => page.run(["remove", p.name], r => {
                            if (!r.error)
                                page.selected = "";
                        }));
                }
            }
        }
    }
}

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

// Datenschutz & Sicherheit: every kind of permission (Mikrofon, Kamera, Ordner, …); one
// of them opens the list of apps with a switch each, like on a Mac. The decisions live in
// the system's permission store (Privacy.qml); apps without a decision ask on first use.
// Below: how safe the computer is (encryption, Secure Boot, snapshot – scripts/security.py)
// and the firewall with what it lets in (subpage "firewall"; changes: riptide-helper).
Page {
    id: page
    title: kind ? kind.label : selected === "firewall" ? "Firewall" : "Datenschutz & Sicherheit"
    property var window

    property string selected: ""
    readonly property var kind: selected !== "" ? Privacy.kinds[selected] ?? null : null

    // System apps run without a sandbox (sandbox.json)
    property var systemPatterns: []
    FileView {
        path: Quickshell.env("HOME") + "/.config/macos/sandbox.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                page.systemPatterns = JSON.parse(text()).system_apps ?? [];
            } catch (e) {}
        }
    }
    function isSystem(id) {
        return systemPatterns.some(p => new RegExp("^" + p.replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*") + "$").test(id));
    }
    readonly property var visibleApps: DesktopEntries.applications.values
        .filter(e => !e.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))
    // Terminal programs (nvtop …) run in the terminal, which is a system app
    readonly property var apps: visibleApps.filter(e => !isSystem(e.id) && !e.runInTerminal)
    readonly property var systemApps: visibleApps.filter(e => isSystem(e.id) || e.runInTerminal)

    // ---------------------------------------------------------------- security

    property var security: ({ firewall: { services: [] }, remoteLogin: {}, snapshot: {} })
    property string securityError: ""
    Component.onCompleted: securityReader.running = true
    Process {
        id: securityReader
        command: ["python3", Quickshell.shellPath("scripts/security.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.security = JSON.parse(text);
                } catch (e) {}
            }
        }
    }
    // root steps through riptide-helper (pkexec: our password dialog)
    Process {
        id: securityChange
        stdout: StdioCollector { id: changeOut }
        stderr: StdioCollector { id: changeErr }
        onExited: code => {
            page.securityError = code === 0 ? ""
                : code === 126 ? "" // password dialog cancelled
                : /unbekannter Bereich/.test(changeErr.text) ? "Dafür einmal im Terminal ausführen: sudo ~/dotfiles/system/setup-os.sh"
                : "Nicht geändert: " + (changeErr.text.trim().split("\n").pop() || "unbekannter Fehler");
            securityReader.running = true;
        }
    }
    function helper(args) {
        securityError = "";
        securityChange.command = ["pkexec", "/usr/local/sbin/riptide-helper"].concat(args);
        securityChange.running = true;
    }
    readonly property var serviceNames: ({
        "mdns": "Geräte und Drucker im Netzwerk finden",
        "ssh": "Entfernte Anmeldung (SSH)",
        "samba": "Dateifreigabe (Windows-Netzwerk)",
        "kdeconnect": "KDE Connect",
        "ipp": "Druckerfreigabe",
        "http": "Webserver (HTTP)",
        "https": "Webserver (HTTPS)"
    })
    function snapshotText(s) {
        if (!s.allowed)
            return "Sichtbar nach einmaligem Einrichten";
        if (!s.date)
            return "Noch keiner";
        const d = new Date(s.date.replace(" ", "T"));
        const minutes = Math.round((Date.now() - d.getTime()) / 60000);
        return minutes < 60 ? `Vor ${Math.max(1, minutes)} Min.` : minutes < 1440 ? `Vor ${Math.round(minutes / 60)} Std.`
            : Qt.formatDateTime(d, "dd.MM.yyyy, HH:mm");
    }

    function allowedCount(key) {
        const n = apps.filter(e => Privacy.state(e.id, key) === "yes").length;
        return n === 0 ? "Keine App erlaubt" : n === 1 ? "1 App erlaubt" : `${n} Apps erlaubt`;
    }
    function howText(k) {
        const how = {
            prompt: "Apps fragen, wenn sie es zum ersten Mal brauchen.",
            portal: "Apps fragen über das System, wenn sie es brauchen.",
            switch: "Apps können hier nicht selbst fragen: Erlaube es nur, wenn eine App es braucht."
        }[k.how] ?? "";
        const files = ["desktop", "documents", "downloads", "pictures", "music", "videos"].includes(k.key)
            ? " Einzelne Dateien kann jede App trotzdem bekommen: Du wählst sie im Öffnen-Dialog aus." : "";
        const applies = k.applies === "restart" ? " Änderungen gelten ab dem nächsten Start der App." : "";
        return how + files + applies;
    }

    // ---------------------------------------------------------------- overview

    Group {
        visible: page.selected === ""
        description: "Apps laufen abgeschirmt und fragen, bevor sie etwas davon benutzen. "
            + "Hier siehst du, was jede App darf, und kannst es jederzeit ändern."

        Repeater {
            model: Privacy.kindList

            SettingRow {
                required property var modelData
                required property int index
                first: index === 0
                glyph: modelData.glyph
                glyphColour: modelData.colour
                title: modelData.label
                subtitle: page.allowedCount(modelData.key)
                link: true
                onClicked: page.selected = modelData.key
            }
        }
    }

    Group {
        visible: page.selected === ""
        title: "Ohne Abschirmung"
        description: "Systemprogramme laufen wie beim Mac ohne Sandbox und dürfen alles. "
            + "Das gilt auch für alles, was du im Terminal startest."

        Repeater {
            model: page.systemApps

            SettingRow {
                required property var modelData
                required property int index
                first: index === 0
                iconEntry: modelData
                title: modelData.name
            }
        }
    }

    Group {
        visible: page.selected === ""
        title: "Sicherheit"
        SettingRow {
            first: true
            glyph: "\u{f033e}"
            glyphColour: page.security.encryption ? "#30d158" : "#ff9f0a"
            title: "Festplattenverschlüsselung"
            subtitle: page.security.encryption ? "An – ohne dein Passwort beim Start sind deine Daten nicht lesbar" : "Aus"
        }
        SettingRow {
            glyph: "\u{f0483}"
            glyphColour: page.security.secureBoot ? "#30d158" : "#8e8e93"
            title: "Secure Boot"
            subtitle: page.security.secureBoot === true ? "An – beim Start läuft nur geprüfte Software"
                : page.security.secureBoot === false ? "Aus – wird im BIOS eingeschaltet (mit eigenen Schlüsseln, sbctl)"
                : "Nicht verfügbar"
        }
        SettingRow {
            glyph: "\u{f1a11}"
            glyphColour: page.security.firewall.running ? "#30d158" : "#ff9f0a"
            title: "Firewall"
            subtitle: page.security.firewall.running ? "An" : "Aus – Verbindungen von außen sind nicht gefiltert"
            link: true
            onClicked: page.selected = "firewall"
        }
        SettingRow {
            glyph: "\u{f02da}"
            title: "Letzter Snapshot"
            subtitle: page.snapshotText(page.security.snapshot ?? {})
        }
        SettingRow {
            glyph: "\u{f0306}"
            glyphColour: "#8e8e93"
            title: "Passwörter und Schlüssel"
            link: true
            onClicked: Quickshell.execDetached(["uwsm", "app", "--", "org.gnome.seahorse.Application.desktop"])
        }
    }

    // ---------------------------------------------------------------- one kind

    Text {
        visible: page.selected !== ""
        text: "\u{f0141} Datenschutz & Sicherheit"
        font.family: Config.fontSans
        font.pixelSize: 13
        color: back.containsMouse ? Config.text : Config.accent
        MouseArea {
            id: back
            anchors.fill: parent
            hoverEnabled: true
            onClicked: page.selected = ""
        }
    }

    Group {
        visible: page.kind !== null
        description: page.kind ? page.howText(page.kind) : ""

        Repeater {
            model: page.kind !== null ? page.apps : []

            SettingRow {
                id: row
                required property var modelData
                required property int index
                readonly property string state: Privacy.state(modelData.id, page.selected)
                first: index === 0
                iconEntry: modelData
                title: modelData.name
                subtitle: state === "ask" ? (page.kind?.how === "switch" ? "Nicht erlaubt" : "Noch nicht gefragt") : ""

                Toggle {
                    checked: row.state === "yes"
                    onToggled: on => Privacy.set(row.modelData.id, page.selected, on ? "yes" : "no")
                }
            }
        }
    }

    // ---------------------------------------------------------------- firewall

    Text {
        visible: page.securityError !== "" && page.selected === "firewall"
        Layout.fillWidth: true
        text: page.securityError
        wrapMode: Text.Wrap
        font.family: Config.fontSans
        font.pixelSize: 13
        color: "#ff453a"
    }
    Group {
        visible: page.selected === "firewall"
        description: "Die Firewall lässt von außen nur herein, was du unten erlaubst. Verbindungen, die dein "
            + "Computer selbst aufbaut – Websites, Updates, Drucken – sind nicht betroffen."
        SettingRow {
            first: true
            title: "Firewall"
            Toggle {
                checked: page.security.firewall.running === true
                onToggled: on => page.helper(["firewall", on ? "on" : "off"])
            }
        }
    }
    Group {
        visible: page.selected === "firewall" && page.security.firewall.running === true
        title: "Eingehende Verbindungen erlauben"
        SettingRow {
            first: true
            title: page.serviceNames.mdns
            subtitle: "Damit Drucker, Scanner und andere Geräte gefunden werden"
            Toggle {
                checked: page.security.firewall.services.includes("mdns")
                onToggled: on => page.helper(["firewall", on ? "allow" : "deny", "mdns"])
            }
        }
        SettingRow {
            title: page.serviceNames.ssh
            subtitle: page.security.remoteLogin.enabled ? "An – andere Computer können sich mit deinem Passwort anmelden"
                : page.security.firewall.services.includes("ssh") ? "Aus, aber der Zugang in der Firewall ist noch offen"
                : "Aus"
            Row {
                spacing: 8
                DialogButton {
                    visible: !page.security.remoteLogin.enabled && page.security.firewall.services.includes("ssh")
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 90
                    width: implicitWidth
                    text: "Schließen"
                    onClicked: page.helper(["firewall", "deny", "ssh"])
                }
                Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: page.security.remoteLogin.enabled === true
                    onToggled: on => page.helper(["remote-login", on ? "on" : "off"])
                }
            }
        }
        Repeater {
            model: page.security.firewall.services.filter(s => !["mdns", "ssh", "dhcpv6-client"].includes(s))
            SettingRow {
                required property var modelData
                title: page.serviceNames[modelData] ?? modelData
                Toggle {
                    checked: true
                    onToggled: on => page.helper(["firewall", on ? "allow" : "deny", modelData])
                }
            }
        }
    }
}

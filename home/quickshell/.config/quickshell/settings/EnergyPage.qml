import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs

// "Energie", like on a Mac: when the screen locks, the screens go off and the computer
// sleeps while nobody uses it (hypridle, written by scripts/hypridle-config.py), the
// energy mode (power-profiles-daemon), and opening the windows again at login.
Page {
    id: page
    title: "Energie"
    property var window

    readonly property var energy: Config.settings.energy ?? ({})
    function after(minutes) {
        return [1, 2, 5, 10, 15, 20, 30, 45, 60, 120, 180].filter(m => m >= minutes).concat([0]);
    }
    function options(list) {
        return list.map(m => ({ value: m, text: m === 0 ? "Nie" : m < 60 ? m + " Min." : (m / 60) + " Std." }));
    }
    function set(key, minutes) {
        Store.set("energy", key, minutes);
        apply.restart();
    }
    // hypridle reads its settings when it starts: write them, start it again
    Timer {
        id: apply
        interval: 400
        onTriggered: Quickshell.execDetached(["sh", "-c", "\"$1\" && systemctl --user restart hypridle.service", "sh",
            Quickshell.shellPath("scripts/hypridle-config.py")])
    }

    Group {
        title: "Wenn der Computer nicht benutzt wird"
        description: "Videos und Anrufe halten den Bildschirm wach. „Computer wachhalten“ im Kontrollzentrum verhindert alles davon."
        SettingRow {
            first: true
            title: "Bildschirm sperren nach"
            Choice {
                window: page.window
                options: page.options(page.after(1))
                current: page.energy.lock ?? 10
                onPicked: v => page.set("lock", v)
            }
        }
        SettingRow {
            title: "Bildschirme ausschalten nach"
            Choice {
                window: page.window
                options: page.options(page.after(1))
                current: page.energy.display_off ?? 12
                onPicked: v => page.set("display_off", v)
            }
        }
        SettingRow {
            title: "Ruhezustand nach"
            subtitle: "Der Computer schläft und wacht mit einer Taste oder der Maus wieder auf"
            Choice {
                window: page.window
                options: page.options(page.after(15))
                current: page.energy.sleep ?? 0
                onPicked: v => page.set("sleep", v)
            }
        }
    }

    Group {
        title: "Energiemodus"
        description: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
            ? "„Hohe Leistung“ ist gerade eingeschränkt (Temperatur)." : "Auch im Kontrollzentrum zu ändern."
        Repeater {
            model: [
                { profile: PowerProfile.PowerSaver, title: "Energiesparen", text: "Leiser und kühler, etwas langsamer" },
                { profile: PowerProfile.Balanced, title: "Automatisch", text: "Schnell, wenn es gebraucht wird – sonst sparsam" },
                { profile: PowerProfile.Performance, title: "Hohe Leistung", text: "Immer volle Geschwindigkeit (Spiele, Videoschnitt)" }
            ]
            SettingRow {
                required property var modelData
                required property int index
                first: index === 0
                title: modelData.title
                subtitle: modelData.text
                link: true
                onClicked: PowerProfiles.profile = modelData.profile
                Text {
                    visible: PowerProfiles.profile === modelData.profile
                    text: "" // check
                    font.family: Config.fontSymbols
                    font.pixelSize: 14
                    color: Config.accent
                }
            }
        }
    }

    Group {
        title: "Anmelden"
        SettingRow {
            first: true
            title: "Fenster beim erneuten Anmelden wieder öffnen"
            subtitle: "Die Apps, die beim Abmelden oder Neustarten offen waren, öffnen sich wieder"
            Toggle {
                checked: Store.get("session", "reopen", true)
                onToggled: on => Store.set("session", "reopen", on)
            }
        }
    }
}

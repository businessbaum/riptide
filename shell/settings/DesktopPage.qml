import QtQuick
import QtQuick.Layouts
import qs

Page {
    id: page
    title: "Schreibtisch & Dock"
    property var window

    Group {
        title: "Dock"
        SettingRow {
            first: true
            title: "Größe"
            Slider {
                width: 260
                from: 32
                to: 96
                stepSize: 4
                showValue: true
                unit: " px"
                value: Config.dockSize
                onMoved: v => Store.set("dock", "size", v)
            }
        }
    }

    Group {
        title: "Fenster"
        SettingRow {
            first: true
            title: "Einrasten an Bildschirmrändern"
            subtitle: "Fenster an den Rand ziehen: halber Bildschirm, Ecke: Viertel, oben: ganzer Bildschirm"
            Toggle {
                checked: Store.get("windows", "snapping", true)
                onToggled: on => Store.set("windows", "snapping", on, true)
            }
        }
        SettingRow {
            title: "Abstand zwischen Fenstern"
            Slider {
                width: 260
                from: 0
                to: 24
                stepSize: 1
                showValue: true
                unit: " px"
                value: Store.get("windows", "gap", 8)
                onMoved: v => Store.set("windows", "gap", v, true)
            }
        }
        SettingRow {
            title: "Eckenradius"
            Slider {
                width: 260
                from: 0
                to: 24
                stepSize: 1
                showValue: true
                unit: " px"
                value: Store.get("windows", "corner_radius", 12)
                onMoved: v => Store.set("windows", "corner_radius", v, true)
            }
        }
    }

    // "Aktive Ecken" (HotCorners.qml in the shell)
    readonly property var cornerActions: [
        { value: "none", text: "–" },
        { value: "mission", text: "Mission Control" },
        { value: "app", text: "App-Fenster" },
        { value: "desktop", text: "Schreibtisch" },
        { value: "launchpad", text: "Launchpad" },
        { value: "notifications", text: "Mitteilungszentrale" },
        { value: "screens-off", text: "Bildschirme ausschalten" },
        { value: "lock", text: "Bildschirm sperren" },
        { value: "sleep", text: "Ruhezustand" }
    ]
    readonly property var hotCorners: Config.settings.desktop?.hot_corners ?? ({})
    function setCorner(key, value) {
        Store.set("desktop", "hot_corners", Object.assign({}, hotCorners, { [key]: value }));
    }

    Group {
        title: "Aktive Ecken"
        description: "Bewege den Zeiger in eine Ecke eines Bildschirms, um das Gewählte zu starten. "
            + "Bei Apps im Vollbild (Spiele) bleiben die Ecken aus."
        Repeater {
            model: [
                { key: "tl", title: "Oben links" },
                { key: "tr", title: "Oben rechts" },
                { key: "bl", title: "Unten links" },
                { key: "br", title: "Unten rechts" }
            ]
            SettingRow {
                required property var modelData
                required property int index
                first: index === 0
                title: modelData.title
                Choice {
                    window: page.window
                    options: page.cornerActions
                    current: page.hotCorners[modelData.key] ?? "none"
                    onPicked: v => page.setCorner(modelData.key, v)
                }
            }
        }
    }
}

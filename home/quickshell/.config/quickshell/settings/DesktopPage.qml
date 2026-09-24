import QtQuick
import QtQuick.Layouts
import qs

Page {
    title: "Schreibtisch & Dock"

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
}

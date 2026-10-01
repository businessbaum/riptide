import QtQuick
import qs

// "Laden" / "Öffnen" / progress, as a pill button like in the Mac App Store.
Rectangle {
    id: root

    required property var app
    readonly property bool installed: Catalog.isInstalled(app)
    readonly property bool working: Catalog.busy !== null && Catalog.busy.pkgs.includes(app.pkg)

    implicitWidth: Math.max(72, label.implicitWidth + 28)
    implicitHeight: 26
    radius: height / 2
    color: working ? "transparent" : installed ? Config.tile : Config.accent
    opacity: Catalog.busy !== null && !working ? 0.5 : 1

    // While working: the progress circle instead of the label
    ProgressRing {
        anchors.centerIn: parent
        visible: root.working
        value: PackageAdmin.progress
    }

    Text {
        id: label
        visible: !root.working
        anchors.centerIn: parent
        text: root.working ? (Catalog.busy.action === "remove" ? "Entfernt …" : "Lädt …")
            : root.installed ? "Öffnen" : "Laden"
        font.family: Config.fontSans
        font.pixelSize: 12
        font.weight: Font.Bold
        color: root.installed || root.working ? Config.accent : "white"
    }

    MouseArea {
        anchors.fill: parent
        enabled: Catalog.busy === null && (!root.installed || root.app.desktop !== "")
        onClicked: {
            if (root.installed)
                Apps.launch({ id: root.app.desktop });
            else
                Catalog.run("install", [root.app.pkg], root.app.name);
        }
    }
}

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Widgets

// The menu bar at the top of every screen:
//   left:  Apple menu, the active app's menu (its name)
//   right: microphone/camera/screen in use, apps in the background (tray), sound menu,
//   control centre,
//          date and time (opens the notification centre)
PanelWindow {
    id: bar

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property string activeAppId: Hyprland.activeToplevel?.wayland?.appId ?? ""
    // the active app: its key (start entry id), start entry and name ("Finder" on the
    // empty desktop)
    readonly property string activeKey: activeAppId !== "" ? Apps.keyForAppId(activeAppId) : ""
    readonly property var activeEntry: activeKey !== "" ? Apps.entryById(activeKey) : null
    readonly property string appName: activeKey !== "" ? Apps.name(activeKey) : "Finder"

    // over an app in full screen: hidden, shown while the pointer is at the top edge
    FullscreenReveal {
        id: reveal
        screen: bar.screen
        edge: "top"
        hold: barHover.hovered || OpenMenus.count > 0
    }
    HoverHandler {
        id: barHover
    }
    visible: reveal.shown
    WlrLayershell.layer: reveal.layer
    WlrLayershell.namespace: "menubar"
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: 30
    exclusiveZone: implicitHeight
    color: "transparent"

    PwObjectTracker {
        objects: [bar.sink]
    }

    // Open the menus from outside, e.g.  qs ipc call menubar-DP-1 controlCenter
    IpcHandler {
        target: "menubar-" + (bar.screen?.name ?? "")
        function appleMenu(): void {
            appleMenu.toggle();
        }
        function appMenu(): void {
            appMenu.toggle();
        }
        function controlCenter(): void {
            controlCenter.toggle();
        }
        function wifi(): void {
            controlCenter.showList("wifi");
        }
        function bluetooth(): void {
            controlCenter.showList("bluetooth");
        }
        function notificationCenter(): void {
            notificationCenter.toggle();
        }
        function sound(): void {
            soundMixer.toggle();
        }
    }

    // "Computer wachhalten" (control centre): no lock, screens stay on
    IdleInhibitor {
        window: bar
        enabled: Session.keepAwake
    }

    SystemClock {
        id: clock
        precision: Config.clockSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Rectangle {
        anchors.fill: parent
        color: Config.menubar
    }
    // over a full-screen app it slides down from the top and up again (a window itself
    // cannot be moved: its content is)
    Binding {
        target: bar.contentItem
        property: "y"
        value: -reveal.away * bar.implicitHeight
    }

    // Pictures of new notifications (image data), drawn once out of sight and kept as a
    // file for the notification centre (NotificationStore.pendingImages) – on one screen
    Repeater {
        // (by key: a picture that is done does not make the others start over)
        model: ScriptModel {
            values: bar.screen === Quickshell.screens[0] ? NotificationStore.pendingImages : []
            objectProp: "key"
        }
        IconImage {
            id: keep
            required property var modelData
            readonly property string key: modelData.key
            x: -200 // (a grab needs the item in a window, not on screen)
            implicitSize: 72
            source: modelData.url
            // The picture is often there at once – right after the shell (re)loads even before
            // the menu bar has its window: the grab waits until the item is in a shown window
            readonly property bool ready: status === Image.Ready && (Window.window?.visible ?? false)
            property bool asked: false
            function keepIt() {
                if (!ready || asked)
                    return;
                asked = true;
                const key = keep.key;
                if (!keep.grabToImage(result => NotificationStore.imageKept(key, result.saveToFile(NotificationStore.imagePath(key)))))
                    NotificationStore.imageKept(key, false);
            }
            onReadyChanged: keepIt()
            Component.onCompleted: keepIt()
            onStatusChanged: {
                if (status === Image.Error)
                    NotificationStore.imageKept(key, false);
            }
        }
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 8
        height: parent.height

        BarButton {
            id: logo
            text: "" // Apple logo (Symbols Nerd Font)
            symbol: true
            active: appleMenu.visible
            onClicked: appleMenu.toggle()
        }

        BarButton {
            id: appButton
            text: bar.appName
            bold: true
            active: appMenu.visible
            onClicked: appMenu.toggle()
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 8
        height: parent.height

        // Microphone, camera, screen in use (orange, green, purple dots)
        PrivacyIndicator {
            barWindow: bar
        }

        // Apps running in the background (Discord, Claude, …)
        Repeater {
            model: SystemTray.items
            TrayItem {
                required property var modelData
                item: modelData
                barWindow: bar
            }
        }
        // … and the ones we keep there (dock menu "In die Menüleiste ausblenden")
        Repeater {
            model: Background.running
            BackgroundItem {
                required property var modelData
                app: modelData
            }
        }

        // External drives: eject (like the Finder's eject button)
        BarButton {
            id: drivesButton
            visible: Drives.list.length > 0
            text: "\u{f01ea}" // eject
            symbol: true
            active: drivesMenu.visible
            onClicked: drivesMenu.toggle()
        }

        BarButton {
            visible: Session.keepAwake
            text: "\uf0f4" // cup: the computer is kept awake
            symbol: true
            onClicked: Session.keepAwake = false
        }

        BarButton {
            id: soundButton
            readonly property var audio: bar.sink?.audio
            visible: audio !== undefined && audio !== null
            symbol: true
            active: soundMixer.visible
            // speaker muted / low / high; click: sound menu, scroll: volume
            text: !audio ? "" : audio.muted ? "" : audio.volume < 0.4 ? "" : ""
            onClicked: soundMixer.toggle()
            onScrolled: delta => audio.volume = Math.max(0, Math.min(1, audio.volume + (delta > 0 ? 0.05 : -0.05)))
        }

        BarButton {
            id: controlButton
            text: "\uf1de" // control centre (sliders)
            symbol: true
            active: controlCenter.visible
            onClicked: controlCenter.toggle()
        }

        BarButton {
            id: clockButton
            text: clock.date.toLocaleString(Qt.locale(), Config.clockFormat)
            active: notificationCenter.visible
            onClicked: notificationCenter.toggle()
        }
    }

    SoundMixer {
        id: soundMixer
        anchorItem: soundButton
        backdropScreen: bar.screen
    }

    ControlCenter {
        id: controlCenter
        anchorItem: controlButton
        backdropScreen: bar.screen
    }

    NotificationCenter {
        id: notificationCenter
        anchorItem: clockButton
        backdropScreen: bar.screen
    }

    // one line per drive: open it; then eject each, or all
    MenuPopup {
        id: drivesMenu
        anchorItem: drivesButton
        backdropScreen: bar.screen
        items: {
            const list = [];
            for (const d of Drives.list)
                list.push({ text: `${d.name}  ·  ${Drives.size(d.size)}`, action: () => Drives.open(d) });
            list.push({ separator: true });
            for (const d of Drives.list)
                list.push({ text: `„${d.name}“ auswerfen`, action: () => Drives.eject(d) });
            list.push({ separator: true });
            for (const d of Drives.list)
                list.push({ text: `„${d.name}“ formatieren …`, action: () => Quickshell.execDetached(["gnome-disks", "--block-device", d.device]) });
            return list;
        }
    }

    // The menu of the active app, like on a Mac: about it, its own actions (sandbox.json
    // part_of, desktop actions), hide, quit – and quit at once
    MenuPopup {
        id: appMenu
        anchorItem: appButton
        backdropScreen: bar.screen
        items: {
            const id = bar.activeAppId, e = bar.activeEntry, name = bar.appName;
            const showAll = { text: "Alle einblenden", action: () => Hyprland.dispatch("macos.show_all()") };
            if (id === "") {
                const finder = Apps.entryById("org.gnome.Nautilus");
                return finder ? [{ text: "Neues Finder-Fenster", hint: "⌥⌘ Leertaste", action: () => Apps.launchNew(finder) },
                                 { separator: true }, showAll]
                              : [showAll];
            }
            const list = [];
            if (e) {
                list.push({ text: `Über „${name}“`, action: () => AppInfo.show(e) }, { separator: true });
                list.push({ text: "Neues Fenster", action: () => Apps.launchNew(e) });
                for (const a of Apps.actionsOf(e))
                    list.push({ text: a.name, action: () => Apps.launchAction(e, a.id) });
            }
            list.push({ text: "Alle Fenster zeigen", hint: "⌃↓", action: () => Quickshell.execDetached(["qs", "ipc", "call", "mission", "app"]) });
            list.push({ separator: true },
                { text: `„${name}“ ausblenden`, hint: "⌘H", action: () => Hyprland.dispatch(`macos.hide_app('${Apps.safe(id)}')`) },
                { text: "Andere ausblenden", hint: "⌥⌘H", action: () => Hyprland.dispatch(`macos.hide_others('${Apps.safe(id)}')`) },
                showAll);
            if (e) {
                const pinned = Apps.isPinned(e);
                list.push({ separator: true }, { text: pinned ? "Aus dem Dock entfernen" : "Im Dock behalten", action: () => Apps.setPinned(e, !pinned) });
            }
            list.push({ separator: true },
                { text: `„${name}“ beenden`, hint: "⌘Q", action: () => Apps.quit(id) },
                { text: `„${name}“ sofort beenden …`, action: () => bar.forceQuit(id, name) });
            return list;
        }
    }
    // all of the app at once, after asking (like the Force Quit window: ForceQuit.qml)
    function forceQuit(id, name) {
        const key = Apps.keyForAppId(id);
        const classes = [...new Set(Apps.windows.filter(w => Apps.keyForAppId(w.appId) === key).map(w => w.appId))];
        Confirm.ask(`„${name}“ sofort beenden?`, "Nicht gesicherte Änderungen gehen dabei verloren.", "Sofort beenden",
            () => ForceQuit.quit(classes.length > 0 ? classes : [id]));
    }

    MenuPopup {
        id: appleMenu
        anchorItem: logo
        backdropScreen: bar.screen
        items: [
            { text: "Über diesen Computer", action: () => About.show() },
            { separator: true },
            { text: "Systemeinstellungen …", action: () => Quickshell.execDetached(["uwsm", "app", "--", "org.riptide.SystemSettings.desktop"]) },
            { separator: true },
            { text: "Sofort beenden …", action: () => ForceQuit.show() },
            { separator: true },
            { text: "Ruhezustand", action: () => Session.sleep() },
            { text: "Neustart …", action: () => Session.ask("reboot") },
            { text: "Ausschalten …", action: () => Session.ask("poweroff") },
            { separator: true },
            { text: "Bildschirm sperren", hint: "⌃⌘Q", action: () => Lock.lock() },
            { text: "Abmelden …", action: () => Session.ask("logout") }
        ]
    }
}

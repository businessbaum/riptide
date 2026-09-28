import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pam
import Quickshell.Wayland

// The lock screen (Lock.qml): the login window (LoginScreen.qml) on every screen, over your
// own wallpaper. The form is on the screen with the pointer. The password is checked by PAM
// ("login", which also unlocks the keyring). At boot it offers "Anderer Benutzer …" and
// sleep / restart / shut down; "Anderer Benutzer …" and ⌃⌥F2 end the session – greetd's
// login screen follows.
//
// "Riptide", how it comes and goes:
//   locking    your wallpaper settles over the desktop (zooming in a little, the windows
//              dissolve into it), then the clock comes down and the person rises
//   unlocking  the form fades and a ripple spreads from the person: a ring of light whose
//              inside is the desktop again
//   at boot    a slower ripple with an echo – the apps already start behind it – and then
//              menu bar and dock arrive (MenuBar.qml, Dock.qml)
// Seen through (Hyprland session_lock_xray) only while it moves; otherwise the lock screen
// is black behind its wallpaper – whatever fails to draw, the desktop never shows.
Scope {
    id: root

    property bool busy: false
    property string error: ""
    property int failures: 0
    property bool leaving: false
    property string pending: "" // the password, until PAM asks for it

    function submit(password) {
        if (busy)
            return;
        error = "";
        busy = true;
        pending = password;
        pam.start();
    }

    // to greetd's login screen: no logout marker (Session.qml), so it stays there
    function endSession() {
        Hyprland.dispatch("hl.dsp.exit()");
    }

    // the ripple: every screen plays it (signal), then the lock goes
    signal ripple(int duration, bool echo)
    function accepted() {
        const first = !Lock.loggedIn;
        Lock.passwordAccepted(); // at boot the apps start now, behind the animation
        leaving = true;          // the form fades (LoginScreen.qml)
        rippleStart.duration = first ? 1500 : 700;
        rippleStart.echo = first;
        rippleStart.interval = first ? 380 : 200;
        rippleStart.restart();
    }
    Timer {
        id: rippleStart
        property int duration: 700
        property bool echo: false
        onTriggered: {
            root.ripple(duration, echo);
            done.interval = duration;
            done.restart();
        }
    }
    Timer {
        id: done
        onTriggered: {
            Lock.unlocked();
            root.leaving = false;
        }
    }

    PamContext {
        id: pam
        config: "login"
        onResponseRequiredChanged: {
            if (responseRequired) {
                respond(root.pending);
                root.pending = "";
            }
        }
        onCompleted: result => {
            root.busy = false;
            root.pending = "";
            if (result === PamResult.Success) {
                root.accepted();
            } else {
                root.error = "Falsches Passwort.";
                root.failures++;
            }
        }
        onError: error => {
            root.busy = false;
            root.pending = "";
            root.error = "Das Passwort ließ sich nicht prüfen.";
            console.warn("lock: pam error", error);
        }
    }

    WlSessionLock {
        id: lock
        locked: Lock.locked
        onSecureChanged: Lock.secure = secure

        WlSessionLockSurface {
            id: surface
            // see-through only while it moves (the desktop below, session_lock_xray)
            property bool moving: false
            color: moving ? "transparent" : "black"

            // the ripple: its middle, how far it has come, the farthest corner
            property point origin: Qt.point(width / 2, height / 2)
            property real reach: 0
            property real ring: 0 // 0 → 1 over the ripple, for the rings' light
            readonly property real farthest: Math.hypot(Math.max(origin.x, width - origin.x), Math.max(origin.y, height - origin.y)) + 60

            LoginScreen {
                id: screen
                anchors.fill: parent
                main: Hyprland.focusedMonitor?.name === surface.screen?.name
                backdrop: Component {
                    WallpaperImage {}
                }
                displayName: Lock.displayName
                busy: root.busy
                error: root.error
                failures: root.failures
                leaving: root.leaving
                offerOther: !Lock.loggedIn
                typeOther: false
                offerPower: !Lock.loggedIn
                onSubmit: (name, password) => root.submit(password)
                onSwitchUser: root.endSession()
                onEmergency: root.endSession()
                onPower: action => Quickshell.execDetached(["systemctl", action])
                onMainChanged: if (main) focusField()

                // the hole the ripple opens
                layer.enabled: surface.reach > 0
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskInverted: true
                    maskSource: hole
                }
            }
            Item {
                id: hole
                anchors.fill: parent
                visible: false
                layer.enabled: true
                Rectangle {
                    x: surface.origin.x - surface.reach
                    y: surface.origin.y - surface.reach
                    width: surface.reach * 2
                    height: width
                    radius: width / 2
                    color: "white"
                }
            }
            // the wave front: a ring of light on the edge, and at boot an echo behind it
            Repeater {
                model: [{ lag: 0, width: 5 }, { lag: 0.16, width: 3 }]
                Rectangle {
                    required property var modelData
                    readonly property real r: Math.max(0, surface.reach - modelData.lag * surface.farthest)
                    visible: surface.reach > 0 && (modelData.lag === 0 || surface.echo)
                    x: surface.origin.x - r
                    y: surface.origin.y - r
                    width: r * 2
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: modelData.width
                    border.color: Qt.rgba(1, 1, 1, 0.55 * (1 - surface.ring) * (modelData.lag === 0 ? 1 : 0.6))
                    layer.enabled: visible
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: 0.45
                        blurMax: 20
                        brightness: 0.25
                    }
                }
            }
            property bool echo: false

            ParallelAnimation {
                id: rippleAnimation
                property int duration: 700
                NumberAnimation { target: surface; property: "reach"; from: 1; to: surface.farthest; duration: rippleAnimation.duration; easing.type: Easing.InOutCubic }
                NumberAnimation { target: surface; property: "ring"; from: 0; to: 1; duration: rippleAnimation.duration; easing.type: Easing.InQuad }
                NumberAnimation { target: screen; property: "backdropScale"; from: 1; to: 1.05; duration: rippleAnimation.duration; easing.type: Easing.InOutCubic }
            }
            Connections {
                target: root
                function onRipple(duration, echo) {
                    surface.origin = screen.rippleOrigin();
                    surface.echo = echo;
                    surface.moving = true;
                    rippleAnimation.duration = duration;
                    rippleAnimation.restart();
                }
            }

            // coming in: from the desktop the wallpaper settles over it, then clock and person
            SequentialAnimation {
                id: comeIn
                ParallelAnimation {
                    NumberAnimation { target: screen; property: "opacity"; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }
                    NumberAnimation { target: screen; property: "backdropScale"; from: 1.08; to: 1; duration: 650; easing.type: Easing.OutCubic }
                    SequentialAnimation {
                        PauseAnimation { duration: 180 }
                        NumberAnimation { target: screen; property: "intro"; from: 0; to: 1; duration: 620; easing.type: Easing.OutCubic }
                    }
                }
                ScriptAction { script: surface.moving = false }
            }
            // at boot and after a crash: already there, only clock and person come in
            NumberAnimation {
                id: introOnly
                target: screen
                property: "intro"
                from: 0
                to: 1
                duration: 700
                easing.type: Easing.OutCubic
            }

            Component.onCompleted: {
                if (Lock.animateIn) {
                    screen.opacity = 0;
                    screen.intro = 0;
                    moving = true;
                    comeIn.start();
                } else if (!Lock.loggedIn) {
                    screen.intro = 0;
                    introOnly.start();
                }
                if (screen.main)
                    screen.focusField();
            }
        }
    }
    // (every screen has read it when its surface came)
    Connections {
        target: lock
        function onSecureChanged() {
            if (lock.secure)
                Lock.animateIn = false;
        }
    }
}

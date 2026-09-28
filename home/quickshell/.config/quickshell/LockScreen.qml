import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pam
import Quickshell.Wayland

// The lock screen (Lock.qml): the login window (LoginScreen.qml) on every screen, over your
// own wallpaper – so unlocking goes straight on into the desktop. The form is on the main
// screen (MainScreen.qml; none chosen: the one with the pointer), the others show what was
// chosen for them (LockInfo.qml). The password is checked by PAM ("login", which also unlocks the
// keyring). At boot it offers "Anderer Benutzer …" and sleep / restart / shut down;
// "Anderer Benutzer …" and ⌃⌥F2 end the session – greetd's login screen follows.
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
                root.leaving = true; // the form fades, the wallpaper stays
                fade.restart();
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
    Timer {
        id: fade
        interval: 300
        onTriggered: {
            Lock.unlocked();
            root.leaving = false;
        }
    }

    WlSessionLock {
        id: lock
        locked: Lock.locked
        onSecureChanged: Lock.secure = secure

        WlSessionLockSurface {
            id: surface
            color: "black"

            LoginScreen {
                id: screen
                anchors.fill: parent
                main: MainScreen.name === surface.screen?.name
                backdrop: Component {
                    WallpaperImage {}
                }
                aside: Component {
                    LockInfo {}
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
                Component.onCompleted: if (main) focusField()
            }
        }
    }
}

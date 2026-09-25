import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Widgets

// App notification: icon, app name, time, title, text. The same card as a banner at the
// top right (Banners.qml) and in the notification centre; the frame is Banner.qml.
Banner {
    id: card

    // A live Notification (banner) or a history entry (notification centre)
    property var n
    // Banner: hides itself (timeout from Banners.qml). In the centre it stays until removed.
    property bool banner: false

    readonly property var live: banner ? n : n?.live ?? null
    readonly property bool critical: n?.urgency === NotificationUrgency.Critical
    readonly property string iconSource: {
        if (!n)
            return "";
        if (n.image)
            return n.image;
        if (n.appIcon)
            return n.appIcon.startsWith("/") ? "file://" + n.appIcon : Quickshell.iconPath(n.appIcon, "dialog-information");
        return Quickshell.iconPath("dialog-information");
    }

    // "jetzt", "vor 5 Min.", "14:02"
    readonly property date arrived: banner ? new Date() : NotificationStore.timeOf(n)
    Component.onCompleted: updateAge()
    property string age: "jetzt"
    function updateAge() {
        const minutes = Math.floor((Date.now() - arrived.getTime()) / 60000);
        age = minutes < 1 ? "jetzt" : minutes < 60 ? `vor ${minutes} Min.` : Qt.formatTime(arrived, "HH:mm");
    }
    Timer {
        interval: 30000
        running: !card.banner
        repeat: true
        onTriggered: card.updateAge()
    }

    animated: banner
    implicitHeight: content.implicitHeight + 24

    // Click: the notification's default action, otherwise just close the banner.
    // The banner hides; the notification stays in the centre.
    onClicked: {
        const action = live?.actions?.find(a => a.identifier === "default") ?? null;
        if (action)
            action.invoke();
        else if (banner)
            n?.dismiss();
        leave();
    }
    // ×: gone for good (also from the centre)
    onCloseClicked: {
        if (banner)
            n?.dismiss();
        else
            NotificationStore.remove(n.key);
        leave();
    }
    // Closed by the app or expired → the banner goes
    Connections {
        target: card.banner ? card.n : null
        ignoreUnknownSignals: true
        function onClosed() {
            card.leave();
        }
    }

    Row {
        id: content
        x: 12
        y: 12
        width: parent.width - 24
        spacing: 10

        IconImage {
            implicitSize: 36
            source: card.iconSource
            asynchronous: true
        }

        Column {
            width: parent.width - 46
            spacing: 2

            Item {
                width: parent.width
                height: appName.implicitHeight

                Text {
                    id: appName
                    text: NotificationStore.nameOf(card.n).toUpperCase()
                    font.family: Config.fontSans
                    font.pixelSize: 10
                    font.letterSpacing: 0.4
                    color: Config.textSecondary
                }
                Text {
                    anchors.right: parent.right
                    text: card.age
                    font.family: Config.fontSans
                    font.pixelSize: 11
                    color: Config.textSecondary
                }
            }
            Text {
                width: parent.width
                text: card.n?.summary ?? ""
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: Config.fontSans
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: Config.text
            }
            Text {
                width: parent.width
                visible: text !== ""
                text: card.n?.body ?? ""
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: 6
                elide: Text.ElideRight
                font.family: Config.fontSans
                font.pixelSize: 13
                color: Config.text
                opacity: 0.85
            }
        }
    }
}

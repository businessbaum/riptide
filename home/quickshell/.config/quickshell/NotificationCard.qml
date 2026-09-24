import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Widgets

// One notification banner: icon, app name, time, title, text; × while hovering.
Rectangle {
    id: card

    property var n
    // Banner: hides itself after a while. In the centre the card stays until dismissed.
    property bool banner: false
    signal done

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
    readonly property date arrived: NotificationStore.timeOf(n)
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

    implicitHeight: content.implicitHeight + 24
    radius: Config.radiusPanel
    color: Config.glassMenu
    border.color: Config.border

    // Gone from the server (closed by the app or expired) → remove the banner
    Connections {
        target: card.n
        function onClosed() {
            card.done();
        }
    }

    Timer {
        id: expire
        interval: card.n && card.n.expireTimeout > 0 ? card.n.expireTimeout : 5000
        running: card.banner && !card.critical && !mouse.containsMouse
        onTriggered: card.done() // banner hides; the notification stays for the centre
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
                    text: (card.n?.appName ?? "").toUpperCase()
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

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            const action = card.n?.actions.find(a => a.identifier === "default") ?? null;
            if (action)
                action.invoke();
            else
                card.n?.dismiss();
            card.done();
        }
    }

    // × in the top left corner while hovering, like on a Mac
    Rectangle {
        visible: mouse.containsMouse || closeMouse.containsMouse
        x: -6
        y: -6
        width: 20
        height: 20
        radius: 10
        color: Config.glassMenu
        border.color: Config.border

        Text {
            anchors.centerIn: parent
            text: ""
            font.family: Config.fontSymbols
            font.pixelSize: 10
            color: Config.text
        }
        MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                card.n?.dismiss();
                card.done();
            }
        }
    }
}

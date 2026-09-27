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
    // The app's own buttons ("Als gelesen markieren" …; the default action is the click
    // on the card) and, for apps that take one, an answer typed right here
    readonly property var buttons: (live?.actions ?? []).filter(a => a.identifier !== "default" && a.text).slice(0, 3)
    readonly property bool canReply: live?.hasInlineReply ?? false
    property bool replying: false
    // In the centre: the front card of a stack of this app's notifications (how many lie
    // behind it). A click opens the stack, × clears it.
    property int stack: 0
    signal openStack
    onReplyingChanged: if (banner) Banners.typing = replying
    busy: replying
    Component.onDestruction: if (banner && replying) Banners.typing = false
    readonly property bool critical: n?.urgency === NotificationUrgency.Critical
    // The picture: what the notification brings (a photo, an avatar), else the icon of the
    // app that sent it (its start entry, like in the dock), else the icon it names
    readonly property string picture: {
        if (!n)
            return "";
        const image = n.image || (n.live?.image ?? "");
        if (image)
            return image;
        if (n.appIcon?.startsWith("/"))
            return "file://" + n.appIcon;
        return "";
    }
    // (the system's own messages carry the System Settings icon, as on a Mac)
    readonly property var appEntry: !n ? null : NotificationStore.entryOf(n) ?? Apps.entryById(n.app ?? "")
        ?? (NotificationStore.systemApps.includes(n.appName ?? n.app) ? Apps.entryById("org.riptide.SystemSettings") : null)

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
        if (stack > 0)
            return openStack();
        const action = live?.actions?.find(a => a.identifier === "default") ?? null;
        if (action)
            action.invoke();
        else if (banner)
            n?.dismiss();
        leave();
    }
    // ×: gone for good (also from the centre)
    onCloseClicked: {
        if (stack > 0)
            return NotificationStore.removeGroup(NotificationStore.groupOf(n));
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

        Item {
            width: 36
            height: 36
            IconImage {
                visible: card.picture !== ""
                implicitSize: 36
                source: card.picture
                asynchronous: true
            }
            AppIcon {
                visible: card.picture === ""
                size: 36
                entry: card.appEntry
                appId: card.n?.appIcon || card.n?.app || "dialog-information"
            }
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
                    text: card.stack > 0 ? `${card.stack} weitere · ${card.age}` : card.age
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
                id: bodyText
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

            // buttons of the notification, and "Antworten"
            Row {
                visible: (card.buttons.length > 0 || card.canReply) && !card.replying
                topPadding: 6
                spacing: 6
                Repeater {
                    model: card.buttons
                    delegate: pill
                }
                Loader {
                    active: card.canReply
                    sourceComponent: pill
                    property var modelData: ({ text: "Antworten", reply: true })
                }
            }
            // the answer: Enter sends, Esc gives up
            Rectangle {
                visible: card.replying
                width: parent.width
                height: 30
                radius: 8
                color: Config.tile
                border.color: Config.accent
                TextInput {
                    id: reply
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Config.fontSans
                    font.pixelSize: 13
                    color: Config.text
                    clip: true
                    onAccepted: {
                        if (text.trim() !== "")
                            card.live?.sendInlineReply(text);
                        card.replying = false;
                        card.leave();
                    }
                    Keys.onEscapePressed: card.replying = false
                    Text {
                        visible: reply.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: card.live?.inlineReplyPlaceholder || "Antworten …"
                        font: reply.font
                        color: Config.textSecondary
                    }
                }
            }
        }
    }

    Component {
        id: pill
        Rectangle {
            required property var modelData
            width: label.implicitWidth + 20
            height: 26
            radius: 13
            color: pillMouse.containsMouse ? Config.hover : Config.tile
            border.color: Config.border
            Text {
                id: label
                anchors.centerIn: parent
                text: parent.modelData.text
                font.family: Config.fontSans
                font.pixelSize: 12
                color: Config.text
            }
            MouseArea {
                id: pillMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    if (parent.modelData.reply) {
                        card.replying = true;
                        reply.forceActiveFocus();
                        return;
                    }
                    parent.modelData.invoke();
                    card.leave();
                }
            }
        }
    }
}

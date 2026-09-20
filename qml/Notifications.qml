// Desktop notifications: a NotificationServer (org.freedesktop.Notifications)
// with popups styled like the rest of the shell.
//
// The window follows the focused monitor and is mapped only while something is
// showing; the server object is a child and so exists regardless. Newest is on
// top; up to `maxVisible` cards are shown and any excess is stacked behind the
// bottom one like a hand of cards. A notification auto-dismisses after its
// expireTimeout (0 = never, -1 = the 5s default) unless hovered, with a
// countdown ring; critical ones never auto-dismiss. Clicking the body invokes
// the default action (or dismisses), and each advertised action gets a button.
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: root

    required property Theme theme

    readonly property var notifications: server.trackedNotifications.values
    // Newest first.
    readonly property var ordered: notifications.slice().reverse()
    readonly property int maxVisible: {
        var n = parseInt(Quickshell.env("QSHELL_NOTIFICATION_LIMIT"));
        return isNaN(n) || n < 1 ? 4 : n;
    }
    readonly property int overflowCount: Math.max(0, ordered.length - maxVisible)

    // The screen currently focused by Hyprland, matched to a Quickshell screen.
    readonly property var focusedScreen: {
        var monitor = Hyprland.focusedMonitor;
        if (!monitor)
            return null;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === monitor.name)
                return screens[i];
        }
        return null;
    }

    visible: notifications.length > 0
    screen: focusedScreen
    anchors {
        top: true
        right: true
    }
    margins.top: 40
    margins.right: 8
    implicitWidth: 360
    implicitHeight: column.implicitHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications"
    // Never take keyboard focus: notifications must not steal typing.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    NotificationServer {
        id: server

        // Advertise everything so apps send markup, images and actions.
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        imageSupported: true
        actionsSupported: true
        actionIconsSupported: true
        persistenceSupported: true
        keepOnReload: true

        onNotification: notification => {
            notification.tracked = true;
        }
    }

    Column {
        id: column

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        spacing: 8

        Repeater {
            model: root.ordered

            Item {
                id: card

                required property var modelData
                required property int index

                readonly property var notification: modelData
                readonly property bool critical: notification.urgency === NotificationUrgency.Critical
                readonly property var buttonActions: (notification.actions || []).filter(a => a.identifier !== "default")
                readonly property string iconSource: {
                    if (!notification.appIcon)
                        return "";
                    var path = Quickshell.iconPath(notification.appIcon, true);
                    return path !== "" ? path : notification.appIcon;
                }
                readonly property int autoMs: {
                    // Critical notifications stay until dismissed, as the spec
                    // asks. A sender can keep a normal one too by requesting
                    // `expire_timeout = 0` (`notify-send -t 0`).
                    if (critical)
                        return -1;
                    if (notification.expireTimeout === 0)
                        return -1;
                    if (notification.expireTimeout > 0)
                        return Math.round(notification.expireTimeout * 1000);
                    return 5000;
                }
                // Beyond the cap, cards are created (so their countdown still
                // runs) but not laid out.
                readonly property bool shown: index < root.maxVisible
                readonly property bool stacked: index === root.maxVisible - 1 && root.overflowCount > 0
                readonly property int ghostCount: stacked ? Math.min(root.overflowCount, 3) : 0

                width: column.width
                implicitHeight: surface.height + ghostCount * 6
                visible: shown

                // 1 -> 0 over the auto-dismiss window. The animation *is* the
                // timer: it pauses (restarts) with hover, and expiring on finish
                // keeps the countdown ring and the dismissal on one clock.
                property real remaining: 1

                NumberAnimation {
                    target: card
                    property: "remaining"
                    from: 1
                    to: 0
                    duration: card.autoMs > 0 ? card.autoMs : 1
                    running: card.autoMs > 0 && !hover.hovered
                    onFinished: card.notification.expire()
                }

                // The excess, peeking out behind the bottom card.
                Repeater {
                    model: card.ghostCount

                    Rectangle {
                        required property int index

                        x: (index + 1) * 4
                        y: (index + 1) * 6
                        z: -1 - index
                        width: card.width - (index + 1) * 8
                        height: surface.height
                        radius: root.theme.radius
                        color: root.theme.surface
                        border.width: 1
                        border.color: root.theme.surfaceAlt
                        opacity: 0.6 - index * 0.15
                    }
                }

                Rectangle {
                    id: surface

                    width: parent.width
                    height: content.implicitHeight + 20
                    z: 0
                    radius: root.theme.radius
                    color: root.theme.surface
                    border.width: 1
                    border.color: card.critical ? root.theme.danger : root.theme.surfaceAlt

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            var actions = card.notification.actions || [];
                            for (var i = 0; i < actions.length; i++) {
                                if (actions[i].identifier === "default") {
                                    actions[i].invoke();
                                    return;
                                }
                            }
                            card.notification.dismiss();
                        }
                    }

                    ColumnLayout {
                        id: content

                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            leftMargin: 12
                            rightMargin: 12
                            topMargin: 10
                        }
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            IconImage {
                                visible: card.iconSource !== ""
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                implicitSize: 24
                                source: card.iconSource
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: card.notification.appName
                                    color: root.theme.subtext
                                    font.family: root.theme.fontFamily
                                    font.pixelSize: root.theme.fontSizeTiny
                                }

                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: card.notification.summary
                                    color: root.theme.text
                                    font.family: root.theme.fontFamily
                                    font.pixelSize: root.theme.fontSizeSmall
                                    font.bold: true
                                }
                            }

                            // Close control. A self-closing card shows the
                            // countdown ring, which turns into a close button
                            // on hover; a manual-closing card always shows the
                            // close button. Clicking it dismisses.
                            Item {
                                id: notifControl

                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                width: 16
                                height: 16

                                readonly property bool showClose: card.autoMs <= 0 || hover.hovered

                                Canvas {
                                    id: countdown

                                    anchors.centerIn: parent
                                    visible: !notifControl.showClose
                                    width: 14
                                    height: 14

                                    onPaint: {
                                        var ctx = getContext("2d");
                                        ctx.reset();
                                        var c = width / 2;
                                        ctx.lineWidth = 2;
                                        ctx.strokeStyle = root.theme.accent;
                                        ctx.beginPath();
                                        ctx.arc(c, c, c - 1, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * card.remaining, false);
                                        ctx.stroke();
                                    }

                                    Connections {
                                        target: card

                                        function onRemainingChanged() {
                                            countdown.requestPaint();
                                        }
                                    }

                                    Component.onCompleted: requestPaint()
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: notifControl.showClose
                                    text: "󰅖"
                                    color: controlArea.containsMouse ? root.theme.danger : root.theme.overlay
                                    font.family: root.theme.fontFamily
                                    font.pixelSize: root.theme.fontSizeSmall
                                }

                                MouseArea {
                                    id: controlArea

                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    onClicked: card.notification.dismiss()
                                }
                            }
                        }

                        Image {
                            visible: card.notification.image !== ""
                            Layout.fillWidth: true
                            Layout.preferredHeight: visible ? 160 : 0
                            source: card.notification.image
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }

                        Text {
                            id: bodyText

                            visible: card.notification.body !== ""
                            Layout.fillWidth: true
                            text: card.notification.body
                            textFormat: Text.RichText
                            wrapMode: Text.Wrap
                            color: root.theme.subtext
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fontSizeSmall

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                hoverEnabled: true
                                // Let a click that is not on a link fall through
                                // to the card's default-action/dismiss handler.
                                propagateComposedEvents: true
                                cursorShape: bodyText.linkAt(mouseX, mouseY) !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: mouse => {
                                    var link = bodyText.linkAt(mouse.x, mouse.y);
                                    if (link !== "") {
                                        Qt.openUrlExternally(link);
                                        mouse.accepted = true;
                                    } else {
                                        mouse.accepted = false;
                                    }
                                }
                            }
                        }

                        RowLayout {
                            visible: card.buttonActions.length > 0
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: card.buttonActions

                                Rectangle {
                                    required property var modelData

                                    Layout.fillWidth: true
                                    implicitHeight: 28
                                    radius: root.theme.itemRadius
                                    color: actionArea.containsMouse ? root.theme.accent : root.theme.surfaceAlt

                                    Text {
                                        anchors.centerIn: parent
                                        width: parent.width - 12
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        text: modelData.text
                                        color: actionArea.containsMouse ? root.theme.base : root.theme.text
                                        font.family: root.theme.fontFamily
                                        font.pixelSize: root.theme.fontSizeTiny
                                    }

                                    MouseArea {
                                        id: actionArea

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: modelData.invoke()
                                    }
                                }
                            }
                        }
                    }
                }

                HoverHandler {
                    id: hover
                }
            }
        }
    }
}

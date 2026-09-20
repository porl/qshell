// Session menu: a full-screen overlay toggled by the qshell bridge.
//
// The overlay animates itself in QML (the backdrop fades, the card scales), so
// the compositor must not animate the layer surface too (`no_anim` in the
// Hyprland layer rules) — that would scale the whole-surface blur as a
// rectangle. `shown` drives the visuals; `visible` only maps/unmaps, a beat
// after the close animation has finished.
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: menu

    required property Theme theme

    visible: false
    property bool shown: false
    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-session"

    property int current: 1

    Timer {
        id: closeTimer

        interval: 170
        onTriggered: menu.visible = false
    }

    function open(): void {
        closeTimer.stop();
        visible = true;
        shown = true;
        scope.forceActiveFocus();
    }

    function close(): void {
        shown = false;
        closeTimer.restart();
    }

    function toggle(): void {
        if (shown)
            close();
        else
            open();
    }

    function run(action: string): void {
        close();
        if (action === "lock")
            Quickshell.execDetached(["hyprlock"]);
        else if (action === "logout")
            Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.exit()"]);
        else if (action === "reboot")
            Quickshell.execDetached(["systemctl", "reboot"]);
        else if (action === "poweroff")
            Quickshell.execDetached(["systemctl", "poweroff"]);
    }

    ListModel {
        id: actions

        ListElement { label: "Lock"; action: "lock" }
        ListElement { label: "Log out"; action: "logout" }
        ListElement { label: "Restart"; action: "reboot" }
        ListElement { label: "Shut down"; action: "poweroff" }
        ListElement { label: "Cancel"; action: "cancel" }
    }

    Rectangle {
        anchors.fill: parent
        color: menu.theme.backdrop
        opacity: menu.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutQuad
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: menu.close()
        }
    }

    Rectangle {
        id: card

        anchors.centerIn: parent
        width: 260
        height: column.implicitHeight + 32
        radius: menu.theme.radius
        color: menu.theme.surface
        border.width: 1
        border.color: menu.theme.border
        scale: menu.shown ? 1 : 0.92
        opacity: menu.shown ? 1 : 0

        Behavior on scale {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutBack
                easing.overshoot: 1.1
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutQuad
            }
        }

        MouseArea {
            anchors.fill: parent
        }

        FocusScope {
            id: scope

            anchors.fill: parent
            focus: true

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    menu.visible = false;
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                    menu.current = (menu.current + 1) % actions.count;
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    menu.current = (menu.current + actions.count - 1) % actions.count;
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    menu.run(actions.get(menu.current).action);
                    event.accepted = true;
                }
            }

            Column {
                id: column

                anchors.centerIn: parent
                width: parent.width - 32
                spacing: 8

                Repeater {
                    model: actions

                    Rectangle {
                        required property string label
                        required property string action
                        required property int index

                        width: column.width
                        height: 40
                        radius: menu.theme.itemRadius
                        color: index === menu.current
                            ? (action === "logout" || action === "reboot" || action === "poweroff" ? menu.theme.danger : (action === "cancel" ? menu.theme.surfaceAlt : menu.theme.accent))
                            : (area.containsMouse ? menu.theme.surfaceAlt : "transparent")

                        Text {
                            anchors.centerIn: parent
                            text: label
                            color: index === menu.current && action !== "cancel" ? menu.theme.base : menu.theme.text
                            font.family: menu.theme.fontFamily
                            font.pixelSize: menu.theme.fontSize
                        }

                        MouseArea {
                            id: area
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: menu.run(action)
                        }
                    }
                }
            }
        }
    }
}

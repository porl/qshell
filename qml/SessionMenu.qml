// Session menu: a full-screen overlay toggled by the qshell bridge.
//
// Hyprland blurs a layer surface by namespace, but the blur covers the whole
// surface, so the overlay is mapped only while open (`visible`). That is also
// what lets Hyprland play its layer animation on open and close.
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: menu

    required property Theme theme

    visible: false
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

    function toggle(): void {
        visible = !visible;
        if (visible)
            scope.forceActiveFocus();
    }

    function run(action: string): void {
        visible = false;
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

        MouseArea {
            anchors.fill: parent
            onClicked: menu.visible = false
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
        border.color: menu.theme.surfaceAlt

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
                            font.pixelSize: 14
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

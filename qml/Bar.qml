// The session top bar: a Hyprland layer-shell surface. The translucent
// background lets Hyprland's layer blur show as frosted glass (the
// `quickshell-.*` namespace is matched by the compositor's layer rule).
import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: bar

    required property Theme theme

    // Forwarded from the power block; the shell root opens the session menu.
    signal powerRequested()

    // Width of everything to the tray's right (volume, battery, power and their
    // gaps), so the tray can cap itself without colliding with the clock.
    readonly property real rightFixedWidth: volume.implicitWidth + battery.implicitWidth + power.implicitWidth + rightCluster.spacing * 3

    // On a PanelWindow these anchors are booleans meaning "attach to this screen
    // edge", not QML item anchors. exclusiveZone reserves the space so maximised
    // windows don't slide underneath.
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: 32
    exclusiveZone: 32
    color: theme.bar
    WlrLayershell.namespace: "quickshell-bar"

    Workspaces {
        id: workspaces

        theme: bar.theme
        screen: bar.screen
        height: bar.implicitHeight
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
        }
    }

    Row {
        id: rightCluster

        anchors {
            right: parent.right
            rightMargin: 8
            verticalCenter: parent.verticalCenter
        }
        height: bar.implicitHeight
        spacing: 12

        // Keep the tray clear of the centred clock. `bar.width` is the screen
        // width; the clock is centred, so half its width plus a gap is reserved.
        Tray {
            theme: bar.theme
            height: bar.implicitHeight
            maxWidth: Math.max(0, bar.width / 2 - clock.width / 2 - bar.rightFixedWidth - 8 - 16)
        }

        Volume {
            id: volume

            theme: bar.theme
            height: bar.implicitHeight
            verticalAlignment: Text.AlignVCenter
        }

        Battery {
            id: battery

            theme: bar.theme
            height: bar.implicitHeight
        }

        Power {
            id: power

            theme: bar.theme
            height: bar.implicitHeight
            verticalAlignment: Text.AlignVCenter
            onActivated: bar.powerRequested()
        }
    }

    Text {
        id: clock

        anchors.centerIn: parent
        color: theme.text
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSize
        text: Qt.formatDateTime(new Date(), "ddd d MMM  HH:mm")

        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: clock.text = Qt.formatDateTime(new Date(), "ddd d MMM  HH:mm")
        }
    }
}

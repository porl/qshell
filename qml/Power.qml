// Power block: opens the session menu.
import QtQuick

Text {
    id: power

    required property Theme theme

    signal activated()

    color: hover.containsMouse ? theme.accent : theme.text
    font.family: theme.fontFamily
    font.pixelSize: theme.fontSize
    text: "󰐥"

    MouseArea {
        id: hover

        // Extend to the screen's top-right corner so there is no dead zone.
        anchors {
            fill: parent
            rightMargin: -8
        }
        hoverEnabled: true
        onClicked: power.activated()
    }
}

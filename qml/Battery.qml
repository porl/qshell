// Battery block: a small drawn indicator + percentage from UPower. Hidden on
// machines without a battery (e.g. the test VM). Drawn rather than using an
// icon so it does not depend on an icon theme being installed.
import Quickshell
import Quickshell.Services.UPower
import QtQuick

Item {
    id: battery

    required property Theme theme

    readonly property var device: UPower.displayDevice
    readonly property bool present: device !== null && device.isLaptopBattery
    readonly property int percent: device ? Math.round(device.percentage * 100) : 0
    readonly property bool charging: device !== null && [UPowerDeviceState.Charging, UPowerDeviceState.FullyCharged, UPowerDeviceState.PendingCharge].includes(device.state)
    readonly property color levelColor: charging ? theme.accent : percent <= 20 ? theme.danger : theme.text

    visible: present
    implicitWidth: row.implicitWidth

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 4

        Item {
            width: 20
            height: 12

            Rectangle {
                width: 17
                height: 12
                radius: 3
                color: "transparent"
                border.width: 1
                border.color: battery.theme.text
            }

            Rectangle {
                x: 2
                y: 2
                width: Math.max(0, 13 * battery.percent / 100)
                height: 8
                radius: 1
                color: battery.levelColor
            }

            Rectangle {
                x: 17.5
                y: 3.5
                width: 2.5
                height: 5
                radius: 1
                color: battery.theme.text
            }
        }

        Text {
            height: 12
            verticalAlignment: Text.AlignVCenter
            color: battery.levelColor
            font.family: battery.theme.fontFamily
            font.pixelSize: 12
            text: battery.percent + "%"
        }
    }
}

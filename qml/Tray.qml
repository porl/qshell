// System tray block for the bar.
//
// Shows as many StatusNotifierItems as fit in `maxWidth`; the rest collapse
// behind an expander whose popup is a grid of the hidden icons. Every icon —
// on the bar or in the grid — uses TrayItem, so menu/mouse behaviour is
// identical in both places.
import Quickshell
import Quickshell.Services.SystemTray
import QtQuick

Item {
    id: tray

    required property Theme theme
    // Room the bar can spare, derived from the gap between the clock and the
    // fixed right-hand blocks (see Bar.qml).
    property real maxWidth: 0

    readonly property int iconSize: theme.fontSize
    readonly property int cellWidth: iconSize + 10
    readonly property int cellHeight: iconSize + 10
    readonly property int spacing: 4
    readonly property int stride: cellWidth + spacing

    readonly property var items: SystemTray.items.values
    readonly property int count: items.length

    // One cell per icon, plus one for the expander when they do not all fit.
    readonly property int capacity: Math.max(0, Math.floor((maxWidth + spacing) / stride))
    readonly property bool overflow: count > capacity
    readonly property int visibleCount: overflow ? Math.max(0, capacity - 1) : count
    readonly property var visibleItems: items.slice(0, visibleCount)
    readonly property var hiddenItems: overflow ? items.slice(visibleCount, count) : []
    readonly property int shownCells: visibleCount + (overflow ? 1 : 0)

    // Only one menu may be open at a time; each TrayItem claims this slot when
    // it opens.
    property var activePopout: null

    function claimPopout(state): void {
        if (activePopout && activePopout !== state)
            activePopout.close();
        activePopout = state;
    }

    visible: count > 0
    implicitWidth: shownCells > 0 ? shownCells * stride - spacing : 0

    Row {
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
        }
        height: tray.height
        spacing: tray.spacing

        Repeater {
            model: tray.visibleItems

            TrayItem {
                required property var modelData

                theme: tray.theme
                item: modelData
                iconSize: tray.iconSize
                claim: tray.claimPopout
            }
        }

        Item {
            id: expander

            visible: tray.overflow
            width: visible ? tray.cellWidth : 0
            height: visible ? tray.cellHeight : 0

            property PopoutState popout: PopoutState {
                openDelay: 250
            }

            Connections {
                target: expander.popout

                function onOpenChanged() {
                    if (expander.popout.open)
                        tray.claimPopout(expander.popout);
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: tray.theme.itemRadius
                color: hover.containsMouse || expander.popout.open ? tray.theme.surfaceAlt : "transparent"
            }

            Text {
                anchors.centerIn: parent
                color: hover.containsMouse || expander.popout.open ? tray.theme.accent : tray.theme.text
                font.family: tray.theme.fontFamily
                font.pixelSize: tray.theme.fontSizeSmall
                text: "»"
            }

            MouseArea {
                id: hover

                anchors.fill: parent
                hoverEnabled: true

                onContainsMouseChanged: containsMouse ? expander.popout.anchorEntered() : expander.popout.anchorExited()
                onClicked: expander.popout.hoverActivate()
            }

            TrayOverflow {
                theme: tray.theme
                items: tray.hiddenItems
                open: expander.popout.open

                anchor.item: expander
                onHoveredChanged: hovered ? expander.popout.contentEntered() : expander.popout.contentExited()
                onActivated: expander.popout.close()
            }
        }
    }
}

// Grid of tray icons that did not fit on the bar, opened from the expander.
//
// Unlike the per-icon menus this popup never pins: it is opened by hover or a
// click on the expander and closes when the pointer leaves, or after an icon is
// activated. It stays "hovered" while one of its icons has a menu open, so the
// menu's anchor does not disappear underneath it.
import Quickshell
import QtQuick

PopupWindow {
    id: overflow

    required property Theme theme
    property var items: []
    property bool open: false
    property var claim: null

    signal focusLost()
    signal activated()

    property int openMenus: 0
    readonly property bool hovered: overflowHover.hovered || openMenus > 0

    function menuToggled(active): void {
        openMenus += active ? 1 : -1;
        if (openMenus < 0)
            openMenus = 0;
    }

    visible: overflow.open
    color: "transparent"
    implicitWidth: grid.width + 20
    implicitHeight: grid.height + 20

    anchor.edges: Edges.Bottom | Edges.Right
    anchor.gravity: Edges.Bottom | Edges.Right
    anchor.adjustment: PopupAdjustment.All

    Rectangle {
        anchors.fill: parent
        radius: overflow.theme.radius
        color: overflow.theme.surface
        border.width: 1
        border.color: overflow.theme.border

        Grid {
            id: grid

            anchors.centerIn: parent
            columns: 4
            spacing: 4

            Repeater {
                model: overflow.items

                TrayItem {
                    required property var modelData

                    theme: overflow.theme
                    item: modelData
                    onMenuVisibilityChanged: open => overflow.menuToggled(open)
                    onActivated: overflow.activated()
                }
            }
        }
    }

    // Hover tracking only; does not consume presses, so the icons still work.
    Item {
        anchors.fill: parent

        HoverHandler {
            id: overflowHover
        }
    }
}

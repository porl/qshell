// One StatusNotifierItem icon. Left click runs the primary action (or opens the
// menu for menu-only items), middle click the secondary action, right click the
// menu; scroll is forwarded to the item.
//
// When the item has a menu, the icon follows the shared popout rules: hover
// opens after a delay, a click pins it, content hover keeps it open and a
// pinned menu closes when focus is lost.
import Quickshell
import Quickshell.Widgets
import QtQuick

Item {
    id: root

    required property Theme theme
    property var item: null
    property int iconSize: theme.fontSize
    // Registration callback so the tray can close any other open menu.
    property var claim: null

    readonly property bool hasMenu: item !== null && item.hasMenu
    readonly property int cellWidth: iconSize + 10
    readonly property int cellHeight: iconSize + 10
    readonly property bool menuOpen: popout.open

    signal menuVisibilityChanged(bool open)
    signal activated()

    implicitWidth: cellWidth
    implicitHeight: cellHeight

    property PopoutState popout: PopoutState {}

    onMenuOpenChanged: {
        if (menuOpen && claim)
            claim(popout);
        root.menuVisibilityChanged(menuOpen);
    }

    function closeMenu(): void {
        popout.close();
    }

    Rectangle {
        anchors.fill: parent
        radius: root.theme.itemRadius
        color: hover.containsMouse || root.menuOpen ? root.theme.surfaceAlt : "transparent"
    }

    IconImage {
        anchors.centerIn: parent
        implicitSize: root.iconSize
        width: root.iconSize
        height: root.iconSize
        source: root.item ? root.item.icon : ""
    }

    Text {
        anchors.centerIn: parent
        visible: root.item !== null && root.item.icon === ""
        color: root.theme.text
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.fontSizeTiny
        text: "▣"
    }

    MouseArea {
        id: hover

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

        onContainsMouseChanged: {
            if (!root.hasMenu)
                return;
            if (containsMouse)
                root.popout.anchorEntered();
            else
                root.popout.anchorExited();
        }

        onClicked: mouse => {
            if (!root.item)
                return;
            if (mouse.button === Qt.MiddleButton) {
                hoveredClose();
                root.item.secondaryActivate();
                root.activated();
            } else if (mouse.button === Qt.RightButton) {
                if (root.hasMenu)
                    root.popout.activate();
                else {
                    root.item.secondaryActivate();
                    root.activated();
                }
            } else if (root.item.onlyMenu && root.hasMenu) {
                root.popout.activate();
            } else {
                hoveredClose();
                root.item.activate();
                root.activated();
            }
        }

        onWheel: event => {
            if (!root.item)
                return;
            if (root.hasMenu)
                root.popout.hoverActivate();
            root.item.scroll(event.angleDelta.y, event.angleDelta.x !== 0);
        }

        // A left/middle activation is terminal: drop a menu the hover opened.
        function hoveredClose(): void {
            if (root.menuOpen && !root.popout.pinned)
                root.popout.close();
        }
    }

    TrayMenu {
        theme: root.theme
        handle: root.item ? root.item.menu : null
        open: root.popout.open && root.hasMenu
        pinned: root.popout.pinned
        isRoot: true
        anchor.item: root

        onHoveredChanged: hovered ? root.popout.contentEntered() : root.popout.contentExited()
        onFocusLost: root.popout.focusLost()
        onCloseRequested: root.popout.close()
    }
}

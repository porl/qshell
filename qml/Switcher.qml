// Window switcher: a layer-shell overlay listing the open windows, most
// recently used first, each row a live capture. The bridge drives it — a
// SUPER+Tab tap opens it, holding SUPER and tapping Tab walks it, and
// releasing SUPER commits (`switcher commit`). While it is open it can be
// typed into, walked with the arrows, committed with Enter or a click, or
// cancelled with Escape or a click on the backdrop; Shift+Enter (or a
// shift-click) brings the window to the current workspace instead.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import "SwitcherOrder.js" as Order

PanelWindow {
    id: switcher

    required property Theme theme

    visible: false
    // Visual state: the card animates itself (backdrop fades, card scales) and
    // Hyprland is told not to animate the surface, so `visible` only maps and
    // unmaps, a beat after the close animation.
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
    // Exclusive while open, released as soon as it closes: an exclusive
    // keyboard layer surface blocks focusing another window until it unmaps,
    // and the commit dispatches a focus while the close animation plays.
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-switcher"

    // All rows in show order (the focused workspace's windows first, MRU
    // within each group) and the filtered subset; `current` indexes `entries`.
    property var ordered: []
    property var entries: []
    property int current: -1
    property string query: ""
    // Most-recently-used addresses across the session, tracked from Hyprland's
    // focus changes and seeded from its focus history.
    property var mru: []

    // Tiles lay out left to right; the card shows up to five and scrolls
    // horizontally past that.
    readonly property int tileWidth: 200
    readonly property int tileHeight: 152
    readonly property int thumbHeight: 104
    readonly property int tileSpacing: 8
    readonly property int maxTiles: 5
    readonly property int visibleTiles: Math.max(1, Math.min(maxTiles, entries.length))
    readonly property int cardWidth: visibleTiles * tileWidth + (visibleTiles - 1) * tileSpacing + 16

    function open(): void {
        closeTimer.stop();
        query = "";
        field.text = "";
        refreshEntries();
        current = initialIndex();
        visible = true;
        shown = true;
        // Class and focus history only arrive with a refresh; the delegate
        // reads both live once it lands.
        Hyprland.refreshToplevels();
        scope.forceActiveFocus();
        field.forceActiveFocus();
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

    // `switcher next` / `switcher prev`: the first press opens with the most
    // recently used *other* window selected; later presses walk the list.
    function advance(delta: int): void {
        if (!shown) {
            open();
            if (delta < 0 && entries.length > 0)
                setCurrent(entries.length - 1);
            return;
        }
        move(delta);
    }

    function move(delta: int): void {
        if (entries.length === 0)
            return;
        setCurrent((current + delta + entries.length) % entries.length);
    }

    function setCurrent(index: int): void {
        current = index;
        list.positionViewAtIndex(index, ListView.Contain);
    }

    property var pendingEntry: null
    property bool pendingBringHere: false

    function commit(bringHere: bool): void {
        if (!shown || current < 0 || current >= entries.length)
            return;
        pendingEntry = entries[current];
        pendingBringHere = bringHere;
        close();
        commitTimer.restart();
    }

    function runCommit(): void {
        var entry = pendingEntry;
        if (!entry)
            return;
        pendingEntry = null;
        if (pendingBringHere)
            moveToCurrentWorkspace(entry);
        else
            activate(entry);
    }

    // The dispatcher's window selector for an entry. The QML address property
    // is bare hex, and Hyprland's selector wants the 0x prefix.
    function selector(entry): string {
        return "address:0x" + entry.address;
    }

    // Focus through the compositor rather than the wayland handle:
    // `Toplevel.activate()` silently does nothing when the shell client has
    // never had an input device (a keyboard-only switcher drive does exactly
    // that). The Lua dispatcher form is Hyprland 0.56+.
    function activate(entry): void {
        if (Hyprland.usingLua && entry.address.length > 0) {
            Hyprland.dispatch('hl.dsp.focus({ window = "' + selector(entry) + '" })');
            return;
        }
        if (entry.toplevel.wayland)
            entry.toplevel.wayland.activate();
    }

    // Move the window to the workspace that is focused now, then focus it.
    // The Lua dispatcher form is Hyprland 0.56+; on a legacy config this
    // degrades to a plain focus. One request only: a move followed by a
    // separate focus request can race.
    function moveToCurrentWorkspace(entry): void {
        if (!Hyprland.usingLua || entry.address.length === 0 || entry.workspaceId === activeWorkspaceId()) {
            activate(entry);
            return;
        }
        Hyprland.dispatch('hl.dsp.window.move({ workspace = hl.get_active_workspace(), window = "'
            + selector(entry) + '", follow = true })');
    }

    function recompute(): void {
        query = field.text;
        rebuild();
    }

    function rebuild(): void {
        // Keep the selection on the same window when it survives the filter.
        var selected = current >= 0 && current < entries.length ? entries[current].address : "";
        entries = Order.filter(ordered, query);
        var index = -1;
        for (var i = 0; i < entries.length && index < 0; i++) {
            if (entries[i].address === selected)
                index = i;
        }
        current = index >= 0 ? index : (entries.length > 0 ? 0 : -1);
    }

    // The window after the focused one: the first Tab selects the previous
    // window, not the one you are on. The list is MRU-ordered, so index 0 is
    // the most recently focused window (the active one once focus events or
    // the history seed have arrived).
    function initialIndex(): int {
        if (entries.length <= 1)
            return entries.length - 1;
        return 1;
    }

    function activeWorkspaceId(): int {
        return Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1;
    }

    function entryFor(toplevel): var {
        var info = toplevel.lastIpcObject || ({});
        var workspace = toplevel.workspace;
        return {
            toplevel: toplevel,
            address: toplevel.address,
            title: toplevel.title || "",
            class: typeof info.class === "string" ? info.class : "",
            workspaceId: workspace ? workspace.id : -1,
            workspaceName: workspace ? workspace.name : "",
            urgent: toplevel.urgent,
            focusHistoryID: typeof info.focusHistoryID === "number" ? info.focusHistoryID : undefined,
        };
    }

    // All windows in the tracked MRU order.
    function buildEntries(): var {
        var byAddress = {};
        var toplevels = Hyprland.toplevels.values;
        for (var i = 0; i < toplevels.length; i++) {
            var entry = entryFor(toplevels[i]);
            if (entry.address.length > 0)
                byAddress[entry.address] = entry;
        }
        var rows = [];
        for (var i = 0; i < mru.length; i++) {
            if (byAddress[mru[i]]) {
                rows.push(byAddress[mru[i]]);
                delete byAddress[mru[i]];
            }
        }
        // Anything the tracked order missed keeps the model's order.
        for (var i = 0; i < toplevels.length; i++) {
            var address = toplevels[i].address;
            if (byAddress[address]) {
                rows.push(byAddress[address]);
                delete byAddress[address];
            }
        }
        return rows;
    }

    // The MRU list is the authority; this prunes closed windows and appends
    // windows it has never seen.
    function reconcileMru(): void {
        var addresses = [];
        var toplevels = Hyprland.toplevels.values;
        for (var i = 0; i < toplevels.length; i++) {
            var address = toplevels[i].address;
            if (address.length > 0 && addresses.indexOf(address) === -1)
                addresses.push(address);
        }
        var next = [];
        for (var i = 0; i < mru.length; i++) {
            if (addresses.indexOf(mru[i]) >= 0 && next.indexOf(mru[i]) === -1)
                next.push(mru[i]);
        }
        for (var i = 0; i < addresses.length; i++) {
            if (next.indexOf(addresses[i]) === -1)
                next.push(addresses[i]);
        }
        mru = next;
    }

    function promote(toplevel): void {
        var address = toplevel ? toplevel.address : "";
        if (!address || address.length === 0)
            return;
        var next = [address];
        for (var i = 0; i < mru.length; i++) {
            if (mru[i] !== address)
                next.push(mru[i]);
        }
        mru = next;
    }

    // Seed from Hyprland's focus history, which the model only carries after a
    // refresh; windows already tracked keep their order.
    function seedMru(): void {
        var entries = [];
        var toplevels = Hyprland.toplevels.values;
        for (var i = 0; i < toplevels.length; i++) {
            var entry = entryFor(toplevels[i]);
            if (entry.address.length > 0)
                entries.push(entry);
        }
        var byHistory = Order.byRecency(entries);
        var next = mru.slice();
        for (var i = 0; i < byHistory.length; i++) {
            if (next.indexOf(byHistory[i].address) === -1)
                next.push(byHistory[i].address);
        }
        mru = next;
    }

    function refreshEntries(): void {
        reconcileMru();
        ordered = Order.order(buildEntries(), activeWorkspaceId());
        rebuild();
    }

    function reorder(): void {
        if (shown)
            refreshEntries();
        else
            reconcileMru();
    }

    function liveClass(entry): string {
        var info = entry.toplevel.lastIpcObject;
        if (info && typeof info.class === "string" && info.class.length > 0)
            return info.class;
        return entry.class;
    }

    function subtitle(entry): string {
        var parts = [];
        var cls = liveClass(entry);
        if (cls.length > 0)
            parts.push(cls);
        if (entry.workspaceName.length > 0 && entry.workspaceId !== activeWorkspaceId())
            parts.push("workspace " + entry.workspaceName);
        if (entry.urgent)
            parts.push("urgent");
        return parts.join("  ·  ");
    }

    Timer {
        id: closeTimer

        interval: 170
        onTriggered: switcher.visible = false
    }

    // Runs the focus/move after `close()` has released the layer surface's
    // exclusive keyboard grab.
    Timer {
        id: commitTimer

        interval: 60
        onTriggered: switcher.runCommit()
    }

    Timer {
        id: seedTimer

        interval: 400
        onTriggered: switcher.seedMru()
    }

    Component.onCompleted: {
        Hyprland.refreshToplevels();
        seedTimer.restart();
    }

    Connections {
        target: Hyprland

        function onActiveToplevelChanged(): void {
            switcher.promote(Hyprland.activeToplevel);
        }
    }

    Connections {
        target: Hyprland.toplevels

        function onObjectRemovedPost(): void {
            switcher.reorder();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: switcher.theme.backdrop
        opacity: switcher.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutQuad
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: switcher.close()
        }
    }

    FocusScope {
        id: scope

        anchors.fill: parent
        focus: true

        Rectangle {
            id: card

            anchors.centerIn: parent
            width: switcher.cardWidth
            height: layout.implicitHeight + 16
            radius: switcher.theme.radius
            color: switcher.theme.surface
            border.width: 1
            border.color: switcher.theme.border
            scale: switcher.shown ? 1 : 0.96
            opacity: switcher.shown ? 1 : 0

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

            Column {
                id: layout

                anchors {
                    left: parent.left
                    right: parent.right
                    leftMargin: 8
                    rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                spacing: 8

                TextField {
                    id: field

                    width: parent.width
                    height: 44
                    color: switcher.theme.text
                    placeholderText: "Switch window…  (Enter focuses, Shift+Enter brings it here)"
                    placeholderTextColor: switcher.theme.overlay
                    font.family: switcher.theme.fontFamily
                    font.pixelSize: switcher.theme.fontSize
                    leftPadding: 12
                    rightPadding: 12
                    selectByMouse: true
                    background: Rectangle {
                        radius: switcher.theme.itemRadius
                        color: switcher.theme.base
                        border.width: 1
                        border.color: field.activeFocus ? switcher.theme.accent : switcher.theme.border
                    }
                    onTextChanged: switcher.recompute()

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            switcher.close();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Right) {
                            switcher.move(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Left) {
                            switcher.move(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            switcher.commit((event.modifiers & Qt.ShiftModifier) !== 0);
                            event.accepted = true;
                        }
                    }
                }

                Text {
                    width: parent.width
                    height: 40
                    visible: switcher.entries.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: switcher.ordered.length === 0 ? "No open windows" : "No matching windows"
                    color: switcher.theme.overlay
                    font.family: switcher.theme.fontFamily
                    font.pixelSize: switcher.theme.fontSizeSmall
                }

                ListView {
                    id: list

                    width: parent.width
                    height: switcher.entries.length > 0 ? switcher.tileHeight : 0
                    visible: switcher.entries.length > 0
                    orientation: ListView.Horizontal
                    spacing: switcher.tileSpacing
                    clip: true
                    model: switcher.entries
                    currentIndex: switcher.current
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Item {
                        required property var modelData
                        required property int index

                        width: switcher.tileWidth
                        height: switcher.tileHeight

                        Rectangle {
                            anchors.fill: parent
                            radius: switcher.theme.itemRadius
                            color: index === switcher.current || hover.containsMouse ? switcher.theme.surfaceAlt : "transparent"
                        }

                        ClippingRectangle {
                            id: thumb

                            anchors {
                                top: parent.top
                                left: parent.left
                                right: parent.right
                                topMargin: 6
                                leftMargin: 6
                                rightMargin: 6
                            }
                            height: switcher.thumbHeight
                            radius: 6
                            color: switcher.theme.base
                            border.width: index === switcher.current ? 2 : 1
                            border.color: index === switcher.current ? switcher.theme.accent : switcher.theme.border

                            ScreencopyView {
                                anchors.fill: parent
                                captureSource: switcher.shown ? modelData.toplevel.wayland : null
                                live: true
                            }
                        }

                        Column {
                            anchors {
                                top: thumb.bottom
                                left: parent.left
                                right: parent.right
                                topMargin: 5
                                leftMargin: 8
                                rightMargin: 8
                            }
                            spacing: 1

                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                color: switcher.theme.text
                                font.family: switcher.theme.fontFamily
                                font.pixelSize: switcher.theme.fontSize
                                text: modelData.toplevel.title.length > 0 ? modelData.toplevel.title : "(untitled)"
                            }

                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                visible: text.length > 0
                                color: switcher.theme.overlay
                                font.family: switcher.theme.fontFamily
                                font.pixelSize: switcher.theme.fontSizeSmall
                                text: switcher.subtitle(modelData)
                            }
                        }

                        MouseArea {
                            id: hover

                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: mouse => {
                                switcher.setCurrent(index);
                                switcher.commit((mouse.modifiers & Qt.ShiftModifier) !== 0);
                            }
                        }
                    }
                }
            }
        }
    }
}

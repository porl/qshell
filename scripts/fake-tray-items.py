#!/usr/bin/env python3
"""TEST-ONLY helper: register N fake StatusNotifierItems to exercise a tray's
tooltips, menus and overflow. Not used by the qshell bridge or the Nix package —
nothing in `bin/` or the build depends on this script.

Each item lives on one connection at its own object path and is registered with
the StatusNotifierWatcher by path, so the host sees a normal registered item.
Icons are generated 32x32 ARGB32 pixmaps (big-endian, per the SNI spec) with a
distinct hue per item, so they exercise the pixmap path rather than the icon
theme.

Items selected by --menus serve a com.canonical.dbusmenu tree on a sibling
object path, exposed as the item's Menu property. The tree has an activatable
leaf, a submenu with a nested submenu inside it, a checkmark row (a click
toggles it and pushes ItemsPropertiesUpdated), a separator and a disabled row.
Right-click opens it; --menu-only also opens it on left click (ItemIsMenu).
Every call the items receive (activate, secondary activate, scroll, menu
events) is printed, so a hand-drive can be followed from here.

Requirements: python3 with dbus-python and PyGObject (GLib) — system packages,
deliberately not pulled in by the flake.

    python3 scripts/fake-tray-items.py [N] [--menus SPEC] [--menu-only SPEC]
                                       [--name NAME] [--no-register]

SPEC selects items by 1-based index: `none` (the default), `all`, or a list
like `1,3,5-7`.

Stop by killing the process (or SIGINT); dropping the connection unregisters
every item. dbus-python has no property decorator, so properties are served
through a hand-written org.freedesktop.DBus.Properties.GetAll, which is what
QtDBus asks for.
"""

import argparse
import signal
import struct
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

IFACE = "org.kde.StatusNotifierItem"
PROPS = "org.freedesktop.DBus.Properties"
MENU_IFACE = "com.canonical.dbusmenu"
PATH_ROOT = "/StatusNotifierItem"
MENU_ROOT = "/FakeMenu"


def log(message):
    print(message, flush=True)


def make_pixmap(hue):
    """A 32x32 ARGB32 (network byte order) square with a white border."""
    import colorsys

    r, g, b = (int(c * 255) for c in colorsys.hsv_to_rgb(hue, 0.75, 0.9))
    size = 32
    data = bytearray()
    for y in range(size):
        for x in range(size):
            if x == 0 or y == 0 or x == size - 1 or y == size - 1:
                a, rr, gg, bb = 255, 255, 255, 255
            else:
                a, rr, gg, bb = 255, r, g, b
            data += struct.pack(">I", (a << 24) | (rr << 16) | (gg << 8) | bb)
    return dbus.Struct(
        (dbus.Int32(size), dbus.Int32(size), dbus.Array(data, signature="y")),
        signature="iiay",
    )


def demo_menu_tree():
    """The menu every --menus item serves, as {id: {props, children}}. Id 0 is
    the root; Quickshell asks for the root first and then for each parent whose
    submenu opens, so every id must be reachable by GetLayout."""

    def leaf(label, **props):
        return {"props": {"label": dbus.String(label), **props}, "children": []}

    def parent(label, children):
        return {
            "props": {
                "label": dbus.String(label),
                "children-display": dbus.String("submenu"),
            },
            "children": children,
        }

    return {
        0: {"props": {}, "children": [1, 2, 3, 8, 9]},
        1: leaf("Activate me"),
        2: leaf("Say hello"),
        3: parent("Submenu", [4, 7]),
        4: parent("Nested", [5, 6]),
        5: leaf("Deep leaf"),
        6: leaf("Deep disabled leaf", enabled=dbus.Boolean(False)),
        7: {
            "props": {
                "label": dbus.String("Checkable"),
                "toggle-type": dbus.String("checkmark"),
                "toggle-state": dbus.Int32(0),
            },
            "children": [],
        },
        8: {"props": {"type": dbus.String("separator")}, "children": []},
        9: {
            "props": {
                "label": dbus.String("Disabled row"),
                "enabled": dbus.Boolean(False),
                "children-display": dbus.String("submenu"),
            },
            "children": [10],
        },
        10: leaf("Unreachable"),
    }


class FakeMenu(dbus.service.Object):
    """A com.canonical.dbusmenu tree: Quickshell reads it with GetLayout after
    AboutToShow, and reports row clicks back through Event."""

    def __init__(self, bus, path, name):
        super().__init__(bus, path)
        self.path = path
        self.name = name
        self.tree = demo_menu_tree()
        self.revision = 1

    def _node(self, item_id, depth):
        node = self.tree[item_id]
        children = []
        if depth != 0:
            for child in node["children"]:
                children.append(self._node(child, depth - 1 if depth > 0 else depth))
        return dbus.Struct(
            (
                dbus.Int32(item_id),
                dbus.Dictionary(node["props"], signature="sv"),
                dbus.Array(children, signature="v"),
            ),
            signature="ia{sv}av",
        )

    @dbus.service.method(MENU_IFACE, in_signature="iias", out_signature="u(ia{sv}av)")
    def GetLayout(self, parent_id, recursion_depth, property_names):
        return dbus.UInt32(self.revision), self._node(int(parent_id), int(recursion_depth))

    @dbus.service.method(MENU_IFACE, in_signature="i", out_signature="b")
    def AboutToShow(self, item_id):
        return dbus.Boolean(False)

    @dbus.service.method(MENU_IFACE, in_signature="isvu", out_signature="")
    def Event(self, item_id, event_id, data, timestamp):
        item_id = int(item_id)
        event = str(event_id)
        props = self.tree[item_id]["props"]
        if "label" in props:
            label = str(props["label"])
        else:
            label = "root" if item_id == 0 else "separator"
        log(f"{self.name}: menu {event} on [{item_id}] {label}")
        if event == "clicked" and "toggle-type" in props:
            state = dbus.Int32(0 if int(props["toggle-state"]) == 1 else 1)
            props["toggle-state"] = state
            self.revision += 1
            self.ItemsPropertiesUpdated(
                [
                    dbus.Struct(
                        (dbus.Int32(item_id), dbus.Dictionary({"toggle-state": state}, signature="sv")),
                        signature="ia{sv}",
                    )
                ],
                [],
            )

    @dbus.service.signal(MENU_IFACE, signature="a(ia{sv})a(ias)")
    def ItemsPropertiesUpdated(self, updated, removed):
        pass

    def _properties(self):
        return {
            "Version": dbus.UInt32(3),
            "TextDirection": dbus.String("ltr"),
            "Status": dbus.String("normal"),
            "IconThemePath": dbus.Array([], signature="s"),
        }

    @dbus.service.method(PROPS, in_signature="ss", out_signature="v")
    def Get(self, interface, prop):
        return self._properties()[prop]

    @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return dbus.Dictionary(self._properties(), signature="sv")


class FakeItem(dbus.service.Object):
    def __init__(self, bus, path, index, menu=None, menu_only=False):
        super().__init__(bus, path)
        self.index = index
        self.title = f"Fake Tray {index + 1}"
        self.pixmap = make_pixmap((index * 0.137) % 1.0)
        self.menu_path = menu
        self.menu_only = menu_only

    @dbus.service.method(IFACE, in_signature="ii", out_signature="")
    def Activate(self, x, y):
        log(f"{self.title}: activate")

    @dbus.service.method(IFACE, in_signature="ii", out_signature="")
    def SecondaryActivate(self, x, y):
        log(f"{self.title}: secondary activate")

    @dbus.service.method(IFACE, in_signature="is", out_signature="")
    def Scroll(self, delta, orientation):
        log(f"{self.title}: scroll {int(delta)} {orientation}")

    @dbus.service.method(IFACE, in_signature="ii", out_signature="")
    def ContextMenu(self, x, y):
        log(f"{self.title}: context menu")

    @dbus.service.signal(IFACE, signature="")
    def NewIcon(self):
        pass

    @dbus.service.signal(IFACE, signature="")
    def NewAttentionIcon(self):
        pass

    @dbus.service.signal(IFACE, signature="")
    def NewOverlayIcon(self):
        pass

    @dbus.service.signal(IFACE, signature="")
    def NewToolTip(self):
        pass

    @dbus.service.signal(IFACE, signature="s")
    def NewStatus(self, status):
        pass

    @dbus.service.signal(IFACE, signature="s")
    def NewTitle(self, title):
        pass

    def _properties(self):
        if self.menu_path is not None:
            if self.menu_only:
                kind = "menu-only"
            else:
                kind = "has menu"
        else:
            kind = "no menu"
        props = {
            "Category": dbus.String("ApplicationStatus"),
            "Id": dbus.String(f"fake-{self.index + 1}"),
            "Title": dbus.String(self.title),
            "Status": dbus.String("Active"),
            "IconName": dbus.String(""),
            "IconPixmap": dbus.Array([self.pixmap], signature="(iiay)"),
            "OverlayIconName": dbus.String(""),
            "OverlayIconPixmap": dbus.Array([], signature="(iiay)"),
            "AttentionIconName": dbus.String(""),
            "AttentionIconPixmap": dbus.Array([], signature="(iiay)"),
            "ToolTip": dbus.Struct(
                (
                    dbus.String(""),
                    dbus.Array([], signature="(iiay)"),
                    dbus.String(self.title),
                    dbus.String(f"Fake item for tray drive testing ({kind})"),
                ),
                signature="sa(iiay)ss",
            ),
            "ItemIsMenu": dbus.Boolean(self.menu_only),
        }
        if self.menu_path is not None:
            props["Menu"] = dbus.ObjectPath(self.menu_path)
        return props

    @dbus.service.method(PROPS, in_signature="ss", out_signature="v")
    def Get(self, interface, prop):
        return self._properties()[prop]

    @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return dbus.Dictionary(self._properties(), signature="sv")


def parse_selection(parser, spec, count, option):
    """`none`, `all`, or 1-based indices/ranges -> a set of 0-based indices."""
    if spec == "none":
        return set()
    if spec == "all":
        return set(range(count))

    selected = set()
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            low, _, high = part.partition("-")
            indices = range(int(low), int(high) + 1)
        else:
            indices = [int(part)]
        for index in indices:
            if not 1 <= index <= count:
                parser.error(f"{option}: item {index} is outside 1..{count}")
            selected.add(index - 1)
    return selected


def main():
    parser = argparse.ArgumentParser(
        description="Register fake StatusNotifierItems to test a tray's tooltips, menus and overflow."
    )
    parser.add_argument("count", nargs="?", type=int, default=18, help="number of items (default 18)")
    parser.add_argument(
        "--menus",
        default="none",
        metavar="SPEC",
        help="items that serve a D-Bus menu: none (default), all, or 1-based indices/ranges like 1,3,5-7",
    )
    parser.add_argument(
        "--menu-only",
        default="none",
        metavar="SPEC",
        help="items whose left click opens the menu instead of activating (ItemIsMenu); implies --menus",
    )
    parser.add_argument(
        "--name",
        default=None,
        help="also request this well-known bus name, e.g. to inspect the objects with busctl",
    )
    parser.add_argument(
        "--no-register",
        action="store_true",
        help="serve the objects but do not register the items with the StatusNotifierWatcher",
    )
    args = parser.parse_args()
    if args.count < 1:
        parser.error("N must be at least 1")

    menus = parse_selection(parser, args.menus, args.count, "--menus")
    menu_only = parse_selection(parser, args.menu_only, args.count, "--menu-only") - menus
    menu_items = menus | menu_only

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    # Keep the name object alive; releasing it when it is collected would drop
    # the well-known name.
    if args.name:
        named = dbus.service.BusName(args.name, bus)  # noqa: F841

    items = []
    for i in range(args.count):
        path = f"{PATH_ROOT}/{i}"
        menu = None
        if i in menu_items:
            menu = f"{MENU_ROOT}/{i}"
            FakeMenu(bus, menu, f"fake-{i + 1}")
        items.append(FakeItem(bus, path, i, menu=menu, menu_only=i in menu_only))

    if not args.no_register:
        watcher = bus.get_object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher")
        register = watcher.get_dbus_method(
            "RegisterStatusNotifierItem", "org.kde.StatusNotifierWatcher"
        )
        for i in range(args.count):
            register(f"{PATH_ROOT}/{i}")
        summary = f"registered {args.count} fake tray item(s)"
    else:
        summary = f"serving {args.count} fake tray item(s) (not registered)"

    for label, selection in (("menus", menus), ("menu-only", menu_only)):
        if selection:
            summary += f"; {label}: {','.join(str(i + 1) for i in sorted(selection))}"
    log(f"{summary} — ^C to remove")

    loop = GLib.MainLoop()

    def stop(*_):
        loop.quit()

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    loop.run()


if __name__ == "__main__":
    main()

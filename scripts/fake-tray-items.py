#!/usr/bin/env python3
"""TEST-ONLY helper: register N fake StatusNotifierItems to exercise a tray's
overflow. Not used by the qshell bridge or the Nix package — nothing in `bin/`
or the build depends on this script.

Each item lives on one connection at its own object path and is registered with
the StatusNotifierWatcher by path, so the host sees a normal registered item.
Icons are generated 32x32 ARGB32 pixmaps (big-endian, per the SNI spec) with a
distinct hue per item, so they exercise the pixmap path rather than the icon
theme. The items have no menu, so hovering shows the tooltip instead.

Requirements: python3 with dbus-python and PyGObject (GLib) — system packages,
deliberately not pulled in by the flake.

    python3 scripts/fake-tray-items.py [N]   # default 18; Ctrl-C / kill to remove

Stop by killing the process (or SIGINT); dropping the connection unregisters
every item. dbus-python has no property decorator, so properties are served
through a hand-written org.freedesktop.DBus.Properties.GetAll, which is what
QtDBus asks for.
"""

import signal
import struct
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

IFACE = "org.kde.StatusNotifierItem"
PROPS = "org.freedesktop.DBus.Properties"
PATH_ROOT = "/StatusNotifierItem"


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


class FakeItem(dbus.service.Object):
    def __init__(self, bus, path, index):
        super().__init__(bus, path)
        self.index = index
        self.title = f"Fake Tray {index + 1}"
        self.pixmap = make_pixmap((index * 0.137) % 1.0)

    @dbus.service.method(IFACE, in_signature="ii", out_signature="")
    def Activate(self, x, y):
        pass

    @dbus.service.method(IFACE, in_signature="ii", out_signature="")
    def SecondaryActivate(self, x, y):
        pass

    @dbus.service.method(IFACE, in_signature="is", out_signature="")
    def Scroll(self, delta, orientation):
        pass

    @dbus.service.method(IFACE, in_signature="ii", out_signature="")
    def ContextMenu(self, x, y):
        pass

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
        return {
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
                    dbus.String("Fake item for tray overflow testing"),
                ),
                signature="sa(iiay)ss",
            ),
            # No menu: hovering should show the tooltip instead.
            "ItemIsMenu": dbus.Boolean(False),
        }

    @dbus.service.method(PROPS, in_signature="ss", out_signature="v")
    def Get(self, interface, prop):
        return self._properties()[prop]

    @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return dbus.Dictionary(self._properties(), signature="sv")


def main():
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 18
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    watcher = bus.get_object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher")
    register = watcher.get_dbus_method(
        "RegisterStatusNotifierItem", "org.kde.StatusNotifierWatcher"
    )

    items = []
    for i in range(count):
        path = f"{PATH_ROOT}/{i}"
        items.append(FakeItem(bus, path, i))
        register(path)

    print(f"registered {count} fake tray item(s); ^C to remove", flush=True)

    loop = GLib.MainLoop()

    def stop(*_):
        loop.quit()

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    loop.run()


if __name__ == "__main__":
    main()

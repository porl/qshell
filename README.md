# qshell

A [Quickshell](https://quickshell.org) desktop shell for
[Hyprland](https://hyprland.org): a top bar, a session menu and an application
launcher.

The session is one process tree. `qshell` is a small Rust bridge that:

- launches and supervises the Quickshell shell;
- registers Hyprland global shortcuts; and
- translates those shortcuts into commands on the shell's control socket.

The shell itself does not know how it is triggered. It exposes a line-based
command socket (`target verb`, e.g. `launcher toggle`) and nothing about
compositor bindings.

## Contents

- `qml/Bar.qml` — top bar (workspaces, media, tray, network, bluetooth,
  brightness, volume, battery, power, clock) as a layer-shell surface. Block hit
  areas extend to the screen edges, so the corners are not dead zones.
- `qml/Workspaces.qml` — per-monitor workspace indicator (click to activate),
  driven by Quickshell's Hyprland integration.
- `qml/Volume.qml` — default-sink volume/mute. Draws headphones when that sink
  is a headset (from the PipeWire device hint) and a speaker otherwise; the
  level waves sit beside the icon and are replaced by the mute cross when muted.
  Opens the audio popout on hover (short delay) or immediately on scroll; scroll
  and middle-click fade out on mouse-out, while left/right click pins it until
  focus is lost. Middle-click mutes, scroll adjusts volume (0 mutes).
- `qml/VolumePopout.qml` — output/input stereo level meters (per-channel
  PwNodePeakMonitor) and volume sliders. The device icon (headphone/speaker/mic)
  doubles as the mute toggle — it draws the shared mute cross when muted — and
  the sliders take the scroll wheel; taking a slider to 0 mutes that device. A
  cog opens the mixer named by `QSHELL_AUDIO_MANAGER` (e.g. `pavucontrol`,
  `pavucontrol-qt`, `kmix`); it is hidden when the variable is unset. The popout
  whitelists the bar in its focus grab, so scrolling the volume block keeps
  working while it is pinned.
- `qml/PopoutState.qml` — shared popout open/close policy: hovering the bar
  block opens after a delay and fades when the pointer leaves; clicking (or
  scrolling) opens immediately and pins the popout until focus is lost. The
  workspace preview deliberately doesn't use it (it closes on mouse-out).
- `qml/Tray.qml` — system tray: at most `maxVisible` (default 6, or
  `QSHELL_TRAY_MAX_VISIBLE`) StatusNotifierItem icons, further limited by the
  space before the clock. Past that, the rest collapse behind an expander after
  the icons; clicking its `»` (slightly smaller than the icons, colouring on
  hover) opens a pinned grid below.
- `qml/TrayItem.qml` — one tray icon. Hover shows the item's title (and
  description) as a tooltip; left click runs the primary action (or opens the
  menu for menu-only items), middle click the secondary action, right click the
  menu. Scroll is forwarded, and does not open the menu. An open menu pins until
  focus is lost. A missing or undecodable icon falls back to a square with the
  item's initial.
- `qml/Tooltip.qml` — the hover tooltip card, anchored as a popup so it works
  both on the bar and inside the overflow grid. Never grabs focus or presses.
- `qml/TrayMenu.qml` / `qml/MenuColumn.qml` / `qml/MenuRow.qml` — the themed
  D-Bus menu popup and its rows, including check/radio state, separators and
  cascading submenus (drawn as extra columns in the same window, since QML
  forbids a component nesting itself).
- `qml/TrayOverflow.qml` — the expander's grid of tray icons that did not fit,
  opened by clicking the expander and pinned with a focus grab (which is what
  lets its icons receive pointer events), laid out square-ish (2-4 columns) and
  showing only one of its icons' menus at a time. Icons use the same tooltips as
  the bar.
- `qml/Battery.qml` — battery level (glyph + percent, charging bolt; hidden when
  the machine has none).
- `qml/NetworkBlock.qml` / `qml/NetworkPopout.qml` — network status and a popout:
  wifi on/off toggle, wired link, the network list (signal shown as percent),
  hover-revealed connect/disconnect actions, and a manager launcher
  (`QSHELL_NETWORK_MANAGER`, e.g. `nm-connection-editor` or `nmtui`) whose cog
  is hidden when the variable is unset. Scans only while open.
- `qml/BluetoothBlock.qml` / `qml/BluetoothPopout.qml` — Bluetooth status and a
  popout: adapter toggle, Scan/Stop, and the device list with hover-revealed
  connect/disconnect/pair actions (right-click forgets).
- `qml/BrightnessBlock.qml` / `qml/BrightnessPopout.qml` — backlight via
  `brightnessctl` (hidden with no backlight) and a slider popout; the popout also
  shows the UPower power-profile switcher when `powerprofilesctl` works.
- `qml/Media.qml` — MPRIS now-playing: expands to artist – title on a track
  change then collapses to the play/pause icon; left/middle/right click
  toggle/previous/next; hover shows the full title.
- `qml/Power.qml` — power button that opens the session menu.
- `qml/Glyph.qml` — the hand-drawn icon set (Canvas) used everywhere in the bar
  and the tray popouts, so the icons match the bar text instead of an icon font.
  `name` selects the shape; `level` drives wifi strength, volume and battery fill.
- `qml/Toggle.qml` — the small on/off switch used by the network and bluetooth
  popouts.
- `qml/WorkspacePreview.qml` — hover a workspace to drop a card showing its
  windows as live captures at their Hyprland geometry (so overlapping and
  hidden windows are visible); clicking a window focuses it, switching
  workspace if needed.
- `qml/SessionMenu.qml` — lock / log out / restart / shut down overlay.
- `qml/Launcher.qml` — application launcher: desktop entries, subsequence
  filtering over name/generic name/keywords/comment, match-quality and
  launch-frequency ranking, and a `>`/`=` run mode.
- `qml/Notifications.qml` — desktop notifications: a `NotificationServer` (so
  qshell owns `org.freedesktop.Notifications`) with themed popups that
  auto-dismiss unless hovered (countdown ring; critical never auto-clears),
  action buttons, images, markup bodies and click-to-invoke. Newest on top, on
  the focused monitor; up to `QSHELL_NOTIFICATION_LIMIT` (default 4) are shown
  and the excess is stacked behind the bottom card like a hand of cards.
- `qml/Calendar.qml` — drop-down calendar from the clock: a month grid with
  prev/next month and year navigation. Click a day to select it; click the
  selected day again, or double-click, to open `QSHELL_CALENDAR` for that date
  (`{date}` in the template is replaced with the ISO date). `QSHELL_WEEK_START`
  picks Mon/Sun.
- `qml/Theme.qml` — shared colours and metrics (including `trayIconSize`, used
  by both the bar and the overflow grid so tray icons match).

Layer surfaces use the `quickshell-*` namespace, so a Hyprland layer rule can
blur them. The bar reserves its height (`exclusiveZone`); the toggled overlays
are mapped only while open.

## Shortcuts

The bridge registers two Hyprland global shortcuts — `qshell:launcher` and
`qshell:session` — which send `launcher toggle` and `session toggle` on the
control socket. The compositor config binds keys to those names; the shell does
not choose them. Hyprland reports a press bind as `pressed` and a release bind
as `released`; the event-to-command mapping lives in the bridge.

## Launcher

Type to filter desktop entries, arrow keys to move, Enter to launch, Escape to
close. A normal query also offers the whole line as run entries, after the
matching applications:

- `=` runs it raw;
- `>` runs it in a terminal, which closes when the command finishes;
- `>>` runs it in a terminal and then leaves the shell open.

A query beginning with `?` searches files under `$HOME` instead. Results show a
mime-type icon; selecting one opens it with the default handler, falling back to
the editor in a terminal when nothing handles it (e.g. a handler that needs a
terminal). Applications launch through `uwsm app -- …`, so they become systemd
user units. Per-application launch counts and last-used times are stored in
`$XDG_STATE_HOME/quickshell/launcher.json` and rank the results within a
match-quality tier: a query that names an application exactly (or matches one of
its words) always outranks a looser match, but within a tier frequency, then
recency, then match score decide.

The terminal used by `>`, `>>` and terminal-based file handlers is
`QSHELL_TERMINAL` — a command prefix, e.g. `foot -e` or `xdg-terminal-exec`,
falling back to `TERMINAL`, then `xdg-terminal-exec`; no emulator is assumed.
The editor fallback is `QSHELL_EDITOR`, then `EDITOR`, then `VISUAL`, then
`nvim`.

## Calendar (TODO)

The drop-down calendar is Phase 1+2 (grid + open-app). **Phase 3, not built: an
agenda for the selected day.** Intended shape — a configurable command
(`QSHELL_CALENDAR_AGENDA`, e.g. `khal list {start} {end}` or `gcalcli agenda …`)
whose output is rendered under the grid, rather than parsing `.ics`/`RRULE` in
QML. No agenda section unless the command is configured.

## Command socket

The shell listens on `$QSHELL_SOCKET` (default `$XDG_RUNTIME_DIR/qshell.sock`)
and reads one command per line. The bridge sets `QSHELL_SOCKET` for the shell,
so the two agree without a shared constant. Commands can also be sent by hand:

```
printf 'launcher toggle\n' | socat - UNIX-CONNECT:"$XDG_RUNTIME_DIR/qshell.sock"
```

## Building

```
nix build
nix flake check
```

The package bakes the QML path into the bridge, so `bin/qshell` is
self-contained; `QSHELL_QML` overrides it.

Run the working tree in the current session:

```
nix develop
./scripts/dev-session.sh
```

## Testing

`scripts/fake-tray-items.py` is a **test-only** helper (not used by the bridge
or the Nix build): it registers N fake StatusNotifierItems over D-Bus so the
tray's overflow expander and grid can be exercised without installing more
apps. It needs system `python3` with `dbus-python` and `PyGObject` (GLib):

```
python3 scripts/fake-tray-items.py 30   # register 30; ^C to remove
```

To force the overflow path without that many items, lower the cap:
`QSHELL_TRAY_MAX_VISIBLE=2` on the qshell unit.

## License

GPL-3.0-or-later. See `LICENSE`.

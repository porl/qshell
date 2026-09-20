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

- `qml/Bar.qml` — top bar (workspaces, tray, clock) as a layer-shell surface.
  Block hit areas extend to the screen edges, so the corners are not dead zones.
- `qml/Workspaces.qml` — per-monitor workspace indicator (click to activate),
  driven by Quickshell's Hyprland integration.
- `qml/Volume.qml` — default-sink volume/mute. Opens the audio popout on hover
  (short delay) or immediately on scroll; scroll and middle-click fade out on
  mouse-out, while left/right click pins it until focus is lost. Middle-click
  mutes, scroll adjusts volume.
- `qml/VolumePopout.qml` — output/input stereo level meters (per-channel
  PwNodePeakMonitor), volume sliders and mute, with a headphone/speaker/mic icon.
- `qml/PopoutState.qml` — shared popout open/close policy: hovering the bar
  block opens after a delay and fades when the pointer leaves; clicking (or
  scrolling) opens immediately and pins the popout until focus is lost. The
  workspace preview deliberately doesn't use it (it closes on mouse-out).
- `qml/Tray.qml` — system tray: as many StatusNotifierItem icons as fit before
  the clock, with an expander (`»`) that opens a grid of the rest.
- `qml/TrayItem.qml` — one tray icon. Left click runs the primary action (or
  opens the menu for menu-only items), middle click the secondary action, right
  click the menu, scroll is forwarded. A menu follows the shared popout rules.
- `qml/TrayMenu.qml` / `qml/MenuColumn.qml` / `qml/MenuRow.qml` — the themed
  D-Bus menu popup and its rows, including check/radio state, separators and
  cascading submenus (drawn as extra columns in the same window, since QML
  forbids a component nesting itself).
- `qml/TrayOverflow.qml` — the expander's grid of tray icons that did not fit.
- `qml/Battery.qml` — battery level (hidden when the machine has none).
- `qml/Power.qml` — power button that opens the session menu.
- `qml/WorkspacePreview.qml` — hover a workspace to drop a card showing its
  windows as live captures at their Hyprland geometry (so overlapping and
  hidden windows are visible); clicking a window focuses it, switching
  workspace if needed.
- `qml/SessionMenu.qml` — lock / log out / restart / shut down overlay.
- `qml/Launcher.qml` — application launcher: desktop entries, subsequence
  filtering over name/generic name/keywords/comment, launch-frequency ranking,
  and a `>`/`=` run mode.
- `qml/Notifications.qml` — desktop notifications: a `NotificationServer` (so
  qshell owns `org.freedesktop.Notifications`) with themed popups that
  auto-dismiss unless hovered (countdown ring; critical never auto-clears),
  action buttons, images, markup bodies and click-to-invoke. Newest on top, on
  the focused monitor; up to `QSHELL_NOTIFICATION_LIMIT` (default 4) are shown
  and the excess is stacked behind the bottom card like a hand of cards.
- `qml/Calendar.qml` — drop-down calendar from the clock: a month grid with
  prev/next month and year navigation. Click a day to select it (the footer
  shows the full date and how far away it is); click the selected day again, or
  double-click, to open `QSHELL_CALENDAR` for that date (`{date}` in the
  template is replaced with the ISO date). `QSHELL_WEEK_START` picks Mon/Sun.
- `qml/Theme.qml` — shared colours and metrics.

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
`$XDG_STATE_HOME/quickshell/launcher.json` and rank the results (frequency, then
recency, then match score).

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

## License

GPL-3.0-or-later. See `LICENSE`.

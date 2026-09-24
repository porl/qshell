// qshell entrypoint: the bar, the session menu and the launcher, all in one
// Quickshell instance.
//
// The shell does not know how it is triggered. It exposes a line-based command
// socket (`target verb`, e.g. "launcher toggle"); the session bridge owns the
// compositor side, translates Hyprland's global shortcuts into those commands
// and launches this shell.
import Quickshell
import Quickshell.Io

ShellRoot {
    id: shell

    readonly property Theme theme: Theme {}
    readonly property PowerCaps powerCaps: PowerCaps {}
    readonly property string controlSocket: Quickshell.env("QSHELL_SOCKET")
        || (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qshell.sock"

    // Which screens get a bar: `QSHELL_BAR_SCREENS` is "all" (default), a
    // comma-separated list of output names, or "primary". Filtering happens in
    // the delegate rather than in the model: `Variants` needs the
    // `Quickshell.screens` property itself (a real list), and a JS array built
    // in a binding arrives as a single value, which yields only one bar.
    function barScreenEnabled(screen): bool {
        var spec = (Quickshell.env("QSHELL_BAR_SCREENS") || "all").trim().toLowerCase();
        if (spec === "" || spec === "all")
            return true;
        if (spec === "primary")
            return Quickshell.screens.length > 0 && screen === Quickshell.screens[0];
        var names = spec.split(",").map(function(n) {
            return n.trim();
        });
        return names.indexOf(screen.name.toLowerCase()) >= 0;
    }

    Variants {
        model: Quickshell.screens

        delegate: Bar {
            required property ShellScreen modelData

            theme: shell.theme
            screen: modelData
            visible: shell.barScreenEnabled(modelData)
            onPowerRequested: sessionMenu.toggle()
        }
    }

    SessionMenu {
        id: sessionMenu

        theme: shell.theme
        context: "session"
        canSuspend: shell.powerCaps.canSuspend
        canHibernate: shell.powerCaps.canHibernate
        onActionTriggered: action => shell.runSessionAction(action)
    }

    function runSessionAction(action: string): void {
        if (action === "lock")
            Quickshell.execDetached(["hyprlock"]);
        else if (action === "logout")
            Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.exit()"]);
        else if (action === "suspend")
            Quickshell.execDetached(["systemctl", "suspend"]);
        else if (action === "hibernate")
            Quickshell.execDetached(["systemctl", "hibernate"]);
        else if (action === "reboot")
            Quickshell.execDetached(["systemctl", "reboot"]);
        else if (action === "poweroff")
            Quickshell.execDetached(["systemctl", "poweroff"]);
    }

    Launcher {
        id: launcher

        theme: shell.theme
    }

    Notifications {
        theme: shell.theme
    }

    function dispatch(command: string): void {
        var parts = command.trim().split(/\s+/);
        if (parts.length < 2)
            return;
        var target = parts[0];
        var verb = parts[1];
        if (verb !== "toggle")
            return;
        if (target === "launcher")
            launcher.toggle();
        else if (target === "session")
            sessionMenu.toggle();
    }

    SocketServer {
        active: true
        path: shell.controlSocket

        handler: Socket {
            parser: SplitParser {
                onRead: line => shell.dispatch(line)
            }
        }
    }

    IpcHandler {
        target: "session"

        function toggle(): void {
            sessionMenu.toggle();
        }
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            launcher.toggle();
        }
    }
}

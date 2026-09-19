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
    readonly property string controlSocket: Quickshell.env("QSHELL_SOCKET")
        || (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qshell.sock"

    Bar {
        theme: shell.theme
        onPowerRequested: sessionMenu.toggle()
    }

    SessionMenu {
        id: sessionMenu

        theme: shell.theme
    }

    Launcher {
        id: launcher

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

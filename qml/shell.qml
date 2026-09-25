// qshell entrypoint: the bar, the session menu and the launcher, all in one
// Quickshell instance.
//
// The shell does not know how it is triggered. It exposes a line-based command
// socket (`target verb`, e.g. "launcher toggle"); the session bridge owns the
// compositor side, translates Hyprland's global shortcuts into those commands
// and launches this shell.
import Quickshell
import Quickshell.Io
import "NightSkySim.js" as Sim

ShellRoot {
    id: shell

    readonly property Theme theme: Theme {}
    readonly property PowerCaps powerCaps: PowerCaps {}
    readonly property string controlSocket: Quickshell.env("QSHELL_SOCKET")
        || (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qshell.sock"

    // -- night sky wallpaper ----------------------------------------------
    //
    // The mode and the sky's toggles (meteors, showers, buildings, missile
    // command) are read once from files under `~/.config/qshell` (falling back to
    // QSHELL_WALLPAPER* env vars) and can be changed at runtime with
    // `quickshell ipc call wallpaper …`, which also persists the choice. The
    // skyline itself is qcommon's NightSkyWallpaper.
    readonly property string wallpaperConfigDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") || "/tmp") + "/.config") + "/qshell"
    readonly property string wallpaperConfigPath: wallpaperConfigDir + "/wallpaper.conf"
    readonly property string wallpaperMeteorsPath: wallpaperConfigDir + "/wallpaper-meteors.conf"
    readonly property string wallpaperShowersPath: wallpaperConfigDir + "/wallpaper-showers.conf"
    readonly property string wallpaperBuildingsPath: wallpaperConfigDir + "/wallpaper-buildings.conf"
    readonly property string wallpaperMissilesPath: wallpaperConfigDir + "/wallpaper-missiles.conf"
    readonly property string wallpaperAntialiasPath: wallpaperConfigDir + "/wallpaper-antialias.conf"
    property string wallpaperModeName: _storedWallpaperMode()
    readonly property int wallpaperMode: Sim.modeFromString(wallpaperModeName)
    property bool wallpaperMeteors: _storedFlag(wallpaperMeteorsConfig, "QSHELL_WALLPAPER_METEORS", true)
    property bool wallpaperShowers: _storedFlag(wallpaperShowersConfig, "QSHELL_WALLPAPER_SHOWERS", true)
    property bool wallpaperBuildings: _storedFlag(wallpaperBuildingsConfig, "QSHELL_WALLPAPER_BUILDINGS", true)
    property bool wallpaperMissiles: _storedFlag(wallpaperMissilesConfig, "QSHELL_WALLPAPER_MISSILES", false)
    property bool wallpaperAntialias: _storedFlag(wallpaperAntialiasConfig, "QSHELL_WALLPAPER_ANTIALIAS", true)

    function _storedWallpaperMode(): string {
        var raw = wallpaperConfig.text();
        var stored = raw ? ("" + raw).trim() : "";
        if (stored.length > 0)
            return stored;
        return Quickshell.env("QSHELL_WALLPAPER") || "always";
    }

    function _storedFlag(view, envName, fallback): bool {
        var stored = view.text() ? ("" + view.text()).trim().toLowerCase() : "";
        if (stored === "on" || stored === "true" || stored === "1")
            return true;
        if (stored === "off" || stored === "false" || stored === "0")
            return false;
        var env = Quickshell.env(envName);
        if (env === "1" || env === "true")
            return true;
        if (env === "0" || env === "false")
            return false;
        return fallback;
    }

    function _writeConfig(path, value): void {
        Quickshell.execDetached([
            "/bin/sh",
            "-c",
            'export PATH=/run/current-system/sw/bin:/usr/bin:/bin; mkdir -p "$(dirname "$2")" && printf "%s\\n" "$1" > "$2"',
            "sh",
            value,
            path
        ]);
    }

    function setWallpaperMode(name: string): void {
        if (name !== "always" && name !== "idle" && name !== "greeter" && name !== "off")
            return;
        wallpaperModeName = name;
        _writeConfig(wallpaperConfigPath, name);
    }

    function setWallpaperToggle(name: string, value: bool): void {
        if (name === "meteors") {
            wallpaperMeteors = value;
            _writeConfig(wallpaperMeteorsPath, value ? "on" : "off");
        } else if (name === "showers") {
            wallpaperShowers = value;
            _writeConfig(wallpaperShowersPath, value ? "on" : "off");
        } else if (name === "buildings") {
            wallpaperBuildings = value;
            _writeConfig(wallpaperBuildingsPath, value ? "on" : "off");
        } else if (name === "missiles") {
            wallpaperMissiles = value;
            _writeConfig(wallpaperMissilesPath, value ? "on" : "off");
        } else if (name === "antialias") {
            wallpaperAntialias = value;
            _writeConfig(wallpaperAntialiasPath, value ? "on" : "off");
        }
    }

    function _flagFromArg(value: string): bool {
        return value === "on" || value === "true" || value === "1";
    }

    FileView {
        id: wallpaperConfig

        path: shell.wallpaperConfigPath
        preload: true
    }

    FileView {
        id: wallpaperMeteorsConfig

        path: shell.wallpaperMeteorsPath
        preload: true
    }

    FileView {
        id: wallpaperShowersConfig

        path: shell.wallpaperShowersPath
        preload: true
    }

    FileView {
        id: wallpaperBuildingsConfig

        path: shell.wallpaperBuildingsPath
        preload: true
    }

    FileView {
        id: wallpaperMissilesConfig

        path: shell.wallpaperMissilesPath
        preload: true
    }

    FileView {
        id: wallpaperAntialiasConfig

        path: shell.wallpaperAntialiasPath
        preload: true
    }

    NightSkyWallpaper {
        id: nightSkyWallpaper

        theme: shell.theme
        mode: shell.wallpaperMode
        pauseOnBattery: Quickshell.env("QSHELL_WALLPAPER_PAUSE_ON_BATTERY") === "1"
        fps: parseInt(Quickshell.env("QSHELL_WALLPAPER_FPS") || "12")
        meteorsEnabled: shell.wallpaperMeteors
        meteorShowers: shell.wallpaperShowers
        buildingsEnabled: shell.wallpaperBuildings
        missileCommand: shell.wallpaperMissiles
        antialias: shell.wallpaperAntialias
        seed: parseInt(Quickshell.env("QSHELL_WALLPAPER_SEED") || "1")
    }

    IpcHandler {
        target: "wallpaper"

        function set(mode: string): void {
            shell.setWallpaperMode(mode);
        }

        function toggle(): void {
            shell.setWallpaperMode(shell.wallpaperMode === Sim.MODE_OFF ? "always" : "off");
        }

        function meteors(value: string): void {
            shell.setWallpaperToggle("meteors", shell._flagFromArg(value));
        }

        function showers(value: string): void {
            shell.setWallpaperToggle("showers", shell._flagFromArg(value));
        }

        function buildings(value: string): void {
            shell.setWallpaperToggle("buildings", shell._flagFromArg(value));
        }

        function missiles(value: string): void {
            shell.setWallpaperToggle("missiles", shell._flagFromArg(value));
        }

        function antialias(value: string): void {
            shell.setWallpaperToggle("antialias", shell._flagFromArg(value));
        }

        function status(): string {
            return Sim.modeName(shell.wallpaperMode) + " meteors=" + (shell.wallpaperMeteors ? "on" : "off") + " showers=" + (shell.wallpaperShowers ? "on" : "off") + " buildings=" + (shell.wallpaperBuildings ? "on" : "off") + " missiles=" + (shell.wallpaperMissiles ? "on" : "off") + " antialias=" + (shell.wallpaperAntialias ? "on" : "off");
        }
    }

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

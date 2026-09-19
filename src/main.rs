//! qshell session bridge.
//!
//! Owns the compositor side of the session: it launches and supervises the
//! Quickshell shell, registers Hyprland global shortcuts, and translates
//! them into commands on the shell's control socket. The shell itself is
//! transport-agnostic; see `qml/shell.qml`.

use std::io::Write;
use std::os::unix::net::UnixStream;
use std::os::unix::process::CommandExt;
use std::process::{Child, Command, Stdio};
use std::thread;
use std::time::Duration;

use wayland_client::{
    globals::{registry_queue_init, GlobalListContents},
    protocol::wl_registry,
    Connection, Dispatch, QueueHandle,
};
use wayland_protocols_hyprland::global_shortcuts::v1::client::{
    hyprland_global_shortcut_v1::{self, HyprlandGlobalShortcutV1},
    hyprland_global_shortcuts_manager_v1::{self, HyprlandGlobalShortcutsManagerV1},
};

const APP_ID: &str = "qshell";

/// Which event fires a shortcut's command. Hyprland reports a press bind as
/// `pressed` and a release bind as `released`.
#[derive(Clone, Copy, PartialEq)]
enum Trigger {
    Pressed,
    Released,
}

struct Binding {
    id: &'static str,
    trigger: Trigger,
    command: &'static str,
    description: &'static str,
}

const BINDINGS: &[Binding] = &[
    Binding {
        id: "launcher",
        trigger: Trigger::Released,
        command: "launcher toggle",
        description: "Toggle the application launcher",
    },
    Binding {
        id: "session",
        trigger: Trigger::Pressed,
        command: "session toggle",
        description: "Toggle the session menu",
    },
];

struct State {
    socket: String,
    // Kept alive for the connection's lifetime; dropping a shortcut destroys it.
    _shortcuts: Vec<HyprlandGlobalShortcutV1>,
}

fn send(socket: &str, command: &str) {
    match UnixStream::connect(socket) {
        Ok(mut stream) => {
            if let Err(error) = writeln!(stream, "{command}") {
                eprintln!("qshell: cannot write to {socket}: {error}");
            }
        }
        Err(error) => eprintln!("qshell: cannot connect to the shell at {socket}: {error}"),
    }
}

impl Dispatch<wl_registry::WlRegistry, GlobalListContents> for State {
    fn event(
        _state: &mut Self,
        _proxy: &wl_registry::WlRegistry,
        _event: wl_registry::Event,
        _data: &GlobalListContents,
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<HyprlandGlobalShortcutsManagerV1, ()> for State {
    fn event(
        _state: &mut Self,
        _proxy: &HyprlandGlobalShortcutsManagerV1,
        _event: hyprland_global_shortcuts_manager_v1::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<HyprlandGlobalShortcutV1, usize> for State {
    fn event(
        state: &mut Self,
        _proxy: &HyprlandGlobalShortcutV1,
        event: hyprland_global_shortcut_v1::Event,
        data: &usize,
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        let binding = &BINDINGS[*data];
        let trigger = match event {
            hyprland_global_shortcut_v1::Event::Pressed { .. } => Trigger::Pressed,
            hyprland_global_shortcut_v1::Event::Released { .. } => Trigger::Released,
            _ => return,
        };
        if binding.trigger == trigger {
            send(&state.socket, binding.command);
        }
    }
}

fn qml_path() -> String {
    std::env::var("QSHELL_QML")
        .ok()
        .or_else(|| option_env!("QSHELL_QML").map(str::to_string))
        .unwrap_or_else(|| "qml".to_string())
}

fn socket_path() -> String {
    std::env::var("QSHELL_SOCKET").unwrap_or_else(|_| {
        let runtime = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".to_string());
        format!("{runtime}/qshell.sock")
    })
}

fn spawn_shell(qml: &str, socket: &str) -> std::io::Result<Child> {
    let binary = std::env::var("QUICKSHELL").unwrap_or_else(|_| "quickshell".to_string());
    let mut command = Command::new(binary);
    command
        .arg("--no-duplicate")
        .arg("--path")
        .arg(qml)
        .env("QSHELL_SOCKET", socket)
        .stdin(Stdio::null());
    // Do not outlive the bridge: a killed bridge (or crash) takes the shell
    // with it rather than leaving an orphan holding the bar.
    unsafe {
        command.pre_exec(|| {
            if libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) == -1 {
                return Err(std::io::Error::last_os_error());
            }
            Ok(())
        });
    }
    command.spawn()
}

fn wayland_loop(socket: String) {
    let conn = match Connection::connect_to_env() {
        Ok(conn) => conn,
        Err(error) => {
            eprintln!("qshell: no Wayland connection ({error}); shortcuts disabled");
            return;
        }
    };
    let (globals, mut queue) = match registry_queue_init::<State>(&conn) {
        Ok(pair) => pair,
        Err(error) => {
            eprintln!("qshell: Wayland registry error ({error}); shortcuts disabled");
            return;
        }
    };
    let qh = queue.handle();
    let manager: HyprlandGlobalShortcutsManagerV1 = match globals.bind(&qh, 1..=1, ()) {
        Ok(manager) => manager,
        Err(error) => {
            eprintln!("qshell: compositor has no global shortcuts ({error}); shortcuts disabled");
            return;
        }
    };

    let mut shortcuts = Vec::new();
    for (index, binding) in BINDINGS.iter().enumerate() {
        shortcuts.push(manager.register_shortcut(
            binding.id.to_string(),
            APP_ID.to_string(),
            binding.description.to_string(),
            String::new(),
            &qh,
            index,
        ));
    }

    let mut state = State {
        socket,
        _shortcuts: shortcuts,
    };
    if let Err(error) = queue.roundtrip(&mut state) {
        eprintln!("qshell: Wayland roundtrip failed: {error}");
        return;
    }
    loop {
        if let Err(error) = queue.blocking_dispatch(&mut state) {
            eprintln!("qshell: Wayland dispatch ended: {error}");
            return;
        }
    }
}

fn main() {
    let qml = qml_path();
    let socket = socket_path();
    eprintln!("qshell: shell {qml}, control socket {socket}");

    {
        let socket = socket.clone();
        thread::spawn(move || wayland_loop(socket));
    }

    let mut child = spawn_shell(&qml, &socket);
    loop {
        match &mut child {
            Ok(process) => {
                let status = process.wait();
                eprintln!("qshell: shell exited ({status:?}); restarting");
            }
            Err(error) => eprintln!("qshell: cannot start the shell: {error}"),
        }
        thread::sleep(Duration::from_millis(750));
        child = spawn_shell(&qml, &socket);
    }
}

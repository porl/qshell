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
use std::time::{Duration, Instant};

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

/// A single Tab press released within this window is a tap: the switcher stays
/// open for typing. A longer hold cycles and commits when SUPER is released.
const SWITCHER_TAP: Duration = Duration::from_millis(300);
/// A hold older than this lost its release (a compositor restart, a swallowed
/// event); the next press starts a fresh one instead of committing.
const SWITCHER_HOLD_MAX: Duration = Duration::from_secs(10);

/// The SUPER+Tab hold: presses in, socket commands out. The Tab press bind
/// reports only presses, so the end of the hold arrives on the transparent
/// `qshell:super-release` twin bind — the lone-SUPER launcher bind is shadowed
/// once Tab is consumed and would never fire here.
struct SwitcherHold {
    presses: u32,
    since: Option<Instant>,
}

impl SwitcherHold {
    fn new() -> Self {
        Self {
            presses: 0,
            since: None,
        }
    }

    /// A Tab press returns its walk command, keeping one command per press.
    fn step(&mut self, command: &'static str, now: Instant) -> &'static str {
        let stale = self
            .since
            .is_some_and(|since| now.duration_since(since) > SWITCHER_HOLD_MAX);
        if self.presses == 0 || stale {
            self.since = Some(now);
            self.presses = 0;
        }
        self.presses += 1;
        command
    }

    /// SUPER was released: end a switcher hold. A single quick tap leaves the
    /// list open for typing; anything longer commits. With no hold this does
    /// nothing — the launcher toggle is the launcher bind's business, and the
    /// compositor only fires that one for a genuine lone SUPER.
    fn release(&mut self, now: Instant) -> Option<&'static str> {
        let presses = std::mem::take(&mut self.presses);
        let since = self.since.take();
        if presses == 0 {
            return None;
        }
        let tap =
            presses == 1 && since.is_some_and(|started| now.duration_since(started) < SWITCHER_TAP);
        if tap {
            None
        } else {
            Some("switcher commit")
        }
    }
}

/// Which event fires a shortcut's command. Hyprland reports a press bind as
/// `pressed` and a release bind as `released`.
#[derive(Clone, Copy, PartialEq, Debug)]
enum Trigger {
    Pressed,
    Released,
}

struct Binding {
    id: &'static str,
    description: &'static str,
}

const BINDINGS: &[Binding] = &[
    Binding {
        id: "launcher",
        description: "Toggle the application launcher",
    },
    Binding {
        id: "super-release",
        description: "SUPER was released (ends a switcher hold)",
    },
    Binding {
        id: "session",
        description: "Toggle the session menu",
    },
    Binding {
        id: "switcher",
        description: "Window switcher: next window",
    },
    Binding {
        id: "switcher-prev",
        description: "Window switcher: previous window",
    },
];

struct State {
    socket: String,
    // Kept alive for the connection's lifetime; dropping a shortcut destroys it.
    _shortcuts: Vec<HyprlandGlobalShortcutV1>,
    hold: SwitcherHold,
}

impl State {
    fn send(&self, command: &str) {
        send(&self.socket, command);
    }

    fn shortcut(&mut self, id: &'static str, trigger: Trigger) {
        let now = Instant::now();
        let command = match (id, trigger) {
            ("launcher", Trigger::Released) => Some("launcher toggle"),
            ("super-release", Trigger::Released) => self.hold.release(now),
            ("session", Trigger::Pressed) => Some("session toggle"),
            ("switcher", Trigger::Pressed) => Some(self.hold.step("switcher next", now)),
            ("switcher-prev", Trigger::Pressed) => Some(self.hold.step("switcher prev", now)),
            _ => None,
        };
        if let Some(command) = command {
            eprintln!("qshell: {id} {trigger:?} -> {command}");
            self.send(command);
        } else if id == "super-release" {
            eprintln!("qshell: {id} {trigger:?} -> (no hold)");
        }
    }
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
        state.shortcut(binding.id, trigger);
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
        hold: SwitcherHold::new(),
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

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh() -> SwitcherHold {
        SwitcherHold::new()
    }

    #[test]
    fn a_release_without_a_hold_does_nothing() {
        // A lone SUPER release is the launcher bind's business; this signal is
        // only the switcher hold's end.
        assert_eq!(fresh().release(Instant::now()), None);
    }

    #[test]
    fn a_single_quick_tap_leaves_the_list_open() {
        let mut hold = fresh();
        let t0 = Instant::now();
        assert_eq!(hold.step("switcher next", t0), "switcher next");
        assert_eq!(hold.release(t0 + Duration::from_millis(120)), None);
    }

    #[test]
    fn holding_commits_on_release() {
        let mut hold = fresh();
        let t0 = Instant::now();
        hold.step("switcher next", t0);
        assert_eq!(
            hold.release(t0 + Duration::from_millis(800)),
            Some("switcher commit")
        );
    }

    #[test]
    fn more_than_one_press_commits_even_when_quick() {
        let mut hold = fresh();
        let t0 = Instant::now();
        hold.step("switcher next", t0);
        hold.step("switcher next", t0 + Duration::from_millis(100));
        assert_eq!(
            hold.release(t0 + Duration::from_millis(150)),
            Some("switcher commit")
        );
    }

    #[test]
    fn reverse_presses_walk_the_other_way_and_commit() {
        let mut hold = fresh();
        let t0 = Instant::now();
        assert_eq!(hold.step("switcher prev", t0), "switcher prev");
        assert_eq!(
            hold.release(t0 + Duration::from_millis(500)),
            Some("switcher commit")
        );
    }

    #[test]
    fn a_release_is_consumed() {
        let mut hold = fresh();
        let t0 = Instant::now();
        hold.step("switcher next", t0);
        assert_eq!(
            hold.release(t0 + Duration::from_millis(500)),
            Some("switcher commit")
        );
        // The release is consumed: the next SUPER release does not commit
        // again (and a lone SUPER is the launcher bind's business).
        assert_eq!(hold.release(t0 + Duration::from_secs(1)), None);
    }

    #[test]
    fn a_stale_hold_starts_fresh() {
        let mut hold = fresh();
        let t0 = Instant::now();
        hold.step("switcher next", t0);
        // The release was lost; the next press must not commit against it.
        let t1 = t0 + SWITCHER_HOLD_MAX + Duration::from_secs(1);
        assert_eq!(hold.step("switcher next", t1), "switcher next");
        assert_eq!(hold.release(t1 + Duration::from_millis(120)), None);
    }
}

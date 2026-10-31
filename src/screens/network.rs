use std::sync::{Arc, Mutex};
use std::thread;

use slint::{ComponentHandle, SharedString, Weak};

use crate::run_cmd;
use crate::to_model;
use crate::{AppWindow, NetMode};

struct NetDevice {
    name: String,
    is_wifi: bool,
    connected: bool,
}

struct WifiNetwork {
    ssid: String,
    signal: u8,
}

// a background op's result, delivered back onto the Slint event-loop thread via
// Weak::upgrade_in_event_loop rather than the mpsc::channel + 100ms on_tick poll the ratatui
// prototype used - Slint's own event loop does the waking now, nothing to poll
type OpResult = Result<String, String>;

enum Mode {
    SelectDevice { devices: Vec<NetDevice>, selected: usize },
    Scanning,
    SelectSsid { networks: Vec<WifiNetwork>, selected: usize },
    EnterPassword { ssid: String, input: String },
    Connecting(String),
    PingTest,
    SyncingRecipes,
    Done,
    Failed(String),
}

pub struct NetworkState {
    mode: Mode,
    iface: String,
    ping_ok: Option<bool>,
}

// Arc<Mutex<_>>, not Rc<RefCell<_>> like InstallConfig in main.rs - this one genuinely
// crosses the thread boundary (a background op's completion closure captures a clone of it),
// and Rc/RefCell aren't Send
pub type SharedNetworkState = Arc<Mutex<NetworkState>>;

pub fn new_state() -> SharedNetworkState {
    Arc::new(Mutex::new(NetworkState {
        mode: Mode::SelectDevice { devices: list_devices(), selected: 0 },
        iface: String::new(),
        ping_ok: None,
    }))
}

fn list_devices() -> Vec<NetDevice> {
    let Ok(out) = std::process::Command::new("nmcli")
        .args(["-t", "-f", "DEVICE,TYPE,STATE"])
        .arg("device")
        .arg("status")
        .output()
    else {
        return Vec::new();
    };
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter_map(|line| {
            let mut parts = line.splitn(3, ':');
            let name = parts.next()?.to_string();
            let kind = parts.next()?;
            let state = parts.next().unwrap_or("");
            if kind == "loopback" {
                return None;
            }
            Some(NetDevice {
                name,
                is_wifi: kind == "wifi",
                connected: state.starts_with("connected"),
            })
        })
        .collect()
}

fn spawn_op(weak: Weak<AppWindow>, state: SharedNetworkState, f: impl FnOnce() -> OpResult + Send + 'static) {
    thread::spawn(move || {
        let result = f();
        let _ = weak.upgrade_in_event_loop(move |app| {
            apply_result(&app, &state, result);
        });
    });
}

fn apply_result(app: &AppWindow, state: &SharedNetworkState, result: OpResult) {
    enum NextAction {
        Ping,
        SyncRecipes,
    }

    let next_action = {
        let mut s = state.lock().unwrap();
        match (&s.mode, result) {
            (Mode::Scanning, Ok(raw)) => {
                let mut networks: Vec<WifiNetwork> = raw
                    .lines()
                    .filter_map(|l| {
                        let mut parts = l.rsplitn(2, ':');
                        let signal: u8 = parts.next()?.parse().ok()?;
                        let ssid = parts.next()?.to_string();
                        if ssid.is_empty() {
                            return None;
                        }
                        Some(WifiNetwork { ssid, signal })
                    })
                    .collect();
                networks.sort_by(|a, b| b.signal.cmp(&a.signal));
                networks.dedup_by(|a, b| a.ssid == b.ssid);
                s.mode = Mode::SelectSsid { networks, selected: 0 };
                None
            }
            (Mode::Scanning, Err(e)) => {
                s.mode = Mode::Failed(e);
                None
            }
            (Mode::Connecting(_), Ok(_)) => Some(NextAction::Ping),
            (Mode::Connecting(_), Err(e)) => {
                s.mode = Mode::Failed(e);
                None
            }
            (Mode::PingTest, Ok(status)) => {
                s.ping_ok = Some(status == "ok");
                Some(NextAction::SyncRecipes)
            }
            (Mode::SyncingRecipes, Ok(_)) => {
                s.mode = Mode::Done;
                None
            }
            (Mode::SyncingRecipes, Err(e)) => {
                s.mode = Mode::Failed(format!("recipe sync failed: {e}"));
                None
            }
            _ => None,
        }
    };

    match next_action {
        Some(NextAction::Ping) => start_ping(app, state),
        Some(NextAction::SyncRecipes) => start_recipe_sync(app, state),
        None => render(app, state),
    }
}

fn start_scan(app: &AppWindow, state: &SharedNetworkState) {
    let iface = {
        let mut s = state.lock().unwrap();
        s.mode = Mode::Scanning;
        s.iface.clone()
    };
    render(app, state);
    spawn_op(app.as_weak(), state.clone(), move || {
        run_cmd::run("nmcli", &["device", "wifi", "rescan", "ifname", &iface]).map_err(|e| e.to_string())?;
        std::thread::sleep(std::time::Duration::from_secs(2));
        let out = std::process::Command::new("nmcli")
            .args(["-t", "-f", "SSID,SIGNAL", "device", "wifi", "list", "ifname", &iface])
            .output()
            .map_err(|e| e.to_string())?;
        Ok(String::from_utf8_lossy(&out.stdout).into_owned())
    });
}

fn start_connect_wifi(app: &AppWindow, state: &SharedNetworkState, ssid: String, password: String) {
    let iface = {
        let mut s = state.lock().unwrap();
        s.mode = Mode::Connecting(format!("connecting to {ssid}..."));
        s.iface.clone()
    };
    render(app, state);
    spawn_op(app.as_weak(), state.clone(), move || {
        let args = ["device", "wifi", "connect", &ssid, "password", &password, "ifname", &iface];
        run_cmd::run("nmcli", &args).map_err(|e| e.to_string())?;
        Ok(String::new())
    });
}

fn start_connect_ethernet(app: &AppWindow, state: &SharedNetworkState) {
    let iface = {
        let mut s = state.lock().unwrap();
        let status = format!("connecting {}...", s.iface);
        s.mode = Mode::Connecting(status);
        s.iface.clone()
    };
    render(app, state);
    spawn_op(app.as_weak(), state.clone(), move || {
        run_cmd::run("nmcli", &["device", "connect", &iface]).map_err(|e| e.to_string())?;
        Ok(String::new())
    });
}

fn start_ping(app: &AppWindow, state: &SharedNetworkState) {
    {
        state.lock().unwrap().mode = Mode::PingTest;
    }
    render(app, state);
    spawn_op(app.as_weak(), state.clone(), || {
        // informational only - install.sh itself never blocks on this, a live ISO with
        // flaky/no internet should still be usable up to this point. .output() (not
        // .status()) captures ping's real-time output instead of letting it inherit the
        // shared terminal - a holdover fix from the ratatui prototype that's simply correct
        // command-piping hygiene even though a GUI has no shared-frame corruption risk to
        // avoid in the first place
        let ok = std::process::Command::new("ping")
            .args(["-c", "3", "8.8.8.8"])
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false);
        Ok(if ok { "ok".to_string() } else { "failed".to_string() })
    });
}

fn start_recipe_sync(app: &AppWindow, state: &SharedNetworkState) {
    {
        state.lock().unwrap().mode = Mode::SyncingRecipes;
    }
    render(app, state);
    spawn_op(app.as_weak(), state.clone(), || {
        run_cmd::run("flux", &["check"]).map_err(|e| e.to_string()).map(|_| String::new())
    });
}

fn render(app: &AppWindow, state: &SharedNetworkState) {
    let s = state.lock().unwrap();
    match &s.mode {
        Mode::SelectDevice { devices, selected } => {
            app.set_net_mode(NetMode::SelectDevice);
            let labels: Vec<String> = devices
                .iter()
                .map(|d| format!("{}{}", d.name, if d.connected { " (connected)" } else { "" }))
                .collect();
            app.set_net_devices(to_model(&labels));
            app.set_net_device_selected(*selected as i32);
        }
        Mode::Scanning => {
            app.set_net_mode(NetMode::Scanning);
        }
        Mode::SelectSsid { networks, selected } => {
            app.set_net_mode(NetMode::SelectSsid);
            let labels: Vec<String> = networks.iter().map(|n| format!("{} ({}%)", n.ssid, n.signal)).collect();
            app.set_net_networks(to_model(&labels));
            app.set_net_network_selected(*selected as i32);
        }
        Mode::EnterPassword { ssid, input } => {
            app.set_net_mode(NetMode::EnterPassword);
            app.set_net_ssid(SharedString::from(ssid.as_str()));
            app.set_net_password_display(SharedString::from("*".repeat(input.chars().count())));
        }
        Mode::Connecting(status) => {
            app.set_net_mode(NetMode::Connecting);
            app.set_net_status_text(SharedString::from(status.as_str()));
        }
        Mode::PingTest => {
            app.set_net_mode(NetMode::PingTest);
            app.set_net_status_text(SharedString::from("checking connectivity..."));
        }
        Mode::SyncingRecipes => {
            app.set_net_mode(NetMode::SyncingRecipes);
            app.set_net_status_text(SharedString::from("syncing recipe repository..."));
        }
        Mode::Done => {
            app.set_net_mode(NetMode::Done);
            let line = match s.ping_ok {
                Some(false) => "connected (internet check failed, continuing anyway)",
                _ => "connected",
            };
            app.set_net_status_text(SharedString::from(line));
        }
        Mode::Failed(e) => {
            app.set_net_mode(NetMode::Failed);
            app.set_net_status_text(SharedString::from(e.as_str()));
        }
    }
}

// entry points called directly from main.rs's callback closures, which already run on the
// event-loop thread and already hold a live &AppWindow - only the background ops above need
// the Weak + upgrade_in_event_loop dance

pub fn enter(app: &AppWindow, state: &SharedNetworkState) {
    {
        state.lock().unwrap().mode = Mode::SelectDevice { devices: list_devices(), selected: 0 };
    }
    render(app, state);
}

pub fn device_chosen(app: &AppWindow, state: &SharedNetworkState, index: i32) {
    enum Action {
        Scan,
        Ping,
        ConnectEthernet,
    }

    let action = {
        let mut s = state.lock().unwrap();
        let Mode::SelectDevice { devices, selected } = &mut s.mode else { return };
        if index < 0 {
            let Some(dev) = devices.get(*selected) else { return };
            let action = if dev.is_wifi {
                if dev.connected { Action::Ping } else { Action::Scan }
            } else {
                Action::ConnectEthernet
            };
            s.iface = dev.name.clone();
            Some(action)
        } else {
            *selected = index as usize;
            None
        }
    };

    match action {
        Some(Action::Scan) => start_scan(app, state),
        Some(Action::Ping) => start_ping(app, state),
        Some(Action::ConnectEthernet) => start_connect_ethernet(app, state),
        None => render(app, state),
    }
}

pub fn ssid_chosen(app: &AppWindow, state: &SharedNetworkState, index: i32) {
    let confirmed_ssid = {
        let mut s = state.lock().unwrap();
        let Mode::SelectSsid { networks, selected } = &mut s.mode else { return };
        if index < 0 {
            networks.get(*selected).map(|n| n.ssid.clone())
        } else {
            *selected = index as usize;
            None
        }
    };

    if let Some(ssid) = confirmed_ssid {
        state.lock().unwrap().mode = Mode::EnterPassword { ssid, input: String::new() };
    }
    render(app, state);
}

pub fn password_char(app: &AppWindow, state: &SharedNetworkState, ch: &str) {
    {
        let mut s = state.lock().unwrap();
        if let Mode::EnterPassword { input, .. } = &mut s.mode {
            input.push_str(ch);
        }
    }
    render(app, state);
}

pub fn password_backspace(app: &AppWindow, state: &SharedNetworkState) {
    {
        let mut s = state.lock().unwrap();
        if let Mode::EnterPassword { input, .. } = &mut s.mode {
            input.pop();
        }
    }
    render(app, state);
}

pub fn password_submit(app: &AppWindow, state: &SharedNetworkState) {
    let creds = {
        let s = state.lock().unwrap();
        match &s.mode {
            Mode::EnterPassword { ssid, input } => Some((ssid.clone(), input.clone())),
            _ => None,
        }
    };
    if let Some((ssid, password)) = creds {
        start_connect_wifi(app, state, ssid, password);
    }
}

// Esc from SelectSsid/EnterPassword, and retry from Failed, both land back on a freshly
// re-scanned device list - matches the old on_key handlers for both cases exactly
pub fn back_to_devices(app: &AppWindow, state: &SharedNetworkState) {
    {
        state.lock().unwrap().mode = Mode::SelectDevice { devices: list_devices(), selected: 0 };
    }
    render(app, state);
}


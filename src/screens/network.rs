use std::sync::mpsc::{self, Receiver};
use std::thread;

use crossterm::event::{KeyCode, KeyEvent};
use ratatui::{
    Frame,
    layout::{Alignment, Constraint, Direction, Layout},
    style::{Modifier, Style},
    text::{Line, Span},
    widgets::Paragraph,
};

use super::{Screen, Transition};
use crate::config::InstallConfig;
use crate::run_cmd;
use crate::theme::{PRIMARY, SUBTEXT, TEXT};

struct NetDevice {
    name: String,
    is_wifi: bool,
    connected: bool,
}

struct WifiNetwork {
    ssid: String,
    signal: u8,
}

// a background op's result, drained in on_tick - every nmcli/ping/flux call in this screen
// can block for real seconds (wifi scan, DHCP, a slow mirror), so none of them run on the
// main thread, matching the install/progress.rs pattern later stages use for the same reason
type OpResult = Result<String, String>;

enum Mode {
    SelectDevice { devices: Vec<NetDevice>, selected: usize },
    Scanning,
    SelectSsid { networks: Vec<WifiNetwork>, selected: usize },
    EnterPassword { ssid: String, input: String },
    Connecting(String), // status line shown while waiting
    PingTest,
    SyncingRecipes,
    Done,
    Failed(String),
}

pub struct NetworkScreen {
    mode: Mode,
    iface: String,
    pending: Option<Receiver<OpResult>>,
    ping_ok: Option<bool>,
}

impl Default for NetworkScreen {
    fn default() -> Self {
        Self {
            mode: Mode::SelectDevice { devices: Vec::new(), selected: 0 },
            iface: String::new(),
            pending: None,
            ping_ok: None,
        }
    }
}

fn spawn<F: FnOnce() -> OpResult + Send + 'static>(f: F) -> Receiver<OpResult> {
    let (tx, rx) = mpsc::channel();
    thread::spawn(move || {
        let _ = tx.send(f());
    });
    rx
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

impl NetworkScreen {
    fn start_scan(&mut self) {
        let iface = self.iface.clone();
        self.pending = Some(spawn(move || {
            run_cmd::run("nmcli", &["device", "wifi", "rescan", "ifname", &iface])
                .map_err(|e| e.to_string())?;
            std::thread::sleep(std::time::Duration::from_secs(2));
            let out = std::process::Command::new("nmcli")
                .args(["-t", "-f", "SSID,SIGNAL", "device", "wifi", "list", "ifname", &iface])
                .output()
                .map_err(|e| e.to_string())?;
            Ok(String::from_utf8_lossy(&out.stdout).into_owned())
        }));
        self.mode = Mode::Scanning;
    }

    fn start_connect_wifi(&mut self, ssid: String, password: String) {
        let iface = self.iface.clone();
        self.mode = Mode::Connecting(format!("connecting to {ssid}..."));
        self.pending = Some(spawn(move || {
            let args = ["device", "wifi", "connect", &ssid, "password", &password, "ifname", &iface];
            run_cmd::run("nmcli", &args).map_err(|e| e.to_string())?;
            Ok(String::new())
        }));
    }

    fn start_connect_ethernet(&mut self) {
        let iface = self.iface.clone();
        self.mode = Mode::Connecting(format!("connecting {iface}..."));
        self.pending = Some(spawn(move || {
            run_cmd::run("nmcli", &["device", "connect", &iface]).map_err(|e| e.to_string())?;
            Ok(String::new())
        }));
    }

    fn start_ping(&mut self) {
        self.pending = Some(spawn(|| {
            // informational only - install.sh itself never blocks on this (`set +e` around
            // it), a live ISO with flaky/no internet should still be usable up to this point.
            // .status() inherits the child's stdio by default - ping's own real-time output
            // was writing straight to the shared terminal, corrupting the TUI's own rendered
            // frame (found by testing: ping's lines were scattered across the screen,
            // interleaved with whatever ratatui had drawn). .output() captures instead.
            let ok = std::process::Command::new("ping")
                .args(["-c", "3", "8.8.8.8"])
                .output()
                .map(|o| o.status.success())
                .unwrap_or(false);
            Ok(if ok { "ok".to_string() } else { "failed".to_string() })
        }));
        self.mode = Mode::PingTest;
    }

    fn start_recipe_sync(&mut self) {
        // run directly on the live rootfs, no chroot - flux and /etc/flux/flux.conf are
        // already present on the live image (confirmed during research), and this is the
        // same sync packages_install() triggers later inside the chroot (via flux install,
        // which syncs recipes+Alpine index on demand) for the real install; running it here
        // too just means step 10's devkit picker has real recipe data to read before any disk
        // write happens. 'flux check' (not 'flux update' - that command doesn't exist anymore,
        // renamed earlier in the same work this installer is part of) is the read-only sync.
        self.pending = Some(spawn(|| run_cmd::run("flux", &["check"]).map_err(|e| e.to_string()).map(|_| String::new())));
        self.mode = Mode::SyncingRecipes;
    }
}

impl Screen for NetworkScreen {
    fn on_enter(&mut self, _cfg: &mut InstallConfig) {
        self.mode = Mode::SelectDevice { devices: list_devices(), selected: 0 };
    }

    fn draw(&mut self, frame: &mut Frame, _cfg: &InstallConfig, _picker: &ratatui_image::picker::Picker) {
        let area = frame.area();
        let rows = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Fill(1),
                Constraint::Length(1), // heading
                Constraint::Length(1), // blank
                Constraint::Min(1),    // body
                Constraint::Length(1), // blank
                Constraint::Length(1), // footer
                Constraint::Fill(1),
            ])
            .split(area);

        let heading = Paragraph::new(Span::styled(
            "Network",
            Style::default().fg(PRIMARY).add_modifier(Modifier::BOLD),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(heading, rows[1]);

        let (body, footer) = self.render_body();
        frame.render_widget(Paragraph::new(body).alignment(Alignment::Center), rows[3]);
        frame.render_widget(
            Paragraph::new(Span::styled(footer, Style::default().fg(SUBTEXT))).alignment(Alignment::Center),
            rows[5],
        );
    }

    fn on_tick(&mut self, _cfg: &mut InstallConfig) -> Transition {
        let Some(rx) = &self.pending else { return Transition::Stay };
        let Ok(result) = rx.try_recv() else { return Transition::Stay };
        self.pending = None;

        match (&self.mode, result) {
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
                self.mode = Mode::SelectSsid { networks, selected: 0 };
            }
            (Mode::Scanning, Err(e)) => self.mode = Mode::Failed(e),
            (Mode::Connecting(_), Ok(_)) => self.start_ping(),
            (Mode::Connecting(_), Err(e)) => self.mode = Mode::Failed(e),
            (Mode::PingTest, Ok(status)) => {
                self.ping_ok = Some(status == "ok");
                self.start_recipe_sync();
            }
            (Mode::SyncingRecipes, Ok(_)) => self.mode = Mode::Done,
            (Mode::SyncingRecipes, Err(e)) => self.mode = Mode::Failed(format!("recipe sync failed: {e}")),
            _ => {}
        }
        Transition::Stay
    }

    fn on_key(&mut self, key: KeyEvent, _cfg: &mut InstallConfig) -> Transition {
        match &mut self.mode {
            Mode::SelectDevice { devices, selected } => match key.code {
                KeyCode::Up | KeyCode::Char('k') if *selected > 0 => {
                    *selected -= 1;
                    Transition::Stay
                }
                KeyCode::Down | KeyCode::Char('j') if *selected + 1 < devices.len() => {
                    *selected += 1;
                    Transition::Stay
                }
                KeyCode::Enter => {
                    let Some(dev) = devices.get(*selected) else { return Transition::Stay };
                    self.iface = dev.name.clone();
                    if dev.is_wifi {
                        if dev.connected {
                            self.start_ping();
                        } else {
                            self.start_scan();
                        }
                    } else {
                        self.start_connect_ethernet();
                    }
                    Transition::Stay
                }
                _ => Transition::Stay,
            },
            Mode::SelectSsid { networks, selected } => match key.code {
                KeyCode::Up | KeyCode::Char('k') if *selected > 0 => {
                    *selected -= 1;
                    Transition::Stay
                }
                KeyCode::Down | KeyCode::Char('j') if *selected + 1 < networks.len() => {
                    *selected += 1;
                    Transition::Stay
                }
                KeyCode::Enter => {
                    if let Some(net) = networks.get(*selected) {
                        self.mode = Mode::EnterPassword { ssid: net.ssid.clone(), input: String::new() };
                    }
                    Transition::Stay
                }
                KeyCode::Esc => {
                    self.mode = Mode::SelectDevice { devices: list_devices(), selected: 0 };
                    Transition::Stay
                }
                _ => Transition::Stay,
            },
            Mode::EnterPassword { ssid, input } => match key.code {
                KeyCode::Char(c) => {
                    input.push(c);
                    Transition::Stay
                }
                KeyCode::Backspace => {
                    input.pop();
                    Transition::Stay
                }
                KeyCode::Enter => {
                    let (ssid, password) = (ssid.clone(), input.clone());
                    self.start_connect_wifi(ssid, password);
                    Transition::Stay
                }
                KeyCode::Esc => {
                    self.mode = Mode::SelectDevice { devices: list_devices(), selected: 0 };
                    Transition::Stay
                }
                _ => Transition::Stay,
            },
            Mode::Done => match key.code {
                KeyCode::Enter => Transition::Next,
                _ => Transition::Stay,
            },
            Mode::Failed(_) => match key.code {
                // retry from the top rather than getting stuck - a flaky mirror/AP shouldn't
                // need the whole installer restarted
                KeyCode::Enter => {
                    self.mode = Mode::SelectDevice { devices: list_devices(), selected: 0 };
                    Transition::Stay
                }
                _ => Transition::Stay,
            },
            Mode::Scanning | Mode::Connecting(_) | Mode::PingTest | Mode::SyncingRecipes => Transition::Stay,
        }
    }
}

impl NetworkScreen {
    fn render_body(&self) -> (Vec<Line<'_>>, &'static str) {
        match &self.mode {
            Mode::SelectDevice { devices, selected } => {
                if devices.is_empty() {
                    return (vec![Line::from("no network devices found")], "");
                }
                let lines = devices
                    .iter()
                    .enumerate()
                    .map(|(i, d)| {
                        let marker = if d.connected { " (connected)" } else { "" };
                        let label = format!("{}{}{}", if i == *selected { "> " } else { "  " }, d.name, marker);
                        let style = if i == *selected {
                            Style::default().fg(PRIMARY).add_modifier(Modifier::BOLD)
                        } else {
                            Style::default().fg(TEXT)
                        };
                        Line::from(Span::styled(label, style))
                    })
                    .collect();
                (lines, "Up/Down to select  -  Enter to continue")
            }
            Mode::Scanning => (vec![Line::from("scanning for wifi networks...")], ""),
            Mode::SelectSsid { networks, selected } => {
                if networks.is_empty() {
                    return (vec![Line::from("no wifi networks found")], "Esc to go back");
                }
                let lines = networks
                    .iter()
                    .enumerate()
                    .map(|(i, n)| {
                        let label = format!(
                            "{}{} ({}%)",
                            if i == *selected { "> " } else { "  " },
                            n.ssid,
                            n.signal
                        );
                        let style = if i == *selected {
                            Style::default().fg(PRIMARY).add_modifier(Modifier::BOLD)
                        } else {
                            Style::default().fg(TEXT)
                        };
                        Line::from(Span::styled(label, style))
                    })
                    .collect();
                (lines, "Up/Down to select  -  Enter to connect  -  Esc to go back")
            }
            Mode::EnterPassword { ssid, input } => (
                vec![
                    Line::from(format!("Password for {ssid}:")),
                    Line::from("*".repeat(input.len())),
                ],
                "Enter to connect  -  Esc to go back",
            ),
            Mode::Connecting(status) => (vec![Line::from(status.as_str())], ""),
            Mode::PingTest => (vec![Line::from("checking connectivity...")], ""),
            Mode::SyncingRecipes => (vec![Line::from("syncing recipe repository...")], ""),
            Mode::Done => {
                let ping_line = match self.ping_ok {
                    Some(true) => "connected",
                    Some(false) => "connected (internet check failed, continuing anyway)",
                    None => "connected",
                };
                (vec![Line::from(ping_line)], "Enter to continue")
            }
            Mode::Failed(e) => (vec![Line::from(e.as_str())], "Enter to try again"),
        }
    }
}

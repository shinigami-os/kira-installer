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

const KEYMAP_DIR: &str = "/usr/share/kira-keymaps";

pub struct KeymapScreen {
    entries: Vec<String>,
    selected: usize,
    // only the error from the *last* loadkmap attempt matters - shown so a selection that
    // silently failed to apply isn't mistaken for one that worked
    apply_error: Option<String>,
}

impl Default for KeymapScreen {
    fn default() -> Self {
        let mut entries: Vec<String> = std::fs::read_dir(KEYMAP_DIR)
            .map(|dir| {
                dir.flatten()
                    .filter_map(|e| {
                        let name = e.file_name().to_string_lossy().into_owned();
                        name.strip_suffix(".bmap").map(str::to_string)
                    })
                    .collect()
            })
            .unwrap_or_default();
        entries.sort();

        // "us" first if present - the existing live-ISO default (kira-branding seeds
        // /etc/keymaps/us.bmap as the active one), so the common case needs no input at all
        let selected = entries.iter().position(|e| e == "us").unwrap_or(0);

        Self {
            entries,
            selected,
            apply_error: None,
        }
    }
}

impl KeymapScreen {
    // applied live on every selection change, not just on confirm - matches the original
    // spec ("applied live to the install session immediately on selection") and lets a wrong
    // layout be visually obvious (via this screen's own text) before it affects anything else
    fn apply_selected(&mut self) {
        let Some(name) = self.entries.get(self.selected) else {
            return;
        };
        let path = format!("{KEYMAP_DIR}/{name}.bmap");
        let bytes = match std::fs::read(&path) {
            Ok(b) => b,
            Err(e) => {
                self.apply_error = Some(format!("failed to read {path}: {e}"));
                return;
            }
        };
        self.apply_error = match run_cmd::run_with_stdin("loadkmap", &[], &bytes) {
            Ok(()) => None,
            Err(e) => Some(e.to_string()),
        };
    }
}

impl Screen for KeymapScreen {
    fn on_enter(&mut self, _cfg: &mut InstallConfig) {
        self.apply_selected();
    }

    fn draw(&mut self, frame: &mut Frame, _cfg: &InstallConfig, _picker: &ratatui_image::picker::Picker) {
        let area = frame.area();

        let list_h = (self.entries.len() as u16).max(1);
        let rows = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Fill(1),
                Constraint::Length(1), // heading
                Constraint::Length(1), // blank
                Constraint::Length(list_h),
                Constraint::Length(1), // blank
                Constraint::Length(1), // error (if any)
                Constraint::Length(1), // footer
                Constraint::Fill(1),
            ])
            .split(area);

        let heading = Paragraph::new(Span::styled(
            "Keyboard Layout",
            Style::default().fg(PRIMARY).add_modifier(Modifier::BOLD),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(heading, rows[1]);

        let lines: Vec<Line> = if self.entries.is_empty() {
            vec![Line::from(Span::styled(
                format!("no keymaps found under {KEYMAP_DIR}"),
                Style::default().fg(SUBTEXT),
            ))]
        } else {
            self.entries
                .iter()
                .enumerate()
                .map(|(i, name)| {
                    if i == self.selected {
                        Line::from(Span::styled(
                            format!("> {name}"),
                            Style::default().fg(PRIMARY).add_modifier(Modifier::BOLD),
                        ))
                    } else {
                        Line::from(Span::styled(format!("  {name}"), Style::default().fg(TEXT)))
                    }
                })
                .collect()
        };
        frame.render_widget(Paragraph::new(lines).alignment(Alignment::Center), rows[3]);

        if let Some(err) = &self.apply_error {
            let error_line = Paragraph::new(Span::styled(err.as_str(), Style::default().fg(theme_error())))
                .alignment(Alignment::Center);
            frame.render_widget(error_line, rows[5]);
        }

        let footer = Paragraph::new(Span::styled(
            "Up/Down to select  -  Enter to continue",
            Style::default().fg(SUBTEXT),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(footer, rows[6]);
    }

    fn on_key(&mut self, key: KeyEvent, cfg: &mut InstallConfig) -> Transition {
        match key.code {
            KeyCode::Up | KeyCode::Char('k') => {
                if self.selected > 0 {
                    self.selected -= 1;
                    self.apply_selected();
                }
                Transition::Stay
            }
            KeyCode::Down | KeyCode::Char('j') => {
                if self.selected + 1 < self.entries.len() {
                    self.selected += 1;
                    self.apply_selected();
                }
                Transition::Stay
            }
            KeyCode::Enter => {
                if let Some(name) = self.entries.get(self.selected) {
                    cfg.keymap = name.clone();
                    Transition::Next
                } else {
                    Transition::Stay
                }
            }
            KeyCode::Esc => Transition::Back,
            _ => Transition::Stay,
        }
    }
}

// secondary/hot accent (#ff00aa) - distinct from theme::PRIMARY, reserved for error/warning
// text; not yet worth promoting into theme.rs for a single call site, but named rather than
// left as a bare literal so the next screen that needs an error color reuses this constant
fn theme_error() -> ratatui::style::Color {
    ratatui::style::Color::Rgb(255, 0, 170)
}

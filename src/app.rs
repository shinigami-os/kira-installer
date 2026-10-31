use std::time::Duration;

use crossterm::event::{self, Event, KeyEventKind};
use ratatui::{DefaultTerminal, style::Style, widgets::Block};
use ratatui_image::picker::Picker;

use crate::config::InstallConfig;
use crate::screens::{self, Screen, ScreenId, Transition};
use crate::theme;

// Temporary: grows as each build stage's screens land (see the implementation plan) - this
// is not the final flow order until every step 1-13 is represented.
const SCREEN_ORDER: &[ScreenId] = &[ScreenId::Welcome, ScreenId::Keymap, ScreenId::Network];

// TEMPORARY diagnostic: input appeared completely unresponsive under cage+foot during testing
// (worked fine on the bare console) - this makes it directly checkable (cat the file) instead
// of guessing from a photo of a TTY whether events are reaching the app at all. Remove once
// cage+foot input is confirmed reliable across a few more build stages.
fn debug_log(line: &str) {
    use std::io::Write;
    if let Ok(mut f) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open("/tmp/kira-installer-input.log")
    {
        let _ = writeln!(f, "{line}");
    }
}

pub struct App {
    cfg: InstallConfig,
    // detected once at startup (term_picker::detect) and shared read-only by every screen
    // that renders an image, rather than each one re-probing the terminal
    picker: Picker,
    index: usize,
    current: Box<dyn Screen>,
}

impl App {
    pub fn new(picker: Picker) -> Self {
        let mut cfg = InstallConfig::default();
        let mut current = screens::build(SCREEN_ORDER[0]);
        current.on_enter(&mut cfg);
        Self {
            cfg,
            picker,
            index: 0,
            current,
        }
    }

    pub fn run(mut self, terminal: &mut DefaultTerminal) -> anyhow::Result<()> {
        loop {
            terminal.draw(|frame| {
                // paint every cell explicitly before the screen draws anything on top -
                // found by testing that foot's own `-o colors.background=...` override isn't
                // reliably honored (or isn't what an unstyled cell actually falls back to) in
                // this environment, so the terminal's own "default background" can't be
                // trusted at all. This is the one thing guaranteed to work on both the bare
                // console and under cage+foot, so no screen needs to think about it itself.
                frame.render_widget(Block::default().style(Style::default().bg(theme::BASE)), frame.area());
                self.current.draw(frame, &self.cfg, &self.picker);
            })?;

            let transition = if event::poll(Duration::from_millis(100))? {
                let ev = event::read()?;
                debug_log(&format!("{ev:?}"));
                match ev {
                    // filtering IN only ::Press (rather than filtering OUT ::Release) silently
                    // dropped every key on a real terminal (foot, under cage) during testing -
                    // the bare VT console's raw termios input has no press/release distinction
                    // at all, so this never showed up testing there. ::Repeat still counts as
                    // real input (holding a key down), only an explicit release is a non-event.
                    Event::Key(key) if key.kind != KeyEventKind::Release => {
                        self.current.on_key(key, &mut self.cfg)
                    }
                    _ => Transition::Stay,
                }
            } else {
                self.current.on_tick(&mut self.cfg)
            };

            match transition {
                Transition::Stay => {}
                Transition::Quit => return Ok(()),
                Transition::Next => {
                    // no screen after this one yet in stage 1 - silently stays put instead of
                    // panicking on an out-of-range index until the next build stage adds more
                    if self.index + 1 < SCREEN_ORDER.len() {
                        self.index += 1;
                        self.switch_to(SCREEN_ORDER[self.index]);
                    }
                }
                Transition::Back => {
                    if self.index > 0 {
                        self.index -= 1;
                        self.switch_to(SCREEN_ORDER[self.index]);
                    }
                }
                Transition::GoTo(id) => {
                    if let Some(pos) = SCREEN_ORDER.iter().position(|s| *s == id) {
                        self.index = pos;
                        self.switch_to(id);
                    }
                }
            }
        }
    }

    fn switch_to(&mut self, id: ScreenId) {
        self.current = screens::build(id);
        self.current.on_enter(&mut self.cfg);
    }
}

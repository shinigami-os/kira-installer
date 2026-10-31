use crossterm::event::KeyEvent;
use ratatui::Frame;
use ratatui_image::picker::Picker;

use crate::config::InstallConfig;

pub mod keymap;
pub mod welcome;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ScreenId {
    Welcome,
    Keymap,
}

pub enum Transition {
    Stay,
    Next,
    Back,
    GoTo(ScreenId),
    Quit,
}

pub trait Screen {
    // called once right after this screen becomes current - most screens won't need it,
    // but e.g. the network/devkit-scan screens (later stages) kick off background work here
    fn on_enter(&mut self, _cfg: &mut InstallConfig) {}
    // picker: the terminal's detected image-rendering capability (term_picker::detect, run
    // once at startup) - only screens that render an image (welcome, devkit/DE previews) use it
    fn draw(&mut self, frame: &mut Frame, cfg: &InstallConfig, picker: &Picker);
    fn on_key(&mut self, key: KeyEvent, cfg: &mut InstallConfig) -> Transition;
    // called instead of on_key whenever a 100ms poll finds no input - default no-op, overridden
    // by screens with their own background work to check on (network connect, install progress)
    fn on_tick(&mut self, _cfg: &mut InstallConfig) -> Transition {
        Transition::Stay
    }
}

pub fn build(id: ScreenId) -> Box<dyn Screen> {
    match id {
        ScreenId::Welcome => Box::new(welcome::WelcomeScreen::default()),
        ScreenId::Keymap => Box::new(keymap::KeymapScreen::default()),
    }
}

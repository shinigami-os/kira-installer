mod app;
mod config;
mod screens;
mod term_picker;
mod theme;

use app::App;

fn main() -> anyhow::Result<()> {
    if !is_root() {
        anyhow::bail!("This program must be run as root");
    }

    // a panic mid-install must never strand the console in raw/alt-screen mode - restore()
    // is safe to call even if init() never ran, so this is a real safety net, not a formality
    std::panic::set_hook(Box::new(|info| {
        ratatui::restore();
        eprintln!("kira-installer crashed: {info}");
    }));

    let mut terminal = ratatui::init();
    // visible under cage+foot during testing (a blinking terminal cursor sitting under the
    // welcome screen's text) - no screen built so far ever positions it, so it should already
    // be implicitly hidden, but evidently isn't reliably in this environment
    let _ = terminal.hide_cursor();
    // must happen before any crossterm event is read - see term_picker's own doc comment
    let picker = term_picker::detect();
    let result = App::new(picker).run(&mut terminal);
    ratatui::restore();
    result
}

fn is_root() -> bool {
    // SAFETY: geteuid takes no arguments, touches no memory, and cannot fail
    let euid = unsafe { libc::geteuid() };
    euid == 0
}

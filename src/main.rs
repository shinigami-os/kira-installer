slint::include_modules!();

fn main() -> anyhow::Result<()> {
    if !is_root() {
        anyhow::bail!("This program must be run as root");
    }

    let app = AppWindow::new()?;
    app.on_quit_requested(|| {
        let _ = slint::quit_event_loop();
    });
    app.run()?;
    Ok(())
}

fn is_root() -> bool {
    // SAFETY: geteuid takes no arguments, touches no memory, and cannot fail
    let euid = unsafe { libc::geteuid() };
    euid == 0
}

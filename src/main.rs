mod config;
mod disk;
mod run_cmd;
mod screens;

use std::cell::RefCell;
use std::rc::Rc;

use slint::{Model, ModelRc, SharedString, VecModel};

slint::include_modules!();

fn main() -> anyhow::Result<()> {
    if !is_root() {
        anyhow::bail!("This program must be run as root");
    }

    let app = AppWindow::new()?;
    // shared across every screen's callbacks (single-threaded - Slint callbacks all run on
    // the event-loop thread), accumulating choices up to the step-11 summary gate per the plan
    let cfg = Rc::new(RefCell::new(config::InstallConfig::default()));

    app.on_quit_requested(|| {
        let _ = slint::quit_event_loop();
    });

    let weak = app.as_weak();
    app.on_keymap_entered(move || {
        let Some(app) = weak.upgrade() else { return };
        let entries = screens::keymap::scan_entries();
        let selected = screens::keymap::default_selected(&entries);
        apply_keymap_selection(&app, entries, selected);
    });

    let weak = app.as_weak();
    app.on_keymap_selection_changed(move |selected| {
        let Some(app) = weak.upgrade() else { return };
        let entries = model_to_vec(&app.get_keymap_entries());
        apply_keymap_selection(&app, entries, selected as usize);
    });

    let weak = app.as_weak();
    app.on_keymap_confirmed(move || {
        let Some(app) = weak.upgrade() else { return };
        let entries = model_to_vec(&app.get_keymap_entries());
        let selected = app.get_keymap_selected() as usize;
        if let Some(name) = entries.get(selected) {
            cfg.borrow_mut().keymap = name.clone();
        }
    });

    let net_state = screens::network::new_state();

    let weak = app.as_weak();
    let state = net_state.clone();
    app.on_network_entered(move || {
        let Some(app) = weak.upgrade() else { return };
        screens::network::enter(&app, &state);
    });

    let weak = app.as_weak();
    let state = net_state.clone();
    app.on_network_device_chosen(move |i| {
        let Some(app) = weak.upgrade() else { return };
        screens::network::device_chosen(&app, &state, i);
    });

    let weak = app.as_weak();
    let state = net_state.clone();
    app.on_network_ssid_chosen(move |i| {
        let Some(app) = weak.upgrade() else { return };
        screens::network::ssid_chosen(&app, &state, i);
    });

    let weak = app.as_weak();
    let state = net_state.clone();
    app.on_network_password_char(move |c| {
        let Some(app) = weak.upgrade() else { return };
        screens::network::password_char(&app, &state, c.as_str());
    });

    let weak = app.as_weak();
    let state = net_state.clone();
    app.on_network_password_backspace(move || {
        let Some(app) = weak.upgrade() else { return };
        screens::network::password_backspace(&app, &state);
    });

    let weak = app.as_weak();
    let state = net_state.clone();
    app.on_network_password_submit(move || {
        let Some(app) = weak.upgrade() else { return };
        screens::network::password_submit(&app, &state);
    });

    let weak = app.as_weak();
    let state = net_state.clone();
    app.on_network_back_pressed(move || {
        let Some(app) = weak.upgrade() else { return };
        screens::network::back_to_devices(&app, &state);
    });

    let weak = app.as_weak();
    let state = net_state.clone();
    app.on_network_retry_pressed(move || {
        let Some(app) = weak.upgrade() else { return };
        screens::network::back_to_devices(&app, &state);
    });

    app.run()?;
    Ok(())
}

// shared by both the initial on-enter scan and every subsequent Up/Down move - loadkmap runs
// synchronously right here on the event-loop thread, same as the ratatui prototype did; it's
// fast enough (just a console keymap load) that a background thread isn't warranted, unlike
// the slower network.rs operations stage 3 re-wires next
fn apply_keymap_selection(app: &AppWindow, entries: Vec<String>, selected: usize) {
    let error = entries
        .get(selected)
        .and_then(|name| screens::keymap::apply(name).err())
        .unwrap_or_default();
    app.set_keymap_entries(to_model(&entries));
    app.set_keymap_selected(selected as i32);
    app.set_keymap_apply_error(error.into());
}

pub(crate) fn to_model(entries: &[String]) -> ModelRc<SharedString> {
    let items: Vec<SharedString> = entries.iter().map(SharedString::from).collect();
    ModelRc::new(VecModel::from(items))
}

fn model_to_vec(model: &ModelRc<SharedString>) -> Vec<String> {
    model.iter().map(|s| s.to_string()).collect()
}

fn is_root() -> bool {
    // SAFETY: geteuid takes no arguments, touches no memory, and cannot fail
    let euid = unsafe { libc::geteuid() };
    euid == 0
}

mod config;
mod disk;
mod install;
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
    let cfg_ref = cfg.clone();
    app.on_keymap_confirmed(move || {
        let Some(app) = weak.upgrade() else { return };
        let entries = model_to_vec(&app.get_keymap_entries());
        let selected = app.get_keymap_selected() as usize;
        if let Some(name) = entries.get(selected) {
            cfg_ref.borrow_mut().keymap = name.clone();
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

    let weak = app.as_weak();
    app.on_disk_select_entered(move || {
        let Some(app) = weak.upgrade() else { return };
        let entries = screens::disk_select::scan_entries();
        app.set_disk_entries(to_disk_model(&entries));
        app.set_disk_selected(0);
    });

    let weak = app.as_weak();
    app.on_disk_selection_changed(move |i| {
        let Some(app) = weak.upgrade() else { return };
        app.set_disk_selected(i);
    });

    let weak = app.as_weak();
    let cfg_ref = cfg.clone();
    app.on_disk_confirmed(move || {
        let Some(app) = weak.upgrade() else { return };
        let entries = app.get_disk_entries();
        let selected = app.get_disk_selected() as usize;
        if let Some(entry) = entries.row_data(selected) {
            cfg_ref.borrow_mut().target_disk = entry.short_name.to_string();
        }
    });

    let part_state = Rc::new(RefCell::new(screens::partition_mode::new_state()));

    let weak = app.as_weak();
    let state = part_state.clone();
    let cfg_ref = cfg.clone();
    app.on_partition_mode_entered(move || {
        let Some(app) = weak.upgrade() else { return };
        let disk = cfg_ref.borrow().target_disk.clone();
        screens::partition_mode::enter(&mut state.borrow_mut(), &disk);
        render_partition_mode(&app, &state.borrow());
    });

    let weak = app.as_weak();
    let state = part_state.clone();
    app.on_partition_method_chosen(move |i| {
        let Some(app) = weak.upgrade() else { return };
        screens::partition_mode::method_chosen(&mut state.borrow_mut(), i);
        render_partition_mode(&app, &state.borrow());
    });

    let weak = app.as_weak();
    let state = part_state.clone();
    app.on_partition_assisted_error_ack(move || {
        let Some(app) = weak.upgrade() else { return };
        screens::partition_mode::assisted_error_ack(&mut state.borrow_mut());
        render_partition_mode(&app, &state.borrow());
    });

    let weak = app.as_weak();
    let state = part_state.clone();
    let cfg_ref = cfg.clone();
    app.on_partition_swap_chosen(move |i| {
        let Some(app) = weak.upgrade() else { return };
        if let Some((method, want_swap, mib)) = screens::partition_mode::swap_chosen(&mut state.borrow_mut(), i) {
            commit_partition_choice(&cfg_ref, method, want_swap, mib);
        }
        render_partition_mode(&app, &state.borrow());
    });

    let weak = app.as_weak();
    let state = part_state.clone();
    app.on_partition_swap_size_char(move |c| {
        let Some(app) = weak.upgrade() else { return };
        screens::partition_mode::swap_size_char(&mut state.borrow_mut(), c.as_str());
        render_partition_mode(&app, &state.borrow());
    });

    let weak = app.as_weak();
    let state = part_state.clone();
    app.on_partition_swap_size_backspace(move || {
        let Some(app) = weak.upgrade() else { return };
        screens::partition_mode::swap_size_backspace(&mut state.borrow_mut());
        render_partition_mode(&app, &state.borrow());
    });

    let weak = app.as_weak();
    let state = part_state.clone();
    let cfg_ref = cfg.clone();
    app.on_partition_swap_size_submit(move || {
        let Some(app) = weak.upgrade() else { return };
        if let Some((method, want_swap, mib)) = screens::partition_mode::swap_size_submit(&mut state.borrow_mut()) {
            commit_partition_choice(&cfg_ref, method, want_swap, mib);
        }
        render_partition_mode(&app, &state.borrow());
    });

    let weak = app.as_weak();
    let state = part_state.clone();
    app.on_partition_mode_back(move || {
        let Some(app) = weak.upgrade() else { return };
        let at_top = screens::partition_mode::view(&state.borrow()).stage
            == screens::partition_mode::ViewStage::SelectMethod;
        if at_top {
            app.set_current_page(Page::DiskSelect);
        } else {
            screens::partition_mode::back_to_method(&mut state.borrow_mut());
            render_partition_mode(&app, &state.borrow());
        }
    });

    app.run()?;
    Ok(())
}

fn commit_partition_choice(cfg: &Rc<RefCell<config::InstallConfig>>, method: config::PartitionMode, want_swap: bool, swap_size_mib: u32) {
    let mut c = cfg.borrow_mut();
    c.partition_mode = method;
    c.want_swap = want_swap;
    c.swap_size_mib = swap_size_mib;
    // no next page yet - stage 4 ends here, same "stays put" precedent every earlier stage's
    // not-yet-built next step followed
}

fn render_partition_mode(app: &AppWindow, state: &screens::partition_mode::State) {
    let v = screens::partition_mode::view(state);
    app.set_part_mode_stage(match v.stage {
        screens::partition_mode::ViewStage::SelectMethod => PartModeStage::SelectMethod,
        screens::partition_mode::ViewStage::AssistedError => PartModeStage::AssistedError,
        screens::partition_mode::ViewStage::ConfirmSwap => PartModeStage::ConfirmSwap,
        screens::partition_mode::ViewStage::EnterSwapSize => PartModeStage::EnterSwapSize,
    });
    app.set_part_method_selected(v.method_selected);
    app.set_part_swap_selected(v.swap_selected);
    app.set_part_free_gib_text(v.free_gib_text.into());
    app.set_part_swap_size_input(v.swap_size_input.into());
    app.set_part_error_text(v.error_text.into());
}

fn to_disk_model(entries: &[screens::disk_select::Entry]) -> ModelRc<DiskEntry> {
    let items: Vec<DiskEntry> = entries
        .iter()
        .map(|e| DiskEntry {
            short_name: e.short_name.as_str().into(),
            label: e.label.as_str().into(),
            is_live: e.is_live_disk,
        })
        .collect();
    ModelRc::new(VecModel::from(items))
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

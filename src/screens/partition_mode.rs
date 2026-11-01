use crate::config::PartitionMode;
use crate::install::partitioning;

// all of this is read-only/decision-making - nothing here calls parted in write mode or
// touches a block device, matching the plan's requirement that no disk write happens before
// the step-11 summary gate. largest_free_region() (used for the Assisted-mode preview below)
// only ever reads the partition table.

pub enum Mode {
    SelectMethod { selected: usize }, // 0 = Automatic, 1 = Assisted
    AssistedError(String),
    ConfirmSwap { method: PartitionMode, free_gib: Option<f64>, selected: usize }, // 0 = No, 1 = Yes
    EnterSwapSize { method: PartitionMode, input: String },
}

pub struct State {
    mode: Mode,
    disk: String,
}

pub fn new_state() -> State {
    State { mode: Mode::SelectMethod { selected: 0 }, disk: String::new() }
}

pub fn enter(state: &mut State, target_disk: &str) {
    state.disk = target_disk.to_string();
    state.mode = Mode::SelectMethod { selected: 0 };
}

pub fn method_chosen(state: &mut State, index: i32) {
    let Mode::SelectMethod { selected } = &mut state.mode else { return };
    if index >= 0 {
        *selected = index as usize;
        return;
    }
    let method = if *selected == 0 { PartitionMode::Automatic } else { PartitionMode::Assisted };
    state.mode = match method {
        PartitionMode::Automatic => Mode::ConfirmSwap { method, free_gib: None, selected: 0 },
        PartitionMode::Assisted => {
            let disk_path = format!("/dev/{}", state.disk);
            match partitioning::largest_free_region(&disk_path) {
                Some((start, end)) if end - start >= partitioning::MIN_FREE_SPACE_MIB => {
                    let free_gib = (end - start) as f64 / 1024.0;
                    Mode::ConfirmSwap { method, free_gib: Some(free_gib), selected: 0 }
                }
                Some((start, end)) => Mode::AssistedError(format!(
                    "not enough free space on {} (need at least 15GiB, found {}GiB)",
                    state.disk,
                    (end - start) / 1024
                )),
                None => Mode::AssistedError(format!("no free space found on {}", state.disk)),
            }
        }
    };
}

pub fn assisted_error_ack(state: &mut State) {
    state.mode = Mode::SelectMethod { selected: 0 };
}

// returns Some((PartitionMode, want_swap, swap_size_mib)) once a full choice is confirmed -
// None means stay on this page, the caller re-renders either way
pub fn swap_chosen(state: &mut State, index: i32) -> Option<(PartitionMode, bool, u32)> {
    let Mode::ConfirmSwap { method, selected, .. } = &mut state.mode else { return None };
    if index >= 0 {
        *selected = index as usize;
        return None;
    }
    let method = *method;
    if *selected == 0 {
        Some((method, false, 0))
    } else {
        state.mode = Mode::EnterSwapSize { method, input: String::new() };
        None
    }
}

pub fn swap_size_char(state: &mut State, ch: &str) {
    if let Mode::EnterSwapSize { input, .. } = &mut state.mode {
        if ch.chars().all(|c| c.is_ascii_digit()) {
            input.push_str(ch);
        }
    }
}

pub fn swap_size_backspace(state: &mut State) {
    if let Mode::EnterSwapSize { input, .. } = &mut state.mode {
        input.pop();
    }
}

// returns Some((PartitionMode, true, mib)) once a valid size is submitted
pub fn swap_size_submit(state: &mut State) -> Option<(PartitionMode, bool, u32)> {
    let Mode::EnterSwapSize { method, input } = &state.mode else { return None };
    let mib: u32 = input.parse().ok()?;
    if mib == 0 {
        return None;
    }
    Some((*method, true, mib))
}

pub fn back_to_method(state: &mut State) {
    state.mode = Mode::SelectMethod { selected: 0 };
}

// ---- rendering ----

pub struct View {
    pub stage: ViewStage,
    pub method_selected: i32,
    pub swap_selected: i32,
    pub free_gib_text: String,
    pub swap_size_input: String,
    pub error_text: String,
}

#[derive(PartialEq)]
pub enum ViewStage {
    SelectMethod,
    AssistedError,
    ConfirmSwap,
    EnterSwapSize,
}

pub fn view(state: &State) -> View {
    match &state.mode {
        Mode::SelectMethod { selected } => View {
            stage: ViewStage::SelectMethod,
            method_selected: *selected as i32,
            swap_selected: 0,
            free_gib_text: String::new(),
            swap_size_input: String::new(),
            error_text: String::new(),
        },
        Mode::AssistedError(e) => View {
            stage: ViewStage::AssistedError,
            method_selected: 0,
            swap_selected: 0,
            free_gib_text: String::new(),
            swap_size_input: String::new(),
            error_text: e.clone(),
        },
        Mode::ConfirmSwap { free_gib, selected, .. } => View {
            stage: ViewStage::ConfirmSwap,
            method_selected: 0,
            swap_selected: *selected as i32,
            free_gib_text: free_gib.map(|g| format!("{g:.1} GiB free")).unwrap_or_default(),
            swap_size_input: String::new(),
            error_text: String::new(),
        },
        Mode::EnterSwapSize { input, .. } => View {
            stage: ViewStage::EnterSwapSize,
            method_selected: 0,
            swap_selected: 0,
            free_gib_text: String::new(),
            swap_size_input: input.clone(),
            error_text: String::new(),
        },
    }
}

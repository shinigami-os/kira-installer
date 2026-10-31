use crate::run_cmd;

pub const KEYMAP_DIR: &str = "/usr/share/kira-keymaps";

// scans /usr/share/kira-keymaps for *.bmap files, sorted - the same discovery approach the
// ratatui prototype used, just no longer paired with a draw()/on_key() of its own; the Slint
// page just renders whatever list Rust hands it
pub fn scan_entries() -> Vec<String> {
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
    entries
}

// "us" first if present - the live-ISO default (kira-branding seeds /etc/keymaps/us.bmap as
// the active one), so the common case needs no input at all
pub fn default_selected(entries: &[String]) -> usize {
    entries.iter().position(|e| e == "us").unwrap_or(0)
}

// applied live to the install session immediately on selection, not just on confirm - matches
// the original spec ("applied live to the install session immediately on selection") and lets
// a wrong layout be visually obvious before it affects anything else
pub fn apply(name: &str) -> Result<(), String> {
    let path = format!("{KEYMAP_DIR}/{name}.bmap");
    let bytes = std::fs::read(&path).map_err(|e| format!("failed to read {path}: {e}"))?;
    run_cmd::run_with_stdin("loadkmap", &[], &bytes).map_err(|e| e.to_string())
}

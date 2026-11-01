use crate::disk;

pub struct Entry {
    pub short_name: String,
    pub label: String,
    pub is_live_disk: bool,
}

// one line per candidate disk, e.g. "nvme0n1  476.9 GiB  Samsung SSD 970 EVO" - the live-medium
// warning is attached per-entry (is_live_disk) rather than baked into the label string, so the
// Slint side can style it distinctly instead of parsing it back out of plain text
pub fn scan_entries() -> Vec<Entry> {
    let live = disk::live_disk();
    disk::list_disks()
        .into_iter()
        .map(|d| {
            let model = if d.model.is_empty() { String::new() } else { format!("  {}", d.model) };
            Entry {
                is_live_disk: live.as_deref() == Some(d.name.as_str()),
                label: format!("{}  {:.1} GiB{}", d.name, d.size_gib(), model),
                short_name: d.name,
            }
        })
        .collect()
}

use crate::disk;
use crate::install::partitioning;

pub struct Entry {
    pub short_name: String,
    pub label: String,
    pub is_live_disk: bool,
}

// one line per candidate disk, e.g. "nvme0n1  476.9 GiB  Samsung SSD 970 EVO  (3 partitions,
// 120.5 GiB free)" - lets the user judge whether Assisted mode is even viable on a disk before
// picking it, rather than only finding out on the next screen. The live-medium warning stays
// a separate per-entry flag (is_live_disk) rather than baked into the label string, so the
// Slint side can style it distinctly instead of parsing it back out of plain text.
pub fn scan_entries() -> Vec<Entry> {
    let live = disk::live_disk();
    disk::list_disks()
        .into_iter()
        .map(|d| {
            let model = if d.model.is_empty() { String::new() } else { format!("  {}", d.model) };
            let path = d.path();
            let count = partitioning::partition_count(&path);
            let layout = if count == 0 {
                "  (no partition table)".to_string()
            } else {
                let free = partitioning::largest_free_region(&path)
                    .map(|(start, end)| format!(", {:.1} GiB free", (end - start) as f64 / 1024.0))
                    .unwrap_or_default();
                let noun = if count == 1 { "partition" } else { "partitions" };
                format!("  ({count} {noun}{free})")
            };
            Entry {
                is_live_disk: live.as_deref() == Some(d.name.as_str()),
                label: format!("{}  {:.1} GiB{}{}", d.name, d.size_gib(), model, layout),
                short_name: d.name,
            }
        })
        .collect()
}

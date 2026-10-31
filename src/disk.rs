// Disk enumeration via /sys/block directly - no lsblk+serde_json dependency pair, no
// reimplementing partition-table/sector math (that's parted's job, used later for the actual
// partitioning screens). This module only lists whole disks; partition-level detail comes
// from parsing `parted ... print`/`print free` output when that's actually needed.

pub struct Disk {
    pub name: String, // e.g. "nvme0n1", "sda"
    pub size_bytes: u64,
    pub model: String, // empty if /sys/block/<name>/device/model doesn't exist (e.g. some virtio disks)
}

impl Disk {
    pub fn path(&self) -> String {
        format!("/dev/{}", self.name)
    }

    pub fn size_gib(&self) -> f64 {
        self.size_bytes as f64 / (1024.0 * 1024.0 * 1024.0)
    }
}

// skips device classes that are never a real install target: loopback, ramdisk, zram, and
// optical (sr*) drives. Not a skip list for *removable* media (USB sticks etc. stay listed -
// filtering those out would also hide the one disk a from-USB install often targets)
fn is_install_candidate(name: &str) -> bool {
    !(name.starts_with("loop") || name.starts_with("ram") || name.starts_with("zram") || name.starts_with("sr"))
}

pub fn list_disks() -> Vec<Disk> {
    let mut disks = Vec::new();
    let Ok(entries) = std::fs::read_dir("/sys/block") else {
        return disks;
    };

    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if !is_install_candidate(&name) {
            continue;
        }

        let path = entry.path();
        let size_sectors: u64 = std::fs::read_to_string(path.join("size"))
            .ok()
            .and_then(|s| s.trim().parse().ok())
            .unwrap_or(0);
        // sysfs "size" is always in 512-byte sectors regardless of the device's real logical
        // block size - a kernel convention, not specific to any one disk/controller type
        let size_bytes = size_sectors * 512;
        if size_bytes == 0 {
            // a card reader with no card inserted, or similar - not a usable install target
            continue;
        }

        let model = std::fs::read_to_string(path.join("device/model"))
            .map(|s| s.trim().to_string())
            .unwrap_or_default();

        disks.push(Disk {
            name,
            size_bytes,
            model,
        });
    }

    disks.sort_by(|a, b| a.name.cmp(&b.name));
    disks
}

// Direct port of install.sh's write_partition() (mode 1, "guided - whole disk"),
// format_free_space()+find_esp() (mode 2, "guided - use free space"), same commands and
// ordering. Pure partitioning only - formatting.rs and mounting.rs come after, matching the
// original script's own function split.

use crate::run_cmd;

pub struct PartitionResult {
    pub esp_part: String,
    pub root_part: String,
    pub swap_part: Option<String>,
    // true when the ESP used lives on a different disk than the install target - only
    // possible in Assisted mode, when the target itself has no ESP. Mirrors install.sh's
    // ESP_EXTERNAL, which bootloader_install() later needs to decide whether to mount/unmount
    // that external ESP around grub-install rather than assuming it's already under MOUNT_POINT
    pub esp_external: bool,
}

pub const MIN_FREE_SPACE_MIB: u64 = 15 * 1024;

// "/dev/nvme0n1" -> "/dev/nvme0n1p", "/dev/sda" -> "/dev/sda" - devices whose name ends in a
// digit need a 'p' separator before the partition number (NVMe, MMC), unlike sdX/vdX. Matches
// install.sh's PART_PREFIX case statement exactly.
fn part_prefix(disk: &str) -> String {
    if disk.ends_with(|c: char| c.is_ascii_digit()) {
        format!("{disk}p")
    } else {
        disk.to_string()
    }
}

fn parted(args: &[&str]) -> Result<(), String> {
    run_cmd::run("parted", args).map_err(|e| e.to_string())
}

// mode 1: wipe the whole disk, GPT label, 512MiB ESP, optional swap, rest to root
pub fn write_whole_disk(disk: &str, want_swap: bool, swap_size_mib: u32) -> Result<PartitionResult, String> {
    parted(&["-s", disk, "mklabel", "gpt"])?;
    parted(&["-s", disk, "mkpart", "ESP", "fat32", "1MiB", "513MiB"])?;
    parted(&["-s", disk, "set", "1", "esp", "on"])?;

    let prefix = part_prefix(disk);
    if want_swap {
        let swap_end = 513 + swap_size_mib;
        parted(&["-s", disk, "mkpart", "swap", "linux-swap", "513MiB", &format!("{swap_end}MiB")])?;
        parted(&["-s", disk, "mkpart", "root", "ext4", &format!("{swap_end}MiB"), "100%"])?;
        Ok(PartitionResult {
            esp_part: format!("{prefix}1"),
            swap_part: Some(format!("{prefix}2")),
            root_part: format!("{prefix}3"),
            esp_external: false,
        })
    } else {
        parted(&["-s", disk, "mkpart", "root", "ext4", "513MiB", "100%"])?;
        Ok(PartitionResult {
            esp_part: format!("{prefix}1"),
            swap_part: None,
            root_part: format!("{prefix}2"),
            esp_external: false,
        })
    }
}

// matches install.sh's `parted -s $DISK unit MiB print free | grep "Free Space" | ...` - the
// largest free region on the disk, in MiB, or None if there isn't one at all
pub fn largest_free_region(disk: &str) -> Option<(u64, u64)> {
    let out = std::process::Command::new("parted")
        .args(["-s", disk, "unit", "MiB", "print", "free"])
        .output()
        .ok()?;
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter(|l| l.contains("Free Space"))
        .filter_map(|l| {
            let fields: Vec<&str> = l.split_whitespace().collect();
            let start: u64 = fields.first()?.trim_end_matches("MiB").parse().ok()?;
            let end: u64 = fields.get(1)?.trim_end_matches("MiB").parse().ok()?;
            Some((start, end))
        })
        .max_by_key(|(start, end)| end - start)
}

// "Disk /dev/loop0: 20480MiB" - the disk's own nominal total size, used to detect whether a
// free region runs all the way to the physical end (see write_free_space)
fn disk_total_mib(disk: &str) -> Option<u64> {
    let out = std::process::Command::new("parted").args(["-s", disk, "unit", "MiB", "print"]).output().ok()?;
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .find(|l| l.starts_with("Disk ") && l.contains("MiB"))
        .and_then(|l| l.rsplit(':').next())
        .and_then(|v| v.trim().trim_end_matches("MiB").parse().ok())
}

fn last_partition_number(disk: &str) -> u32 {
    let Ok(out) = std::process::Command::new("parted").args(["-s", disk, "print"]).output() else {
        return 0;
    };
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter_map(|l| l.trim_start().split_whitespace().next()?.parse::<u32>().ok())
        .max()
        .unwrap_or(0)
}

fn esp_partition_number(disk: &str) -> Option<u32> {
    let out = std::process::Command::new("parted").args(["-s", disk, "print"]).output().ok()?;
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .find(|l| l.to_lowercase().contains("esp"))
        .and_then(|l| l.split_whitespace().next()?.parse().ok())
}

// matches install.sh's find_esp(): an existing ESP on the target disk itself, else the first
// one found on any other disk (e.g. a second drive from a dual-boot Windows install) - unlike
// the shell script, which falls back to prompting for a path if neither is found, this
// returns an error for the caller to surface in the UI instead (there's no synchronous
// terminal prompt available at this layer any more)
pub fn find_esp(target_disk: &str) -> Result<(String, bool), String> {
    if let Some(num) = esp_partition_number(target_disk) {
        return Ok((format!("{}{num}", part_prefix(target_disk)), false));
    }
    for d in crate::disk::list_disks() {
        let path = d.path();
        if path == target_disk {
            continue;
        }
        if let Some(num) = esp_partition_number(&path) {
            return Ok((format!("{}{num}", part_prefix(&path)), true));
        }
    }
    Err("no existing EFI System Partition found on this disk or any other - a UEFI ESP is required".to_string())
}

// mode 2: partitions only the largest free region on an already-partitioned disk, every
// existing partition left untouched, then locates an existing ESP to boot from
pub fn write_free_space(disk: &str, want_swap: bool, swap_size_mib: u32) -> Result<PartitionResult, String> {
    let (start, end) =
        largest_free_region(disk).ok_or_else(|| format!("no free space found on {disk}"))?;
    if end - start < MIN_FREE_SPACE_MIB {
        return Err(format!(
            "not enough free space on {disk} (need at least 15GiB, found {}GiB)",
            (end - start) / 1024
        ));
    }

    let prefix = part_prefix(disk);
    let last_part = last_partition_number(disk);

    // when the free region runs all the way to the physical end of the disk, parted rejects
    // the literal end-of-disk MiB value as "outside of the device" - GPT reserves a few
    // sectors at the very end for the backup partition table, so the real usable boundary is
    // a little short of the disk's nominal size, same reason write_whole_disk already has to
    // use "100%" for its own root partition rather than a literal number. Found live against
    // a scratch loop device whose free space ran to the exact end of the disk - the same bug
    // exists in install.sh's format_free_space(), which has this identical literal-MiB logic.
    let end_arg = match disk_total_mib(disk) {
        Some(total) if end >= total.saturating_sub(1) => "100%".to_string(),
        _ => format!("{end}MiB"),
    };

    let (swap_part, root_part) = if want_swap {
        let swap_end = start + swap_size_mib as u64;
        parted(&["-s", disk, "mkpart", "swap", "linux-swap", &format!("{start}MiB"), &format!("{swap_end}MiB")])?;
        parted(&["-s", disk, "mkpart", "root", "ext4", &format!("{swap_end}MiB"), &end_arg])?;
        (Some(format!("{prefix}{}", last_part + 1)), format!("{prefix}{}", last_part + 2))
    } else {
        parted(&["-s", disk, "mkpart", "root", "ext4", &format!("{start}MiB"), &end_arg])?;
        (None, format!("{prefix}{}", last_part + 1))
    };

    let (esp_part, esp_external) = find_esp(disk)?;
    Ok(PartitionResult { esp_part, root_part, swap_part, esp_external })
}

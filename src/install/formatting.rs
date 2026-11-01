// Direct port of install.sh's format_partition().

use std::path::Path;
use std::time::Duration;

use crate::run_cmd;

use super::partitioning::PartitionResult;

// parted returns as soon as it writes the partition table, before the kernel/udev have
// necessarily created the new partition device nodes yet (especially common on NVMe) -
// without this, mkfs can race ahead and fail with "No such file or directory" on a partition
// that's about to exist. Matches install.sh's wait loop (15 one-second retries) exactly.
fn wait_for_device(part: &str) -> Result<(), String> {
    for _ in 0..15 {
        if Path::new(part).exists() {
            return Ok(());
        }
        std::thread::sleep(Duration::from_secs(1));
    }
    if Path::new(part).exists() {
        Ok(())
    } else {
        Err(format!("{part} never appeared after partitioning"))
    }
}

// format_esp: true only in whole-disk ("Automatic") mode - Assisted mode reuses an existing
// ESP and must never reformat it, since it may belong to another OS already installed there
pub fn format_all(disk: &str, result: &PartitionResult, format_esp: bool, want_swap: bool) -> Result<(), String> {
    // best-effort, matches install.sh's `partprobe ... || true` / `udevadm settle || true`
    let _ = run_cmd::run("partprobe", &[disk]);
    let _ = run_cmd::run("udevadm", &["settle"]);

    wait_for_device(&result.esp_part)?;
    wait_for_device(&result.root_part)?;
    if let Some(swap) = &result.swap_part {
        wait_for_device(swap)?;
    }

    if format_esp {
        run_cmd::run("mkfs.fat", &["-F", "32", &result.esp_part]).map_err(|e| e.to_string())?;
    }
    run_cmd::run("mkfs.ext4", &["-F", &result.root_part]).map_err(|e| e.to_string())?;
    if want_swap {
        if let Some(swap) = &result.swap_part {
            run_cmd::run("mkswap", &[swap]).map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

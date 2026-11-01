// Direct port of install.sh's mount_partition().

use crate::run_cmd;

use super::partitioning::PartitionResult;

pub const MOUNT_POINT: &str = "/mnt";

pub fn mount_all(result: &PartitionResult, want_swap: bool) -> Result<(), String> {
    std::fs::create_dir_all(MOUNT_POINT).map_err(|e| e.to_string())?;
    run_cmd::run("mount", &[&result.root_part, MOUNT_POINT]).map_err(|e| e.to_string())?;

    let efi_dir = format!("{MOUNT_POINT}/boot/efi");
    std::fs::create_dir_all(&efi_dir).map_err(|e| e.to_string())?;
    run_cmd::run("mount", &[&result.esp_part, &efi_dir]).map_err(|e| e.to_string())?;

    if want_swap {
        if let Some(swap) = &result.swap_part {
            run_cmd::run("swapon", &[swap]).map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

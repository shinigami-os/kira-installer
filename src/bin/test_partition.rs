// Dev-only harness for exercising install/partitioning.rs, formatting.rs and mounting.rs
// against a real block device before the real UI flow (summary/progress screens, stage 10)
// exists to drive them. Never shipped as part of the real installer flow - run by hand against
// a scratch disk only, e.g.:
//   test_partition auto /dev/loop0 --swap 512
//   test_partition free /dev/loop0

#[path = "../run_cmd.rs"]
mod run_cmd;
#[path = "../disk.rs"]
mod disk;
#[path = "../install/mod.rs"]
mod install;

use install::{formatting, mounting, partitioning};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let Some(mode) = args.get(1) else {
        eprintln!("usage: test_partition <auto|free> <disk> [--swap <mib>]");
        std::process::exit(1);
    };
    let Some(disk) = args.get(2) else {
        eprintln!("usage: test_partition <auto|free> <disk> [--swap <mib>]");
        std::process::exit(1);
    };
    let swap_mib: Option<u32> = args
        .iter()
        .position(|a| a == "--swap")
        .and_then(|i| args.get(i + 1))
        .and_then(|s| s.parse().ok());
    let want_swap = swap_mib.is_some();

    println!("== partitioning {disk} (mode={mode}, swap={swap_mib:?}) ==");
    let result = match mode.as_str() {
        "auto" => partitioning::write_whole_disk(disk, want_swap, swap_mib.unwrap_or(0)),
        "free" => partitioning::write_free_space(disk, want_swap, swap_mib.unwrap_or(0)),
        other => {
            eprintln!("unknown mode {other}, expected auto or free");
            std::process::exit(1);
        }
    };
    let result = match result {
        Ok(r) => r,
        Err(e) => {
            eprintln!("partitioning failed: {e}");
            std::process::exit(1);
        }
    };
    println!(
        "esp={} root={} swap={:?} esp_external={}",
        result.esp_part, result.root_part, result.swap_part, result.esp_external
    );

    println!("== formatting ==");
    if let Err(e) = formatting::format_all(disk, &result, mode == "auto", want_swap) {
        eprintln!("formatting failed: {e}");
        std::process::exit(1);
    }

    println!("== mounting ==");
    if let Err(e) = mounting::mount_all(&result, want_swap) {
        eprintln!("mounting failed: {e}");
        std::process::exit(1);
    }

    println!("OK - mounted at {}", mounting::MOUNT_POINT);
}

// Everything the installer collects across screens before step 11's summary gate. Each build
// stage adds the fields its own screens need instead of this being pre-declared up front.
#[derive(Default)]
pub struct InstallConfig {
    // name of a /usr/share/kira-keymaps/<name>.bmap entry, e.g. "us", "fr-azerty"
    pub keymap: String,
    // e.g. "nvme0n1", "sda" - short name, matches disk::Disk::name and install.sh's
    // TARGET_DISK_SHORT, not a full /dev/ path
    pub target_disk: String,
    pub partition_mode: PartitionMode,
    pub want_swap: bool,
    pub swap_size_mib: u32,
}

// install.sh's mode 1 ("guided - whole disk") and mode 2 ("guided - use free space") - mode 3
// (full manual) isn't implemented there either, it's this installer's own stage 9
#[derive(Clone, Copy, PartialEq, Eq, Default)]
pub enum PartitionMode {
    #[default]
    Automatic,
    Assisted,
}

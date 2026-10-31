// Everything the installer collects across screens before step 11's summary gate. Each build
// stage adds the fields its own screens need instead of this being pre-declared up front.
#[derive(Default)]
pub struct InstallConfig {
    // name of a /usr/share/kira-keymaps/<name>.bmap entry, e.g. "us", "fr-azerty"
    pub keymap: String,
}

// Everything the installer collects across screens before step 11's summary gate. Each build
// stage adds the fields its own screens need instead of this being pre-declared up front -
// stage 1 has nothing to collect yet.
#[derive(Default)]
pub struct InstallConfig {}

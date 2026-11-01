pub mod formatting;
pub mod mounting;
pub mod partitioning;

// install/mod.rs::run() (the step-12 orchestrator that calls every install/*.rs function in
// install.sh's main() order) lands in stage 10, once the summary/progress screens that drive
// it exist. These three modules are usable standalone before then - see src/bin/test_partition.rs.

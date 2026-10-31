pub mod keymap;

// network.rs stays on disk but unwired until stage 3 re-wires its already-proven business
// logic (the Mode state machine, the nmcli/ping/flux shell-outs) onto Slint callbacks - it
// still references the deleted ratatui Screen trait and crossterm types as-is.

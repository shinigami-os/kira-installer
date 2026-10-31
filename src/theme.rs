use ratatui::style::Color;

// Kira's own brand palette (kira-website design spec), shared across every screen instead of
// each one declaring its own copy. True color throughout, since every terminal Kira ships
// supports it.
pub const BASE: Color = Color::Rgb(10, 10, 15); // #0a0a0f - main background
pub const PRIMARY: Color = Color::Rgb(170, 0, 255); // #aa00ff - main accent
pub const TEXT: Color = Color::Rgb(232, 216, 255); // #e8d8ff - primary text
pub const SUBTEXT: Color = Color::Rgb(176, 154, 204); // #b09acc - secondary text

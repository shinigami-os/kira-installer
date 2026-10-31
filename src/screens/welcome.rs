use crossterm::event::{KeyCode, KeyEvent};
use ratatui::{
    Frame,
    layout::{Alignment, Constraint, Direction, Layout, Rect, Size},
    style::{Color, Modifier, Style},
    text::Span,
    widgets::Paragraph,
};
use ratatui_image::{Image, Resize, picker::Picker, protocol::Protocol};

use super::{Screen, Transition};
use crate::config::InstallConfig;

// Kira's own brand palette (kira-website design spec), true color since every terminal Kira
// ships supports it.
const PRIMARY: Color = Color::Rgb(170, 0, 255); // #aa00ff
const TEXT: Color = Color::Rgb(232, 216, 255); // #e8d8ff
const SUBTEXT: Color = Color::Rgb(176, 154, 204); // #b09acc

// the real kira-linux.com logo (transparent background, light-lavender colorway meant for a
// dark background - the other variant on the site, kira-logo.png proper, is black-on-light
// and would be invisible against this screen's dark base). Embedded rather than fetched at
// runtime: this is the very first screen, shown before the network screen even runs.
const LOGO_PNG: &[u8] = include_bytes!("../../assets/kira-logo.png");
const LOGO_NATIVE_W: f32 = 782.0;
const LOGO_NATIVE_H: f32 = 1165.0;

#[derive(Default)]
pub struct WelcomeScreen {
    logo: Option<Protocol>,
    // the exact cell size Resize::Fit landed on for `logo` - Image renders anchored at the
    // top-left of whatever Rect it's given, not centered within it, so draw() needs this to
    // build a Rect that already *is* the fitted size instead of an oversized bounding box
    logo_size: Option<(u16, u16)>,
    logo_failed: bool,
}

// mirrors what Resize::Fit computes internally, just kept visible so the result can be used
// to build a correctly-sized (and therefore centerable) Rect rather than an oversized one
fn fit_cells(picker: &Picker, max_cols: u16, max_rows: u16) -> (u16, u16) {
    let font = picker.font_size();
    let (cell_w, cell_h) = (font.width.max(1) as f32, font.height.max(1) as f32);
    let max_px_w = max_cols as f32 * cell_w;
    let max_px_h = max_rows as f32 * cell_h;
    let scale = (max_px_w / LOGO_NATIVE_W).min(max_px_h / LOGO_NATIVE_H).min(1.0);
    let cols = ((LOGO_NATIVE_W * scale) / cell_w).ceil().max(1.0) as u16;
    let rows = ((LOGO_NATIVE_H * scale) / cell_h).ceil().max(1.0) as u16;
    (cols.min(max_cols), rows.min(max_rows))
}

impl WelcomeScreen {
    // encoded lazily against the real bounding box once draw() knows the actual terminal
    // size, not eagerly in Default::default() - ratatui-image's own guidance is to encode
    // once and reuse, not that it has to happen before the first frame
    fn ensure_logo(&mut self, picker: &Picker, max_cols: u16, max_rows: u16) {
        if self.logo.is_some() || self.logo_failed {
            return;
        }
        let image = match image::load_from_memory(LOGO_PNG) {
            Ok(img) => img,
            Err(_) => {
                self.logo_failed = true;
                return;
            }
        };
        // flatten the logo's anti-aliased transparent edges onto solid black before encoding -
        // without this, semi-transparent edge pixels (smooth purple-to-nothing gradient in the
        // source PNG) get composited against whatever background the chosen protocol assumes,
        // producing muddy off-palette fringing (tan/olive speckling) not in the source at all
        let (w, h) = (image.width(), image.height());
        let mut background = image::RgbaImage::from_pixel(w, h, image::Rgba([10, 10, 15, 255]));
        image::imageops::overlay(&mut background, &image.to_rgba8(), 0, 0);
        let image = image::DynamicImage::ImageRgba8(background);

        let (cols, rows) = fit_cells(picker, max_cols, max_rows);
        let size = Size {
            width: cols,
            height: rows,
        };
        match picker.new_protocol(image, size, Resize::Fit(None)) {
            Ok(proto) => {
                self.logo = Some(proto);
                self.logo_size = Some((cols, rows));
            }
            Err(_) => self.logo_failed = true,
        }
    }
}

impl Screen for WelcomeScreen {
    fn draw(&mut self, frame: &mut Frame, _cfg: &InstallConfig, picker: &Picker) {
        let area = frame.area();

        // halfblocks (the fallback when no real terminal answered term_picker::detect's
        // query - see main.rs) has a hard ceiling of 2 source pixel-rows per terminal row; a
        // real protocol (Sixel, inside foot under cage) has no such ceiling. Either way, give
        // Resize::Fit a generous-but-not-overwhelming bounding box and let it scale down to
        // the largest size that preserves the logo's real aspect ratio
        let logo_h = (area.height * 2 / 5).max(8);
        let logo_w = area.width.saturating_sub(8);

        let rows = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Fill(1), // top margin - Fill, not Length, for real vertical centering
                Constraint::Length(logo_h),
                Constraint::Length(1), // blank
                Constraint::Length(1), // welcome heading
                Constraint::Length(1), // subtitle
                Constraint::Length(1), // blank
                Constraint::Length(1), // footer
                Constraint::Fill(1), // bottom margin
            ])
            .split(area);

        let logo_box = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Length(4), Constraint::Length(logo_w), Constraint::Length(4)])
            .split(rows[1])[1];

        self.ensure_logo(picker, logo_box.width, logo_box.height);
        if let (Some(proto), Some((cols, lines))) = (&self.logo, self.logo_size) {
            // Image renders top-left-anchored within its Rect - center a Rect of exactly the
            // fitted size within logo_box instead of handing it the whole (larger) box
            let x = logo_box.x + (logo_box.width.saturating_sub(cols)) / 2;
            let y = logo_box.y + (logo_box.height.saturating_sub(lines)) / 2;
            let logo_area = Rect {
                x,
                y,
                width: cols,
                height: lines,
            };
            frame.render_widget(Image::new(proto), logo_area);
        } else {
            // decode/encode failure fallback - still readable without any image support at all
            let title = Paragraph::new(Span::styled("Kira Linux", Style::default().fg(TEXT)))
                .alignment(Alignment::Center);
            frame.render_widget(title, logo_box);
        }

        let heading = Paragraph::new(Span::styled(
            "Welcome to the Kira Installer",
            Style::default().fg(PRIMARY).add_modifier(Modifier::BOLD),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(heading, rows[3]);

        let subtitle = Paragraph::new(Span::styled(
            "A Linux distribution you actually understand",
            Style::default().fg(TEXT),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(subtitle, rows[4]);

        let footer = Paragraph::new(Span::styled(
            "Press Enter to begin  -  Q to quit",
            Style::default().fg(SUBTEXT),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(footer, rows[6]);
    }

    fn on_key(&mut self, key: KeyEvent, _cfg: &mut InstallConfig) -> Transition {
        match key.code {
            KeyCode::Enter => Transition::Next,
            KeyCode::Char('q') | KeyCode::Char('Q') | KeyCode::Esc => Transition::Quit,
            _ => Transition::Stay,
        }
    }
}

use std::sync::mpsc;
use std::time::Duration;

use ratatui_image::picker::Picker;

// ratatui-image's own capability query writes an escape sequence and reads stdin for a reply.
// Inside a real terminal emulator (foot, when this runs under cage - see the install-flow
// plan) that reply comes back and the terminal's actual graphics protocol (Sixel, for foot)
// gets used for a crisp image render. On the live ISO's bare VT console - no terminal
// emulator at all, nothing will ever answer - and the crate documents no timeout of its own,
// so this wraps the query in one: cage/DRM failing to start is an expected, not exceptional,
// fallback path this installer still has to run correctly on.
//
// MUST be called once, early - right after ratatui::init(), before any crossterm event is
// read - per ratatui-image's own documented ordering requirement for from_query_stdio().
//
// known tradeoff: if the query truly never gets a reply, the spawned thread stays blocked on
// stdin for the rest of the process's life after this gives up waiting - one leaked thread,
// not a correctness issue, and there's no portable way to cancel a blocking stdin read instead.
pub fn detect() -> Picker {
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        let _ = tx.send(Picker::from_query_stdio());
    });
    match rx.recv_timeout(Duration::from_millis(500)) {
        Ok(Ok(picker)) => picker,
        _ => Picker::halfblocks(),
    }
}

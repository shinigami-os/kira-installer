use std::io::Write;
use std::process::{Command, Stdio};

use anyhow::{Context, Result};

// runs `program args...`, erroring (with captured stderr) on a non-zero exit - install.sh's
// own implicit `set -e` for privileged one-shot commands, since none of these should fail
// silently and leave a later step building on a half-done state
pub fn run(program: &str, args: &[&str]) -> Result<()> {
    let output = Command::new(program)
        .args(args)
        .output()
        .with_context(|| format!("failed to run {program}"))?;
    check(program, &output)
}

// runs `program args...` with `input` written to its stdin then closed - e.g. `loadkmap <
// file.bmap`, or chpasswd's own "user:pass\n" stdin convention (install.sh already relies on
// both patterns via shell redirection/pipes; this is the same thing from Rust)
pub fn run_with_stdin(program: &str, args: &[&str], input: &[u8]) -> Result<()> {
    let mut child = Command::new(program)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .with_context(|| format!("failed to spawn {program}"))?;
    child
        .stdin
        .take()
        .expect("stdin was piped")
        .write_all(input)
        .with_context(|| format!("failed to write to {program}'s stdin"))?;
    let output = child
        .wait_with_output()
        .with_context(|| format!("failed to wait for {program}"))?;
    check(program, &output)
}

fn check(program: &str, output: &std::process::Output) -> Result<()> {
    if !output.status.success() {
        anyhow::bail!(
            "{program} exited with {}: {}",
            output.status,
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }
    Ok(())
}

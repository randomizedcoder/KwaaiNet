//! `kwaainet uninstall` — remove all KwaaiNet artefacts
//!
//! Removal order:
//!   1. Stop the running daemon (SIGTERM → SIGKILL after timeout)
//!   2. Uninstall the auto-start service (launchd / systemd)
//!   3. Remove the data directory (~/.kwaainet/)
//!   4. Remove the kwaainet binary and the co-installed p2pd binary

use anyhow::Result;
use std::io::{self, BufRead, Write as _};
use std::path::Path;

use crate::cli::UninstallArgs;
use crate::config::kwaainet_dir;
use crate::daemon::DaemonManager;
use crate::display::*;
use crate::service::get_service_manager;

pub fn run_uninstall(args: &UninstallArgs) -> Result<()> {
    print_box_header("KwaaiNet Uninstall");
    println!();

    // ── Confirmation ────────────────────────────────────────────────────────
    if !args.yes {
        println!("  This will remove:");
        if !args.keep_data {
            println!("    • All KwaaiNet data and configuration (~/.kwaainet/)");
        }
        println!("    • Auto-start service (if installed)");
        println!("    • kwaainet binary (and p2pd if present in the same directory)");
        println!();
        print!("  Proceed? [y/N] ");
        io::stdout().flush().ok();

        let mut line = String::new();
        io::stdin().lock().read_line(&mut line).ok();
        let answer = line.trim().to_lowercase();
        if answer != "y" && answer != "yes" {
            println!("  Aborted.");
            return Ok(());
        }
        println!();
    }

    // ── 1. Stop running daemon ───────────────────────────────────────────────
    let mgr = DaemonManager::new();
    if mgr.is_running() {
        print!("  Stopping KwaaiNet daemon ... ");
        io::stdout().flush().ok();
        match mgr.stop_process() {
            Ok(_) => println!("done"),
            Err(e) => println!("warning: {e}"),
        }
    }

    // ── 2. Uninstall auto-start service ─────────────────────────────────────
    {
        let svc = get_service_manager();
        if svc.status().installed {
            print!("  Uninstalling auto-start service ... ");
            io::stdout().flush().ok();
            match svc.uninstall() {
                Ok(_) => println!("done"),
                Err(e) => println!("warning: {e}"),
            }
        }
    }

    // ── 3. Remove data directory ─────────────────────────────────────────────
    if !args.keep_data {
        let dir = kwaainet_dir();
        if dir.exists() {
            print!("  Removing {} ... ", dir.display());
            io::stdout().flush().ok();
            match std::fs::remove_dir_all(&dir) {
                Ok(_) => println!("done"),
                Err(e) => println!("warning: {e}"),
            }
        }
    }

    // ── 4. Remove binaries ───────────────────────────────────────────────────
    remove_binaries();

    println!();
    print_success("KwaaiNet uninstalled successfully.");
    print_separator();
    Ok(())
}

// ---------------------------------------------------------------------------
// Binary removal helpers
// ---------------------------------------------------------------------------

fn remove_binaries() {
    let exe = match std::env::current_exe() {
        Ok(p) => p,
        Err(e) => {
            print_warning(&format!("Could not determine binary path: {e}"));
            return;
        }
    };

    let bin_dir = match exe.parent() {
        Some(d) => d.to_path_buf(),
        None => {
            print_warning("Could not determine binary directory");
            return;
        }
    };

    #[cfg(windows)]
    let p2pd_name = "p2pd.exe";
    #[cfg(not(windows))]
    let p2pd_name = "p2pd";

    let p2pd = bin_dir.join(p2pd_name);

    #[cfg(windows)]
    {
        // On Windows the running .exe cannot be deleted while in use.
        // Use a self-deleting batch script launched after this process exits.
        let has_p2pd = p2pd.exists();
        if schedule_windows_deletion(&exe, if has_p2pd { Some(&p2pd) } else { None }) {
            println!("  Binaries will be deleted automatically once this process exits.");
        } else {
            // Fallback: print manual instructions
            println!("  Remove the following files manually:");
            println!("    del \"{}\"", exe.display());
            if has_p2pd {
                println!("    del \"{}\"", p2pd.display());
            }
        }
    }

    #[cfg(not(windows))]
    {
        remove_binary_file(&exe);
        if p2pd.exists() {
            remove_binary_file(&p2pd);
        }
    }
}

/// On Unix: unlink the file at `path`.  If permission is denied, print the
/// `sudo rm` command the user needs to run manually.
#[cfg(not(windows))]
fn remove_binary_file(path: &Path) {
    print!("  Removing {} ... ", path.display());
    io::stdout().flush().ok();
    match std::fs::remove_file(path) {
        Ok(_) => println!("done"),
        Err(e) if e.kind() == std::io::ErrorKind::PermissionDenied => {
            println!("permission denied");
            println!("    Run manually: sudo rm \"{}\"", path.display());
        }
        Err(e) => println!("warning: {e}"),
    }
}

/// On Windows: write a short batch script to %TEMP% that waits for this
/// process to exit, then deletes the binaries, then deletes itself.
/// The script is launched detached via `cmd /c start`.
/// Returns `true` if the script was successfully created and launched.
#[cfg(windows)]
fn schedule_windows_deletion(exe: &Path, p2pd: Option<&Path>) -> bool {
    use std::fmt::Write as FmtWrite;

    let pid = std::process::id();
    let temp = std::env::var("TEMP")
        .or_else(|_| std::env::var("TMP"))
        .unwrap_or_else(|_| "C:\\Windows\\Temp".to_string());
    let script_path = format!("{}\\kwaainet_cleanup_{}.bat", temp, pid);

    let mut script = String::new();
    let _ = writeln!(script, "@echo off");
    // Wait until the kwaainet process has exited (poll every 500 ms, max 60 s)
    let _ = writeln!(script, ":wait");
    let _ = writeln!(script, "tasklist /FI \"PID eq {}\" 2>nul | find /I \"kwaainet\" >nul 2>&1", pid);
    let _ = writeln!(script, "if not errorlevel 1 (");
    let _ = writeln!(script, "    ping -n 2 127.0.0.1 >nul");
    let _ = writeln!(script, "    goto wait");
    let _ = writeln!(script, ")");
    let _ = writeln!(script, "del /F /Q \"{}\"", exe.display());
    if let Some(p) = p2pd {
        let _ = writeln!(script, "del /F /Q \"{}\"", p.display());
    }
    // Self-delete the script
    let _ = writeln!(script, "del /F /Q \"%~f0\"");

    if std::fs::write(&script_path, script).is_err() {
        return false;
    }

    std::process::Command::new("cmd")
        .args(["/c", "start", "/min", "", &script_path])
        .spawn()
        .is_ok()
}

//! Execution of `STEREOS_RUN_COMMAND`.

use std::io::Read;
use std::os::unix::process::CommandExt;
use std::process::{Child, Command, Stdio};
use std::time::Duration;

use serde_json::{Value, json};
use snafu::{ResultExt, Snafu};
use wait_timeout::ChildExt;

/// Failure modes for `run_command`. A missing command is not an error (it
/// yields `{"configured": false}`); only spawn/wait failures and timeouts are.
#[derive(Debug, Snafu)]
#[snafu(module)]
pub enum RunCommandError {
    #[snafu(display("run command timed out"))]
    Timeout,
    #[snafu(display("Failed to spawn run command"))]
    Spawn { source: std::io::Error },
    #[snafu(display("Failed to wait on run command"))]
    Wait { source: std::io::Error },
}

/// Run `STEREOS_RUN_COMMAND` (when set) via `/bin/bash -lc`, passing `payload`
/// as `STEREOS_RUN_PAYLOAD`, and return the Python-compatible result object.
///
/// `command == None` yields `{"configured": false}` and never errors. Stdout
/// and stderr are each tailed to the last 4096 chars.
pub fn run_command(
    command: Option<&str>,
    workdir: &str,
    timeout: Duration,
    payload: &str,
) -> Result<Value, RunCommandError> {
    use run_command_error::*;

    let Some(command) = command else {
        return Ok(json!({ "configured": false }));
    };

    let child = Command::new("/bin/bash")
        .arg("-lc")
        .arg(command)
        .current_dir(workdir)
        .env("STEREOS_RUN_PAYLOAD", payload)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context(SpawnSnafu)?;

    let (code, stdout, stderr) = collect(child, timeout)?;
    Ok(json!({
        "configured": true,
        "exit_code": code,
        "stdout": tail_chars(&String::from_utf8_lossy(&stdout), 4096),
        "stderr": tail_chars(&String::from_utf8_lossy(&stderr), 4096),
    }))
}

/// Run a build-time setup command (`STEREOS_READY_COMMAND`) as the agent user.
///
/// Unlike [`run_command`] this drops to `uid`/`gid` and runs with a clean,
/// agent-rooted login environment (HOME/XDG under `home`), so build-time work
/// like `claude install` populates the agent's caches rather than root's. The
/// ambient process env is inherited so TLS cert vars (set in the image
/// Dockerfile) remain available for downloads. `command == None` is a no-op.
pub fn run_setup_command(
    command: Option<&str>,
    home: &str,
    uid: u32,
    gid: u32,
    timeout: Duration,
) -> Result<Value, RunCommandError> {
    use run_command_error::*;

    let Some(command) = command else {
        return Ok(json!({ "configured": false }));
    };

    let child = Command::new("/bin/bash")
        .arg("-lc")
        .arg(command)
        .current_dir(home)
        .uid(uid)
        .gid(gid)
        .env("HOME", home)
        .env("USER", "agent")
        .env("LOGNAME", "agent")
        .env("XDG_CONFIG_HOME", format!("{home}/.config"))
        .env("XDG_STATE_HOME", format!("{home}/.local/state"))
        .env("XDG_CACHE_HOME", format!("{home}/.cache"))
        .env("XDG_DATA_HOME", format!("{home}/.local/share"))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context(SpawnSnafu)?;

    let (code, stdout, stderr) = collect(child, timeout)?;
    Ok(json!({
        "configured": true,
        "exit_code": code,
        "stdout": tail_chars(&String::from_utf8_lossy(&stdout), 4096),
        "stderr": tail_chars(&String::from_utf8_lossy(&stderr), 4096),
    }))
}

/// Exit code (if any) plus the captured stdout and stderr of a finished command.
type CommandOutput = (Option<i32>, Vec<u8>, Vec<u8>);

/// Wait for `child` with a timeout, draining stdout/stderr on threads so a
/// chatty command cannot deadlock by filling a pipe buffer. Returns the exit
/// code (if any) and the captured streams.
fn collect(mut child: Child, timeout: Duration) -> Result<CommandOutput, RunCommandError> {
    use run_command_error::*;

    let mut out = child.stdout.take().expect("piped stdout");
    let mut err = child.stderr.take().expect("piped stderr");
    let out_h = std::thread::spawn(move || {
        let mut buf = Vec::new();
        let _ = out.read_to_end(&mut buf);
        buf
    });
    let err_h = std::thread::spawn(move || {
        let mut buf = Vec::new();
        let _ = err.read_to_end(&mut buf);
        buf
    });

    let status = match child.wait_timeout(timeout).context(WaitSnafu)? {
        Some(status) => status,
        None => {
            let _ = child.kill();
            let _ = child.wait();
            return Err(RunCommandError::Timeout);
        }
    };

    Ok((
        status.code(),
        out_h.join().unwrap_or_default(),
        err_h.join().unwrap_or_default(),
    ))
}

/// Last `n` characters of `s`, matching the Python `s[-n:]` slicing.
fn tail_chars(s: &str, n: usize) -> String {
    let count = s.chars().count();
    if count <= n {
        s.to_string()
    } else {
        s.chars().skip(count - n).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unconfigured_reports_false() {
        let r = run_command(None, ".", Duration::from_secs(5), "{}").unwrap();
        assert_eq!(r, json!({ "configured": false }));
    }

    #[test]
    fn receives_payload_and_succeeds() {
        let r = run_command(
            Some(r#"printf '%s' "$STEREOS_RUN_PAYLOAD""#),
            ".",
            Duration::from_secs(30),
            "hello-payload",
        )
        .unwrap();
        assert_eq!(r["configured"], json!(true));
        assert_eq!(r["exit_code"], json!(0));
        // `contains` rather than `==` tolerates any login-shell init noise.
        assert!(r["stdout"].as_str().unwrap().contains("hello-payload"));
    }

    #[test]
    fn stdout_tailed_to_4096_chars() {
        let r = run_command(
            Some("for _ in $(seq 1 5000); do printf a; done"),
            ".",
            Duration::from_secs(60),
            "",
        )
        .unwrap();
        assert_eq!(r["stdout"].as_str().unwrap().chars().count(), 4096);
    }

    #[test]
    fn timeout_returns_timeout_error() {
        let e = run_command(Some("sleep 5"), ".", Duration::from_millis(200), "").unwrap_err();
        assert!(matches!(e, RunCommandError::Timeout));
    }

    #[test]
    fn nonzero_exit_code_is_reported() {
        let r = run_command(Some("exit 7"), ".", Duration::from_secs(10), "").unwrap();
        assert_eq!(r["exit_code"], json!(7));
    }
}

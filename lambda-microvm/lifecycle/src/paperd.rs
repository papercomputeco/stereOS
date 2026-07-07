//! paperd startup: a pure decision step plus a thin privilege-dropping launch.
//!
//! The agent's home and XDG directories are created and owned `1000:1000` at
//! image build time (see `lib/lambda-microvm.nix`), so this module performs no
//! `mkdir` or `chown` at runtime. It only removes a stale socket, drops to
//! uid/gid 1000, and execs.

use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

pub const AGENT_UID: u32 = 1000;
pub const AGENT_GID: u32 = 1000;
pub const AGENT_HOME: &str = "/home/agent";

/// Candidate paperd binary locations, tried in order (matches the Python).
pub const CANDIDATES: &[&str] = &["/usr/local/bin/paperd", "/bin/paperd", "/bin/paper"];

/// What to do about paperd, decided purely from configuration so it is testable.
#[derive(Debug, PartialEq, Eq)]
pub enum PaperdAction {
    Disabled,
    Missing,
    Start {
        binary: PathBuf,
        env: Vec<(String, String)>,
    },
}

/// Decide what to do about paperd.
///
/// Truthiness matches the Python exactly: only `1`, `true`, or `yes` enable it.
/// `exists` is injected so binary discovery can be tested without a filesystem.
pub fn decide(
    start_flag: Option<&str>,
    candidates: &[&str],
    exists: impl Fn(&Path) -> bool,
    home: &str,
) -> PaperdAction {
    let enabled = matches!(start_flag, Some("1") | Some("true") | Some("yes"));
    if !enabled {
        return PaperdAction::Disabled;
    }
    let Some(binary) = candidates.iter().map(Path::new).find(|p| exists(p)) else {
        return PaperdAction::Missing;
    };
    PaperdAction::Start {
        binary: binary.to_path_buf(),
        env: paperd_env(home),
    }
}

/// The HOME / XDG overrides paperd runs with, all under the agent home.
fn paperd_env(home: &str) -> Vec<(String, String)> {
    vec![
        ("HOME".to_string(), home.to_string()),
        ("XDG_CONFIG_HOME".to_string(), format!("{home}/.config")),
        ("XDG_STATE_HOME".to_string(), format!("{home}/.local/state")),
        (
            "XDG_RUNTIME_DIR".to_string(),
            format!("{home}/.local/state"),
        ),
    ]
}

/// Path of the paper daemon socket we defensively remove before launch.
pub fn socket_path(home: &str) -> PathBuf {
    PathBuf::from(format!("{home}/.local/state/paper/paperd.sock"))
}

/// Carry out `action`, returning the value to store in `State.paperd`.
pub fn start(action: PaperdAction) -> String {
    match action {
        PaperdAction::Disabled => {
            tracing::info!("paperd startup disabled");
            "disabled".to_string()
        }
        PaperdAction::Missing => {
            tracing::warn!("paperd binary missing");
            "missing".to_string()
        }
        PaperdAction::Start { binary, env } => {
            // A stale socket from a prior boot would block bind. This is a file
            // removal, not a permission change, so it is fine at runtime.
            // Derive the home from the env we were handed, so socket cleanup and
            // the daemon we launch always agree on the path.
            let home = env
                .iter()
                .find(|(k, _)| k == "HOME")
                .map(|(_, v)| v.as_str())
                .unwrap_or(AGENT_HOME);
            let sock = socket_path(home);
            if let Err(e) = std::fs::remove_file(&sock) {
                if e.kind() != std::io::ErrorKind::NotFound {
                    tracing::warn!(?sock, error = %e, "could not remove stale paper socket");
                }
            }

            let mut cmd = Command::new(&binary);
            cmd.envs(env)
                .uid(AGENT_UID)
                .gid(AGENT_GID)
                .stdin(Stdio::null())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                // Detach into its own process group so a terminal hangup on the
                // lifecycle process does not propagate to paperd.
                .process_group(0);

            match cmd.spawn() {
                Ok(mut child) => {
                    tracing::info!(binary = %binary.display(), "started paperd");
                    // Reap the child when it exits so it does not linger as a
                    // zombie — the lifecycle process is the container's PID 1,
                    // which the kernel will not reap for us.
                    std::thread::spawn(move || {
                        let _ = child.wait();
                        tracing::warn!("paperd exited");
                    });
                    "started".to_string()
                }
                Err(e) => {
                    tracing::error!(binary = %binary.display(), error = %e, "paperd startup failed");
                    format!("error:{e}")
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn unset_is_disabled() {
        assert_eq!(
            decide(None, CANDIDATES, |_| true, AGENT_HOME),
            PaperdAction::Disabled
        );
    }

    #[test]
    fn falsey_values_are_disabled() {
        for v in ["0", "false", "no", "", "TRUE", "Yes"] {
            assert_eq!(
                decide(Some(v), CANDIDATES, |_| true, AGENT_HOME),
                PaperdAction::Disabled,
                "value {v:?} should be disabled"
            );
        }
    }

    #[test]
    fn truthy_values_pick_first_candidate() {
        for v in ["1", "true", "yes"] {
            match decide(Some(v), CANDIDATES, |_| true, AGENT_HOME) {
                PaperdAction::Start { binary, .. } => {
                    assert_eq!(binary, Path::new("/usr/local/bin/paperd"));
                }
                other => panic!("value {v:?}: expected Start, got {other:?}"),
            }
        }
    }

    #[test]
    fn picks_first_existing_candidate_in_order() {
        let present: HashSet<&str> = ["/bin/paper"].into_iter().collect();
        match decide(
            Some("1"),
            CANDIDATES,
            |p| present.contains(p.to_str().unwrap()),
            AGENT_HOME,
        ) {
            PaperdAction::Start { binary, .. } => assert_eq!(binary, Path::new("/bin/paper")),
            other => panic!("expected Start, got {other:?}"),
        }
    }

    #[test]
    fn none_existing_is_missing() {
        assert_eq!(
            decide(Some("1"), CANDIDATES, |_| false, AGENT_HOME),
            PaperdAction::Missing
        );
    }

    #[test]
    fn env_points_at_agent_home() {
        match decide(Some("1"), CANDIDATES, |_| true, "/home/agent") {
            PaperdAction::Start { env, .. } => {
                let map: std::collections::HashMap<_, _> = env.into_iter().collect();
                assert_eq!(map["HOME"], "/home/agent");
                assert_eq!(map["XDG_CONFIG_HOME"], "/home/agent/.config");
                assert_eq!(map["XDG_STATE_HOME"], "/home/agent/.local/state");
                assert_eq!(map["XDG_RUNTIME_DIR"], "/home/agent/.local/state");
            }
            other => panic!("expected Start, got {other:?}"),
        }
    }

    #[test]
    fn socket_path_under_state_home() {
        assert_eq!(
            socket_path("/home/agent"),
            PathBuf::from("/home/agent/.local/state/paper/paperd.sock")
        );
    }
}

//! Shared lifecycle state and the JSON snapshot returned by every endpoint.

use serde::Serialize;
use serde_json::Value;

/// A recorded lifecycle hook invocation.
///
/// Mirrors the Python `record_hook` event: `{hook, body, at}` where `body` is
/// truncated to 256 chars and `at` is seconds since boot.
#[derive(Debug, Clone, Serialize)]
pub struct Hook {
    pub hook: String,
    pub body: String,
    pub at: f64,
}

/// Mutable lifecycle state shared across request handlers.
///
/// Field names and the serialized snapshot intentionally match the original
/// Python `STATE` dict so downstream AWS hook consumers and the demo runbook
/// observe an identical JSON shape.
#[derive(Debug)]
pub struct State {
    pub booted_at: f64,
    pub run_count: u64,
    pub last_run_payload: Option<String>,
    pub last_run_dispatch: Option<Value>,
    pub last_run_command: Option<Value>,
    pub suspended: bool,
    pub paperd: String,
    pub hooks: Vec<Hook>,
    /// Whether the build-time ready warm-up has already run. Not serialized:
    /// it guards a one-shot side effect and is not part of the AWS snapshot
    /// contract.
    pub ready_warmed: bool,
}

impl State {
    pub fn new(booted_at: f64) -> Self {
        Self {
            booted_at,
            run_count: 0,
            last_run_payload: None,
            last_run_dispatch: None,
            last_run_command: None,
            suspended: false,
            paperd: "not-started".to_string(),
            hooks: Vec::new(),
            ready_warmed: false,
        }
    }

    /// Build the JSON snapshot returned by every endpoint.
    ///
    /// `now` is the current unix time in seconds; passing it in keeps this pure
    /// and testable. Keys serialize sorted (serde_json's `Map` is a `BTreeMap`),
    /// matching the Python `json.dumps(..., sort_keys=True)`.
    pub fn snapshot(&self, mixtape: &str, version: &str, now: f64) -> Value {
        serde_json::json!({
            "booted_at": self.booted_at,
            "run_count": self.run_count,
            "last_run_payload": self.last_run_payload,
            "last_run_dispatch": self.last_run_dispatch,
            "last_run_command": self.last_run_command,
            "suspended": self.suspended,
            "paperd": self.paperd,
            "hooks": self.hooks,
            "uptime_seconds": round3(now - self.booted_at),
            "mixtape": mixtape,
            "version": version,
        })
    }

    /// Append a hook event, truncating the recorded body to 256 chars.
    pub fn record_hook(&mut self, hook: &str, body: &str, now: f64) {
        let truncated: String = body.chars().take(256).collect();
        self.hooks.push(Hook {
            hook: hook.to_string(),
            body: truncated,
            at: round3(now - self.booted_at),
        });
    }
}

/// Round to 3 decimal places, matching the Python `round(x, 3)` calls.
pub fn round3(x: f64) -> f64 {
    (x * 1000.0).round() / 1000.0
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Drift guard: the snapshot key set is a contract with AWS hook consumers
    /// and the demo runbook. If this changes, that is a deliberate break.
    #[test]
    fn snapshot_has_exact_key_set() {
        let s = State::new(100.0);
        let snap = s.snapshot("coder", "1.2.3", 100.5);
        let obj = snap.as_object().unwrap();
        let mut keys: Vec<&str> = obj.keys().map(String::as_str).collect();
        keys.sort_unstable();
        assert_eq!(
            keys,
            vec![
                "booted_at",
                "hooks",
                "last_run_command",
                "last_run_dispatch",
                "last_run_payload",
                "mixtape",
                "paperd",
                "run_count",
                "suspended",
                "uptime_seconds",
                "version",
            ]
        );
        assert_eq!(obj["uptime_seconds"], serde_json::json!(0.5));
        assert_eq!(obj["mixtape"], "coder");
        assert_eq!(obj["version"], "1.2.3");
        assert_eq!(obj["paperd"], "not-started");
    }

    #[test]
    fn record_hook_truncates_body_to_256() {
        let mut s = State::new(0.0);
        let body = "x".repeat(300);
        s.record_hook("run", &body, 1.0);
        assert_eq!(s.hooks.len(), 1);
        assert_eq!(s.hooks[0].body.chars().count(), 256);
        assert_eq!(s.hooks[0].hook, "run");
        assert_eq!(s.hooks[0].at, 1.0);
    }
}

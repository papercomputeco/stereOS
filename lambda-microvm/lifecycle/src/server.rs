//! HTTP routing as a pure function over `(method, path, body)`.
//!
//! Side effects (running commands, scheduling shutdown, reading the clock) are
//! injected via the [`Effects`] trait so routing and state transitions are
//! unit-testable without binding a socket.

use std::sync::Mutex;

use serde_json::{Value, json};

use crate::command::RunCommandError;
use crate::dispatch::parse_run_dispatch;
use crate::state::State;

/// Side effects the router triggers, injected for testability.
pub trait Effects: Send + Sync {
    /// Run `STEREOS_RUN_COMMAND` synchronously (direct `POST /run`).
    fn run_command_sync(&self, payload: &str) -> Result<Value, RunCommandError>;
    /// Run the parsed dispatch in the background (AWS `/run`).
    fn spawn_dispatch(&self, dispatch: Value);
    /// Schedule process shutdown shortly after responding (terminate hooks).
    fn schedule_shutdown(&self);
    /// Current unix time in seconds (injectable for deterministic tests).
    fn now(&self) -> f64;
}

/// Static configuration surfaced in every snapshot.
pub struct Config {
    pub mixtape: String,
    pub version: String,
}

/// An HTTP response: status code plus JSON body.
pub struct Reply {
    pub status: u16,
    pub body: Value,
}

const HOOK_PATHS: &[(&str, &str)] = &[
    ("/aws/lambda-microvms/runtime/v1/ready", "ready"),
    ("/aws/lambda-microvms/runtime/v1/validate", "validate"),
    ("/aws/lambda-microvms/runtime/v1/run", "run"),
    ("/aws/lambda-microvms/runtime/v1/suspend", "suspend"),
    ("/aws/lambda-microvms/runtime/v1/resume", "resume"),
    ("/aws/lambda-microvms/runtime/v1/terminate", "terminate"),
];

fn hook_for(path: &str) -> Option<&'static str> {
    HOOK_PATHS.iter().find(|(p, _)| *p == path).map(|(_, h)| *h)
}

fn not_found() -> Reply {
    Reply {
        status: 404,
        body: json!({ "error": "not found" }),
    }
}

/// Route a request to a reply, mutating state and triggering effects.
///
/// This is the unit-test seam, so it takes its dependencies explicitly rather
/// than behind a context struct.
#[allow(clippy::too_many_arguments)]
pub fn handle(
    method: &str,
    path: &str,
    body: &str,
    state: &Mutex<State>,
    cfg: &Config,
    effects: &dyn Effects,
) -> Reply {
    let router = Router {
        state,
        cfg,
        effects,
        now: effects.now(),
    };
    let path = path.split('?').next().unwrap_or(path);
    match method {
        "GET" => router.get(path),
        "POST" => router.post(path, body),
        _ => not_found(),
    }
}

/// Per-request routing context: bundles the dependencies so handlers stay
/// small and the clock is captured once per request.
struct Router<'a> {
    state: &'a Mutex<State>,
    cfg: &'a Config,
    effects: &'a dyn Effects,
    now: f64,
}

impl Router<'_> {
    fn snapshot(&self) -> Value {
        self.state
            .lock()
            .unwrap()
            .snapshot(&self.cfg.mixtape, &self.cfg.version, self.now)
    }

    fn ok(&self) -> Reply {
        Reply {
            status: 200,
            body: self.snapshot(),
        }
    }

    fn get(&self, path: &str) -> Reply {
        if let Some(hook @ ("ready" | "validate")) = hook_for(path) {
            self.state.lock().unwrap().record_hook(hook, "", self.now);
            return self.ok();
        }
        match path {
            "/" | "/health" | "/ready" | "/validate" => self.ok(),
            _ => not_found(),
        }
    }

    fn post(&self, path: &str, body: &str) -> Reply {
        if let Some(hook) = hook_for(path) {
            self.state.lock().unwrap().record_hook(hook, body, self.now);
            return Reply {
                status: 200,
                body: self.apply_hook(hook, body),
            };
        }

        match path {
            "/ready" | "/validate" => self.ok(),
            "/run" => self.direct_run(body),
            "/suspend" => {
                self.state.lock().unwrap().suspended = true;
                Reply {
                    status: 200,
                    body: json!({ "ok": true, "state": self.snapshot() }),
                }
            }
            "/resume" => {
                self.state.lock().unwrap().suspended = false;
                Reply {
                    status: 200,
                    body: json!({ "ok": true, "state": self.snapshot() }),
                }
            }
            "/terminate" => {
                // Build the reply (acknowledging) before scheduling shutdown, so
                // the client always sees the 200 first.
                let reply = Reply {
                    status: 200,
                    body: json!({ "ok": true, "state": self.snapshot() }),
                };
                self.effects.schedule_shutdown();
                reply
            }
            _ => not_found(),
        }
    }

    /// Direct `POST /run`: runs `STEREOS_RUN_COMMAND` synchronously with the raw
    /// body as the payload (no envelope parsing).
    fn direct_run(&self, body: &str) -> Reply {
        {
            let mut s = self.state.lock().unwrap();
            s.run_count += 1;
            s.last_run_payload = Some(body.to_string());
        }
        match self.effects.run_command_sync(body) {
            Ok(command) => Reply {
                status: 200,
                body: json!({ "ok": true, "state": self.snapshot(), "command": command }),
            },
            Err(RunCommandError::Timeout) => Reply {
                status: 504,
                body: json!({ "ok": false, "error": "run command timed out" }),
            },
            Err(e) => Reply {
                status: 500,
                body: json!({ "ok": false, "error": e.to_string() }),
            },
        }
    }

    fn apply_hook(&self, hook: &str, body: &str) -> Value {
        match hook {
            "run" => {
                let dispatch = parse_run_dispatch(body);
                {
                    let mut s = self.state.lock().unwrap();
                    s.run_count += 1;
                    s.last_run_payload = Some(body.to_string());
                    s.last_run_dispatch = Some(dispatch.clone());
                }
                self.effects.spawn_dispatch(dispatch);
                json!({ "status": "accepted", "state": self.snapshot() })
            }
            "suspend" => {
                self.state.lock().unwrap().suspended = true;
                json!({ "status": "ok", "state": self.snapshot() })
            }
            "resume" => {
                self.state.lock().unwrap().suspended = false;
                json!({ "status": "ok", "state": self.snapshot() })
            }
            "terminate" => {
                self.effects.schedule_shutdown();
                json!({ "status": "ok", "state": self.snapshot() })
            }
            // ready / validate and any future hook: acknowledge with a snapshot.
            _ => json!({ "status": "ok", "state": self.snapshot() }),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    enum RunMode {
        Ok,
        Timeout,
        Err,
    }

    struct Mock {
        run_mode: RunMode,
        dispatched: Mutex<Vec<Value>>,
        shutdowns: AtomicUsize,
    }

    impl Mock {
        fn new(run_mode: RunMode) -> Self {
            Self {
                run_mode,
                dispatched: Mutex::new(Vec::new()),
                shutdowns: AtomicUsize::new(0),
            }
        }
    }

    impl Effects for Mock {
        fn run_command_sync(&self, payload: &str) -> Result<Value, RunCommandError> {
            match self.run_mode {
                RunMode::Ok => Ok(json!({ "configured": true, "echo": payload })),
                RunMode::Timeout => Err(RunCommandError::Timeout),
                RunMode::Err => Err(RunCommandError::Spawn {
                    source: std::io::Error::other("boom"),
                }),
            }
        }
        fn spawn_dispatch(&self, dispatch: Value) {
            self.dispatched.lock().unwrap().push(dispatch);
        }
        fn schedule_shutdown(&self) {
            self.shutdowns.fetch_add(1, Ordering::SeqCst);
        }
        fn now(&self) -> f64 {
            1.0
        }
    }

    fn ctx() -> (Mutex<State>, Config) {
        (
            Mutex::new(State::new(0.0)),
            Config {
                mixtape: "m".to_string(),
                version: "v".to_string(),
            },
        )
    }

    #[test]
    fn get_ready_and_validate_are_200() {
        let (st, cfg) = ctx();
        let m = Mock::new(RunMode::Ok);
        for p in ["/ready", "/validate", "/", "/health"] {
            assert_eq!(handle("GET", p, "", &st, &cfg, &m).status, 200, "{p}");
        }
    }

    #[test]
    fn aws_get_ready_validate_are_200_and_record_hooks() {
        let (st, cfg) = ctx();
        let m = Mock::new(RunMode::Ok);
        let r = handle(
            "GET",
            "/aws/lambda-microvms/runtime/v1/ready",
            "",
            &st,
            &cfg,
            &m,
        );
        assert_eq!(r.status, 200);
        assert_eq!(st.lock().unwrap().hooks.len(), 1);
    }

    #[test]
    fn aws_get_run_path_is_404() {
        // GET on a non-ready/validate AWS hook path is not routed.
        let (st, cfg) = ctx();
        let m = Mock::new(RunMode::Ok);
        let r = handle(
            "GET",
            "/aws/lambda-microvms/runtime/v1/run",
            "",
            &st,
            &cfg,
            &m,
        );
        assert_eq!(r.status, 404);
    }

    #[test]
    fn unknown_path_is_404() {
        let (st, cfg) = ctx();
        let m = Mock::new(RunMode::Ok);
        assert_eq!(handle("GET", "/nope", "", &st, &cfg, &m).status, 404);
        assert_eq!(handle("POST", "/nope", "", &st, &cfg, &m).status, 404);
    }

    #[test]
    fn suspend_then_resume_toggles_state() {
        let (st, cfg) = ctx();
        let m = Mock::new(RunMode::Ok);
        handle("POST", "/suspend", "", &st, &cfg, &m);
        assert!(st.lock().unwrap().suspended);
        handle("POST", "/resume", "", &st, &cfg, &m);
        assert!(!st.lock().unwrap().suspended);
    }

    #[test]
    fn direct_run_increments_run_count() {
        let (st, cfg) = ctx();
        let m = Mock::new(RunMode::Ok);
        let r = handle("POST", "/run", "raw-body", &st, &cfg, &m);
        assert_eq!(r.status, 200);
        assert_eq!(st.lock().unwrap().run_count, 1);
        assert_eq!(
            st.lock().unwrap().last_run_payload.as_deref(),
            Some("raw-body")
        );
        assert_eq!(r.body["command"]["echo"], json!("raw-body"));
    }

    #[test]
    fn direct_run_timeout_is_504() {
        let (st, cfg) = ctx();
        let m = Mock::new(RunMode::Timeout);
        assert_eq!(handle("POST", "/run", "x", &st, &cfg, &m).status, 504);
    }

    #[test]
    fn direct_run_error_is_500() {
        let (st, cfg) = ctx();
        let m = Mock::new(RunMode::Err);
        assert_eq!(handle("POST", "/run", "x", &st, &cfg, &m).status, 500);
    }

    #[test]
    fn aws_run_records_dispatch_and_spawns() {
        let (st, cfg) = ctx();
        let m = Mock::new(RunMode::Ok);
        let body = r#"{"runHookPayload":"{\"session\":{\"mode\":\"smoke\"}}"}"#;
        let r = handle(
            "POST",
            "/aws/lambda-microvms/runtime/v1/run",
            body,
            &st,
            &cfg,
            &m,
        );
        assert_eq!(r.status, 200);
        assert_eq!(r.body["status"], json!("accepted"));
        assert_eq!(st.lock().unwrap().run_count, 1);
        assert_eq!(
            st.lock().unwrap().last_run_dispatch,
            Some(json!({ "mode": "smoke" }))
        );
        assert_eq!(
            m.dispatched.lock().unwrap().as_slice(),
            &[json!({ "mode": "smoke" })]
        );
    }

    #[test]
    fn terminate_acknowledges_then_schedules_shutdown() {
        let (st, cfg) = ctx();
        let m = Mock::new(RunMode::Ok);
        let r = handle("POST", "/terminate", "", &st, &cfg, &m);
        assert_eq!(r.status, 200);
        assert_eq!(r.body["ok"], json!(true));
        assert_eq!(m.shutdowns.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn aws_terminate_hook_schedules_shutdown() {
        let (st, cfg) = ctx();
        let m = Mock::new(RunMode::Ok);
        let r = handle(
            "POST",
            "/aws/lambda-microvms/runtime/v1/terminate",
            "",
            &st,
            &cfg,
            &m,
        );
        assert_eq!(r.status, 200);
        assert_eq!(r.body["status"], json!("ok"));
        assert_eq!(m.shutdowns.load(Ordering::SeqCst), 1);
    }
}

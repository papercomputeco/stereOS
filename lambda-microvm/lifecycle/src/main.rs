//! AWS Lambda MicroVM lifecycle hook server for stereOS source bundles.
//!
//! Serves the image-build (`ready`, `validate`) and runtime (`run`, `suspend`,
//! `resume`, `terminate`) hooks AWS calls against the MicroVM, plus direct debug
//! endpoints, and optionally starts `paperd`. This is a faithful port of the
//! original `lifecycle.py` proof of concept; the HTTP contract is unchanged.

mod command;
mod dispatch;
mod paperd;
mod server;
mod state;

use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde_json::Value;
use tiny_http::{Header, Response, Server};

use crate::server::{Config, Effects};
use crate::state::State;

fn unix_now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

fn env_or(key: &str, default: &str) -> String {
    std::env::var(key).unwrap_or_else(|_| default.to_string())
}

/// Production [`Effects`]: runs real commands and exits the process.
struct RealEffects {
    state: Arc<Mutex<State>>,
    run_command: Option<String>,
    workdir: String,
    timeout: Duration,
    ready_command: Option<String>,
    ready_timeout: Duration,
    agent_home: String,
}

impl Effects for RealEffects {
    fn run_command_sync(&self, payload: &str) -> Result<Value, command::RunCommandError> {
        command::run_command(
            self.run_command.as_deref(),
            &self.workdir,
            self.timeout,
            payload,
        )
    }

    fn spawn_dispatch(&self, dispatch: Value) {
        let state = self.state.clone();
        let command = self.run_command.clone();
        let workdir = self.workdir.clone();
        let timeout = self.timeout;
        std::thread::spawn(move || {
            // Serialize sorted, matching the Python `json.dumps(sort_keys=True)`.
            let payload = serde_json::to_string(&dispatch).unwrap_or_else(|_| "{}".to_string());
            let result = match command::run_command(command.as_deref(), &workdir, timeout, &payload)
            {
                Ok(v) => v,
                Err(command::RunCommandError::Timeout) => {
                    serde_json::json!({ "configured": true, "error": "run command timed out" })
                }
                Err(e) => serde_json::json!({
                    "configured": command.is_some(),
                    "error": e.to_string(),
                }),
            };
            state.lock().unwrap().last_run_command = Some(result);
        });
    }

    fn schedule_shutdown(&self) {
        std::thread::spawn(|| {
            std::thread::sleep(Duration::from_millis(250));
            std::process::exit(0);
        });
    }

    fn warm_ready(&self) {
        if self.ready_command.is_none() {
            return;
        }
        tracing::info!("running ready warm-up command");
        match command::run_setup_command(
            self.ready_command.as_deref(),
            &self.agent_home,
            paperd::AGENT_UID,
            paperd::AGENT_GID,
            self.ready_timeout,
        ) {
            // Logged, not stored in the snapshot: `last_run_command` is reserved
            // for actual /run calls, and the warm output would otherwise ship in
            // every MicroVM's initial state.
            Ok(result) => tracing::info!(result = %result, "ready warm-up finished"),
            Err(e) => tracing::warn!(error = %e, "ready warm-up failed"),
        }
    }

    fn now(&self) -> f64 {
        unix_now()
    }
}

fn serve_one(
    mut request: tiny_http::Request,
    state: &Mutex<State>,
    cfg: &Config,
    effects: &dyn Effects,
) {
    let method = request.method().to_string();
    let url = request.url().to_string();

    // Read the body lossily so invalid UTF-8 cannot drop the request, matching
    // the Python `decode("utf-8", errors="replace")`.
    let mut buf = Vec::new();
    let _ = request.as_reader().read_to_end(&mut buf);
    let body = String::from_utf8_lossy(&buf);

    let reply = server::handle(&method, &url, &body, state, cfg, effects);
    let data = serde_json::to_string(&reply.body).unwrap_or_else(|_| "{}".to_string());
    let header = Header::from_bytes(&b"content-type"[..], &b"application/json"[..])
        .expect("static header is valid");
    let response = Response::from_string(data)
        .with_status_code(reply.status)
        .with_header(header);
    if let Err(e) = request.respond(response) {
        tracing::warn!(error = %e, "failed to write response");
    }
}

fn main() {
    tracing_subscriber::fmt()
        .with_writer(std::io::stderr)
        .with_target(false)
        .init();

    let state = Arc::new(Mutex::new(State::new(unix_now())));

    // Start paperd before serving (matches the Python ordering).
    let start_flag = std::env::var("STEREOS_START_PAPERD").ok();
    let action = paperd::decide(
        start_flag.as_deref(),
        paperd::CANDIDATES,
        |p| p.exists(),
        paperd::AGENT_HOME,
    );
    state.lock().unwrap().paperd = paperd::start(action);

    let cfg = Arc::new(Config {
        mixtape: env_or("STEREOS_MIXTAPE", "unknown"),
        version: env_or("STEREOS_VERSION", "unknown"),
    });

    let timeout_secs: u64 = env_or("STEREOS_RUN_TIMEOUT_SECONDS", "300")
        .parse()
        .unwrap_or(300);
    // Default under the AWS `readyTimeoutInSeconds` (300) so the warm-up cannot
    // overrun the build's ready window and abort image creation.
    let ready_timeout_secs: u64 = env_or("STEREOS_READY_TIMEOUT_SECONDS", "240")
        .parse()
        .unwrap_or(240);
    let effects = Arc::new(RealEffects {
        state: state.clone(),
        run_command: std::env::var("STEREOS_RUN_COMMAND")
            .ok()
            .filter(|s| !s.is_empty()),
        workdir: env_or("STEREOS_WORKDIR", "/home/agent/workspace"),
        timeout: Duration::from_secs(timeout_secs),
        ready_command: std::env::var("STEREOS_READY_COMMAND")
            .ok()
            .filter(|s| !s.is_empty()),
        ready_timeout: Duration::from_secs(ready_timeout_secs),
        agent_home: env_or("STEREOS_AGENT_HOME", paperd::AGENT_HOME),
    });

    let host = env_or("HOST", "0.0.0.0");
    let port: u16 = std::env::var("HOOK_PORT")
        .ok()
        .or_else(|| std::env::var("PORT").ok())
        .and_then(|p| p.parse().ok())
        .unwrap_or(9000);
    let addr = format!("{host}:{port}");

    tracing::info!(%addr, "starting lifecycle server");
    let server = match Server::http(&addr) {
        Ok(s) => Arc::new(s),
        Err(e) => {
            eprintln!("failed to bind {addr}: {e}");
            std::process::exit(1);
        }
    };

    loop {
        let request = match server.recv() {
            Ok(r) => r,
            Err(e) => {
                tracing::error!(error = %e, "recv failed");
                continue;
            }
        };
        // Thread-per-request, mirroring the Python ThreadingHTTPServer so a slow
        // /run cannot block /health.
        let state = state.clone();
        let cfg = cfg.clone();
        let effects = effects.clone();
        std::thread::spawn(move || {
            serve_one(request, state.as_ref(), cfg.as_ref(), effects.as_ref());
        });
    }
}

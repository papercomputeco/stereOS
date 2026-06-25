//! Parsing of the AWS Lambda MicroVM `runHookPayload` envelope.

use serde_json::{Value, json};

/// Parse the AWS `runHookPayload` envelope into the dispatch object handed to
/// `STEREOS_RUN_COMMAND`.
///
/// Mirrors the Python `parse_run_dispatch` exactly:
/// - empty body -> `{}`
/// - invalid JSON -> `{"raw": body}`
/// - object with a truthy `runHookPayload` string -> parse the inner JSON
///   (inner parse failure -> `{"raw": <inner string>}`)
/// - otherwise the envelope itself is the inner value
/// - inner object with an object `session` -> just the `session`
/// - inner object -> the inner object
/// - inner non-object -> `{"value": inner}`
pub fn parse_run_dispatch(body: &str) -> Value {
    if body.is_empty() {
        return json!({});
    }

    let envelope: Value = match serde_json::from_str(body) {
        Ok(v) => v,
        Err(_) => return json!({ "raw": body }),
    };

    let inner: Value = match envelope.get("runHookPayload") {
        Some(rhp) if is_truthy(rhp) => {
            // The Python calls json.loads on the value; in practice AWS always
            // sends a JSON string. A non-string cannot be re-parsed, so we treat
            // it as raw, matching the "could not decode" branch.
            match rhp.as_str() {
                Some(s) => match serde_json::from_str(s) {
                    Ok(v) => v,
                    Err(_) => return json!({ "raw": s }),
                },
                None => return json!({ "raw": body }),
            }
        }
        _ => envelope,
    };

    let session_is_object = inner.get("session").map(Value::is_object).unwrap_or(false);
    if inner.is_object() {
        if session_is_object {
            return inner.get("session").cloned().unwrap();
        }
        return inner;
    }
    json!({ "value": inner })
}

/// Python truthiness for a JSON value, used for the `runHookPayload` guard.
fn is_truthy(v: &Value) -> bool {
    match v {
        Value::Null => false,
        Value::Bool(b) => *b,
        Value::Number(n) => n.as_f64().map(|f| f != 0.0).unwrap_or(true),
        Value::String(s) => !s.is_empty(),
        Value::Array(a) => !a.is_empty(),
        Value::Object(o) => !o.is_empty(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_body_is_empty_object() {
        assert_eq!(parse_run_dispatch(""), json!({}));
    }

    #[test]
    fn invalid_json_is_raw() {
        assert_eq!(parse_run_dispatch("not json"), json!({ "raw": "not json" }));
    }

    #[test]
    fn direct_object_returned() {
        assert_eq!(parse_run_dispatch(r#"{"a":1}"#), json!({ "a": 1 }));
    }

    #[test]
    fn envelope_inner_parsed() {
        let body = r#"{"runHookPayload":"{\"version\":\"1\",\"foo\":true}"}"#;
        assert_eq!(
            parse_run_dispatch(body),
            json!({ "version": "1", "foo": true })
        );
    }

    #[test]
    fn session_object_extracted() {
        let body = r#"{"runHookPayload":"{\"session\":{\"mode\":\"smoke\"}}"}"#;
        assert_eq!(parse_run_dispatch(body), json!({ "mode": "smoke" }));
    }

    #[test]
    fn non_object_inner_is_wrapped() {
        let body = r#"{"runHookPayload":"[1,2,3]"}"#;
        assert_eq!(parse_run_dispatch(body), json!({ "value": [1, 2, 3] }));
    }

    #[test]
    fn empty_run_hook_payload_falls_back_to_envelope() {
        // "" is falsy, so the envelope itself becomes the inner value.
        let body = r#"{"runHookPayload":"","x":1}"#;
        assert_eq!(
            parse_run_dispatch(body),
            json!({ "runHookPayload": "", "x": 1 })
        );
    }

    #[test]
    fn inner_parse_failure_is_raw() {
        let body = r#"{"runHookPayload":"{bad"}"#;
        assert_eq!(parse_run_dispatch(body), json!({ "raw": "{bad" }));
    }

    #[test]
    fn non_object_session_keeps_inner() {
        let body = r#"{"runHookPayload":"{\"session\":\"s\",\"a\":1}"}"#;
        assert_eq!(parse_run_dispatch(body), json!({ "session": "s", "a": 1 }));
    }
}

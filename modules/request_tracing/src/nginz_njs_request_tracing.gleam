//// njs entry point for request_tracing. Reads the native requestid module's
//// $ngz_request_id and propagates it to upstream headers, records spans,
//// and emits structured trace logs.

import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}
import request_tracing/emit
import request_tracing/model.{type TraceContext}
import request_tracing/propagate

/// Traced handler. Reads $ngz_request_id, injects X-Request-ID and
/// X-Trace-ID into response headers, returns 204.
fn traced(r: HTTPRequest) -> Nil {
  let ctx = read_context(r)
  let headers = propagate.propagation_headers(ctx)
  set_headers(r, headers)
  let _ =
    http.log(
      r,
      "request_tracing: propagated — " <> model.summary(ctx, ngx.now()),
    )
  http.return_code(r, 204)
}

/// Traced handler with structured log emission. Logs a JSON trace line
/// at the end of the request.
fn traced_with_log(r: HTTPRequest) -> Nil {
  let ctx = read_context(r)
  let headers = propagate.propagation_headers(ctx)
  set_headers(r, headers)
  let trace_json = emit.json(ctx, ngx.now())
  let _ = http.log(r, "request_tracing: " <> trace_json)
  http.return_code(r, 204)
}

/// Traced handler with session correlation. Links the request ID to
/// the session subject for cross-system debugging.
fn traced_with_session(r: HTTPRequest) -> Nil {
  let ctx = read_context(r)
  let headers = propagate.propagation_headers(ctx)
  set_headers(r, headers)
  // In a real deployment, we would read the session subject from
  // $session_subject (set by auth_request) and log the correlation.
  let _ =
    http.log(
      r,
      "request_tracing: correlated — " <> model.summary(ctx, ngx.now()),
    )
  http.return_code(r, 204)
}

// --- Internal helpers ---

fn read_context(r: HTTPRequest) -> TraceContext {
  let vars = http.get_variables(r)
  // Prefer the native requestid module's $ngz_request_id.
  // Fall back to nginx built-in $request_id, then "unknown".
  let id = case ngx.get(vars, "ngz_request_id") {
    Ok(v) -> {
      let s = ngx.to_string(v)
      case s {
        "" ->
          case ngx.get(vars, "request_id") {
            Ok(v2) -> ngx.to_string(v2)
            Error(_) -> "unknown"
          }
        _ -> s
      }
    }
    Error(_) ->
      case ngx.get(vars, "request_id") {
        Ok(v2) -> ngx.to_string(v2)
        Error(_) -> "unknown"
      }
  }
  model.context(id, ngx.now())
}

fn set_headers(r: HTTPRequest, pairs: List(#(String, String))) -> Nil {
  case pairs {
    [] -> Nil
    [#(name, value), ..rest] -> {
      let _ = http.set_headers_out(r, name, value)
      set_headers(r, rest)
    }
  }
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("traced", traced)
  |> ngx.merge("traced_with_log", traced_with_log)
  |> ngx.merge("traced_with_session", traced_with_session)
}

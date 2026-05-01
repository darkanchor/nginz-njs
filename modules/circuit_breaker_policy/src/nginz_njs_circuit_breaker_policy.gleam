//// njs entry point for circuit_breaker_policy. Reads the native
//// circuit-breaker module's $ngz_circuit_state variable and applies
//// scripted policy: fallback responses, error bodies, and logging.

import circuit_breaker_policy/fallback
import circuit_breaker_policy/model.{
  type CircuitContext, Closed, HalfOpen, Open, Unknown,
}
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}

/// Circuit-protected handler. Reads $ngz_circuit_state and blocks requests
/// when circuit is open (503), passes through when closed.
fn circuit_protected(r: HTTPRequest) -> Nil {
  let ctx = read_context(r)
  case ctx.state {
    Closed -> {
      let _ = http.log(r, "circuit_breaker_policy: closed — passing through")
      http.return_code(r, 204)
    }
    Open -> {
      let _ = http.log(r, "circuit_breaker_policy: open — blocking request")
      http.return_code(r, 503)
    }
    HalfOpen -> {
      let _ = http.log(r, "circuit_breaker_policy: half_open — allowing probe")
      http.return_code(r, 204)
    }
    Unknown -> {
      let _ =
        http.log(r, "circuit_breaker_policy: unknown state — passing through")
      http.return_code(r, 204)
    }
  }
}

/// Circuit handler with custom fallback body when open.
fn circuit_with_fallback(r: HTTPRequest) -> Nil {
  let ctx = read_context(r)
  case ctx.state {
    Open -> {
      let body =
        fallback.json_error("Service temporarily unavailable. Please retry.")
      let _ = http.set_headers_out(r, "Content-Type", "application/json")
      let _ = http.log(r, "circuit_breaker_policy: open — serving fallback")
      http.return_text(r, 503, body)
    }
    HalfOpen -> {
      let body =
        fallback.json_degraded("Service is recovering. Limited capacity.")
      let _ = http.set_headers_out(r, "Content-Type", "application/json")
      let _ =
        http.log(r, "circuit_breaker_policy: half_open — serving degraded")
      http.return_text(r, 503, body)
    }
    Closed -> {
      let _ = http.log(r, "circuit_breaker_policy: closed — passing through")
      http.return_code(r, 204)
    }
    Unknown -> http.return_code(r, 204)
  }
}

/// Circuit handler with JSON error response for all non-closed states.
fn circuit_json_error(r: HTTPRequest) -> Nil {
  let ctx = read_context(r)
  let #(status, ct, body) = fallback.auto_body(ctx, "Circuit breaker triggered")
  case status {
    200 -> {
      let _ = http.log(r, "circuit_breaker_policy: " <> model.summary(ctx))
      http.return_code(r, 204)
    }
    _ -> {
      let _ = http.set_headers_out(r, "Content-Type", ct)
      let _ = http.log(r, "circuit_breaker_policy: " <> model.summary(ctx))
      http.return_text(r, status, body)
    }
  }
}

// --- Internal helpers ---

fn read_context(r: HTTPRequest) -> CircuitContext {
  let vars = http.get_variables(r)
  let raw_state = case ngx.get(vars, "ngz_circuit_state") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  model.context(raw_state)
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("circuit_protected", circuit_protected)
  |> ngx.merge("circuit_with_fallback", circuit_with_fallback)
  |> ngx.merge("circuit_json_error", circuit_json_error)
}

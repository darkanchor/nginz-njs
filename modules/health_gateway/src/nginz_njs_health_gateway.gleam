//// njs entry point for health_gateway. Reads health data from the native
//// healthcheck module's JSON endpoints via subrequest, aggregates across
//// backends, and applies readiness gating.

import gleam/int
import gleam/list
import gleam/string
import health_gateway/model.{
  type AggregateStatus, type BackendHealth, AllHealthy, AllUnhealthy, Degraded,
}
import health_gateway/response
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}

/// Aggregate health handler. Returns a JSON response combining the health
/// status of all configured backends.
fn aggregate_health(r: HTTPRequest) -> Nil {
  let backends = read_backends(r)
  let status = model.aggregate(backends)
  let body = response.aggregate_json(status, backends)
  let _ = http.set_headers_out(r, "Content-Type", "application/json")
  let _ =
    http.log(r, "health_gateway: aggregate — " <> aggregate_summary(status))
  case status {
    AllUnhealthy -> http.return_text(r, 503, body)
    _ -> http.return_text(r, 200, body)
  }
}

/// Readiness gate handler. Blocks requests (503) when all backends are
/// unhealthy, passes through otherwise.
fn readiness_gate(r: HTTPRequest) -> Nil {
  let backends = read_backends(r)
  let status = model.aggregate(backends)
  let decision = model.gate_decision(status)
  case decision {
    model.Allow -> {
      let _ = http.log(r, "health_gateway: gate — allow")
      http.return_code(r, 204)
    }
    model.Block(reason) -> {
      let body = response.readiness_json(False, reason)
      let _ = http.set_headers_out(r, "Content-Type", "application/json")
      let _ = http.log(r, "health_gateway: gate — block — " <> reason)
      http.return_text(r, 503, body)
    }
  }
}

/// Custom health response handler. Combines native healthcheck data with
/// scripted signals (e.g., session status, feature flag state).
fn custom_health(r: HTTPRequest) -> Nil {
  let backends = read_backends(r)
  let status = model.aggregate(backends)
  let body = response.aggregate_json(status, backends)
  let _ = http.set_headers_out(r, "Content-Type", "application/json")
  let _ = http.log(r, "health_gateway: custom — " <> aggregate_summary(status))
  case status {
    AllUnhealthy -> http.return_text(r, 503, body)
    _ -> http.return_text(r, 200, body)
  }
}

// --- Internal helpers ---

/// Read backend health from nginx variables. In a real deployment, this
/// would parse JSON from subrequests to healthcheck endpoints.
fn read_backends(r: HTTPRequest) -> List(BackendHealth) {
  let backend_status = case http.get_variable(r, "health_backends") {
    Ok(v) -> v
    Error(_) -> ""
  }
  parse_backends(backend_status)
}

fn parse_backends(value: String) -> List(BackendHealth) {
  case value {
    "" -> []
    _ ->
      string.split(value, ",")
      |> list.map(parse_backend_entry)
  }
}

fn parse_backend_entry(entry: String) -> BackendHealth {
  case string.split(entry, "=") {
    [name, "healthy"] -> model.healthy_backend(name, 100)
    [name, "unhealthy"] -> model.unhealthy_backend(name, 1)
    [name] -> model.healthy_backend(name, 100)
    _ -> model.healthy_backend("unknown", 0)
  }
}

fn aggregate_summary(status: AggregateStatus) -> String {
  case status {
    AllHealthy -> "all_healthy"
    Degraded(h, t) -> "degraded " <> int.to_string(h) <> "/" <> int.to_string(t)
    AllUnhealthy -> "all_unhealthy"
  }
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("aggregate_health", aggregate_health)
  |> ngx.merge("readiness_gate", readiness_gate)
  |> ngx.merge("custom_health", custom_health)
}

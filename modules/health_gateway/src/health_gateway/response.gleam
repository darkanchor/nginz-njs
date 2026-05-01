//// Health response rendering. Produces JSON health check responses
//// combining native healthcheck data with scripted aggregation.

import gleam/int
import gleam/list
import gleam/string
import health_gateway/model.{
  type AggregateStatus, type BackendHealth, AllHealthy, AllUnhealthy, Degraded,
}

/// JSON response for aggregate health.
pub fn aggregate_json(
  status: AggregateStatus,
  backends: List(BackendHealth),
) -> String {
  let status_str = aggregate_status_string(status)
  let backends_json = backends |> list.map(backend_json) |> string.join(",")
  "{\"status\":\"" <> status_str <> "\",\"backends\":[" <> backends_json <> "]}"
}

/// JSON response for a single backend.
fn backend_json(h: BackendHealth) -> String {
  "{\"name\":\""
  <> h.name
  <> "\",\"healthy\":"
  <> bool_to_string(h.healthy)
  <> ",\"success_rate\":"
  <> int.to_string(h.success_rate)
  <> ",\"consecutive_failures\":"
  <> int.to_string(h.consecutive_failures)
  <> "}"
}

/// JSON response for readiness gate.
pub fn readiness_json(ready: Bool, reason: String) -> String {
  "{\"ready\":" <> bool_to_string(ready) <> ",\"reason\":\"" <> reason <> "\"}"
}

fn aggregate_status_string(s: AggregateStatus) -> String {
  case s {
    AllHealthy -> "healthy"
    Degraded(_, _) -> "degraded"
    AllUnhealthy -> "unhealthy"
  }
}

fn bool_to_string(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}

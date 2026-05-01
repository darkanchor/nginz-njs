//// Health gateway model. Represents backend health state and aggregation
//// decisions for scripted health policy.

import gleam/int
import gleam/list

/// Health status of a single backend.
pub type BackendHealth {
  BackendHealth(
    /// Backend name or identifier.
    name: String,
    /// Whether the backend is healthy.
    healthy: Bool,
    /// Success rate as a percentage (0-100).
    success_rate: Int,
    /// Number of consecutive probe successes.
    consecutive_successes: Int,
    /// Number of consecutive probe failures.
    consecutive_failures: Int,
  )
}

/// Aggregate health across multiple backends.
pub type AggregateStatus {
  /// All backends are healthy.
  AllHealthy
  /// Some backends are degraded but service is available.
  Degraded(healthy_count: Int, total_count: Int)
  /// No backends are healthy.
  AllUnhealthy
}

/// The complete health gate decision.
pub type GateDecision {
  /// Allow the request through.
  Allow
  /// Block with a service unavailable response.
  Block(reason: String)
}

/// Build a healthy backend record.
pub fn healthy_backend(name: String, success_rate: Int) -> BackendHealth {
  BackendHealth(
    name: name,
    healthy: True,
    success_rate: success_rate,
    consecutive_successes: 1,
    consecutive_failures: 0,
  )
}

/// Build an unhealthy backend record.
pub fn unhealthy_backend(name: String, failures: Int) -> BackendHealth {
  BackendHealth(
    name: name,
    healthy: False,
    success_rate: 0,
    consecutive_successes: 0,
    consecutive_failures: failures,
  )
}

/// Aggregate health across a list of backends.
pub fn aggregate(backends: List(BackendHealth)) -> AggregateStatus {
  let total = list.length(backends)
  let healthy = backends |> list.filter(fn(b) { b.healthy }) |> list.length
  case healthy {
    0 -> AllUnhealthy
    _ if healthy == total -> AllHealthy
    _ -> Degraded(healthy_count: healthy, total_count: total)
  }
}

/// Decide whether to allow a request based on aggregate health.
pub fn gate_decision(status: AggregateStatus) -> GateDecision {
  case status {
    AllHealthy -> Allow
    Degraded(_, _) -> Allow
    AllUnhealthy -> Block("All backends are unhealthy")
  }
}

/// Summary string for logging.
pub fn backend_summary(h: BackendHealth) -> String {
  h.name
  <> "="
  <> bool_to_string(h.healthy)
  <> "("
  <> int.to_string(h.success_rate)
  <> "%)"
}

fn bool_to_string(b: Bool) -> String {
  case b {
    True -> "healthy"
    False -> "unhealthy"
  }
}

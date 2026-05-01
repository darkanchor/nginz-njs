//// Readiness gating. Workflow step wrapper that checks backend health
//// before dispatching. Skips upstream when backends are unhealthy.

import health_gateway/model.{type AggregateStatus, gate_decision}

/// Check if the aggregate health status permits dispatching to upstream.
pub fn can_dispatch(status: AggregateStatus) -> Bool {
  case gate_decision(status) {
    model.Allow -> True
    model.Block(_) -> False
  }
}

/// Wrap a value with a health gate: returns the value if dispatch is
/// allowed, or the fallback if backends are unhealthy.
pub fn with_gate(status: AggregateStatus, value: a, fallback: a) -> a {
  case can_dispatch(status) {
    True -> value
    False -> fallback
  }
}

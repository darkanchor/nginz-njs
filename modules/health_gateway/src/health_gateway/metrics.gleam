//// Metrics adapter for health gateway. Emits counters for health check
//// outcomes and gate decisions.

import health_gateway/model.{
  type AggregateStatus, AllHealthy, AllUnhealthy, Degraded,
}
import metrics/helpers
import metrics/line.{type Metric, Tag}

/// Counter for aggregate health check outcomes.
pub fn aggregate_counter(status: AggregateStatus, route: String) -> Metric {
  helpers.increment("health_gateway_aggregate_total", [
    Tag(name: "status", value: aggregate_tag(status)),
    Tag(name: "route", value: route),
  ])
}

/// Counter for gate decisions (allow/block).
pub fn gate_counter(allowed: Bool, route: String) -> Metric {
  helpers.increment("health_gateway_gate_total", [
    Tag(name: "decision", value: case allowed {
      True -> "allow"
      False -> "block"
    }),
    Tag(name: "route", value: route),
  ])
}

fn aggregate_tag(s: AggregateStatus) -> String {
  case s {
    AllHealthy -> "healthy"
    Degraded(_, _) -> "degraded"
    AllUnhealthy -> "unhealthy"
  }
}

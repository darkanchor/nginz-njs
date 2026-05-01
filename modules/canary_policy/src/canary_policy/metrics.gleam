//// Metrics adapter for canary policy. Emits counters for canary vs stable
//// routing decisions to the metrics module.

import canary_policy/model.{
  type CanaryContext, type CanaryDecision, Canary, Stable, Unknown,
}
import metrics/helpers
import metrics/line.{type Metric, Tag}

/// Counter for a canary routing decision.
pub fn decision_counter(ctx: CanaryContext, route: String) -> Metric {
  helpers.increment("canary_decision_total", [
    Tag(name: "decision", value: decision_tag(ctx.decision)),
    Tag(name: "route", value: route),
  ])
}

/// Counter specifically for canary-routed requests.
pub fn canary_counter(route: String) -> Metric {
  helpers.increment("canary_routed_total", [
    Tag(name: "route", value: route),
  ])
}

fn decision_tag(d: CanaryDecision) -> String {
  case d {
    Canary -> "canary"
    Stable -> "stable"
    Unknown -> "unknown"
  }
}

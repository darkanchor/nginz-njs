//// Metrics adapter for rate limit policy decisions. Emits counters and
//// gauges to the metrics module for observability.

import metrics/helpers
import metrics/line.{type Metric, Tag}
import ratelimit_policy/model.{
  type RateLimitContext, type RateLimitResult, Allowed, Denied, Unknown,
}

/// Counter for a rate limit decision.
pub fn decision_counter(ctx: RateLimitContext, route: String) -> Metric {
  helpers.increment("ratelimit_decision_total", [
    Tag(name: "result", value: result_tag(ctx.result)),
    Tag(name: "source", value: ctx.source),
    Tag(name: "route", value: route),
  ])
}

/// Counter for rate-limited (denied) requests only.
pub fn denied_counter(ctx: RateLimitContext, route: String) -> Metric {
  helpers.increment("ratelimit_denied_total", [
    Tag(name: "source", value: ctx.source),
    Tag(name: "route", value: route),
  ])
}

fn result_tag(r: RateLimitResult) -> String {
  case r {
    Allowed -> "allowed"
    Denied -> "denied"
    Unknown -> "unknown"
  }
}

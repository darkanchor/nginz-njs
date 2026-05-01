//// Metrics adapter for circuit breaker policy. Emits counters for circuit
//// state observations and fallback decisions.

import circuit_breaker_policy/model.{
  type CircuitContext, type CircuitState, Closed, HalfOpen, Open, Unknown,
}
import metrics/helpers
import metrics/line.{type Metric, Tag}

/// Counter for observing the current circuit state.
pub fn state_counter(ctx: CircuitContext, route: String) -> Metric {
  helpers.increment("circuit_breaker_state_total", [
    Tag(name: "state", value: state_tag(ctx.state)),
    Tag(name: "route", value: route),
  ])
}

/// Counter for fallback decisions (circuit open → serving fallback).
pub fn fallback_counter(ctx: CircuitContext, route: String) -> Metric {
  helpers.increment("circuit_breaker_fallback_total", [
    Tag(name: "state", value: state_tag(ctx.state)),
    Tag(name: "route", value: route),
  ])
}

fn state_tag(s: CircuitState) -> String {
  case s {
    Closed -> "closed"
    Open -> "open"
    HalfOpen -> "half_open"
    Unknown -> "unknown"
  }
}

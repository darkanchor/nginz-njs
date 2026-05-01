//// Security gateway metrics. Emits counters for security decisions
//// broken down by outcome: auth failures, rate limits, IP blocks, challenges.

import gleam/int
import metrics/helpers
import metrics/line.{type Metric, Tag}
import security_gateway/model.{type SecurityDecision, Allow, Challenge, Deny}

/// Counter for security decisions, tagged by outcome.
pub fn decision_counter(decision: SecurityDecision, route: String) -> Metric {
  helpers.increment("security_gateway_decision_total", [
    Tag(name: "outcome", value: outcome_tag(decision)),
    Tag(name: "route", value: route),
  ])
}

/// Counter for denied requests, tagged by reason.
pub fn denied_counter(status: Int, reason: String, route: String) -> Metric {
  helpers.increment("security_gateway_denied_total", [
    Tag(name: "status", value: int.to_string(status)),
    Tag(name: "reason", value: reason),
    Tag(name: "route", value: route),
  ])
}

/// Counter for challenge requests.
pub fn challenge_counter(challenge_type: String, route: String) -> Metric {
  helpers.increment("security_gateway_challenge_total", [
    Tag(name: "type", value: challenge_type),
    Tag(name: "route", value: route),
  ])
}

fn outcome_tag(d: SecurityDecision) -> String {
  case d {
    Allow -> "allow"
    Deny(_, _) -> "deny"
    Challenge(_, _, _) -> "challenge"
  }
}

//// Transform authz policy decisions into `metrics` instrumentation values.
////
//// These adapter functions map domain-specific outcomes (allow, deny,
//// remote OPA calls) into generic `Metric` values for downstream emission.

import authz/policy.{type Decision, Allow, Deny}
import gleam/string
import metrics/helpers
import metrics/line.{type Metric, Tag}

/// Produce a decision counter for a policy evaluation.
///
/// `policy_name` is a stable label for the rule set being evaluated
/// (e.g. `"api_gateway"`, `"admin_panel"`).
///
pub fn decision(decision: Decision, policy_name: String) -> Metric {
  case decision {
    Allow -> allow_counter(policy_name)
    Deny(status:, reason:) -> deny_counter(policy_name, status, reason)
  }
}

/// Produce an allow counter.
///
pub fn allow_counter(policy_name: String) -> Metric {
  helpers.increment("authz_decision_total", [
    helpers.tag_result("allow"),
    helpers.tag_route(policy_name),
  ])
}

/// Produce a deny counter tagged with status code and reason.
///
pub fn deny_counter(
  policy_name: String,
  status: Int,
  reason: String,
) -> Metric {
  helpers.increment("authz_decision_total", [
    helpers.tag_result("deny"),
    helpers.tag_route(policy_name),
    helpers.tag_status(status),
    Tag(name: "reason", value: string_slice(reason, 64)),
  ])
}

/// Produce a counter for remote OPA call outcomes.
///
/// `endpoint` is a stable label for the OPA endpoint (e.g. `"opa"`,
/// `"cedar"`), not the full URL. `latency_ms` is the observed round-trip
/// time.
///
pub fn opa_call_outcome(
  decision: Decision,
  endpoint: String,
  latency_ms: Int,
) -> #(Metric, Metric) {
  let outcome = case decision {
    Allow ->
      helpers.increment("authz_opa_call_total", [
        helpers.tag_result("allow"),
        helpers.tag_route(endpoint),
      ])
    Deny(status:, reason:) ->
      helpers.increment("authz_opa_call_total", [
        helpers.tag_result("deny"),
        helpers.tag_route(endpoint),
        helpers.tag_status(status),
        Tag(name: "reason", value: string_slice(reason, 64)),
      ])
  }
  let timing =
    helpers.latency("authz_opa_latency_ms", latency_ms, [
      helpers.tag_route(endpoint),
    ])
  #(outcome, timing)
}

fn string_slice(s: String, max: Int) -> String {
  case string.length(s) <= max {
    True -> s
    False -> string.slice(s, 0, max)
  }
}

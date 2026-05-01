import canary_policy/feature_flags.{
  FlagOverride, canary_flag, check_override, stable_flag,
}
import canary_policy/metrics
import canary_policy/model.{
  Canary, CanaryContext, Stable, Unknown, canary_headers, context,
  parse_decision, stable_headers, summary, with_headers,
}
import canary_policy/session
import gleeunit
import gleeunit/should
import metrics/line

pub fn main() {
  gleeunit.main()
}

// --- model tests ---

pub fn parse_decision_canary_test() {
  parse_decision("1") |> should.equal(Canary)
}

pub fn parse_decision_stable_test() {
  parse_decision("0") |> should.equal(Stable)
}

pub fn parse_decision_unknown_test() {
  parse_decision("") |> should.equal(Unknown)
  parse_decision("something") |> should.equal(Unknown)
}

pub fn context_from_canary_test() {
  let ctx = context("1")
  ctx.decision |> should.equal(Canary)
  ctx.extra_headers |> should.equal([])
}

pub fn context_from_stable_test() {
  let ctx = context("0")
  ctx.decision |> should.equal(Stable)
}

pub fn with_headers_test() {
  let ctx = context("1") |> with_headers([#("X-Custom", "value")])
  ctx.extra_headers |> should.equal([#("X-Custom", "value")])
}

pub fn canary_headers_test() {
  canary_headers() |> should.equal([#("X-Canary", "true")])
}

pub fn stable_headers_test() {
  stable_headers() |> should.equal([#("X-Canary", "false")])
}

pub fn summary_canary_test() {
  context("1") |> summary |> should.equal("canary=true")
}

pub fn summary_stable_test() {
  context("0") |> summary |> should.equal("canary=false")
}

// --- feature_flags tests ---

pub fn check_override_canary_match_test() {
  let ctx = context("1")
  let overrides = [
    canary_flag("new_ui", "true"),
    stable_flag("new_ui", "false"),
  ]
  check_override(ctx, overrides)
  |> should.equal(Ok(canary_flag("new_ui", "true")))
}

pub fn check_override_stable_match_test() {
  let ctx = context("0")
  let overrides = [
    canary_flag("new_ui", "true"),
    stable_flag("new_ui", "false"),
  ]
  check_override(ctx, overrides)
  |> should.equal(Ok(stable_flag("new_ui", "false")))
}

pub fn check_override_no_match_test() {
  let ctx = context("0")
  let overrides = [canary_flag("new_ui", "true")]
  check_override(ctx, overrides)
  |> should.equal(Error(Nil))
}

pub fn check_override_empty_test() {
  let ctx = context("1")
  check_override(ctx, [])
  |> should.equal(Error(Nil))
}

// --- session tests ---

pub fn resolve_sticky_stored_canary_test() {
  let ctx = context("0")
  session.resolve_sticky(ctx, Ok("canary"))
  |> should.equal(Canary)
}

pub fn resolve_sticky_stored_stable_test() {
  let ctx = context("1")
  session.resolve_sticky(ctx, Ok("stable"))
  |> should.equal(Stable)
}

pub fn resolve_sticky_no_session_test() {
  let ctx = context("1")
  session.resolve_sticky(ctx, Error(Nil))
  |> should.equal(Canary)
}

pub fn serialize_canary_test() {
  session.serialize_decision(Canary) |> should.equal("canary")
}

pub fn serialize_stable_test() {
  session.serialize_decision(Stable) |> should.equal("stable")
}

pub fn deserialize_canary_test() {
  session.deserialize_decision("canary") |> should.equal(Canary)
}

pub fn deserialize_stable_test() {
  session.deserialize_decision("stable") |> should.equal(Stable)
}

pub fn deserialize_unknown_test() {
  session.deserialize_decision("something") |> should.equal(Stable)
}

// --- metrics tests ---

pub fn decision_counter_canary_test() {
  let ctx = context("1")
  let m = metrics.decision_counter(ctx, "/api")
  line.render_statsd(m)
  |> should.equal("nginz.canary_decision_total:1|c|#decision:canary,route:/api")
}

pub fn decision_counter_stable_test() {
  let ctx = context("0")
  let m = metrics.decision_counter(ctx, "/api")
  line.render_statsd(m)
  |> should.equal("nginz.canary_decision_total:1|c|#decision:stable,route:/api")
}

pub fn canary_counter_test() {
  let m = metrics.canary_counter("/api")
  line.render_statsd(m)
  |> should.equal("nginz.canary_routed_total:1|c|#route:/api")
}

import circuit_breaker_policy/fallback
import circuit_breaker_policy/metrics
import circuit_breaker_policy/model.{
  Closed, HalfOpen, Open, Unknown, context, default_fallback, parse_state,
  summary,
}
import gleam/string
import gleeunit
import gleeunit/should
import metrics/line

pub fn main() {
  gleeunit.main()
}

// --- model tests ---

pub fn parse_state_closed_test() {
  parse_state("closed") |> should.equal(Closed)
}

pub fn parse_state_open_test() {
  parse_state("open") |> should.equal(Open)
}

pub fn parse_state_half_open_test() {
  parse_state("half_open") |> should.equal(HalfOpen)
}

pub fn parse_state_unknown_test() {
  parse_state("") |> should.equal(Unknown)
  parse_state("something") |> should.equal(Unknown)
}

pub fn context_from_closed_test() {
  let ctx = context("closed")
  ctx.state |> should.equal(Closed)
  ctx.raw_state |> should.equal("closed")
}

pub fn context_from_open_test() {
  let ctx = context("open")
  ctx.state |> should.equal(Open)
}

pub fn default_fallback_test() {
  let cfg = default_fallback()
  cfg.status |> should.equal(503)
  cfg.content_type |> should.equal("application/json")
  cfg.log_fallback |> should.equal(True)
}

pub fn summary_closed_test() {
  context("closed") |> summary |> should.equal("circuit=closed")
}

pub fn summary_open_test() {
  context("open") |> summary |> should.equal("circuit=open")
}

pub fn summary_half_open_test() {
  context("half_open") |> summary |> should.equal("circuit=half_open")
}

// --- fallback tests ---

pub fn json_error_test() {
  let body = fallback.json_error("service down")
  string.contains(body, "\"error\":\"service_unavailable\"")
  |> should.equal(True)
  string.contains(body, "\"circuit\":\"open\"") |> should.equal(True)
  string.contains(body, "service down") |> should.equal(True)
}

pub fn json_degraded_test() {
  let body = fallback.json_degraded("recovering")
  string.contains(body, "\"error\":\"service_degraded\"") |> should.equal(True)
  string.contains(body, "\"circuit\":\"half_open\"") |> should.equal(True)
}

pub fn html_error_test() {
  let body = fallback.html_error("maintenance")
  string.contains(body, "503 Service Unavailable") |> should.equal(True)
  string.contains(body, "maintenance") |> should.equal(True)
}

pub fn text_error_test() {
  fallback.text_error("down")
  |> should.equal("503 Service Unavailable: down\n")
}

pub fn auto_body_open_test() {
  let ctx = context("open")
  let #(status, ct, body) = fallback.auto_body(ctx, "down")
  status |> should.equal(503)
  ct |> should.equal("application/json")
  string.contains(body, "\"circuit\":\"open\"") |> should.equal(True)
}

pub fn auto_body_half_open_test() {
  let ctx = context("half_open")
  let #(status, ct, body) = fallback.auto_body(ctx, "recovering")
  status |> should.equal(503)
  ct |> should.equal("application/json")
  string.contains(body, "\"circuit\":\"half_open\"") |> should.equal(True)
}

pub fn auto_body_closed_test() {
  let ctx = context("closed")
  let #(status, _, _) = fallback.auto_body(ctx, "ok")
  status |> should.equal(200)
}

// --- metrics tests ---

pub fn state_counter_closed_test() {
  let ctx = context("closed")
  let m = metrics.state_counter(ctx, "/api")
  line.render_statsd(m)
  |> should.equal(
    "nginz.circuit_breaker_state_total:1|c|#state:closed,route:/api",
  )
}

pub fn state_counter_open_test() {
  let ctx = context("open")
  let m = metrics.state_counter(ctx, "/api")
  line.render_statsd(m)
  |> should.equal(
    "nginz.circuit_breaker_state_total:1|c|#state:open,route:/api",
  )
}

pub fn fallback_counter_test() {
  let ctx = context("open")
  let m = metrics.fallback_counter(ctx, "/api")
  line.render_statsd(m)
  |> should.equal(
    "nginz.circuit_breaker_fallback_total:1|c|#state:open,route:/api",
  )
}

import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import metrics/line
import ratelimit_policy/headers
import ratelimit_policy/metrics
import ratelimit_policy/model.{Allowed, Denied, RateLimitHeaders, Unknown}
import ratelimit_policy/response

pub fn main() {
  gleeunit.main()
}

// --- model tests ---

pub fn parse_result_allowed_test() {
  model.parse_result("allow") |> should.equal(Allowed)
}

pub fn parse_result_denied_test() {
  model.parse_result("deny") |> should.equal(Denied)
}

pub fn parse_result_unknown_test() {
  model.parse_result("") |> should.equal(Unknown)
  model.parse_result("something_else") |> should.equal(Unknown)
}

pub fn context_from_strings_test() {
  let ctx = model.context("deny", "192.168.1.1", "ip", "3")
  ctx.result |> should.equal(Denied)
  ctx.key |> should.equal("192.168.1.1")
  ctx.source |> should.equal("ip")
  ctx.cost |> should.equal(3)
}

pub fn context_default_cost_test() {
  let ctx = model.context("allow", "key", "variable", "not_a_number")
  ctx.cost |> should.equal(1)
}

pub fn deny_headers_test() {
  let hdrs = model.deny_headers(60)
  hdrs.remaining |> should.equal(Some("0"))
  hdrs.reset |> should.equal(Some("60"))
  hdrs.retry_after |> should.equal(Some("60"))
  hdrs.limit |> should.equal(None)
}

pub fn allow_headers_test() {
  let hdrs = model.allow_headers(100, 75, 30)
  hdrs.limit |> should.equal(Some("100"))
  hdrs.remaining |> should.equal(Some("75"))
  hdrs.reset |> should.equal(Some("30"))
  hdrs.retry_after |> should.equal(None)
}

pub fn default_error_body_test() {
  let body = model.default_error_body("too fast")
  body |> should.equal("{\"error\":\"rate_limited\",\"message\":\"too fast\"}")
}

pub fn summary_test() {
  let ctx = model.context("deny", "10.0.0.1", "ip", "2")
  model.summary(ctx)
  |> should.equal("key=10.0.0.1 source=ip cost=2 result=deny")
}

// --- headers tests ---

pub fn render_all_denied_test() {
  let hdrs = model.deny_headers(60)
  let pairs = headers.render_all(hdrs)
  pairs
  |> should.equal([
    #("X-RateLimit-Remaining", "0"),
    #("X-RateLimit-Reset", "60"),
    #("Retry-After", "60"),
  ])
}

pub fn render_all_allowed_test() {
  let hdrs = model.allow_headers(100, 99, 60)
  let pairs = headers.render_all(hdrs)
  pairs
  |> should.equal([
    #("X-RateLimit-Limit", "100"),
    #("X-RateLimit-Remaining", "99"),
    #("X-RateLimit-Reset", "60"),
  ])
}

pub fn render_all_empty_test() {
  let hdrs =
    RateLimitHeaders(
      limit: None,
      remaining: None,
      reset: None,
      retry_after: None,
    )
  headers.render_all(hdrs) |> should.equal([])
}

// --- response tests ---

pub fn json_error_test() {
  let body = response.json_error("slow down", 30)
  body
  |> should.equal(
    "{\"error\":\"too_many_requests\",\"message\":\"slow down\",\"retry_after\":30}",
  )
}

pub fn html_error_test() {
  let body = response.html_error("slow down", 30)
  string.contains(body, "429 Too Many Requests") |> should.equal(True)
  string.contains(body, "slow down") |> should.equal(True)
  string.contains(body, "30 seconds") |> should.equal(True)
}

pub fn text_error_test() {
  response.text_error("too fast")
  |> should.equal("429 Too Many Requests: too fast\n")
}

// --- metrics tests ---

pub fn decision_counter_allowed_test() {
  let ctx = model.context("allow", "key", "ip", "1")
  let m = metrics.decision_counter(ctx, "/api")
  line.render_statsd(m)
  |> should.equal(
    "nginz.ratelimit_decision_total:1|c|#result:allow,source:ip,route:/api",
  )
}

pub fn decision_counter_denied_test() {
  let ctx = model.context("deny", "key", "variable", "1")
  let m = metrics.decision_counter(ctx, "/api")
  line.render_statsd(m)
  |> should.equal(
    "nginz.ratelimit_decision_total:1|c|#result:deny,source:variable,route:/api",
  )
}

pub fn denied_counter_test() {
  let ctx = model.context("deny", "key", "ip", "1")
  let m = metrics.denied_counter(ctx, "/api")
  line.render_statsd(m)
  |> should.equal("nginz.ratelimit_denied_total:1|c|#source:ip,route:/api")
}

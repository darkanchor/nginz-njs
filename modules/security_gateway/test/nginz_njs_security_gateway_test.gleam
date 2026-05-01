import gleam/string
import gleeunit
import gleeunit/should
import metrics/line
import security_gateway/challenge
import security_gateway/evaluate
import security_gateway/metrics
import security_gateway/model.{
  Allow, Challenge, Deny, decision_summary, ip_reputation, jwt_anonymous,
  jwt_authenticated, oidc_anonymous, oidc_identity, rate_limit, signal_summary,
}
import security_gateway/response

pub fn main() {
  gleeunit.main()
}

// --- model tests ---

pub fn signal_constructors_test() {
  jwt_authenticated([#("sub", "user-1")])
  |> signal_summary
  |> should.equal("jwt:authenticated")

  jwt_anonymous() |> signal_summary |> should.equal("jwt:anonymous")

  oidc_identity("sub-1", "a@b.com", "Alice")
  |> signal_summary
  |> string.starts_with("oidc:sub-1")
  |> should.equal(True)

  oidc_anonymous() |> signal_summary |> should.equal("oidc:anonymous")

  rate_limit(True, "key-1", "ip")
  |> signal_summary
  |> should.equal("ratelimit:allowed")

  rate_limit(False, "key-1", "ip")
  |> signal_summary
  |> should.equal("ratelimit:denied")

  ip_reputation(True, "blocklist")
  |> signal_summary
  |> should.equal("ip:matched")

  ip_reputation(False, "")
  |> signal_summary
  |> should.equal("ip:clean")
}

pub fn decision_summary_test() {
  decision_summary(Allow) |> should.equal("allow")
  decision_summary(Deny(403, "forbidden")) |> should.equal("deny 403 forbidden")
  decision_summary(Challenge(401, "auth", "login"))
  |> should.equal("challenge 401 login auth")
}

// --- evaluate tests ---

pub fn evaluate_allow_test() {
  let signals = [jwt_authenticated([#("sub", "u1")])]
  let rules = [evaluate.require_jwt()]
  evaluate.evaluate(signals, rules) |> should.equal(Allow)
}

pub fn evaluate_deny_jwt_test() {
  let signals = [jwt_anonymous()]
  let rules = [evaluate.require_jwt()]
  evaluate.evaluate(signals, rules) |> should.equal(Deny(401, "jwt required"))
}

pub fn evaluate_deny_rate_limit_test() {
  let signals = [
    jwt_authenticated([#("sub", "u1")]),
    rate_limit(False, "k", "ip"),
  ]
  let rules = [evaluate.deny_if_rate_limited(), evaluate.require_jwt()]
  let result = evaluate.evaluate(signals, rules)
  result |> should.equal(Deny(429, "rate limited"))
}

pub fn evaluate_any_auth_jwt_test() {
  let signals = [jwt_authenticated([#("sub", "u1")])]
  let rules = [evaluate.require_any_auth()]
  evaluate.evaluate(signals, rules) |> should.equal(Allow)
}

pub fn evaluate_any_auth_oidc_test() {
  let signals = [oidc_identity("sub-1", "a@b.com", "A")]
  let rules = [evaluate.require_any_auth()]
  evaluate.evaluate(signals, rules) |> should.equal(Allow)
}

pub fn evaluate_any_auth_deny_test() {
  let signals = [jwt_anonymous(), oidc_anonymous()]
  let rules = [evaluate.require_any_auth()]
  evaluate.evaluate(signals, rules)
  |> should.equal(Deny(401, "authentication required"))
}

pub fn evaluate_all_of_test() {
  let policy =
    evaluate.all_of([
      evaluate.deny_if_rate_limited(),
      evaluate.require_jwt(),
    ])
  let signals = [jwt_authenticated([#("sub", "u1")])]
  evaluate.evaluate(signals, [policy]) |> should.equal(Allow)
}

pub fn evaluate_any_of_test() {
  let policy =
    evaluate.any_of([
      evaluate.require_jwt(),
      evaluate.require_oidc(),
    ])
  let signals = [oidc_identity("sub-1", "a@b.com", "A")]
  evaluate.evaluate(signals, [policy]) |> should.equal(Allow)
}

pub fn evaluate_not_test() {
  let rule = evaluate.not_(evaluate.require_jwt())
  let signals = [jwt_anonymous()]
  evaluate.evaluate(signals, [rule]) |> should.equal(Allow)
}

pub fn evaluate_challenge_test() {
  let signals = [jwt_anonymous()]
  let rules = [evaluate.challenge_if_anonymous()]
  evaluate.evaluate(signals, rules)
  |> should.equal(Challenge(401, "authentication required", "login_redirect"))
}

// --- challenge tests ---

pub fn login_redirect_test() {
  let body = challenge.login_redirect("/login")
  string.contains(body, "/login") |> should.equal(True)
  string.contains(body, "text/html") |> should.equal(False)
}

pub fn json_challenge_test() {
  let body = challenge.json_challenge(401, "auth required", "login")
  string.contains(body, "\"type\":\"login\"") |> should.equal(True)
  string.contains(body, "\"status\":401") |> should.equal(True)
}

// --- response tests ---

pub fn json_401_test() {
  let body = response.json_401("no jwt")
  string.contains(body, "\"error\":\"unauthorized\"") |> should.equal(True)
  string.contains(body, "\"status\":401") |> should.equal(True)
}

pub fn json_403_test() {
  let body = response.json_403("blocked")
  string.contains(body, "\"error\":\"forbidden\"") |> should.equal(True)
}

pub fn json_429_test() {
  let body = response.json_429("rate limited", 60)
  string.contains(body, "\"error\":\"too_many_requests\"") |> should.equal(True)
  string.contains(body, "\"retry_after\":60") |> should.equal(True)
}

// --- metrics tests ---

pub fn decision_counter_allow_test() {
  let m = metrics.decision_counter(Allow, "/api")
  line.render_statsd(m)
  |> should.equal(
    "nginz.security_gateway_decision_total:1|c|#outcome:allow,route:/api",
  )
}

pub fn decision_counter_deny_test() {
  let m = metrics.decision_counter(Deny(403, "blocked"), "/api")
  line.render_statsd(m)
  |> should.equal(
    "nginz.security_gateway_decision_total:1|c|#outcome:deny,route:/api",
  )
}

pub fn challenge_counter_test() {
  let m = metrics.challenge_counter("login", "/api")
  line.render_statsd(m)
  |> should.equal(
    "nginz.security_gateway_challenge_total:1|c|#type:login,route:/api",
  )
}

import gleeunit
import gleeunit/should
import metrics/line
import session/cookie
import session/metrics
import session/model.{
  CookieConfig, RotateNegative, SessionDescriptor, TtlNotPositive,
}

pub fn main() {
  gleeunit.main()
}

// --- model: summary ---

pub fn default_descriptor_summary_test() {
  model.default_descriptor()
  |> model.summary
  |> should.equal("sid backend=shared_dict ttl=3600 rotate=0 same_site=Lax")
}

pub fn summary_with_rotate_test() {
  SessionDescriptor(
    ..model.default_descriptor(),
    ttl_seconds: 1800,
    rotate_after_seconds: 900,
  )
  |> model.summary
  |> should.equal("sid backend=shared_dict ttl=1800 rotate=900 same_site=Lax")
}

// --- model: validate ---

pub fn validate_default_test() {
  model.default_descriptor()
  |> model.validate
  |> should.be_ok
}

pub fn validate_ttl_zero_test() {
  SessionDescriptor(..model.default_descriptor(), ttl_seconds: 0)
  |> model.validate
  |> should.equal(Error(TtlNotPositive))
}

pub fn validate_ttl_negative_test() {
  SessionDescriptor(..model.default_descriptor(), ttl_seconds: -1)
  |> model.validate
  |> should.equal(Error(TtlNotPositive))
}

pub fn validate_rotate_negative_test() {
  SessionDescriptor(..model.default_descriptor(), rotate_after_seconds: -1)
  |> model.validate
  |> should.equal(Error(RotateNegative))
}

pub fn validate_rotate_zero_ok_test() {
  SessionDescriptor(..model.default_descriptor(), rotate_after_seconds: 0)
  |> model.validate
  |> should.be_ok
}

pub fn validate_ttl_checked_first_test() {
  SessionDescriptor(
    ..model.default_descriptor(),
    ttl_seconds: 0,
    rotate_after_seconds: -1,
  )
  |> model.validate
  |> should.equal(Error(TtlNotPositive))
}

// --- cookie: set_header ---

pub fn cookie_set_header_http_only_test() {
  let cfg = model.default_descriptor().cookie
  cookie.set_header(cfg, "abc123", 3600)
  |> should.equal("sid=abc123; Max-Age=3600; Path=/; SameSite=Lax; HttpOnly")
}

pub fn cookie_set_header_secure_test() {
  let cfg =
    CookieConfig(
      name: "sid",
      http_only: False,
      secure: True,
      path: "/app",
      same_site: "Strict",
    )
  cookie.set_header(cfg, "xyz", 600)
  |> should.equal("sid=xyz; Max-Age=600; Path=/app; SameSite=Strict; Secure")
}

pub fn cookie_set_header_both_flags_test() {
  let cfg =
    CookieConfig(
      name: "sess",
      http_only: True,
      secure: True,
      path: "/",
      same_site: "None",
    )
  cookie.set_header(cfg, "tok", 7200)
  |> should.equal(
    "sess=tok; Max-Age=7200; Path=/; SameSite=None; HttpOnly; Secure",
  )
}

// --- cookie: clear_header ---

pub fn cookie_clear_header_test() {
  let cfg = model.default_descriptor().cookie
  cookie.clear_header(cfg)
  |> should.equal("sid=; Max-Age=0; Path=/")
}

// --- cookie: read_id ---

pub fn cookie_read_id_found_test() {
  cookie.read_id("sid=abc123; other=val", "sid")
  |> should.equal(Ok("abc123"))
}

pub fn cookie_read_id_second_cookie_test() {
  cookie.read_id("first=a; sid=secret; last=z", "sid")
  |> should.equal(Ok("secret"))
}

pub fn cookie_read_id_missing_test() {
  cookie.read_id("other=val; another=x", "sid")
  |> should.equal(Error(Nil))
}

pub fn cookie_read_id_empty_header_test() {
  cookie.read_id("", "sid")
  |> should.equal(Error(Nil))
}

// --- Metrics adapter ---

pub fn metrics_start_test() {
  line.render_statsd(metrics.start())
  |> should.equal(
    "nginz.session_lifecycle_total:1|c|#operation:start,result:success",
  )
}

pub fn metrics_verify_success_test() {
  line.render_statsd(metrics.verify(True))
  |> should.equal(
    "nginz.session_lifecycle_total:1|c|#operation:verify,result:success",
  )
}

pub fn metrics_verify_failure_test() {
  line.render_statsd(metrics.verify(False))
  |> should.equal(
    "nginz.session_lifecycle_total:1|c|#operation:verify,result:failure",
  )
}

pub fn metrics_end_session_test() {
  line.render_statsd(metrics.end_session())
  |> should.equal(
    "nginz.session_lifecycle_total:1|c|#operation:end,result:success",
  )
}

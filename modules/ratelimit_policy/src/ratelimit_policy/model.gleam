//// Rate-limit policy model. Reads the native ratelimit module's decision
//// context and maps it to scripted policy decisions with response shaping.

import gleam/int
import gleam/option.{type Option, None, Some}

/// The native ratelimit module's decision for this request.
pub type RateLimitResult {
  Allowed
  Denied
  /// Variable was missing or empty — ratelimit module may not be configured.
  Unknown
}

/// Context read from native ratelimit nginx variables.
pub type RateLimitContext {
  RateLimitContext(
    result: RateLimitResult,
    key: String,
    source: String,
    cost: Int,
  )
}

/// What the scripted policy decides to do with the rate limit outcome.
pub type PolicyDecision {
  /// Pass through — no rate limit headers injected.
  PassThrough
  /// Inject rate limit headers and continue.
  InjectHeaders(headers: RateLimitHeaders)
  /// Deny with a custom response.
  DenyWith(status: Int, body: String, content_type: String)
}

/// Standard rate limit response headers.
pub type RateLimitHeaders {
  RateLimitHeaders(
    limit: Option(String),
    remaining: Option(String),
    reset: Option(String),
    retry_after: Option(String),
  )
}

/// Parse a rate limit result string from the native module.
pub fn parse_result(value: String) -> RateLimitResult {
  case value {
    "allowed" -> Allowed
    "denied" -> Denied
    _ -> Unknown
  }
}

/// Build a context from raw nginx variable values.
pub fn context(
  result: String,
  key: String,
  source: String,
  cost: String,
) -> RateLimitContext {
  RateLimitContext(
    result: parse_result(result),
    key: key,
    source: source,
    cost: case int.parse(cost) {
      Ok(n) -> n
      Error(_) -> 1
    },
  )
}

/// Build headers for a denied request with retry-after information.
pub fn deny_headers(retry_after_seconds: Int) -> RateLimitHeaders {
  RateLimitHeaders(
    limit: None,
    remaining: Some("0"),
    reset: Some(int.to_string(retry_after_seconds)),
    retry_after: Some(int.to_string(retry_after_seconds)),
  )
}

/// Build headers for an allowed request showing quota information.
pub fn allow_headers(
  limit: Int,
  remaining: Int,
  reset_seconds: Int,
) -> RateLimitHeaders {
  RateLimitHeaders(
    limit: Some(int.to_string(limit)),
    remaining: Some(int.to_string(remaining)),
    reset: Some(int.to_string(reset_seconds)),
    retry_after: None,
  )
}

/// Default JSON error body for 429 responses.
pub fn default_error_body(reason: String) -> String {
  "{\"error\":\"rate_limited\",\"message\":\"" <> reason <> "\"}"
}

/// Summary string for logging.
pub fn summary(ctx: RateLimitContext) -> String {
  "key="
  <> ctx.key
  <> " source="
  <> ctx.source
  <> " cost="
  <> int.to_string(ctx.cost)
  <> " result="
  <> result_to_string(ctx.result)
}

fn result_to_string(r: RateLimitResult) -> String {
  case r {
    Allowed -> "allowed"
    Denied -> "denied"
    Unknown -> "unknown"
  }
}

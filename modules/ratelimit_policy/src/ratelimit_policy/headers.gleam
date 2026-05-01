//// Rate limit header construction. Builds standard HTTP rate limit headers
//// (X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Reset, Retry-After)
//// from policy decisions.

import gleam/option.{type Option, None, Some}
import ratelimit_policy/model.{type RateLimitHeaders}

/// Render a single header pair if the value is present.
pub fn render_header(
  name: String,
  value: Option(String),
) -> Option(#(String, String)) {
  case value {
    Some(v) -> Some(#(name, v))
    None -> None
  }
}

/// Render all rate limit headers as a list of name-value pairs.
/// Only present headers are included.
pub fn render_all(headers: RateLimitHeaders) -> List(#(String, String)) {
  [
    render_header("X-RateLimit-Limit", headers.limit),
    render_header("X-RateLimit-Remaining", headers.remaining),
    render_header("X-RateLimit-Reset", headers.reset),
    render_header("Retry-After", headers.retry_after),
  ]
  |> option_values
}

fn option_values(items: List(Option(a))) -> List(a) {
  case items {
    [] -> []
    [Some(v), ..rest] -> [v, ..option_values(rest)]
    [None, ..rest] -> option_values(rest)
  }
}

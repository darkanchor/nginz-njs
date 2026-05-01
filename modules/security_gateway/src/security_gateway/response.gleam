//// Error response rendering. Produces custom error bodies per denial reason
//// — 401 (unauthenticated), 403 (forbidden), 429 (rate limited).

import gleam/int

/// JSON error body for a 401 Unauthorized response.
pub fn json_401(reason: String) -> String {
  "{\"error\":\"unauthorized\",\"status\":401,\"reason\":\"" <> reason <> "\"}"
}

/// JSON error body for a 403 Forbidden response.
pub fn json_403(reason: String) -> String {
  "{\"error\":\"forbidden\",\"status\":403,\"reason\":\"" <> reason <> "\"}"
}

/// JSON error body for a 429 Too Many Requests response.
pub fn json_429(reason: String, retry_after: Int) -> String {
  "{\"error\":\"too_many_requests\",\"status\":429,\"reason\":\""
  <> reason
  <> "\",\"retry_after\":"
  <> int.to_string(retry_after)
  <> "}"
}

/// Plain text error body.
pub fn text_error(status: Int, reason: String) -> String {
  "HTTP " <> int.to_string(status) <> " " <> reason
}

//// Response body rendering for rate-limited requests. Produces JSON or
//// HTML error bodies for 429 responses.

import gleam/int

/// JSON error body for a rate-limited request.
pub fn json_error(message: String, retry_after: Int) -> String {
  "{\"error\":\"too_many_requests\","
  <> "\"message\":\""
  <> message
  <> "\","
  <> "\"retry_after\":"
  <> int.to_string(retry_after)
  <> "}"
}

/// HTML error body for a rate-limited request.
pub fn html_error(message: String, retry_after: Int) -> String {
  "<!DOCTYPE html><html><head><title>429 Too Many Requests</title></head>"
  <> "<body><h1>429 Too Many Requests</h1><p>"
  <> message
  <> "</p><p>Retry after "
  <> int.to_string(retry_after)
  <> " seconds.</p></body></html>"
}

/// Minimal plain text error body.
pub fn text_error(message: String) -> String {
  "429 Too Many Requests: " <> message <> "\n"
}

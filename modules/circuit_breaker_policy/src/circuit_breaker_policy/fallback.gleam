//// Fallback response rendering for circuit breaker policy. Produces JSON
//// error bodies when the circuit is open.

import circuit_breaker_policy/model.{
  type CircuitContext, Closed, HalfOpen, Open, Unknown,
}

/// JSON error body for an open circuit.
pub fn json_error(message: String) -> String {
  "{\"error\":\"service_unavailable\","
  <> "\"message\":\""
  <> message
  <> "\","
  <> "\"circuit\":\"open\"}"
}

/// JSON error body for half-open state (degraded).
pub fn json_degraded(message: String) -> String {
  "{\"error\":\"service_degraded\","
  <> "\"message\":\""
  <> message
  <> "\","
  <> "\"circuit\":\"half_open\"}"
}

/// HTML error page for open circuit.
pub fn html_error(message: String) -> String {
  "<!DOCTYPE html><html><head><title>503 Service Unavailable</title></head>"
  <> "<body><h1>503 Service Unavailable</h1><p>"
  <> message
  <> "</p><p>The service is temporarily unavailable. Please retry later.</p>"
  <> "</body></html>"
}

/// Minimal plain text error.
pub fn text_error(message: String) -> String {
  "503 Service Unavailable: " <> message <> "\n"
}

/// Choose the appropriate fallback body based on circuit state.
pub fn auto_body(
  ctx: CircuitContext,
  message: String,
) -> #(Int, String, String) {
  case ctx.state {
    Open -> #(503, "application/json", json_error(message))
    HalfOpen -> #(503, "application/json", json_degraded(message))
    Closed -> #(200, "", "")
    Unknown -> #(200, "", "")
  }
}

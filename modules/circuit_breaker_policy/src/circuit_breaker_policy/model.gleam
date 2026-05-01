//// Circuit breaker policy model. Reads the native circuit-breaker module's
//// state and maps it to scripted policy decisions for fallback, error
//// responses, and observability.

/// The native circuit-breaker module's state.
pub type CircuitState {
  /// Normal operation — requests pass through.
  Closed
  /// Circuit tripped — requests should be blocked or served fallback.
  Open
  /// Testing recovery — limited requests allowed through.
  HalfOpen
  /// Variable was missing — circuit-breaker module may not be configured.
  Unknown
}

/// Context read from native circuit-breaker nginx variables.
pub type CircuitContext {
  CircuitContext(
    state: CircuitState,
    /// Raw state string for logging.
    raw_state: String,
  )
}

/// What the scripted policy decides to do with the circuit state.
pub type PolicyDecision {
  /// Pass request through to upstream.
  PassThrough
  /// Serve a fallback response.
  ServeFallback(status: Int, body: String, content_type: String)
  /// Block with an error response.
  Block(status: Int, body: String, content_type: String)
}

/// Fallback configuration for open circuit.
pub type FallbackConfig {
  FallbackConfig(
    /// HTTP status code for fallback responses.
    status: Int,
    /// Content type for fallback body.
    content_type: String,
    /// Whether to log fallback decisions.
    log_fallback: Bool,
  )
}

/// Parse the `$ngz_circuit_state` variable value.
pub fn parse_state(value: String) -> CircuitState {
  case value {
    "closed" -> Closed
    "open" -> Open
    "half_open" -> HalfOpen
    _ -> Unknown
  }
}

/// Build a context from the raw nginx variable value.
pub fn context(raw_state: String) -> CircuitContext {
  CircuitContext(state: parse_state(raw_state), raw_state: raw_state)
}

/// Default fallback configuration.
pub fn default_fallback() -> FallbackConfig {
  FallbackConfig(
    status: 503,
    content_type: "application/json",
    log_fallback: True,
  )
}

/// Summary string for logging.
pub fn summary(ctx: CircuitContext) -> String {
  "circuit=" <> state_to_string(ctx.state)
}

fn state_to_string(s: CircuitState) -> String {
  case s {
    Closed -> "closed"
    Open -> "open"
    HalfOpen -> "half_open"
    Unknown -> "unknown"
  }
}

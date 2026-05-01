//// Canary policy model. Reads the native canary module's decision and
//// maps it to scripted policy decisions for header injection, routing,
//// and observability.

/// The native canary module's routing decision.
pub type CanaryDecision {
  /// Request is routed to the canary deployment.
  Canary
  /// Request is routed to the stable deployment.
  Stable
  /// Variable was missing — canary module may not be configured.
  Unknown
}

/// Context read from native canary nginx variables.
pub type CanaryContext {
  CanaryContext(
    decision: CanaryDecision,
    /// Additional headers to inject into the upstream request.
    extra_headers: List(#(String, String)),
  )
}

/// What the scripted policy decides to do with the canary outcome.
pub type PolicyAction {
  /// Pass through with injected headers.
  Route(headers: List(#(String, String)))
  /// Override the canary decision (e.g., force stable for certain users).
  Override(decision: CanaryDecision, reason: String)
}

/// Parse the `$ngz_canary` variable value.
pub fn parse_decision(value: String) -> CanaryDecision {
  case value {
    "1" -> Canary
    "0" -> Stable
    _ -> Unknown
  }
}

/// Build a context from the raw nginx variable value.
pub fn context(canary_value: String) -> CanaryContext {
  CanaryContext(decision: parse_decision(canary_value), extra_headers: [])
}

/// Add headers to a canary context.
pub fn with_headers(
  ctx: CanaryContext,
  headers: List(#(String, String)),
) -> CanaryContext {
  CanaryContext(..ctx, extra_headers: headers)
}

/// Default headers for canary requests.
pub fn canary_headers() -> List(#(String, String)) {
  [#("X-Canary", "true")]
}

/// Default headers for stable requests.
pub fn stable_headers() -> List(#(String, String)) {
  [#("X-Canary", "false")]
}

/// Summary string for logging.
pub fn summary(ctx: CanaryContext) -> String {
  "canary=" <> decision_to_string(ctx.decision)
}

fn decision_to_string(d: CanaryDecision) -> String {
  case d {
    Canary -> "true"
    Stable -> "false"
    Unknown -> "unknown"
  }
}

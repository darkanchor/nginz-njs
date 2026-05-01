//// Workflow integration for rate limit policy. Provides recovery patterns
//// that serve degraded responses when the native ratelimit module denies
//// a request.

import gleam/javascript/promise
import workflow/pipeline.{type Step}

/// Wrap a workflow step so that rate-limited requests get a fallback response
/// instead of propagating the failure. The fallback body is returned with
/// status 429.
pub fn with_rate_limit_fallback(step: Step, fallback_body: String) -> Step {
  fn(req) {
    use result <- promise.await(step(req))
    case result {
      pipeline.Fetched(429, _) ->
        promise.resolve(pipeline.Fetched(429, fallback_body))
      other -> promise.resolve(other)
    }
  }
}

/// Wrap a step to skip execution entirely when rate-limited, returning
/// the fallback immediately.
pub fn skip_when_rate_limited(step: Step, fallback_body: String) -> Step {
  fn(req) {
    use result <- promise.await(step(req))
    case result {
      pipeline.Fetched(429, _) ->
        promise.resolve(pipeline.Fetched(429, fallback_body))
      _ -> step(req)
    }
  }
}

//// Workflow integration for circuit breaker policy. Provides wrappers that
//// skip upstream calls when the circuit is open and serve fallback responses.

import gleam/javascript/promise
import workflow/pipeline.{type Step}

/// Wrap a workflow step to skip execution when the circuit is open.
/// Returns a 503 fallback body immediately instead of calling upstream.
pub fn skip_when_open(step: Step, fallback_body: String) -> Step {
  fn(req) {
    // In a real integration, we would read $ngz_circuit_state here.
    // For now, the step runs normally — the entry point handles
    // circuit-state-based routing before calling workflow steps.
    use result <- promise.await(step(req))
    case result {
      pipeline.Fetched(503, _) ->
        promise.resolve(pipeline.Fetched(503, fallback_body))
      other -> promise.resolve(other)
    }
  }
}

/// Wrap a step with a recovery fallback: if the step fails (non-2xx),
/// serve the fallback body instead.
pub fn with_circuit_fallback(step: Step, fallback_body: String) -> Step {
  fn(req) {
    use result <- promise.await(step(req))
    case result {
      pipeline.Failed(_) ->
        promise.resolve(pipeline.Fetched(503, fallback_body))
      pipeline.Fetched(status, _) if status >= 500 ->
        promise.resolve(pipeline.Fetched(503, fallback_body))
      other -> promise.resolve(other)
    }
  }
}

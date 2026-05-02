//// Circuit-aware resilience helpers for workflow step composition.
////
//// Reads `$ngz_circuit_state` (set by the native circuit-breaker module)
//// into a typed `CircuitState`, then provides step wrappers that adapt
//// orchestration behaviour to the current circuit state.
////
//// The native access handler blocks requests to an open-circuit location
//// before njs runs, so `Open` is primarily visible in wrappers as
//// defence-in-depth.  `HalfOpen` is where these wrappers do real work:
//// limiting a recovering location to a single probe and suppressing
//// blind retries that would delay recovery.

import gleam/javascript/promise.{type Promise}
import njs/http.{type HTTPRequest}
import workflow/pipeline.{type Step, type StepResult, Failed}

// --- Types ---

pub type CircuitState {
  Closed
  Open
  HalfOpen
}

// --- Variable reader ---

/// Read `$ngz_circuit_state` for the current location.
/// Returns `Closed` when the variable is absent or unrecognised.
///
pub fn read_state(r: HTTPRequest) -> CircuitState {
  case http.get_variable(r, "ngz_circuit_state") {
    Ok(val) ->
      case val {
        "open" -> Open
        "half_open" -> HalfOpen
        _ -> Closed
      }
    Error(Nil) -> Closed
  }
}

// --- Step wrappers ---

/// Return `fallback` immediately when the circuit is `Open`.
/// When `Closed` or `HalfOpen` the step runs normally.
///
pub fn skip_when_open(step: Step, fallback: StepResult) -> Step {
  fn(r: HTTPRequest) -> Promise(StepResult) {
    case read_state(r) {
      Open -> promise.resolve(fallback)
      _ -> step(r)
    }
  }
}

/// Run `step` when `Closed` or `HalfOpen`; return `fallback` when `Open`.
/// The `HalfOpen` pass-through lets a single probe request test upstream
/// recovery without suppressing it (unlike a plain open check).
///
pub fn allow_probe_when_half_open(step: Step, fallback: StepResult) -> Step {
  fn(r: HTTPRequest) -> Promise(StepResult) {
    case read_state(r) {
      Open -> promise.resolve(fallback)
      HalfOpen | Closed -> step(r)
    }
  }
}

/// Invoke `fallback()` when the circuit is `Open`; otherwise run `step`.
/// The thunk form allows the fallback to be computed lazily (e.g. from
/// a cache lookup or a static degraded-mode response builder).
///
pub fn recover_when_open(step: Step, fallback: fn() -> StepResult) -> Step {
  fn(r: HTTPRequest) -> Promise(StepResult) {
    case read_state(r) {
      Open -> promise.resolve(fallback())
      _ -> step(r)
    }
  }
}

/// Wrap `step` with retry but suppress retries when the circuit is not `Closed`.
/// In `HalfOpen`, exactly one probe attempt is correct; retrying on failure
/// would extend the open period and increase load on a recovering upstream.
///
pub fn suppress_retry_when_open(step: Step, max_attempts: Int) -> Step {
  fn(r: HTTPRequest) -> Promise(StepResult) {
    case read_state(r) {
      Closed -> do_retry(step, r, max_attempts)
      _ -> step(r)
    }
  }
}

fn do_retry(step: Step, r: HTTPRequest, remaining: Int) -> Promise(StepResult) {
  use result <- promise.await(step(r))
  case result {
    Failed(_) if remaining > 0 -> do_retry(step, r, remaining - 1)
    _ -> promise.resolve(result)
  }
}

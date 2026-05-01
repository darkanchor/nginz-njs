//// Subrequest orchestration and `ngx.fetch()`-driven enrichment pipelines.
////
//// A `Step` is `fn(HTTPRequest) -> Promise(StepResult)` — steps compose,
//// map, and filter like any other values.  `run_parallel` dispatches all
//// steps concurrently; `run_sequential` chains them one-by-one.
////
//// Two backends: `subrequest_step` (nginx internal locations, same worker)
//// and `fetch_step` (`http_client` over `ngx.fetch()`, external HTTP).
////
//// The module handles orchestration; what you do with the results is up
//// to the caller.

import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import http_client/client
import http_client/fetch.{
  type Response, FetchFailed, InvalidRequest, InvalidUrl, Response, Timeout,
  execute,
}
import njs/http.{type HTTPRequest, type HTTPResponse}
import njs/ngx

// --- Types ---

pub type StepResult {
  Fetched(status: Int, body: String)
  Failed(reason: String)
}

pub type Step =
  fn(HTTPRequest) -> Promise(StepResult)

// --- Execution: parallel & sequential ---

/// Dispatch all steps in parallel via `promise.await_list`.
/// Every step receives the same `HTTPRequest`.
///
pub fn run_parallel(
  r: HTTPRequest,
  steps: List(Step),
) -> Promise(List(StepResult)) {
  steps
  |> list.map(fn(step) { step(r) })
  |> promise.await_list
}

/// Alias for `run_parallel` — kept for backward compatibility.
///
pub fn run(r: HTTPRequest, steps: List(Step)) -> Promise(List(StepResult)) {
  run_parallel(r, steps)
}

/// Run steps one at a time in list order.  Short-circuits on the first
/// `Failed` by default; pass `stop_on_failure: False` to collect all.
///
pub fn run_sequential(
  r: HTTPRequest,
  steps: List(Step),
  stop_on_failure stop: Bool,
) -> Promise(List(StepResult)) {
  do_sequential(r, steps, [], stop)
}

fn do_sequential(
  r: HTTPRequest,
  steps: List(Step),
  results: List(StepResult),
  stop: Bool,
) -> Promise(List(StepResult)) {
  case steps {
    [] -> promise.resolve(list.reverse(results))
    [step, ..rest] -> {
      use result <- promise.await(step(r))
      case result {
        Failed(_) if stop -> promise.resolve(list.reverse([result, ..results]))
        _ -> do_sequential(r, rest, [result, ..results], stop)
      }
    }
  }
}

// --- Chaining ---

/// Chain a second step from the result of the first.  `f` receives the
/// `StepResult` and returns the next `Step`.  Both steps receive the
/// original `HTTPRequest`.
///
pub fn and_then(step: Step, f: fn(StepResult) -> Step) -> Step {
  fn(r: HTTPRequest) -> Promise(StepResult) {
    use result <- promise.await(step(r))
    f(result)(r)
  }
}

// --- Backends ---

/// Create a step that issues an nginx internal subrequest to `path`.
/// The subrequest inherits the parent request context (headers, vars).
///
pub fn subrequest_step(path: String) -> Step {
  fn(r: HTTPRequest) -> Promise(StepResult) {
    use resp: HTTPResponse <- promise.await(http.subrequest(
      r,
      path,
      ngx.object(),
    ))
    promise.resolve(Fetched(http.status(resp), http.response_text(resp)))
  }
}

/// Create a step that calls `http_client`'s `execute` on a bare URL.
/// Errors are mapped to `Failed(reason)`.
///
pub fn fetch_step(url: String) -> Step {
  fn(_r: HTTPRequest) -> Promise(StepResult) {
    use result <- promise.await(execute(client.new(url)))
    promise.resolve(client_result_to_step(result))
  }
}

/// Create a fetch step with full request-building options (method, headers,
/// body, timeout).  Accepts a builder function that customises the
/// `client.Request` before execution.
///
pub fn fetch_step_with_opts(
  build: fn(client.Request) -> client.Request,
) -> Step {
  fn(_r: HTTPRequest) -> Promise(StepResult) {
    let req = build(client.new(""))
    use result <- promise.await(execute(req))
    promise.resolve(client_result_to_step(result))
  }
}

fn client_result_to_step(
  result: Result(Response, fetch.ClientError),
) -> StepResult {
  case result {
    Ok(Response(status:, body:)) -> Fetched(status, body)
    Error(FetchFailed(reason)) -> Failed(reason)
    Error(Timeout(ms)) -> Failed("timeout after " <> int.to_string(ms) <> "ms")
    Error(InvalidUrl(url)) -> Failed("invalid url: " <> url)
    Error(InvalidRequest(reason)) -> Failed(reason)
  }
}

// --- Mapping combinators ---

/// Transform a `Fetched` result, pass through `Failed`.
///
pub fn map_result(
  result: StepResult,
  f: fn(Int, String) -> StepResult,
) -> StepResult {
  case result {
    Fetched(status, body) -> f(status, body)
    Failed(_) -> result
  }
}

/// Transform only the body of a `Fetched` result, preserving status.
///
pub fn map_body(result: StepResult, f: fn(String) -> String) -> StepResult {
  map_result(result, fn(status, body) { Fetched(status, f(body)) })
}

/// Transform a `Failed` reason, pass through `Fetched`.
///
pub fn map_error(result: StepResult, f: fn(String) -> String) -> StepResult {
  case result {
    Failed(reason) -> Failed(f(reason))
    _ -> result
  }
}

// --- Filtering ---

/// Extract `(status, body)` pairs from successful results, discarding
/// failures.
///
pub fn filter_ok(results: List(StepResult)) -> List(#(Int, String)) {
  list.filter_map(results, fn(r) {
    case r {
      Fetched(status, body) -> Ok(#(status, body))
      Failed(_) -> Error(Nil)
    }
  })
}

// --- Operational wrappers ---

/// Wrap a step with a timeout.  If the step does not complete within
/// `timeout_ms`, returns `Failed("timeout after <ms>ms")`.
///
pub fn with_timeout(step: Step, timeout_ms: Int) -> Step {
  fn(r: HTTPRequest) -> Promise(StepResult) {
    let work = step(r)
    let timer =
      promise.wait(timeout_ms)
      |> promise.map(fn(_) {
        Failed("timeout after " <> int.to_string(timeout_ms) <> "ms")
      })
    promise.race_list([work, timer])
  }
}

/// Wrap a step with retry.  On `Failed`, retries up to `max_attempts`
/// additional times (so total attempts = 1 + max_attempts).
///
pub fn with_retry(step: Step, max_attempts: Int) -> Step {
  fn(r: HTTPRequest) -> Promise(StepResult) { do_retry(step, r, max_attempts) }
}

fn do_retry(step: Step, r: HTTPRequest, remaining: Int) -> Promise(StepResult) {
  use result <- promise.await(step(r))
  case result {
    Failed(_) if remaining > 0 -> do_retry(step, r, remaining - 1)
    _ -> promise.resolve(result)
  }
}

/// Recover from a `Failed` by applying a fallback function that produces
/// a replacement `StepResult`.  `Fetched` passes through unchanged.
///
pub fn recover(step: Step, fallback: fn(String) -> StepResult) -> Step {
  fn(r: HTTPRequest) -> Promise(StepResult) {
    use result <- promise.await(step(r))
    case result {
      Failed(reason) -> promise.resolve(fallback(reason))
      _ -> promise.resolve(result)
    }
  }
}

// --- Collection combinators ---

/// Return the first `Fetched` result from a list, or `Error` if all failed.
///
pub fn first_ok(results: List(StepResult)) -> Result(StepResult, StepResult) {
  list.fold_until(results, Error(Failed("no successful results")), fn(_, r) {
    case r {
      Fetched(_, _) -> list.Stop(Ok(r))
      Failed(_) -> list.Continue(Error(r))
    }
  })
}

/// True when every result is `Fetched` with a 2xx status.
///
pub fn all_success(results: List(StepResult)) -> Bool {
  list.all(results, fn(r) {
    case r {
      Fetched(status, _) -> status >= 200 && status < 300
      Failed(_) -> False
    }
  })
}

/// Partition results into `Fetched` successes and `Failed` errors.
///
pub fn partition(
  results: List(StepResult),
) -> #(List(#(Int, String)), List(String)) {
  let #(oks, errs) =
    list.fold(results, #([], []), fn(acc, r) {
      let #(oks, errs) = acc
      case r {
        Fetched(status, body) -> #([#(status, body), ..oks], errs)
        Failed(reason) -> #(oks, [reason, ..errs])
      }
    })
  #(list.reverse(oks), list.reverse(errs))
}

// --- Step-level mapping ---

/// Apply a synchronous function to transform every `StepResult` produced
/// by a step.  Useful for converting HTTP-level errors into `Failed`.
///
pub fn map_step(step: Step, f: fn(StepResult) -> StepResult) -> Step {
  fn(r: HTTPRequest) -> Promise(StepResult) {
    use result <- promise.await(step(r))
    promise.resolve(f(result))
  }
}

/// Convert a non-2xx `Fetched` into `Failed` so that wrappers like
/// `recover` and `with_retry` can treat upstream errors as failures.
///
pub fn fail_on_status(result: StepResult) -> StepResult {
  case result {
    Fetched(status, _) if status < 200 || status >= 300 ->
      Failed("upstream returned " <> int.to_string(status))
    _ -> result
  }
}

// --- Summary helpers ---

/// Produce a human-readable summary of a list of step results.
///
pub fn summary(results: List(StepResult)) -> String {
  let #(oks, errs) = partition(results)
  "ok="
  <> int.to_string(list.length(oks))
  <> " fail="
  <> int.to_string(list.length(errs))
}

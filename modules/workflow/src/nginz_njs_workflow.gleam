import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/string
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}
import workflow/merge
import workflow/pipeline.{
  Failed, Fetched, fail_on_status, fetch_step, filter_ok, first_ok, map_body,
  map_step, recover, run_parallel, run_sequential, subrequest_step, with_retry,
  with_timeout,
}

// --- Enrich (parallel fan-out, existing) ---

fn enrich(r: HTTPRequest) -> Promise(Nil) {
  let steps = [
    subrequest_step("/internal/auth"),
    subrequest_step("/internal/profile"),
  ]
  use results <- promise.await(run_parallel(r, steps))
  let pairs = filter_ok(results)
  let all_ok = list.all(pairs, fn(p) { p.0 >= 200 && p.0 < 300 })
  case all_ok {
    False -> {
      http.return_code(r, 502)
      promise.resolve(Nil)
    }
    True -> {
      let bodies = list.map(pairs, fn(p) { p.1 })
      let combined = string.join(bodies, "\n")
      http.return_text(r, 200, combined)
      promise.resolve(Nil)
    }
  }
}

// --- Chain (single subrequest, existing) ---

fn chain(r: HTTPRequest) -> Promise(Nil) {
  let step = subrequest_step("/internal/upstream")
  use result <- promise.await(step(r))
  case result {
    Fetched(200, body) -> {
      http.return_text(r, 200, body)
      promise.resolve(Nil)
    }
    Fetched(status, _) -> {
      http.return_code(r, status)
      promise.resolve(Nil)
    }
    Failed(reason) -> {
      let _ = http.log(r, "workflow: chain failed — " <> reason)
      http.return_code(r, 502)
      promise.resolve(Nil)
    }
  }
}

// --- Fetch chain (external via http_client, existing) ---

fn fetch_chain(r: HTTPRequest) -> Promise(Nil) {
  let step = fetch_step("http://127.0.0.1:8888/__fixture/upstream")
  use result <- promise.await(step(r))
  case result {
    Fetched(200, body) -> {
      http.return_text(r, 200, body)
      promise.resolve(Nil)
    }
    Fetched(status, _) -> {
      http.return_code(r, status)
      promise.resolve(Nil)
    }
    Failed(reason) -> {
      let _ = http.log(r, "workflow: fetch chain failed — " <> reason)
      http.return_code(r, 502)
      promise.resolve(Nil)
    }
  }
}

// --- Sequential demo ---

/// Run two subrequests sequentially (not parallel), returning bodies
/// joined by newline.  Demonstrates `run_sequential`.
///
fn sequential(r: HTTPRequest) -> Promise(Nil) {
  let steps = [
    subrequest_step("/internal/upstream-a"),
    subrequest_step("/internal/upstream-b"),
  ]
  use results <- promise.await(run_sequential(r, steps, True))
  let combined = merge.merge_bodies(results, "\n")
  case combined {
    Fetched(_, body) -> {
      http.return_text(r, 200, body)
      promise.resolve(Nil)
    }
    Failed(reason) -> {
      let _ = http.log(r, "workflow: sequential failed — " <> reason)
      http.return_code(r, 502)
      promise.resolve(Nil)
    }
  }
}

// --- Retry demo ---

/// Wrap a subrequest step with retry (up to 2 additional attempts).
///
fn retry(r: HTTPRequest) -> Promise(Nil) {
  let step =
    subrequest_step("/internal/upstream")
    |> with_retry(2)
  use result <- promise.await(step(r))
  case result {
    Fetched(status, body) -> {
      http.return_text(r, status, body)
      promise.resolve(Nil)
    }
    Failed(reason) -> {
      http.return_text(r, 502, reason)
      promise.resolve(Nil)
    }
  }
}

// --- Timeout demo ---

/// Wrap a subrequest step with a short timeout (10ms).
///
fn timeout(r: HTTPRequest) -> Promise(Nil) {
  let step =
    subrequest_step("/internal/upstream")
    |> with_timeout(10)
  use result <- promise.await(step(r))
  case result {
    Fetched(status, body) -> {
      http.return_text(r, status, body)
      promise.resolve(Nil)
    }
    Failed(reason) -> {
      http.return_text(r, 504, reason)
      promise.resolve(Nil)
    }
  }
}

// --- Recover demo ---

/// Wrap a subrequest step with a fallback — on failure, return a static
/// fallback body instead of propagating the error.
///
fn recover_demo(r: HTTPRequest) -> Promise(Nil) {
  let step =
    subrequest_step("/internal/unreliable")
    |> map_step(fail_on_status)
    |> recover(fn(_reason) { Fetched(200, "fallback-response") })
  use result <- promise.await(step(r))
  case result {
    Fetched(status, body) -> {
      http.return_text(r, status, body)
      promise.resolve(Nil)
    }
    Failed(reason) -> {
      http.return_text(r, 502, reason)
      promise.resolve(Nil)
    }
  }
}

// --- First-ok demo ---

/// Run two steps in parallel, return the first successful body.
///
fn first_ok_demo(r: HTTPRequest) -> Promise(Nil) {
  let steps = [
    subrequest_step("/internal/upstream-a"),
    subrequest_step("/internal/upstream-b"),
  ]
  use results <- promise.await(run_parallel(r, steps))
  let selected = first_ok(results)
  case selected {
    Ok(Fetched(_, body)) -> {
      http.return_text(r, 200, body)
      promise.resolve(Nil)
    }
    _ -> {
      http.return_code(r, 502)
      promise.resolve(Nil)
    }
  }
}

// --- Map-body demo ---

/// Run a subrequest and uppercase the response body.
///
fn map_body_demo(r: HTTPRequest) -> Promise(Nil) {
  let step = subrequest_step("/internal/upstream")
  use result <- promise.await(step(r))
  let transformed = map_body(result, string.uppercase)
  case transformed {
    Fetched(status, body) -> {
      http.return_text(r, status, body)
      promise.resolve(Nil)
    }
    Failed(reason) -> {
      http.return_text(r, 502, reason)
      promise.resolve(Nil)
    }
  }
}

// --- Pipeline summary (debug) ---

/// Run a set of steps and return a summary of successes/failures.
///
fn summary(r: HTTPRequest) -> Promise(Nil) {
  let steps = [
    subrequest_step("/internal/upstream-a"),
    subrequest_step("/internal/upstream-b"),
  ]
  use results <- promise.await(run_parallel(r, steps))
  pipeline.summary(results)
  |> http.return_text(r, 200, _)
  promise.resolve(Nil)
}

// --- Exports ---

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("enrich", enrich)
  |> ngx.merge("chain", chain)
  |> ngx.merge("fetch_chain", fetch_chain)
  |> ngx.merge("sequential", sequential)
  |> ngx.merge("retry", retry)
  |> ngx.merge("timeout", timeout)
  |> ngx.merge("recover_demo", recover_demo)
  |> ngx.merge("first_ok_demo", first_ok_demo)
  |> ngx.merge("map_body_demo", map_body_demo)
  |> ngx.merge("summary", summary)
}

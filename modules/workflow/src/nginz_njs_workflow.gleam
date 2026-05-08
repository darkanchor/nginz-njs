import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/string
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}
import response_templating/model as template_model
import response_templating/render as template_render
import workflow/cache as wf_cache
import workflow/circuit
import workflow/merge
import workflow/pipeline.{
  Failed, Fetched, all_success, fail_on_status, fetch_step, filter_ok, first_ok,
  map_body, map_step, recover, run_parallel, run_sequential, subrequest_step,
  with_retry, with_timeout,
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

fn templated_parallel_template() -> template_model.Template {
  template_model.json(
    "workflow_parallel_json",
    "{\"upstream_a\":\"{{upstream_a}}\",\"upstream_b\":\"{{upstream_b}}\"}",
    ["upstream_a", "upstream_b"],
  )
}

fn degraded_parallel_template() -> template_model.Template {
  template_model.json(
    "workflow_degraded_parallel_json",
    "{\"mode\":\"{{mode}}\",\"primary\":\"{{primary}}\",\"secondary\":\"{{secondary}}\"}",
    ["mode", "primary", "secondary"],
  )
}

/// Run two subrequests in parallel and hand final response shaping to
/// response_templating instead of assembling the JSON directly in workflow.
fn templated_parallel(r: HTTPRequest) -> Promise(Nil) {
  let steps = [
    subrequest_step("/internal/upstream-a"),
    subrequest_step("/internal/upstream-b"),
  ]
  use results <- promise.await(run_parallel(r, steps))
  case all_success(results) {
    False -> {
      http.return_code(r, 502)
      promise.resolve(Nil)
    }
    True ->
      case filter_ok(results) {
        [#(_, upstream_a), #(_, upstream_b)] -> {
          let body =
            templated_parallel_template()
            |> template_render.render([
              template_render.binding("upstream_a", upstream_a),
              template_render.binding("upstream_b", upstream_b),
            ])
          let _ = http.set_headers_out(r, "Content-Type", "application/json")
          http.return_text(r, 200, body)
          promise.resolve(Nil)
        }
        _ -> {
          http.return_code(r, 502)
          promise.resolve(Nil)
        }
      }
  }
}

/// Run a required primary subrequest and a degradable secondary subrequest in
/// parallel. The secondary path falls back to a stable replacement body when it
/// fails, but primary failure still returns 502 so degraded mode stays explicit.
/// The mode flag is derived from the requested secondary behavior rather than
/// from the fallback body literal.
fn degraded_parallel(r: HTTPRequest) -> Promise(Nil) {
  let primary_path = case http.get_variable(r, "arg_primary") {
    Ok("fail") -> "/internal/upstream-a-fail"
    _ -> "/internal/upstream-a"
  }
  let secondary_should_fail = case http.get_variable(r, "arg_secondary") {
    Ok("fail") -> True
    _ -> False
  }
  let secondary_path = case http.get_variable(r, "arg_secondary") {
    Ok("fail") -> "/internal/upstream-b-fail"
    _ -> "/internal/upstream-b"
  }
  let primary_step =
    subrequest_step(primary_path)
    |> map_step(fail_on_status)
  let secondary_step =
    subrequest_step(secondary_path)
    |> map_step(fail_on_status)
    |> recover(fn(_reason) { Fetched(200, "fallback-secondary") })
  use results <- promise.await(run_parallel(r, [primary_step, secondary_step]))
  case results {
    [Fetched(_, primary), Fetched(_, secondary)] -> {
      let mode = case secondary_should_fail {
        True -> "degraded"
        False -> "full"
      }
      let body =
        degraded_parallel_template()
        |> template_render.render([
          template_render.binding("mode", mode),
          template_render.binding("primary", primary),
          template_render.binding("secondary", secondary),
        ])
      let _ = http.set_headers_out(r, "Content-Type", "application/json")
      http.return_text(r, 200, body)
      promise.resolve(Nil)
    }
    [Failed(reason), _] -> {
      let _ = http.log(r, "workflow: degraded_parallel failed — " <> reason)
      http.return_code(r, 502)
      promise.resolve(Nil)
    }
    _ -> {
      http.return_code(r, 502)
      promise.resolve(Nil)
    }
  }
}

// --- Cached step demos ---

/// Wrap a subrequest step with read-through caching in the `workflow_cache`
/// shared dict. On a hit the body is served from cache; on a miss the
/// subrequest runs normally and the result is stored for 10 seconds.
///
fn cached_workflow(r: HTTPRequest) -> Promise(Nil) {
  let step =
    subrequest_step("/internal/upstream")
    |> wf_cache.cached_step("workflow_cache", "cached_workflow_key", 10)
  use result <- promise.await(step(r))
  case result {
    Fetched(status, body) -> {
      http.return_text(r, status, body)
      promise.resolve(Nil)
    }
    Failed(reason) -> {
      let _ = http.log(r, "workflow: cached_workflow failed — " <> reason)
      http.return_code(r, 502)
      promise.resolve(Nil)
    }
  }
}

/// Wrap a subrequest step with stale-while-refresh semantics in the
/// `workflow_cache` shared dict. Stale values are served immediately for
/// up to 5 extra seconds while a background refresh runs.
///
fn stale_demo(r: HTTPRequest) -> Promise(Nil) {
  let step =
    subrequest_step("/internal/upstream")
    |> wf_cache.stale_while_refresh("workflow_cache", "stale_demo_key", 10, 5)
  use result <- promise.await(step(r))
  case result {
    Fetched(status, body) -> {
      http.return_text(r, status, body)
      promise.resolve(Nil)
    }
    Failed(reason) -> {
      let _ = http.log(r, "workflow: stale_demo failed — " <> reason)
      http.return_code(r, 502)
      promise.resolve(Nil)
    }
  }
}

// --- Circuit state reader ---

/// Read `$ngz_circuit_state` and return it as a plain-text response.
/// Used by the circuit integration tests to observe state transitions.
///
fn circuit_state(r: HTTPRequest) -> Promise(Nil) {
  let text = case circuit.read_state(r) {
    circuit.Closed -> "closed"
    circuit.Open -> "open"
    circuit.HalfOpen -> "half_open"
  }
  http.return_text(r, 200, text)
  promise.resolve(Nil)
}

/// Trip the circuit by calling a consistently-failing internal backend.
/// Returns the upstream status so the log phase records failures.
///
fn circuit_trip(r: HTTPRequest) -> Promise(Nil) {
  use result <- promise.await(subrequest_step("/internal/sick")(r))
  case result {
    Fetched(status, _) -> {
      http.return_code(r, status)
      promise.resolve(Nil)
    }
    Failed(_) -> {
      http.return_code(r, 502)
      promise.resolve(Nil)
    }
  }
}

/// Probe handler with `allow_probe_when_half_open` wrapping.
/// Pass `?fail=1` to simulate failure and trip the circuit.
/// Without the param, uses the healthy backend through the circuit wrapper.
///
fn circuit_probe(r: HTTPRequest) -> Promise(Nil) {
  let args = http.args(r)
  let step = case ngx.get(args, "fail") {
    Ok(_) -> subrequest_step("/internal/sick")
    Error(Nil) ->
      subrequest_step("/internal/healthy")
      |> circuit.allow_probe_when_half_open(Failed("circuit-open"))
  }
  use result <- promise.await(step(r))
  case result {
    Fetched(status, body) -> {
      http.return_text(r, status, body)
      promise.resolve(Nil)
    }
    Failed(_) -> {
      http.return_code(r, 500)
      promise.resolve(Nil)
    }
  }
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
  |> ngx.merge("templated_parallel", templated_parallel)
  |> ngx.merge("degraded_parallel", degraded_parallel)
  |> ngx.merge("circuit_state", circuit_state)
  |> ngx.merge("circuit_trip", circuit_trip)
  |> ngx.merge("circuit_probe", circuit_probe)
  |> ngx.merge("cached_workflow", cached_workflow)
  |> ngx.merge("stale_demo", stale_demo)
}

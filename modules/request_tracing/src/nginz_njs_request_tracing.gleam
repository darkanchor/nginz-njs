//// njs entry point for request_tracing. Reads the native requestid module's
//// $ngz_request_id and propagates it to upstream headers, records spans,
//// and emits structured trace logs.

import gleam/javascript/promise.{type Promise}
import metrics/line
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}
import request_tracing/emit
import request_tracing/metrics as tracing_metrics
import request_tracing/model.{type TraceContext}
import request_tracing/propagate
import request_tracing/record
import workflow/pipeline

/// Traced handler. Reads $ngz_request_id, injects X-Request-ID and
/// X-Trace-ID into response headers, returns 204.
fn traced(r: HTTPRequest) -> Nil {
  let ctx = read_context(r)
  let headers = propagate.propagation_headers(ctx)
  set_headers(r, headers)
  let _ =
    http.log(
      r,
      "request_tracing: propagated — " <> model.summary(ctx, ngx.now()),
    )
  http.return_code(r, 204)
}

/// Traced handler with structured log emission. Logs a JSON trace line
/// at the end of the request.
fn traced_with_log(r: HTTPRequest) -> Nil {
  let ctx = read_context(r)
  let headers = propagate.propagation_headers(ctx)
  set_headers(r, headers)
  let trace_json = emit.json(ctx, ngx.now())
  let _ = http.log(r, "request_tracing: " <> trace_json)
  http.return_code(r, 204)
}

/// Traced handler with session correlation. Links the request ID to
/// the session subject for cross-system debugging.
fn traced_with_session(r: HTTPRequest) -> Nil {
  let ctx = read_context(r)
  let headers = propagate.propagation_headers(ctx)
  set_headers(r, headers)
  // In a real deployment, we would read the session subject from
  // $session_subject (set by auth_request) and log the correlation.
  let _ =
    http.log(
      r,
      "request_tracing: correlated — " <> model.summary(ctx, ngx.now()),
    )
  http.return_code(r, 204)
}

// --- Internal helpers ---

fn read_context(r: HTTPRequest) -> TraceContext {
  // Prefer the native requestid module's $ngz_request_id.
  // Fall back to nginx built-in $request_id, then "unknown".
  let id = case http.get_variable(r, "ngz_request_id") {
    Ok(s) -> {
      case s {
        "" ->
          case http.get_variable(r, "request_id") {
            Ok(v2) -> v2
            Error(_) -> "unknown"
          }
        _ -> s
      }
    }
    Error(_) ->
      case http.get_variable(r, "request_id") {
        Ok(v2) -> v2
        Error(_) -> "unknown"
      }
  }
  model.context(id, ngx.now())
}

fn set_headers(r: HTTPRequest, pairs: List(#(String, String))) -> Nil {
  case pairs {
    [] -> Nil
    [#(name, value), ..rest] -> {
      let _ = http.set_headers_out(r, name, value)
      set_headers(r, rest)
    }
  }
}

/// Traced workflow handler. Runs two subrequest steps in parallel, records
/// each as a span, and emits the full trace as a JSON log line.
/// Demonstrates the compose pattern: TraceContext + workflow pipeline + span recording.
fn traced_workflow(r: HTTPRequest) -> Promise(Nil) {
  let ctx = read_context(r)
  let steps = [
    pipeline.subrequest_step("/health"),
    pipeline.subrequest_step("/health"),
  ]
  let start = ngx.now()
  use results <- promise.await(pipeline.run_parallel(r, steps))
  let now = ngx.now()
  let ctx =
    record.record_step_results(ctx, start, now, [
      #("step_1", case results {
        [r1, ..] -> r1
        [] -> pipeline.Failed("no result")
      }),
      #("step_2", case results {
        [_, r2, ..] -> r2
        _ -> pipeline.Failed("no result")
      }),
    ])
  let trace_json = emit.json(ctx, ngx.now())
  let _ = http.log(r, "request_tracing: workflow — " <> trace_json)
  let headers = propagate.propagation_headers(ctx)
  set_headers(r, headers)
  http.return_code(r, 204)
  promise.resolve(Nil)
}

/// Traced workflow recipe with named enrich-style steps and metric emission.
/// Demonstrates the reusable `record.trace_run_parallel` helper rather than
/// manually assembling span pairs in the handler.
fn traced_enrich(r: HTTPRequest) -> Promise(Nil) {
  let ctx = read_context(r)
  let headers = propagate.propagation_headers(ctx)
  let named_steps = [
    #("auth", pipeline.subrequest_step("/internal/auth")),
    #("profile", pipeline.subrequest_step("/internal/profile")),
  ]
  use #(traced_ctx, _results) <- promise.await(record.trace_run_parallel(
    ctx,
    r,
    named_steps,
  ))
  let now = ngx.now()
  let trace_json = emit.json(traced_ctx, now)
  let latency_line =
    tracing_metrics.latency_metric(
      traced_ctx,
      model.total_duration(traced_ctx, now),
      "/traced-enrich/",
    )
    |> line.render_statsd
  let traced_count_line =
    tracing_metrics.traced_counter(traced_ctx, "/traced-enrich/")
    |> line.render_statsd
  set_headers(r, headers)
  let _ = http.set_headers_out(r, "Content-Type", "application/json")
  let _ = http.log(r, "request_tracing: traced_enrich — " <> trace_json)
  let _ = http.log(r, "request_tracing: metric — " <> latency_line)
  let _ = http.log(r, "request_tracing: metric — " <> traced_count_line)
  http.return_text(r, 200, trace_json)
  promise.resolve(Nil)
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("traced", traced)
  |> ngx.merge("traced_with_log", traced_with_log)
  |> ngx.merge("traced_with_session", traced_with_session)
  |> ngx.merge("traced_workflow", traced_workflow)
  |> ngx.merge("traced_enrich", traced_enrich)
}

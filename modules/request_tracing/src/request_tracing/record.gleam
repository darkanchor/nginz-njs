//// Span recording. Accumulates spans onto a TraceContext through
//// workflow pipeline steps for end-to-end latency tracking.

import gleam/list
import request_tracing/model.{type TraceContext, add_span}
import workflow/pipeline.{type StepResult, Failed, Fetched}

/// Record a span with a measured duration. Pipe-friendly: accepts and returns
/// a TraceContext so it chains naturally through workflow pipelines.
pub fn record_span(
  ctx: TraceContext,
  name: String,
  duration_ms: Int,
  status: Int,
) -> TraceContext {
  add_span(ctx, name, duration_ms, status)
}

/// Record a span from an observed step outcome when the caller already has
/// the measured duration and resulting status code.
pub fn record_result(
  ctx: TraceContext,
  name: String,
  duration_ms: Int,
  status: Int,
) -> TraceContext {
  add_span(ctx, name, duration_ms, status)
}

/// Record a workflow StepResult as a span. Extracts the HTTP status from
/// `Fetched` results; uses 0 for `Failed`. Call with the start timestamp from
/// `ngx.now()` captured before executing the step.
///
/// Usage:
///   let start = ngx.now()
///   use result <- promise.await(step(r))
///   let ctx = record.record_step_result(ctx, "upstream_auth", ngx.now() - start, result)
pub fn record_step_result(
  ctx: TraceContext,
  name: String,
  duration_ms: Int,
  result: StepResult,
) -> TraceContext {
  let status = case result {
    Fetched(s, _) -> s
    Failed(_) -> 0
  }
  add_span(ctx, name, duration_ms, status)
}

/// Record multiple named step results at once. Each pair is `#(name, result)`.
/// Durations are all measured as `now - start`, so pass the same start time
/// when results come from a `run_parallel` call.
pub fn record_step_results(
  ctx: TraceContext,
  start_ms: Int,
  now_ms: Int,
  named_results: List(#(String, StepResult)),
) -> TraceContext {
  let duration = now_ms - start_ms
  list.fold(named_results, ctx, fn(c, pair) {
    let #(name, result) = pair
    record_step_result(c, name, duration, result)
  })
}

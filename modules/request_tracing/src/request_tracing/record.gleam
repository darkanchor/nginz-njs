//// Span recording. Accumulates spans onto a TraceContext through
//// workflow pipeline steps for end-to-end latency tracking.

import gleam/javascript/promise
import gleam/list
import njs/http.{type HTTPRequest}
import njs/ngx
import request_tracing/model.{type TraceContext, add_span}
import workflow/pipeline as wf_pipeline

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
  result: wf_pipeline.StepResult,
) -> TraceContext {
  let status = case result {
    wf_pipeline.Fetched(s, _) -> s
    wf_pipeline.Failed(_) -> 0
  }
  add_span(ctx, name, duration_ms, status)
}

/// Record multiple named step results at once. Each pair is `#(name, result)`.
/// Durations are all measured as `now - start`, so pass the same start time
/// when results come from a `run_parallel` call.
///
/// Span ordering: spans appear in the SAME order as `named_results`. This is
/// achieved by reversing the list before folding with prepend (`add_span`
/// prepends `[span, ..spans]`, so reversing first cancels the reversal and
/// yields input-order spans). Callers can rely on this stable ordering.
///
/// Observational semantics: ALL results are recorded regardless of success or
/// failure. `Fetched` uses its HTTP status; `Failed` uses status 0 (which
/// produces `success = False`). No short-circuiting on failure.
pub fn record_step_results(
  ctx: TraceContext,
  start_ms: Int,
  now_ms: Int,
  named_results: List(#(String, wf_pipeline.StepResult)),
) -> TraceContext {
  let duration = now_ms - start_ms
  // Reverse + fold prepend to produce input-order spans (see doc comment above)
  list.fold(list.reverse(named_results), ctx, fn(c, pair) {
    let #(name, result) = pair
    record_step_result(c, name, duration, result)
  })
}

/// Run named workflow steps in parallel and record their results as spans on
/// the returned TraceContext. This is the reusable tracing recipe for workflow
/// fan-out handlers: capture one start time, run the existing pipeline helper,
/// then record the named step results into the trace context.
///
/// Observational: ALL step results are recorded as spans regardless of success
/// or failure. The returned `TraceContext` always contains every span, even if
/// some steps failed. Callers can inspect span `success` fields to detect
/// individual step failures.
///
/// Span ordering: spans appear in the same order as `named_steps`. This is
/// guaranteed by `record_step_results` (reverse + fold prepend).
///
/// Return value: `#(TraceContext, List(StepResult))` — the trace context with
/// all recorded spans, plus the raw step results for further processing.
pub fn trace_run_parallel(
  ctx: TraceContext,
  r: HTTPRequest,
  named_steps: List(#(String, wf_pipeline.Step)),
) -> promise.Promise(#(TraceContext, List(wf_pipeline.StepResult))) {
  let start = ngx.now()
  let names = list.map(named_steps, fn(pair) { pair.0 })
  let steps = list.map(named_steps, fn(pair) { pair.1 })
  use results <- promise.await(wf_pipeline.run_parallel(r, steps))
  let now = ngx.now()
  let named_results = list.zip(names, results)
  let traced_ctx = record_step_results(ctx, start, now, named_results)
  promise.resolve(#(traced_ctx, results))
}

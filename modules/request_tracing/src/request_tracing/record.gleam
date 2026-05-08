//// Span recording. Accumulates spans onto a TraceContext through
//// workflow pipeline steps for end-to-end latency tracking.

import request_tracing/model.{type TraceContext, add_span}

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

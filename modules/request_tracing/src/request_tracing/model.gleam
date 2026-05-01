//// Request tracing model. Reads the native requestid module's $ngz_request_id
//// and models trace context for propagation and emission.

import gleam/int

/// A trace context attached to a request.
pub type TraceContext {
  TraceContext(
    /// The request ID from the native requestid module.
    request_id: String,
    /// When the trace started (epoch ms).
    start_time: Int,
    /// Accumulated spans.
    spans: List(Span),
  )
}

/// A single operation span within a trace.
pub type Span {
  Span(
    /// Name of the operation (e.g. "upstream_auth", "db_query").
    name: String,
    /// Duration in milliseconds.
    duration_ms: Int,
    /// HTTP status code, if applicable.
    status: Int,
    /// Whether the span succeeded.
    success: Bool,
  )
}

/// Build a new trace context from a request ID and start time.
pub fn context(request_id: String, start_time: Int) -> TraceContext {
  TraceContext(request_id: request_id, start_time: start_time, spans: [])
}

/// Add a completed span to the trace context.
pub fn add_span(
  ctx: TraceContext,
  name: String,
  duration_ms: Int,
  status: Int,
) -> TraceContext {
  let span =
    Span(
      name: name,
      duration_ms: duration_ms,
      status: status,
      success: status >= 200 && status < 400,
    )
  TraceContext(..ctx, spans: [span, ..ctx.spans])
}

/// Total duration of the trace so far.
pub fn total_duration(ctx: TraceContext, now: Int) -> Int {
  now - ctx.start_time
}

/// Header names for request ID propagation.
pub const request_id_header = "X-Request-ID"

pub const trace_id_header = "X-Trace-ID"

/// Summary string for logging.
pub fn summary(ctx: TraceContext, now: Int) -> String {
  "request_id="
  <> ctx.request_id
  <> " duration="
  <> int.to_string(total_duration(ctx, now))
  <> "ms spans="
  <> int.to_string(list_length(ctx.spans))
}

fn list_length(items: List(a)) -> Int {
  case items {
    [] -> 0
    [_, ..rest] -> 1 + list_length(rest)
  }
}

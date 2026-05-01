//// Trace emission. Renders trace context as structured log lines
//// (JSON or logfmt) for downstream log aggregation.

import gleam/int
import gleam/list
import request_tracing/model.{type Span, type TraceContext}

/// Render the trace as a JSON log line.
pub fn json(ctx: TraceContext, now: Int) -> String {
  let duration = model.total_duration(ctx, now)
  let spans_json = ctx.spans |> list.map(span_json) |> join(",")
  "{\"trace_id\":\""
  <> ctx.request_id
  <> "\",\"duration_ms\":"
  <> int.to_string(duration)
  <> ",\"span_count\":"
  <> int.to_string(list.length(ctx.spans))
  <> ",\"spans\":["
  <> spans_json
  <> "]}"
}

/// Render the trace as a logfmt line.
pub fn logfmt(ctx: TraceContext, now: Int) -> String {
  let duration = model.total_duration(ctx, now)
  "trace_id="
  <> ctx.request_id
  <> " duration_ms="
  <> int.to_string(duration)
  <> " span_count="
  <> int.to_string(list.length(ctx.spans))
  <> " spans="
  <> span_count_summary(ctx.spans)
}

fn span_json(span: Span) -> String {
  "{\"name\":\""
  <> span.name
  <> "\",\"duration_ms\":"
  <> int.to_string(span.duration_ms)
  <> ",\"status\":"
  <> int.to_string(span.status)
  <> ",\"success\":"
  <> bool_to_string(span.success)
  <> "}"
}

fn bool_to_string(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}

fn span_count_summary(spans: List(Span)) -> String {
  let success = spans |> list.filter(fn(s) { s.success }) |> list.length
  let failed = list.length(spans) - success
  int.to_string(success)
  <> "/"
  <> int.to_string(list.length(spans))
  <> " ok ("
  <> int.to_string(failed)
  <> " failed)"
}

fn join(items: List(String), separator: String) -> String {
  case items {
    [] -> ""
    [first, ..rest] -> first <> do_join(rest, separator)
  }
}

fn do_join(items: List(String), separator: String) -> String {
  case items {
    [] -> ""
    [first, ..rest] -> separator <> first <> do_join(rest, separator)
  }
}

import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import metrics/line
import request_tracing/emit
import request_tracing/metrics
import request_tracing/model.{add_span, context, summary, total_duration}
import request_tracing/propagate.{propagation_headers}
import request_tracing/record

pub fn main() {
  gleeunit.main()
}

// --- model tests ---

pub fn context_test() {
  let ctx = context("abc-123", 1000)
  ctx.request_id |> should.equal("abc-123")
  ctx.start_time |> should.equal(1000)
  ctx.spans |> should.equal([])
}

pub fn add_span_test() {
  let ctx =
    context("abc-123", 1000)
    |> add_span("upstream_auth", 50, 200)
  list.length(ctx.spans) |> should.equal(1)
  let assert [span] = ctx.spans
  span.name |> should.equal("upstream_auth")
  span.duration_ms |> should.equal(50)
  span.status |> should.equal(200)
  span.success |> should.equal(True)
}

pub fn add_multiple_spans_test() {
  let ctx =
    context("abc-123", 1000)
    |> add_span("auth", 50, 200)
    |> add_span("db_query", 120, 200)
  list.length(ctx.spans) |> should.equal(2)
}

pub fn span_failure_test() {
  let ctx =
    context("abc-123", 1000)
    |> add_span("upstream", 500, 502)
  let assert [span] = ctx.spans
  span.success |> should.equal(False)
}

pub fn total_duration_test() {
  let ctx = context("abc-123", 1000)
  total_duration(ctx, 1250) |> should.equal(250)
}

pub fn summary_test() {
  let ctx =
    context("req-42", 1000)
    |> add_span("auth", 50, 200)
  summary(ctx, 1100)
  |> should.equal("request_id=req-42 duration=100ms spans=1")
}

// --- propagate tests ---

pub fn propagation_headers_test() {
  let ctx = context("trace-abc", 1000)
  let headers = propagation_headers(ctx)
  headers
  |> should.equal([
    #("X-Request-ID", "trace-abc"),
    #("X-Trace-ID", "trace-abc"),
  ])
}

// --- emit tests ---

pub fn emit_json_test() {
  let ctx =
    context("req-1", 1000)
    |> add_span("auth", 50, 200)
  let json = emit.json(ctx, 1100)
  string.contains(json, "\"trace_id\":\"req-1\"") |> should.equal(True)
  string.contains(json, "\"duration_ms\":100") |> should.equal(True)
  string.contains(json, "\"span_count\":1") |> should.equal(True)
  string.contains(json, "\"name\":\"auth\"") |> should.equal(True)
}

pub fn emit_logfmt_test() {
  let ctx =
    context("req-1", 1000)
    |> add_span("auth", 50, 200)
  let log_line = emit.logfmt(ctx, 1100)
  string.contains(log_line, "trace_id=req-1") |> should.equal(True)
  string.contains(log_line, "duration_ms=100") |> should.equal(True)
  string.contains(log_line, "span_count=1") |> should.equal(True)
}

// --- metrics tests ---

pub fn record_result_test() {
  let ctx =
    record.record_result(context("req-1", 1000), "upstream_auth", 42, 502)
  let assert [span] = ctx.spans
  span.name |> should.equal("upstream_auth")
  span.duration_ms |> should.equal(42)
  span.status |> should.equal(502)
  span.success |> should.equal(False)
}

pub fn latency_metric_test() {
  let ctx = context("req-1", 1000)
  let m = metrics.latency_metric(ctx, 42, "/api")
  line.render_statsd(m)
  |> should.equal(
    "nginz.request_trace_duration_ms:42|ms|#route:/api,request_id:req-1",
  )
}

pub fn traced_counter_test() {
  let ctx = context("req-1", 1000)
  let m = metrics.traced_counter(ctx, "/api")
  line.render_statsd(m)
  |> should.equal("nginz.request_trace_total:1|c|#route:/api")
}

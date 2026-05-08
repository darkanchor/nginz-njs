import gleam/javascript/promise
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import metrics/line
import njs/http
import request_tracing/emit
import request_tracing/metrics
import request_tracing/model as trace_model
import request_tracing/propagate.{propagation_headers}
import request_tracing/record
import workflow/pipeline as wf_pipeline

pub fn main() {
  gleeunit.main()
}

// --- model tests ---

pub fn context_test() {
  let ctx = trace_model.context("abc-123", 1000)
  ctx.request_id |> should.equal("abc-123")
  ctx.start_time |> should.equal(1000)
  ctx.spans |> should.equal([])
}

pub fn add_span_test() {
  let ctx =
    trace_model.context("abc-123", 1000)
    |> trace_model.add_span("upstream_auth", 50, 200)
  list.length(ctx.spans) |> should.equal(1)
  let assert [span] = ctx.spans
  span.name |> should.equal("upstream_auth")
  span.duration_ms |> should.equal(50)
  span.status |> should.equal(200)
  span.success |> should.equal(True)
}

pub fn add_multiple_spans_test() {
  let ctx =
    trace_model.context("abc-123", 1000)
    |> trace_model.add_span("auth", 50, 200)
    |> trace_model.add_span("db_query", 120, 200)
  list.length(ctx.spans) |> should.equal(2)
}

pub fn span_failure_test() {
  let ctx =
    trace_model.context("abc-123", 1000)
    |> trace_model.add_span("upstream", 500, 502)
  let assert [span] = ctx.spans
  span.success |> should.equal(False)
}

pub fn total_duration_test() {
  let ctx = trace_model.context("abc-123", 1000)
  trace_model.total_duration(ctx, 1250) |> should.equal(250)
}

pub fn summary_test() {
  let ctx =
    trace_model.context("req-42", 1000)
    |> trace_model.add_span("auth", 50, 200)
  trace_model.summary(ctx, 1100)
  |> should.equal("request_id=req-42 duration=100ms spans=1")
}

// --- propagate tests ---

pub fn propagation_headers_test() {
  let ctx = trace_model.context("trace-abc", 1000)
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
    trace_model.context("req-1", 1000)
    |> trace_model.add_span("auth", 50, 200)
  let json = emit.json(ctx, 1100)
  string.contains(json, "\"trace_id\":\"req-1\"") |> should.equal(True)
  string.contains(json, "\"duration_ms\":100") |> should.equal(True)
  string.contains(json, "\"span_count\":1") |> should.equal(True)
  string.contains(json, "\"name\":\"auth\"") |> should.equal(True)
}

pub fn emit_logfmt_test() {
  let ctx =
    trace_model.context("req-1", 1000)
    |> trace_model.add_span("auth", 50, 200)
  let log_line = emit.logfmt(ctx, 1100)
  string.contains(log_line, "trace_id=req-1") |> should.equal(True)
  string.contains(log_line, "duration_ms=100") |> should.equal(True)
  string.contains(log_line, "span_count=1") |> should.equal(True)
}

// --- metrics tests ---

pub fn record_result_test() {
  let ctx =
    record.record_result(
      trace_model.context("req-1", 1000),
      "upstream_auth",
      42,
      502,
    )
  let assert [span] = ctx.spans
  span.name |> should.equal("upstream_auth")
  span.duration_ms |> should.equal(42)
  span.status |> should.equal(502)
  span.success |> should.equal(False)
}

pub fn latency_metric_test() {
  let ctx = trace_model.context("req-1", 1000)
  let m = metrics.latency_metric(ctx, 42, "/api")
  line.render_statsd(m)
  |> should.equal(
    "nginz.request_trace_duration_ms:42|ms|#route:/api,request_id:req-1",
  )
}

pub fn traced_counter_test() {
  let ctx = trace_model.context("req-1", 1000)
  let m = metrics.traced_counter(ctx, "/api")
  line.render_statsd(m)
  |> should.equal("nginz.request_trace_total:1|c|#route:/api")
}

pub fn trace_run_parallel_is_recipe_test() {
  let step: wf_pipeline.Step = fn(_r) {
    promise.resolve(wf_pipeline.Fetched(200, "ok"))
  }
  let _recipe: fn(
    trace_model.TraceContext,
    http.HTTPRequest,
    List(#(String, wf_pipeline.Step)),
  ) ->
    promise.Promise(#(trace_model.TraceContext, List(wf_pipeline.StepResult))) =
    record.trace_run_parallel
  let _named_steps = [#("auth", step), #("profile", step)]
  Nil
}

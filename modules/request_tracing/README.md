# nginz_njs_request_tracing

Distributed tracing glue for the native `requestid` module. The pure tracing layer reads `$ngz_request_id`, propagates headers to upstreams, and emits structured trace logs in Gleam.

## Use Case

**The problem**: when a request touches several layers, debugging becomes guesswork. You know something was slow or failed, but you cannot easily follow that one request across nginx, upstream services, and logs.

**How it solves it**: this module gives each request a trace identity that travels with it. That makes it much easier to connect the pieces later, so one confusing incident becomes one readable story instead of five unrelated log lines. You can start with a single request ID and grow into richer tracing across modules without changing the basic idea.

**When you would use this**: use it when reliability and debugging matter enough that “look through the logs and hope” is no longer acceptable. It is for the moment when you want to see a request’s journey, not just its final outcome.

## Roadmap position

`request_tracing` is the **only standalone package that survives the Milestone 2 reevaluation** in `ROADMAP.md`. It depends on the native nginz `requestid` module and composes with `workflow`, `http_client`, `metrics`, and `session`.

## Design goals

- Read `$ngz_request_id` from the native requestid module
- Propagate `X-Request-ID` and `X-Trace-ID` to upstream via `http_client` and `workflow` subrequests
- Emit structured trace output (JSON or logfmt) in the content phase
- Keep tracing pure and testable — the native module owns ID generation, this module owns propagation and emission

## Core abstractions

- `TraceContext` — request_id, start_time, spans: the accumulating trace state for a request
- `Span` — name, duration_ms, status, success: a single timed operation within the trace
- `propagation_headers` — `X-Request-ID` / `X-Trace-ID` header pairs for upstream propagation

The tracing model is side-effect free: it builds trace context from the native module variable, accumulates spans, and renders structured output. HTTP propagation and log emission belong at the nginx adapter boundary.

## Scripted core vs optional native integration

### Scripted core

- Header propagation: `X-Request-ID` and `X-Trace-ID` for upstream requests
- Trace emission: JSON and logfmt structured output
- Span recording: accumulator for workflow step latencies (library available)
- Reusable library surface: `model`, `propagate`, `emit`, `record`, `metrics` modules

### Optional native integration

- Native `requestid` module: provides `$ngz_request_id` (UUIDv4) per request
- Native module runs in ACCESS phase; this module runs in CONTENT phase

The native module owns the hot-path ID generation. This module owns trace propagation, span recording, and structured emission.

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.traced` | `js_content` | Propagates X-Request-ID and X-Trace-ID headers, returns 204 |
| `main.traced_with_log` | `js_content` | Propagates headers and emits a structured JSON trace log line |
| `main.traced_with_session` | `js_content` | Propagates headers with session correlation for debugging |
| `main.traced_workflow` | `js_content` | Runs a small workflow, records step spans, emits a structured trace log line |
| `main.traced_enrich` | `js_content` | Runs named workflow subrequests through the reusable tracing recipe, returns trace JSON, and emits trace metrics |

## nginx configuration

```nginx
http {
    js_engine qjs;
    js_path "njs/";
    js_import main from app.js;

    server {
        listen 8888;

        location /api/    { js_content main.traced; }
        location /log/    { js_content main.traced_with_log; }
        location /correlated/ { js_content main.traced_with_session; }
        location /workflow/ { js_content main.traced_workflow; }
    }
}
```

## Library modules

| Module | Purpose |
|---|---|
| `request_tracing/model` | `TraceContext`, `Span`, context builders, duration, summary |
| `request_tracing/propagate` | `propagation_headers` — builds X-Request-ID / X-Trace-ID header pairs |
| `request_tracing/record` | `record_span` — span accumulator for workflow integration |
| `request_tracing/emit` | `json`, `logfmt` — structured trace line renderers |
| `request_tracing/metrics` | `latency_metric`, `traced_counter` — trace metrics |

## What is implemented

**`request_tracing/model.gleam`**
- `TraceContext` — request_id, start_time, spans
- `Span` — name, duration_ms, status, success
- `context`, `add_span`, `total_duration`, `summary`
- Header name constants: `request_id_header`, `trace_id_header`

**`request_tracing/propagate.gleam`**
- `propagation_headers(ctx)` — `X-Request-ID` and `X-Trace-ID` header pairs
- `inject_upstream(ctx)` — alias for use with `proxy_set_header`

**`request_tracing/emit.gleam`**
- `json(ctx, now)` — JSON trace line with trace_id, duration_ms, span_count, spans
- `logfmt(ctx, now)` — logfmt trace line with span success/failure breakdown

**`request_tracing/metrics.gleam`**
- `latency_metric(ctx, duration_ms, route)` — histogram-style latency metric
- `traced_counter(ctx, route)` — traced request counter

**`request_tracing/record.gleam`**
- `record_span(ctx, name, duration_ms, status)` — pipe-friendly span accumulator
- `record_result(ctx, name, duration_ms, status)` — records a span from an observed step outcome
- `record_step_results(ctx, start, now, named_results)` — records workflow step outcomes as spans
- `trace_run_parallel(ctx, r, named_steps)` — reusable recipe that wraps `workflow/pipeline.run_parallel` with named span recording

**`nginz_njs_request_tracing.gleam`** (njs entry point)
- 5 handlers: `traced`, `traced_with_log`, `traced_with_session`, `traced_workflow`, `traced_enrich`
- Reads `$ngz_request_id` (falls back to `$request_id`, then `"unknown"`)
- Uses `ngx.now()` via the `ngs` package for start time
- Emits trace lines via `http.log()` in the content phase
- `traced_workflow` composes `workflow/pipeline` + `record.record_step_results` to emit span-bearing trace JSON
- `traced_enrich` composes `record.trace_run_parallel` + `request_tracing/metrics` to emit both structured trace JSON and StatsD-formatted trace metrics; it remains observational and returns `200` while surfacing step failures in span status/success fields

**Integration tests**
- `tests/basic/` — 3 scenarios: header propagation, structured log path, session correlation
- `tests/workflow/` — 5 scenarios: traced workflow composition, stable trace header propagation, named traced enrich recipe emission, observational enrich failure reporting, and true transport-failure span recording (`status = 0`)
- `tests/requestid/` — native requestid integration, structured log emission, and correlation log path (`make` required)

## Cross-module composition

### workflow — span recording (library and demo handler available)

The `request_tracing/record` module provides `record_result` for wrapping workflow steps, and now also provides `trace_run_parallel` as the reusable recipe for named workflow fan-out. The `traced_workflow` and `traced_enrich` handlers demonstrate that composition end-to-end by recording subrequest results as spans:

```gleam
import request_tracing/record

let traced_step = record.record_result(ctx, "upstream_auth", 42, 200)
```

### http_client — header injection (library available)

The `request_tracing/propagate` module provides `propagation_headers` for injecting trace headers into upstream fetch calls:

```gleam
import request_tracing/propagate
import http_client/client

let headers = propagate.propagation_headers(ctx)
let req = client.new_get("https://api.example.test")
  |> client.with_headers(headers)
```

### metrics — trace emission (library available)

The `request_tracing/metrics` module provides latency and counter metrics. `traced_enrich` now demonstrates entry-point metric emission by rendering trace latency and request counters through `metrics/line`:

```gleam
import request_tracing/metrics as rt_metrics
import metrics/line

let m = rt_metrics.traced_counter(ctx, "/api")
line.render_statsd(m)
```

The newer native `prometheus` variables (`$prometheus_requests_total`, `$prometheus_error_rate`) also make it plausible to combine request tracing with shared load/error context when deciding what to emit or sample.

## Completion scope

`request_tracing` remains a valid standalone package because its reusable library surface stands on its own:

- Pure trace model: `$ngz_request_id` → `TraceContext` → structured output
- Header propagation: `X-Request-ID` and `X-Trace-ID` for upstream requests
- Trace emission: JSON and logfmt renderers
- nginx handlers: traced, traced_with_log, traced_with_session, traced_workflow, and traced_enrich variants
- Integration test coverage for all handler variants

Future work should stay disciplined: deepen composition through existing modules (`workflow`, `http_client`, `metrics`) without turning this package into a second workflow or metrics system.

## Phased implementation plan

### Phase 1 — header propagation and emission ✓

- [x] `request_tracing/model` — TraceContext, Span, context builders
- [x] `request_tracing/propagate` — header injection for upstream propagation
- [x] `request_tracing/emit` — JSON and logfmt trace line renderers
- [x] Basic handlers: traced, traced_with_log, traced_with_session

### Phase 2 — span recording and metrics libraries ✓

- [x] `request_tracing/metrics` — latency and counter emission
- [x] `request_tracing/record` — span accumulation interface
- [x] Integration test scenarios

### Phase 3 — composition through existing modules (future)

- [x] `traced_workflow` composes `request_tracing/record` for span recording
- [x] broaden span recording beyond the workflow demo handler where it adds real value
- [x] Entry point handlers compose `request_tracing/metrics` for trace emission
- [ ] Trace context propagation through `http_client` middleware
- [ ] OpenTelemetry-compatible trace format emission
- [ ] Log-phase emission via `js_log` handler pattern
- [ ] Optional Prometheus-aware sampling or emission policies using `$prometheus_requests_total` / `$prometheus_error_rate`

### Phase 4 — milestone 3 first-class ecosystem wiring

Goal: make tracing feel native to the rest of the repo by wiring the existing reusable tracing surface through the modules that already need it.

- [ ] compose `request_tracing/record` into documented `workflow` recipes and handler paths
- [ ] compose propagation through `http_client` middleware helpers so trace forwarding is easy to adopt consistently
- [ ] add runtime/API-facing summaries or debug surfaces only where they reuse the existing trace model cleanly
- [ ] keep `request_tracing` focused on trace context, propagation, and emission rather than growing a second workflow or metrics subsystem

## TDD plan

- [x] unit-test TraceContext construction and span addition
- [x] unit-test total_duration and summary
- [x] unit-test propagation_headers output
- [x] unit-test emit.json and emit.logfmt rendering
- [x] `tests/basic/` — 3 integration scenarios with simulated `$ngz_request_id`
- [x] `tests/workflow/` — traced workflow composition with stable propagated trace headers
- [x] `tests/requestid/` — native requestid integration, log emission, and correlation paths

## Verification checklist

- [x] `bun scripts/test.js request_tracing` — 15 unit tests pass
- [x] `bun test modules/request_tracing/tests/basic/do.test.js` — 3 integration tests pass
- [x] `bun test modules/request_tracing/tests/workflow/do.test.js` — 5 traced workflow integration tests pass
- [x] `bun test modules/request_tracing/tests/requestid/do.test.js` — native requestid integration passes (`make` required)

## Limitations

- **Span recording is only wired in workflow-style handlers.** `traced_workflow` and `traced_enrich` record spans today, but the simpler propagation/logging handlers still do not capture general spans.
- **No OpenTelemetry format.** Trace emission currently uses custom JSON/logfmt. OTLP-compatible format is a future item.
- **Log-phase emission is simulated.** The current handler emits trace lines via `http.log()` in the content phase. True log-phase emission requires a `js_log` handler pattern.
- **Session correlation requires auth_request.** The `traced_with_session` handler expects `$session_subject` to be set by a prior `auth_request` call.

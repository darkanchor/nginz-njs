# nginz_njs_request_tracing

Distributed tracing glue for the native `requestid` module. Reads `$ngz_request_id`, propagates headers to upstreams, records spans, and emits structured trace logs in Gleam.

## Roadmap position

Sprint 5 (observability + tracing) in Milestone 2 of `ROADMAP.md`. Depends on the native nginz `requestid` module. Composes with `workflow`, `http_client`, `metrics`, and `session`.

## Design goals

- read `$ngz_request_id` from the native requestid module
- propagate `X-Request-ID` and `X-Trace-ID` to upstream via `http_client` and `workflow` subrequests
- record spans through workflow steps for end-to-end latency tracking
- emit structured trace output (JSON or logfmt) in the log phase
- correlate request ID with session subject for debugging
- keep tracing pure and testable — the native module owns ID generation, this module owns propagation and emission

## Native dependency

Requires the nginz native `requestid` module (`make NGINZ_MODULES="requestid"`). The native module:

- Runs in ACCESS phase and sets `$ngz_request_id` to a UUIDv4 per request
- Handles the hot-path ID generation

This module runs in a later phase and reads `$ngz_request_id` to apply scripted tracing policy.

For integration tests without the native module, the variable can be simulated with `set $ngz_request_id "test-request-123"` directives (see `tests/basic/nginx.conf`).

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.traced` | `js_content` | Propagates X-Request-ID and X-Trace-ID headers, returns 204 |
| `main.traced_with_log` | `js_content` | Propagates headers and emits a structured JSON trace log line |
| `main.traced_with_session` | `js_content` | Propagates headers with session correlation for debugging |

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
    }
}
```

## Library modules

| Module | Purpose |
|---|---|
| `request_tracing/model` | `TraceContext`, `Span`, context builders, duration, summary |
| `request_tracing/propagate` | `propagation_headers` — builds X-Request-ID / X-Trace-ID header pairs |
| `request_tracing/record` | `record_span` — accumulates spans onto a TraceContext through workflow steps |
| `request_tracing/emit` | `json`, `logfmt` — structured trace line renderers |
| `request_tracing/metrics` | `latency_metric`, `traced_counter` — emits trace metrics to the `metrics` module |

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
- Internal helpers: `span_json`, `span_count_summary`

**`request_tracing/metrics.gleam`**
- `latency_metric(ctx, duration_ms, route)` — histogram-style latency metric
- `traced_counter(ctx, route)` — traced request counter

**`request_tracing/record.gleam`** (stub)
- `record_span(ctx, name, duration_ms, status)` — pipe-friendly span accumulator
- `record_result(ctx, name, status)` — records a span from a workflow step result

**`nginz_njs_request_tracing.gleam`** (njs entry point)
- 3 handlers: `traced`, `traced_with_log`, `traced_with_session`
- Reads `$ngz_request_id` (falls back to `$request_id`, then `"unknown"`)
- Uses `ngx.now()` via the `ngs` package for start time

**Integration tests**
- `tests/basic/` — 3 scenarios: header propagation, structured log emission, session correlation
- Simulates `$ngz_request_id` via `set` directive

## Cross-module composition

### workflow — span recording

Wrap workflow steps with span recording for end-to-end visibility:

```gleam
import request_tracing/record

let traced_step = record.record_result(ctx, "upstream_auth", step_result)
```

### http_client — header injection

Inject trace headers into upstream fetch calls:

```gleam
import request_tracing/propagate
import http_client/client

let headers = propagate.propagation_headers(ctx)
let req = client.new_get("https://api.example.test")
  |> client.with_headers(headers)
```

### metrics — trace emission

Emit trace metrics alongside other instrumentation:

```gleam
import request_tracing/metrics as rt_metrics
import metrics/line

let m = rt_metrics.traced_counter(ctx, "/api")
line.render_statsd(m)
// → "nginz.request_trace_total:1|c|#route:/api"
```

## Phased implementation plan

### Phase 1 — header propagation and emission ✓

- [x] `request_tracing/model` — TraceContext, Span, context builders
- [x] `request_tracing/propagate` — header injection for upstream propagation
- [x] `request_tracing/emit` — JSON and logfmt trace line renderers
- [x] Basic handlers: traced, traced_with_log, traced_with_session

### Phase 2 — span recording and metrics ✓

- [x] `request_tracing/metrics` — latency and counter emission
- [x] `request_tracing/record` — span accumulation stub
- [x] Integration test scenarios

### Phase 3 — full workflow integration (future)

- [ ] Span recording throughout workflow pipeline steps with automatic latency
- [ ] Trace context propagation through `http_client` middleware
- [ ] OpenTelemetry-compatible trace format emission
- [ ] Log-phase emission via `js_log` handler pattern

## TDD plan

- [x] unit-test TraceContext construction and span addition
- [x] unit-test total_duration and summary
- [x] unit-test propagation_headers output
- [x] unit-test emit.json and emit.logfmt rendering
- [x] unit-test metrics counter formatting
- [x] `tests/basic/` — 3 integration scenarios with simulated `$ngz_request_id`

## Verification checklist

- [x] `bun scripts/test.js request_tracing` — 10 unit tests pass
- [x] `bun test modules/request_tracing/tests/basic/do.test.js` — 3 integration tests pass
- [ ] `make NGINZ_MODULES="requestid" && bun run test:native` — native integration (requires native module)

## Limitations

- **Span recording is a stub.** The `record.gleam` module provides the interface but full workflow/pipeline integration is deferred to Phase 3.
- **No OpenTelemetry format.** Trace emission currently uses custom JSON/logfmt. OTLP-compatible format is a Phase 3 item.
- **Log-phase emission is simulated.** The current handler emits trace lines via `http.log()` in the content phase. True log-phase emission requires a `js_log` handler pattern.
- **Session correlation requires auth_request.** The `traced_with_session` handler expects `$session_subject` to be set by a prior `auth_request` call.

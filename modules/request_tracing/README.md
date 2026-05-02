# nginz_njs_request_tracing

Distributed tracing glue for the native `requestid` module. The pure tracing layer reads `$ngz_request_id`, propagates headers to upstreams, and emits structured trace logs in Gleam.

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
- `record_result(ctx, name, status)` — records a span from a workflow step result

**`nginz_njs_request_tracing.gleam`** (njs entry point)
- 3 handlers: `traced`, `traced_with_log`, `traced_with_session`
- Reads `$ngz_request_id` (falls back to `$request_id`, then `"unknown"`)
- Uses `ngx.now()` via the `ngs` package for start time
- Emits trace lines via `http.log()` in the content phase

**Integration tests**
- `tests/basic/` — 3 scenarios: header propagation, structured log emission, session correlation

## Cross-module composition

### workflow — span recording (library available)

The `request_tracing/record` module provides `record_result` for wrapping workflow steps. Current entry point handlers do not record spans; workflow integration is a future enhancement:

```gleam
import request_tracing/record

let traced_step = record.record_result(ctx, "upstream_auth", step_result)
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

The `request_tracing/metrics` module provides latency and counter metrics. Current entry point handlers do not emit metrics; instrumentation is a future enhancement:

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
- nginx handlers: traced, traced_with_log, traced_with_session variants
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

- [ ] Entry point handlers compose `request_tracing/record` for span recording
- [ ] Entry point handlers compose `request_tracing/metrics` for trace emission
- [ ] Trace context propagation through `http_client` middleware
- [ ] OpenTelemetry-compatible trace format emission
- [ ] Log-phase emission via `js_log` handler pattern
- [ ] Optional Prometheus-aware sampling or emission policies using `$prometheus_requests_total` / `$prometheus_error_rate`

## TDD plan

- [x] unit-test TraceContext construction and span addition
- [x] unit-test total_duration and summary
- [x] unit-test propagation_headers output
- [x] unit-test emit.json and emit.logfmt rendering
- [x] `tests/basic/` — 3 integration scenarios with simulated `$ngz_request_id`

## Verification checklist

- [x] `bun scripts/test.js request_tracing` — 10 unit tests pass
- [x] `bun test modules/request_tracing/tests/basic/do.test.js` — 3 integration tests pass
- [ ] `make NGINZ_MODULES="requestid" && bun run test:native` — native integration (requires native module)

## Limitations

- **Span recording not wired to handlers.** The `record.gleam` module provides the interface but entry point handlers do not record spans. Full workflow/pipeline integration is a future enhancement.
- **No OpenTelemetry format.** Trace emission currently uses custom JSON/logfmt. OTLP-compatible format is a future item.
- **Log-phase emission is simulated.** The current handler emits trace lines via `http.log()` in the content phase. True log-phase emission requires a `js_log` handler pattern.
- **Session correlation requires auth_request.** The `traced_with_session` handler expects `$session_subject` to be set by a prior `auth_request` call.

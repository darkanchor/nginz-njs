# nginz_njs_health_gateway

Scripted health aggregation and readiness gating. The pure policy layer parses `$health_backends` nginx variable and applies aggregation/gating logic in Gleam.

## Roadmap position

Sprint 5 (observability + tracing) in Milestone 2 of `ROADMAP.md`. Intended to compose with `workflow`, `http_client`, `mlcache`, `session`, and `feature_flags`.

## Design goals

- Parse `$health_backends` nginx variable to determine backend health status
- Provide readiness gating: block requests when all backends are unhealthy
- Render JSON health responses
- Keep health policy pure and testable

## Core abstractions

- `BackendHealth` — name, healthy, success_rate, consecutive_failures: the health status of a single backend
- `AggregateStatus` — `AllHealthy` | `Degraded(n, total)` | `AllUnhealthy`: the aggregated health across backends
- `GateDecision` — `Allow` | `Block(reason)`: the readiness decision for dispatch

The aggregator is side-effect free: it transforms backend health data into an aggregate status, and status into gate decisions. Health data fetching and HTTP response belong at the nginx adapter boundary.

## Scripted core vs optional native integration

### Scripted core

- Health aggregation: combining multiple backend statuses into `AggregateStatus`
- Readiness gating: mapping aggregate status to `GateDecision`
- Response rendering: JSON output for aggregate and readiness endpoints
- Reusable library surface: `model`, `response`, `gate`, `metrics`, `aggregate`, `cache` modules

### Optional native integration

- Native `healthcheck` module: provides `/health_status`, `/health_liveness`, `/health_readiness` JSON endpoints
- Native module probes backends on configured intervals

**Current implementation does not fetch from native module endpoints.** The entry point reads `$health_backends` as a simulated nginx variable. Future work should compose `http_client` for subrequest-based health fetching.

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.aggregate_health` | `js_content` | Returns JSON combining health status of all configured backends (parsed from `$health_backends`) |
| `main.readiness_gate` | `js_content` | Blocks (503) when all backends unhealthy, passes through otherwise |
| `main.custom_health` | `js_content` | Returns health JSON |

## nginx configuration

```nginx
http {
    js_engine qjs;
    js_path "njs/";
    js_import main from app.js;

    server {
        listen 8888;

        location /health/aggregate { js_content main.aggregate_health; }
        location /api/             { js_content main.readiness_gate; }
        location /health/custom    { js_content main.custom_health; }
    }
}
```

Response on healthy aggregate:
```json
{
  "status": "healthy",
  "backends": [
    {"name": "api", "healthy": true, "success_rate": 99, "consecutive_failures": 0},
    {"name": "db", "healthy": true, "success_rate": 100, "consecutive_failures": 0}
  ]
}
```

Response on readiness block:
```json
{"ready": false, "reason": "All backends are unhealthy"}
```

## Library modules

| Module | Purpose |
|---|---|
| `health_gateway/model` | `BackendHealth`, `AggregateStatus`, `GateDecision`, `aggregate`, `gate_decision` |
| `health_gateway/aggregate` | `fetch_aggregate` — http_client-based aggregation interface |
| `health_gateway/gate` | `can_dispatch`, `with_gate` — workflow step wrapper helpers |
| `health_gateway/response` | `aggregate_json`, `readiness_json` — JSON response renderers |
| `health_gateway/metrics` | `aggregate_counter`, `gate_counter` — health metrics |
| `health_gateway/cache` | `cached_health` — mlcache-based lookup interface |

## What is implemented

**`health_gateway/model.gleam`**
- `BackendHealth` — name, healthy, success_rate, consecutive_successes, consecutive_failures
- `AggregateStatus` — `AllHealthy` | `Degraded(healthy_count, total_count)` | `AllUnhealthy`
- `GateDecision` — `Allow` | `Block(reason)`
- `healthy_backend`, `unhealthy_backend` — constructors
- `aggregate(backends)` — computes aggregate status
- `gate_decision(status)` — maps aggregate status to allow/block

**`health_gateway/response.gleam`**
- `aggregate_json(status, backends)` — full health JSON response
- `backend_json(h)` — per-backend JSON
- `readiness_json(ready, reason)` — readiness gate JSON

**`health_gateway/metrics.gleam`**
- `aggregate_counter(status, route)` — health aggregate counter tagged by status
- `gate_counter(allowed, route)` — gate decision counter

**`health_gateway/gate.gleam`**
- `can_dispatch(status)` — boolean check for upstream dispatch
- `with_gate(status, value, fallback)` — guarded value selection

**`health_gateway/aggregate.gleam`**
- `fetch_aggregate(backends)` — interface for http_client-based aggregation (implementation deferred)

**`health_gateway/cache.gleam`**
- `cached_health(key)` — interface for mlcache-based lookup (implementation deferred)

**`nginz_njs_health_gateway.gleam`** (njs entry point)
- 3 handlers: `aggregate_health`, `readiness_gate`, `custom_health`
- Reads `$health_backends` variable as a comma-separated string (e.g., `"api=healthy,db=unhealthy"`)
- Parses the string and applies aggregation/gating logic

**Integration tests**
- `tests/basic/` — 8 scenarios: all healthy, all unhealthy, degraded, empty, gate healthy, gate unhealthy, custom healthy, custom unhealthy

## Cross-module composition

### workflow — health-aware routing (library available)

The `health_gateway/gate` module provides `can_dispatch` and `with_gate` for wrapping workflow steps:

```gleam
import health_gateway/gate
import workflow/pipeline

case gate.can_dispatch(status) {
  True -> pipeline.run_step(upstream_step, ctx)
  False -> Ok(fallback_response)
}
```

### mlcache — health caching (interface available)

The `health_gateway/cache` module provides the interface for mlcache-backed health lookup. Implementation is deferred to a future phase:

```gleam
import health_gateway/cache
import mlcache/shared
```

### metrics — health observability (library available)

The `health_gateway/metrics` module provides counters for health aggregate and gate decisions. Current entry point handlers do not emit metrics; instrumentation is a future enhancement:

```gleam
import health_gateway/metrics as hg_metrics
import metrics/line

let m = hg_metrics.aggregate_counter(status, "/health")
line.render_statsd(m)
```

### http_client — subrequest aggregation (future)

The `health_gateway/aggregate` module provides the interface for http_client-based health fetching from native module endpoints. Implementation is deferred to a future phase.

## Completion scope

`health_gateway` is complete for its core contract as a health aggregation and gating layer:

- Pure aggregation model: backend health list → `AggregateStatus` → `GateDecision`
- Response rendering: JSON output for aggregate and readiness endpoints
- nginx handlers: aggregate_health, readiness_gate, custom_health variants
- Integration test coverage for all handler variants

The `aggregate` and `cache` modules provide interfaces for future `http_client` and `mlcache` integration. Current entry point handlers read health data from nginx variables rather than fetching from native module endpoints.

## Phased implementation plan

### Phase 1 — model and response rendering ✓

- [x] `health_gateway/model` — BackendHealth, AggregateStatus, GateDecision, aggregate, gate_decision
- [x] `health_gateway/response` — JSON renderers for aggregate and readiness responses
- [x] Basic handlers: aggregate_health, readiness_gate, custom_health

### Phase 2 — metrics and gating ✓

- [x] `health_gateway/metrics` — aggregate counter and gate counter
- [x] `health_gateway/gate` — can_dispatch, with_gate wrappers
- [x] Integration test scenarios

### Phase 3 — subrequest aggregation and caching (interfaces available, implementation deferred)

- [x] `health_gateway/aggregate` — interface for http_client-based aggregation
- [x] `health_gateway/cache` — interface for mlcache-based lookup
- [ ] Implement `fetch_aggregate` with http_client subrequests
- [ ] Implement `cached_health` with mlcache/shared stale/hit/miss semantics
- [ ] Health-aware routing in workflow `first_ok` collectors

## TDD plan

- [x] unit-test BackendHealth construction
- [x] unit-test aggregate: all healthy, all unhealthy, degraded, empty
- [x] unit-test gate_decision: healthy → allow, degraded → allow, unhealthy → block
- [x] unit-test backend_summary formatting
- [x] unit-test aggregate_json and readiness_json rendering
- [x] `tests/basic/` — 8 integration scenarios with simulated `$health_backends`

## Verification checklist

- [x] `bun scripts/test.js health_gateway` — 19 unit tests pass
- [x] `bun test modules/health_gateway/tests/basic/do.test.js` — 8 integration tests pass
- [ ] `make NGINZ_MODULES="healthcheck" && bun run test:native` — native integration (requires native module)

## Limitations

- **Health data from nginx variables.** The entry point reads `$health_backends` as a simulated variable string. Production deployment with the native module should fetch health data from `/health_status` endpoints via `http_client`.
- **Aggregation implementation deferred.** The `aggregate.gleam` module provides the interface but subrequest-based fetching is not implemented.
- **Cache implementation deferred.** The `cache.gleam` module provides the interface but mlcache integration is not implemented.

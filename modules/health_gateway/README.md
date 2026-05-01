# nginz_njs_health_gateway

Scripted health aggregation, readiness gating, and custom health responses for the native `healthcheck` module. Reads health data via subrequests to `/health_status` endpoints and applies policy in Gleam.

## Roadmap position

Sprint 5 (observability + tracing) in Milestone 2 of `ROADMAP.md`. Depends on the native nginz `healthcheck` module. Composes with `workflow`, `http_client`, `mlcache`, `session`, and `feature_flags`.

## Design goals

- aggregate health across multiple backends via `http_client` subrequests
- provide readiness gating: block requests when all backends are unhealthy
- combine native healthcheck data with scripted signals (session, feature flags) into custom health responses
- cache backend health via `mlcache` to avoid probing on every request
- keep health policy pure and testable — the native module owns probing, this module owns aggregation and gating

## Native dependency

Requires the nginz native `healthcheck` module (`make NGINZ_MODULES="healthcheck"`). The native module:

- Exposes `/health_status`, `/health_liveness`, and `/health_readiness` JSON endpoints via subrequest
- Probes backend health on configured intervals
- Provides detailed health JSON for each probed backend

This module reads health data via subrequests to those endpoints and applies scripted aggregation, gating, and response shaping.

For integration tests without the native module, health data can be simulated with `set $health_backends "api=healthy,db=healthy"` directives (see `tests/basic/nginx.conf`).

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.aggregate_health` | `js_content` | Returns JSON combining health status of all configured backends |
| `main.readiness_gate` | `js_content` | Blocks (503) when all backends unhealthy, passes through otherwise |
| `main.custom_health` | `js_content` | Combines native healthcheck data with scripted signals |

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
| `health_gateway/aggregate` | `fetch_aggregate` — fetches health from multiple backends via http_client subrequests |
| `health_gateway/gate` | `can_dispatch`, `with_gate` — workflow step wrapper that skips unhealthy backends |
| `health_gateway/response` | `aggregate_json`, `readiness_json` — JSON response renderers |
| `health_gateway/metrics` | `aggregate_counter`, `gate_counter` — emits health metrics to the `metrics` module |
| `health_gateway/cache` | `cached_health` — caches health via mlcache (stale/hit/miss) |

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

**`health_gateway/aggregate.gleam`** (stub)
- `fetch_aggregate(backends)` — full subrequest-based aggregation deferred to Phase 2

**`health_gateway/gate.gleam`**
- `can_dispatch(status)` — boolean check for upstream dispatch
- `with_gate(status, value, fallback)` — guarded value selection

**`health_gateway/cache.gleam`** (stub)
- `cached_health(key)` — mlcache-backed lookup, currently returns Miss

**`nginz_njs_health_gateway.gleam`** (njs entry point)
- 3 handlers: `aggregate_health`, `readiness_gate`, `custom_health`
- Reads `$health_backends` variable (simulated in tests, real data from healthcheck subrequests in production)

**Integration tests**
- `tests/basic/` — 8 scenarios: all healthy, all unhealthy, degraded, empty, gate healthy, gate unhealthy, custom healthy, custom unhealthy
- Simulates `$health_backends` via `set` directive

## Cross-module composition

### workflow — health-aware routing

Skip unhealthy backends in workflow pipelines:

```gleam
import health_gateway/gate
import workflow/pipeline

case gate.can_dispatch(status) {
  True -> pipeline.run_step(upstream_step, ctx)
  False -> Ok(fallback_response)
}
```

### mlcache — health caching

Cache health to avoid probing on every request:

```gleam
import health_gateway/cache
import mlcache/shared
```

### metrics — health observability

Emit health check metrics alongside other instrumentation:

```gleam
import health_gateway/metrics as hg_metrics
import metrics/line

let m = hg_metrics.aggregate_counter(status, "/health")
line.render_statsd(m)
// → "nginz.health_gateway_aggregate_total:1|c|#status:healthy,route:/health"
```

## Phased implementation plan

### Phase 1 — model and response rendering ✓

- [x] `health_gateway/model` — BackendHealth, AggregateStatus, GateDecision, aggregate, gate_decision
- [x] `health_gateway/response` — JSON renderers for aggregate and readiness responses
- [x] Basic handlers: aggregate_health, readiness_gate, custom_health

### Phase 2 — metrics and gating ✓

- [x] `health_gateway/metrics` — aggregate counter and gate counter
- [x] `health_gateway/gate` — can_dispatch, with_gate wrappers
- [x] Integration test scenarios

### Phase 3 — subrequest aggregation and caching (future)

- [x] `health_gateway/aggregate` — stub for http_client-based aggregation
- [x] `health_gateway/cache` — stub for mlcache-based health caching
- [ ] Real subrequest-based health fetching with timeout and retry
- [ ] mlcache integration with stale/hit/miss semantics
- [ ] Health-aware routing in workflow `first_ok` collectors

## TDD plan

- [x] unit-test BackendHealth construction
- [x] unit-test aggregate: all healthy, all unhealthy, degraded, empty
- [x] unit-test gate_decision: healthy → allow, degraded → allow, unhealthy → block
- [x] unit-test backend_summary formatting
- [x] unit-test aggregate_json and readiness_json rendering
- [x] unit-test metrics counter formatting
- [x] `tests/basic/` — 8 integration scenarios with simulated `$health_backends`

## Verification checklist

- [x] `bun scripts/test.js health_gateway` — 19 unit tests pass
- [x] `bun test modules/health_gateway/tests/basic/do.test.js` — 8 integration tests pass
- [ ] `make NGINZ_MODULES="healthcheck" && bun run test:native` — native integration (requires native module)

## Limitations

- **Subrequest aggregation is a stub.** The `aggregate.gleam` module returns empty. Full `http_client`-based health fetching from `/health_status` endpoints is deferred to Phase 3.
- **Cache is a stub.** The `cache.gleam` module always returns `Miss`. Full `mlcache/shared` integration with stale/hit/miss semantics is deferred to Phase 3.
- **Health data comes from nginx variables.** In production, health data should come from subrequests to the native healthcheck module's JSON endpoints. The current entry point reads `$health_backends` as a simulated variable.
- **No scripted signal integration.** The `custom_health` handler currently delegates to `aggregate_health`. Combining session status and feature flag state into the health response is deferred.

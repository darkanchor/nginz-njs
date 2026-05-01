# nginz_njs_circuit_breaker_policy

Scripted circuit-breaker fallback, workflow recovery, and observability for the native `circuit-breaker` module. Reads `$ngz_circuit_state` and applies policy logic in Gleam.

## Roadmap position

Sprint 4 in Milestone 2 of `ROADMAP.md`. Depends on the native nginz `circuit-breaker` module which provides the shared-memory state machine and `$ngz_circuit_state`. This module provides the scripted policy layer on top.

## Design goals

- Read `$ngz_circuit_state` ("closed", "open", "half_open") from the native circuit-breaker module
- Serve custom fallback responses when circuit is open (JSON, HTML, plain text)
- Provide workflow integration: skip upstream calls and serve degraded responses when circuit is open
- Emit circuit state and fallback metrics via the `metrics` module
- Keep the policy layer pure and testable — the native module owns the state machine, this module owns the response and composition

## Native dependency

Requires the nginz native `circuit-breaker` module (`make NGINZ_MODULES="circuit-breaker"`). The native module:

- Runs in ACCESS phase and blocks requests when circuit is open
- Runs in LOG phase and records 5xx responses as failures
- Manages shared-memory state in `circuit_breaker_zone`
- Sets `$ngz_circuit_state` to "closed", "open", or "half_open"

This module runs in a later phase and reads `$ngz_circuit_state` to apply scripted policy beyond the native module's simple block/allow behavior.

For integration tests without the native module, the variable can be simulated with `set $ngz_circuit_state "open"` directives (see `tests/basic/nginx.conf`).

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.circuit_protected` | `js_content` | 204 on closed/half-open, 503 on open; logs state |
| `main.circuit_with_fallback` | `js_content` | JSON fallback body for open (service_unavailable) and half-open (service_degraded) |
| `main.circuit_json_error` | `js_content` | Auto-selects error body based on circuit state |

## nginx configuration

### Basic circuit-protected endpoint

```nginx
http {
    js_engine qjs;
    js_path "njs/";
    js_import main from app.js;

    # Shared memory for native circuit-breaker state
    # js_shared_dict_zone zone=circuit_breaker_zone:1m;

    server {
        listen 8080;

        location /api/ {
            circuit_breaker_threshold 5;
            circuit_breaker_success_threshold 2;
            circuit_breaker_timeout 30s;
            js_content main.circuit_protected;
        }
    }
}
```

### With custom fallback

```nginx
location /api/ {
    circuit_breaker_threshold 5;
    circuit_breaker_timeout 30s;
    js_content main.circuit_with_fallback;
}
```

Response when circuit is open:
```json
{
  "error": "service_unavailable",
  "message": "Service temporarily unavailable. Please retry.",
  "circuit": "open"
}
```

Response when half-open:
```json
{
  "error": "service_degraded",
  "message": "Service is recovering. Limited capacity.",
  "circuit": "half_open"
}
```

### Composing with workflow

Use `circuit_with_fallback` as the outermost handler, then use workflow steps internally. The circuit breaker gates the entire workflow:

```nginx
location /api/enriched {
    circuit_breaker_threshold 3;
    circuit_breaker_timeout 60s;
    js_content main.circuit_with_fallback;
}
```

Inside the njs handler, workflow steps can read `$ngz_circuit_state` to adjust behavior:
- Closed: run full pipeline
- Half-open: run reduced pipeline (fewer steps, shorter timeouts)
- Open: return fallback immediately

## Library modules

| Module | Purpose |
|---|---|
| `circuit_breaker_policy/model` | `CircuitState`, `CircuitContext`, `PolicyDecision`, `FallbackConfig`, context builders |
| `circuit_breaker_policy/fallback` | `json_error`, `json_degraded`, `html_error`, `text_error`, `auto_body` — error body renderers |
| `circuit_breaker_policy/metrics` | `state_counter`, `fallback_counter` — circuit state and fallback metrics |
| `circuit_breaker_policy/workflow` | `skip_when_open`, `with_circuit_fallback` — workflow step wrappers |

## What is implemented

**`circuit_breaker_policy/model.gleam`**
- `CircuitState` — `Closed` | `Open` | `HalfOpen` | `Unknown`
- `CircuitContext` — state + raw_state
- `PolicyDecision` — `PassThrough` | `ServeFallback` | `Block`
- `FallbackConfig` — status, content_type, log_fallback
- `parse_state`, `context`, `default_fallback`, `summary`

**`circuit_breaker_policy/fallback.gleam`**
- `json_error(message)` — 503 JSON with `circuit: "open"`
- `json_degraded(message)` — 503 JSON with `circuit: "half_open"`
- `html_error(message)` — HTML error page
- `text_error(message)` — plain text error
- `auto_body(ctx, message)` — returns `#(status, content_type, body)` based on circuit state

**`circuit_breaker_policy/metrics.gleam`**
- `state_counter(ctx, route)` — counter for circuit state observations
- `fallback_counter(ctx, route)` — counter for fallback decisions

**`circuit_breaker_policy/workflow.gleam`**
- `skip_when_open(step, fallback_body)` — skip step on 503, return fallback
- `with_circuit_fallback(step, fallback_body)` — recover from failures with fallback

**`nginz_njs_circuit_breaker_policy.gleam`** (njs entry point)
- 3 handler exports: circuit_protected, circuit_with_fallback, circuit_json_error

**Integration tests**
- `tests/basic/` — 9 scenarios: closed, open, half-open, unknown, fallback variants, JSON error

## Cross-module composition

### workflow — circuit-aware pipelines

Wrap workflow steps so circuit-open requests get degraded responses:

```gleam
import circuit_breaker_policy/workflow as cb_workflow

let safe_step = cb_workflow.with_circuit_fallback(upstream_step, cached_body)
```

### http_client — suppress retries when open

When circuit is open, `http_client` retry policies should be suppressed:

```gleam
// Don't retry when circuit is open — the native module already knows
// the backend is failing. Retrying adds load to an already-failing service.
```

### metrics — circuit state observability

Emit circuit state observations to the metrics module:

```gleam
import circuit_breaker_policy/metrics as cb_metrics
import metrics/line

let m = cb_metrics.state_counter(ctx, "/api")
line.render_statsd(m)
// → "nginz.circuit_breaker_state_total:1|c|#state:open,route:/api"
```

### mlcache — cached fallback responses

Cache successful upstream responses in `mlcache`. When circuit is open, serve the cached response as fallback instead of a static error body.

### authz — circuit-aware authorization

When circuit is open for a backend authorization service, the `authz` module's `remote_check` should fail open or closed based on policy. The circuit breaker state informs that decision.

## Phased implementation plan

### Phase 1 — read native variable and apply basic policy ✓

- [x] `circuit_breaker_policy/model` — parse `$ngz_circuit_state` into typed `CircuitState`
- [x] `circuit_breaker_policy/context` — build `CircuitContext` from nginx variable
- [x] Basic handler: 204 on closed/half-open, 503 on open

### Phase 2 — fallback bodies and error rendering ✓

- [x] `circuit_breaker_policy/fallback` — JSON, HTML, and plain text error body renderers
- [x] `circuit_with_fallback` handler — state-aware fallback responses
- [x] `circuit_json_error` handler — auto-select error body by state

### Phase 3 — metrics and workflow integration ✓

- [x] `circuit_breaker_policy/metrics` — state and fallback counters
- [x] `circuit_breaker_policy/workflow` — `skip_when_open` and `with_circuit_fallback` wrappers

### Phase 4 — advanced composition (future)

- [ ] Cached fallback: serve mlcache-cached response when circuit is open
- [ ] Half-open probe orchestration: route limited traffic through workflow
- [ ] Per-upstream circuit state tracking (multiple backends)
- [ ] Circuit state change notifications (requires native worker event bus)
- [ ] Dynamic threshold configuration via nginx variables

## TDD plan

- [x] unit-test `parse_state` for all variants
- [x] unit-test `context` construction from raw strings
- [x] unit-test `default_fallback` configuration
- [x] unit-test fallback body rendering (JSON, HTML, text, auto)
- [x] unit-test metrics counter formatting
- [x] `tests/basic/` — 9 integration scenarios with simulated variables

## Verification checklist

- [x] `bun scripts/test.js circuit_breaker_policy` — unit tests pass
- [x] `bun test modules/circuit_breaker_policy/tests/basic/do.test.js` — integration tests pass
- [ ] `make NGINZ_MODULES="circuit-breaker" && bun run test:native` — native integration (requires native module)

## Limitations

- **No dynamic threshold control.** Circuit breaker thresholds (failure count, success count, timeout) are set in nginx config by the native module. Scripted policy cannot change them at runtime.
- **Half-open probing is passive.** The native module allows a limited number of requests through in half-open state. Scripted policy cannot control the probe rate.
- **Fallback bodies are static.** Real deployments would want to serve cached responses from `mlcache` as fallback. This is a Phase 4 item.
- **No multi-backend circuit tracking.** The native module tracks one circuit per location. Multi-backend circuit composition requires multiple locations or a future native enhancement.

# nginz_njs_circuit_breaker_policy

Scripted circuit-breaker fallback for the native `circuit-breaker` module. The pure policy layer reads `$ngz_circuit_state` and serves custom fallback responses in Gleam.

## Roadmap position

Sprint 4 in Milestone 2 of `ROADMAP.md`. Depends on the native nginz `circuit-breaker` module which provides the shared-memory state machine and `$ngz_circuit_state`. This module provides the scripted policy layer on top.

## Design goals

- Read `$ngz_circuit_state` ("closed", "open", "half_open") from the native circuit-breaker module
- Serve custom fallback responses when circuit is open (JSON, HTML, plain text)
- Keep the policy layer pure and testable — the native module owns the state machine, this module owns the response

## Core abstractions

- `CircuitState` — `Closed` | `Open` | `HalfOpen` | `Unknown`: the typed state from the native module
- `CircuitContext` — state + raw_state: the full context for policy logic
- `PolicyDecision` — `PassThrough` | `ServeFallback` | `Block`: the action to apply based on circuit state
- `FallbackConfig` — status, content_type, log_fallback: configuration for fallback responses

The evaluator is side-effect free: it transforms the native module variable into a typed decision, and decisions into response bodies. Configuration lookup and HTTP response belong at the nginx adapter boundary.

## Scripted core vs optional native integration

### Scripted core

- Fallback response rendering: JSON, HTML, plain text variants
- State-aware policy: mapping native state to `PolicyDecision`
- Reusable library surface: `model`, `fallback`, `metrics`, `workflow` modules

### Optional native integration

- Native `circuit-breaker` module: provides `$ngz_circuit_state` via shared-memory state machine
- Native module runs in ACCESS phase (blocking) and LOG phase (recording failures)
- This module runs in CONTENT phase

The native module owns the hot-path state machine and failure counting. This module owns the fallback response layer.

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
- Handlers read `$ngz_circuit_state` and serve fallback bodies

**Integration tests**
- `tests/basic/` — 9 scenarios: closed, open, half-open, unknown, fallback variants, JSON error

## Cross-module composition

### workflow — circuit-aware pipelines (library available)

The `circuit_breaker_policy/workflow` module provides `with_circuit_fallback` for wrapping workflow steps. Current entry point handlers serve static fallback; workflow integration is a future enhancement:

```gleam
import circuit_breaker_policy/workflow as cb_workflow

let safe_step = cb_workflow.with_circuit_fallback(upstream_step, cached_body)
```

### metrics — state observability (library available)

The `circuit_breaker_policy/metrics` module provides counters for circuit state observations. Current entry point handlers do not emit metrics; instrumentation is a future enhancement:

```gleam
import circuit_breaker_policy/metrics as cb_metrics
import metrics/line

let m = cb_metrics.state_counter(ctx, "/api")
line.render_statsd(m)
```

### mlcache — cached fallback (future)

Cache successful upstream responses in `mlcache`. When circuit is open, serve the cached response as fallback instead of a static error body.

### authz — circuit-aware authorization (future)

When circuit is open for a backend authorization service, the `authz` module's `remote_check` should fail open or closed based on policy. The circuit breaker state informs that decision.

## Completion scope

`circuit_breaker_policy` is complete for its core contract as a fallback response layer:

- Pure policy model: `$ngz_circuit_state` → `PolicyDecision` → response
- Fallback rendering: JSON, HTML, plain text variants with state-aware selection
- nginx handlers: protected, with_fallback, json_error variants
- Integration test coverage for all handler variants

Future work focuses on composition through existing modules (`workflow`, `metrics`, `mlcache`) rather than new handler logic.

## Phased implementation plan

### Phase 1 — read native variable and apply basic policy ✓

- [x] `circuit_breaker_policy/model` — parse `$ngz_circuit_state` into typed `CircuitState`
- [x] Basic handler: 204 on closed/half-open, 503 on open

### Phase 2 — fallback bodies and error rendering ✓

- [x] `circuit_breaker_policy/fallback` — JSON, HTML, and plain text error body renderers
- [x] `circuit_with_fallback` handler — state-aware fallback responses
- [x] `circuit_json_error` handler — auto-select error body by state

### Phase 3 — composition through existing modules (future)

- [ ] Entry point handlers compose `circuit_breaker_policy/metrics` for state emission
- [ ] Entry point handlers compose `workflow` for step-level fallback
- [ ] Cached fallback via `mlcache` integration

### Phase 4 — advanced composition (future)

- [ ] Half-open probe orchestration: route limited traffic through workflow
- [ ] Per-upstream circuit state tracking (multiple backends)
- [ ] Dynamic threshold configuration via nginx variables

## TDD plan

- [x] unit-test `parse_state` for all variants
- [x] unit-test `context` construction from raw strings
- [x] unit-test `default_fallback` configuration
- [x] unit-test fallback body rendering (JSON, HTML, text, auto)
- [x] `tests/basic/` — 9 integration scenarios with simulated variables

## Verification checklist

- [x] `bun scripts/test.js circuit_breaker_policy` — unit tests pass
- [x] `bun test modules/circuit_breaker_policy/tests/basic/do.test.js` — integration tests pass
- [ ] `make NGINZ_MODULES="circuit-breaker" && bun run test:native` — native integration (requires native module)

## Limitations

- **Fallback bodies are static.** Handlers serve static error bodies. Full cached fallback requires `mlcache` integration.
- **No dynamic threshold control.** Circuit breaker thresholds (failure count, success count, timeout) are set in nginx config by the native module.
- **Half-open probing is passive.** The native module allows a limited number of requests through in half-open state. Scripted policy cannot control the probe rate.
- **No multi-backend circuit tracking.** The native module tracks one circuit per location. Multi-backend composition requires multiple locations.

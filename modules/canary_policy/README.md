# nginz_njs_canary_policy

Scripted canary routing policy for the native `canary` module. The pure policy layer reads `$ngz_canary` and applies header injection and logging in Gleam.

## Roadmap position

Sprint 4 in Milestone 2 of `ROADMAP.md`. Depends on the native nginz `canary` module which provides percentage/header-based routing decision and `$ngz_canary`. This module provides the scripted policy layer on top.

## Design goals

- Read `$ngz_canary` ("1" or "0") from the native canary module
- Inject `X-Canary` request and response headers for downstream visibility
- Keep the policy layer pure and testable — the native module owns routing, this module owns header injection and logging

## Core abstractions

- `CanaryDecision` — `Canary` | `Stable` | `Unknown`: the typed routing outcome from the native module
- `CanaryContext` — decision + extra_headers: the full context for policy logic
- `PolicyAction` — `Route` | `Override`: the action to apply based on canary status

The evaluator is side-effect free: it transforms the native module variable into a typed decision, and decisions into header injection. Configuration lookup and HTTP response belong at the nginx adapter boundary.

## Scripted core vs optional native integration

### Scripted core

- Header injection: `X-Canary` request and response headers
- Decision logging: observability for canary vs stable routing
- Reusable library surface: `model`, `feature_flags`, `session`, `metrics` modules

### Optional native integration

- Native `canary` module: provides `$ngz_canary` variable via percentage/header-based routing
- Native module runs in ACCESS phase; this module runs in CONTENT phase

The native module owns the hot-path routing decision. This module owns the response headers and observability layer.

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.canary_routed` | `js_content` | Injects `X-Canary` header, logs routing decision, returns 204 |
| `main.canary_tagged` | `js_content` | Adds `X-Canary` response header for downstream consumers |
| `main.canary_with_metrics` | `js_content` | Logs routing decision |

## nginx configuration

### Canary routing with header injection

```nginx
http {
    js_engine qjs;
    js_path "njs/";
    js_import main from app.js;

    server {
        listen 8080;

        # Native canary module routes; scripted policy adds headers
        location /api/ {
            canary_percentage "10";
            canary_header "X-Force-Canary" "true";
            js_content main.canary_routed;
        }
    }
}
```

### Response tagging for downstream visibility

```nginx
location /api/ {
    canary_percentage "10";
    js_content main.canary_tagged;
}
```

Response includes:
```
X-Canary: true
```

## Library modules

| Module | Purpose |
|---|---|
| `canary_policy/model` | `CanaryDecision`, `CanaryContext`, `PolicyAction`, context builders, header helpers |
| `canary_policy/feature_flags` | `FlagOverride`, `check_override` — canary-aware flag evaluation |
| `canary_policy/session` | `resolve_sticky`, `serialize/deserialize_decision` — session-sticky helpers |
| `canary_policy/metrics` | `decision_counter`, `canary_counter` — canary routing metrics |

## What is implemented

**`canary_policy/model.gleam`**
- `CanaryDecision` — `Canary` | `Stable` | `Unknown`
- `CanaryContext` — decision + extra_headers
- `PolicyAction` — `Route` | `Override`
- `parse_decision`, `context`, `with_headers`, `canary_headers`, `stable_headers`, `summary`

**`canary_policy/feature_flags.gleam`**
- `FlagOverride` — when (CanaryDecision), flag name, value
- `check_override(ctx, overrides)` — find matching override for current canary decision
- `canary_flag`, `stable_flag` — constructors

**`canary_policy/session.gleam`**
- `resolve_sticky(ctx, stored_assignment)` — return stored decision or current
- `serialize_decision`, `deserialize_decision` — session storage helpers
- `canary_session_key` — constant key for session store

**`canary_policy/metrics.gleam`**
- `decision_counter(ctx, route)` — counter for canary/stable decisions
- `canary_counter(route)` — counter for canary-routed requests only

**`nginz_njs_canary_policy.gleam`** (njs entry point)
- 3 handler exports: canary_routed, canary_tagged, canary_with_metrics
- Handlers read `$ngz_canary`, set `X-Canary` header, and log the decision

**Integration tests**
- `tests/basic/` — 6 scenarios: canary, stable, unknown, tagged, metrics

## Cross-module composition

### feature_flags — canary-aware evaluation (library available)

The `canary_policy/feature_flags` module provides `check_override` for canary-aware flag evaluation. Current entry point handlers do not use this; flag integration is a future enhancement:

```gleam
import canary_policy/feature_flags

let overrides = [
  feature_flags.canary_flag("new_ui", "true"),
  feature_flags.stable_flag("new_ui", "false"),
]
feature_flags.check_override(ctx, overrides)
```

### session — sticky canary assignment (library available)

The `canary_policy/session` module provides `resolve_sticky` for session-backed canary assignment. Current entry point handlers do not persist assignments; session integration is a future enhancement:

```gleam
import canary_policy/session as canary_session

let assignment = canary_session.resolve_sticky(ctx, stored_from_session)
```

### metrics — routing observability (library available)

The `canary_policy/metrics` module provides counters for canary/stable decisions. Current entry point handlers do not emit metrics; instrumentation is a future enhancement:

```gleam
import canary_policy/metrics as canary_metrics
import metrics/line

let m = canary_metrics.decision_counter(ctx, "/api")
line.render_statsd(m)
```

### response_transform — canary-specific shaping (future)

Apply different `response_transform` plans for canary vs stable responses. For example, add a canary indicator to the response body for canary users.

## Completion scope

`canary_policy` is complete for its core contract as a header injection layer:

- Pure policy model: `$ngz_canary` → `CanaryDecision` → headers
- Header injection: `X-Canary` request and response headers
- Decision logging: observability for routing outcomes
- nginx handlers: routed, tagged, with_metrics variants
- Integration test coverage for all handler variants

Future work focuses on composition through existing modules (`feature_flags`, `session`, `metrics`) rather than new handler logic.

## Phased implementation plan

### Phase 1 — read native variable and inject headers ✓

- [x] `canary_policy/model` — parse `$ngz_canary` into typed `CanaryDecision`
- [x] Basic handler: inject `X-Canary` header, log decision

### Phase 2 — response tagging ✓

- [x] `canary_tagged` handler — response header injection

### Phase 3 — composition through existing modules (future)

- [ ] Entry point handlers compose `canary_policy/feature_flags` for flag overrides
- [ ] Entry point handlers compose `canary_policy/session` for sticky assignment
- [ ] Entry point handlers compose `canary_policy/metrics` for decision emission

### Phase 4 — advanced composition (future)

- [ ] Dynamic canary percentage override in scripted policy
- [ ] Canary-specific response body transformation via `response_transform`
- [ ] A/B test assignment integration (canary → bucket mapping)

## TDD plan

- [x] unit-test `parse_decision` for all variants
- [x] unit-test `context` construction and header helpers
- [x] unit-test `check_override` matching logic
- [x] unit-test `resolve_sticky` with stored/no-session cases
- [x] unit-test `serialize/deserialize_decision` round-trip
- [x] `tests/basic/` — 6 integration scenarios with simulated variables

## Verification checklist

- [x] `bun scripts/test.js canary_policy` — unit tests pass
- [x] `bun test modules/canary_policy/tests/basic/do.test.js` — integration tests pass
- [ ] `make NGINZ_MODULES="canary" && bun run test:native` — native integration (requires native module)

## Limitations

- **Handlers are thin.** Current handlers read `$ngz_canary`, set `X-Canary` header, and log. Library modules provide additional capabilities not yet composed into handlers.
- **No dynamic percentage control.** The canary percentage is set in nginx config by the native module. Scripted policy cannot change it at runtime.

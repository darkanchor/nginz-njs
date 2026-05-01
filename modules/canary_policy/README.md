# nginz_njs_canary_policy

Scripted canary routing policy for the native `canary` module. Reads `$ngz_canary` and applies header injection, session-sticky assignment, feature flag overrides, and metrics emission in Gleam.

## Roadmap position

Sprint 4 in Milestone 2 of `ROADMAP.md`. Depends on the native nginz `canary` module which provides the percentage/header-based routing decision and `$ngz_canary`. This module provides the scripted policy layer on top.

## Design goals

- Read `$ngz_canary` ("1" or "0") from the native canary module
- Inject `X-Canary` request and response headers for downstream visibility
- Provide session-sticky canary: once assigned to canary, stay on canary
- Integrate with `feature_flags`: canary users get different flag evaluations
- Emit canary vs stable routing metrics via the `metrics` module
- Keep the policy layer pure and testable — the native module owns routing, this module owns the response and observability

## Native dependency

Requires the nginz native `canary` module (`make NGINZ_MODULES="canary"`). The native module:

- Runs in ACCESS phase and sets `$ngz_canary` to "1" (canary) or "0" (stable)
- Routes to different upstreams based on percentage and/or header match
- Handles the hot-path routing decision

This module runs in a later phase and reads `$ngz_canary` to apply scripted policy.

For integration tests without the native module, the variable can be simulated with `set $ngz_canary "1"` directives (see `tests/basic/nginx.conf`).

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.canary_routed` | `js_content` | Injects `X-Canary` header, logs routing decision, returns 204 |
| `main.canary_tagged` | `js_content` | Adds `X-Canary` response header for downstream consumers |
| `main.canary_with_metrics` | `js_content` | Canary routing with metrics emission |

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

### Canary-aware feature flags

Combine with the `feature_flags` module for canary-specific flag evaluations:

```nginx
location /api/ {
    canary_percentage "10";
    set $ff_key_type session;
    js_content main.canary_routed;
}
```

When `$ngz_canary` is "1", feature flags can enable experimental features for canary users.

## Library modules

| Module | Purpose |
|---|---|
| `canary_policy/model` | `CanaryDecision`, `CanaryContext`, `PolicyAction`, context builders, header helpers |
| `canary_policy/feature_flags` | `FlagOverride`, `check_override` — canary-aware flag evaluation |
| `canary_policy/session` | `resolve_sticky`, `serialize/deserialize_decision` — session-sticky canary assignment |
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

**Integration tests**
- `tests/basic/` — 6 scenarios: canary, stable, unknown, tagged, metrics

## Cross-module composition

### feature_flags — canary-aware evaluation

When `$ngz_canary` is "1", feature flags can return different values for canary users:

```gleam
import canary_policy/feature_flags

let overrides = [
  feature_flags.canary_flag("new_ui", "true"),
  feature_flags.stable_flag("new_ui", "false"),
]
feature_flags.check_override(ctx, overrides)
```

### session — sticky canary

Persist canary assignment in the session so users stay on canary across requests:

```gleam
import canary_policy/session as canary_session

let assignment = canary_session.resolve_sticky(ctx, stored_from_session)
// If session has "canary", use canary even if native module says stable
```

### metrics — routing observability

Emit canary routing decisions to the metrics module:

```gleam
import canary_policy/metrics as canary_metrics
import metrics/line

let m = canary_metrics.decision_counter(ctx, "/api")
line.render_statsd(m)
// → "nginz.canary_decision_total:1|c|#decision:canary,route:/api"
```

### response_transform — canary-specific response shaping

Apply different `response_transform` plans for canary vs stable responses. For example, add a canary indicator to the response body for canary users.

## Phased implementation plan

### Phase 1 — read native variable and inject headers ✓

- [x] `canary_policy/model` — parse `$ngz_canary` into typed `CanaryDecision`
- [x] `canary_policy/context` — build `CanaryContext` from nginx variable
- [x] Basic handler: inject `X-Canary` header, log decision

### Phase 2 — response tagging and metrics ✓

- [x] `canary_policy/metrics` — decision and canary counters
- [x] `canary_tagged` handler — response header injection
- [x] `canary_with_metrics` handler — routing with metrics

### Phase 3 — feature flag and session integration ✓

- [x] `canary_policy/feature_flags` — canary-aware flag overrides
- [x] `canary_policy/session` — sticky canary assignment via session store

### Phase 4 — advanced composition (future)

- [ ] Dynamic canary percentage override in scripted policy
- [ ] Canary-specific response body transformation
- [ ] A/B test assignment integration (canary → bucket mapping)
- [ ] Canary routing metrics dashboard recipe

## TDD plan

- [x] unit-test `parse_decision` for all variants
- [x] unit-test `context` construction and header helpers
- [x] unit-test `check_override` matching logic
- [x] unit-test `resolve_sticky` with stored/no-session cases
- [x] unit-test `serialize/deserialize_decision` round-trip
- [x] unit-test metrics counter formatting
- [x] `tests/basic/` — 6 integration scenarios with simulated variables

## Verification checklist

- [x] `bun scripts/test.js canary_policy` — unit tests pass
- [x] `bun test modules/canary_policy/tests/basic/do.test.js` — integration tests pass
- [ ] `make NGINZ_MODULES="canary" && bun run test:native` — native integration (requires native module)

## Limitations

- **No dynamic percentage control.** The canary percentage is set in nginx config by the native module. Scripted policy cannot change it at runtime.
- **Feature flag overrides are declarative.** Overrides are checked against a static list, not fetched from a dynamic source. Dynamic overrides would require `feature_flags` state integration.
- **Session-sticky is best-effort.** If the session store is unavailable, the native module's routing decision is used as-is.

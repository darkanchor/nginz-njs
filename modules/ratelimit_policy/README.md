# nginz_njs_ratelimit_policy

Scripted rate-limit response shaping and header injection for the native `ratelimit` module. The pure policy layer reads `$ratelimit_result` and related nginx variables, then applies Gleam types to shape responses with standard headers and custom error bodies.

## Roadmap position

Sprint 4 in Milestone 2 of `ROADMAP.md`. Depends on the native nginz `ratelimit` module which provides counter logic and `$ratelimit_*` variables. This module provides the scripted policy layer on top.

## Design goals

- Read `$ratelimit_result`, `$ratelimit_key`, `$ratelimit_source`, `$ratelimit_cost` from the native ratelimit module
- Inject standard rate limit headers (`X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`, `Retry-After`) on every response
- Render custom JSON/HTML/plain-text error bodies for 429 responses
- Keep the policy layer pure and testable — the native module owns counters, this module owns response shaping

## Core abstractions

- `RateLimitResult` — `Allowed` | `Denied` | `Unknown`: the typed outcome from the native module
- `RateLimitContext` — result, key, source, cost: the full decision context for policy logic
- `RateLimitHeaders` — limit, remaining, reset, retry_after: header values as pure data
- `PolicyDecision` — `PassThrough` | `InjectHeaders` | `DenyWith`: the policy action to apply

The evaluator is side-effect free: it transforms native module variables into typed decisions, and decisions into response shapes. Configuration lookup and HTTP response belong at the nginx adapter boundary.

## Scripted core vs optional native integration

### Scripted core

- Response shaping: header injection, error body rendering
- Policy composition: mapping native result to `PolicyDecision`
- Reusable library surface: `model`, `headers`, `response` modules

### Optional native integration

- Native `ratelimit` module: provides `$ratelimit_*` variables via shared-memory counters
- Native module runs in ACCESS phase; this module runs in CONTENT phase

The native module owns the hot-path counter logic and decision. This module owns the response and observability layer.

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.rate_limited` | `js_content` | Basic: 204 on allow, 429 on deny; logs context |
| `main.rate_limited_with_headers` | `js_content` | Injects `X-RateLimit-*` and `Retry-After` headers |
| `main.rate_limited_custom_error` | `js_content` | Deny returns JSON error body with `retry_after` field |
| `main.rate_limited_with_fallback` | `js_content` | Deny serves static degraded response |

## nginx configuration

### Basic rate-limited endpoint

```nginx
http {
    js_engine qjs;
    js_path "njs/";
    js_import main from app.js;

    server {
        listen 8080;

        location /api/ {
            ratelimit_rate "100r/s";
            ratelimit_burst "50";
            ratelimit_key "$remote_addr";
            js_content main.rate_limited;
        }
    }
}
```

### With standard headers

```nginx
location /api/ {
    ratelimit_rate "100r/s";
    ratelimit_key "$remote_addr";
    js_content main.rate_limited_with_headers;
}
```

Response on deny:
```
HTTP/1.1 429 Too Many Requests
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 60
Retry-After: 60
```

### With custom JSON error

```nginx
location /api/ {
    ratelimit_rate "100r/s";
    ratelimit_key "$remote_addr";
    js_content main.rate_limited_custom_error;
}
```

Response on deny:
```json
{
  "error": "too_many_requests",
  "message": "Rate limit exceeded. Please retry later.",
  "retry_after": 60
}
```

### Rate limiting by JWT claim

The native ratelimit module supports any nginx variable as a key. Combine with the JWT module for per-user rate limiting:

```nginx
location /api/ {
    jwt_secret "your-secret";
    jwt_claim $jwt_sub sub;
    ratelimit_rate "1000r/s";
    ratelimit_key "$jwt_sub";
    js_content main.rate_limited_with_headers;
}
```

## Library modules

| Module | Purpose |
|---|---|
| `ratelimit_policy/model` | `RateLimitResult`, `RateLimitContext`, `PolicyDecision`, `RateLimitHeaders`, context builders |
| `ratelimit_policy/headers` | `render_all` — builds `X-RateLimit-*` / `Retry-After` header pairs from `RateLimitHeaders` |
| `ratelimit_policy/response` | `json_error`, `html_error`, `text_error` — error body renderers for 429 responses |

## What is implemented

**`ratelimit_policy/model.gleam`**
- `RateLimitResult` — `Allowed` | `Denied` | `Unknown`
- `RateLimitContext` — result, key, source, cost
- `PolicyDecision` — `PassThrough` | `InjectHeaders` | `DenyWith`
- `RateLimitHeaders` — limit, remaining, reset, retry_after (all `Option(String)`)
- `parse_result`, `context`, `deny_headers`, `allow_headers`, `default_error_body`, `summary`

**`ratelimit_policy/headers.gleam`**
- `render_all(headers)` — returns `List(#(String, String))` of present header pairs

**`ratelimit_policy/response.gleam`**
- `json_error(message, retry_after)` — JSON error body
- `html_error(message, retry_after)` — HTML error page
- `text_error(message)` — plain text error

**`nginz_njs_ratelimit_policy.gleam`** (njs entry point)
- 4 handler exports covering basic, headers, custom error, and fallback patterns
- Handlers read nginx variables, apply pure policy functions, and write HTTP responses

**Integration tests**
- `tests/basic/` — 7 scenarios: allowed, denied, unknown, headers on allow/deny, custom error, fallback

## Cross-module composition

### authz — rate limit by identity

When combined with the JWT module, rate limit by `$jwt_claim_sub` instead of IP:

```nginx
ratelimit_key "$jwt_sub";
```

The scripted layer doesn't need to change — the native module handles key resolution.

### workflow — degraded-mode fallback (library available)

The `ratelimit_policy/workflow` module provides `with_rate_limit_fallback` for wrapping workflow steps. Current entry point handlers use static fallback; workflow integration is a future enhancement:

```gleam
import ratelimit_policy/workflow as rl_workflow

let safe_step = rl_workflow.with_rate_limit_fallback(upstream_step, cached_body)
```

### metrics — decision emission (library available)

The `ratelimit_policy/metrics` module provides counters for allowed/denied decisions. Current entry point handlers do not emit metrics; instrumentation is a future enhancement:

```gleam
import ratelimit_policy/metrics as rl_metrics
import metrics/line

let m = rl_metrics.decision_counter(ctx, "/api")
line.render_statsd(m)
```

## Completion scope

`ratelimit_policy` is complete for its core contract as a response-shaping layer:

- Pure policy model: `RateLimitResult` → `PolicyDecision` → response
- Header injection: `X-RateLimit-*` and `Retry-After` rendering
- Error body rendering: JSON, HTML, plain text variants
- nginx handlers: basic, headers, custom error, fallback patterns
- Integration test coverage for all handler variants

Future work focuses on composition through existing modules (`workflow`, `metrics`) rather than new handler logic.

## Phased implementation plan

### Phase 1 — read native variables and apply basic policy ✓

- [x] `ratelimit_policy/model` — parse `$ratelimit_result` into typed `RateLimitResult`
- [x] Basic handler: 204 on allow, 429 on deny

### Phase 2 — header injection and error bodies ✓

- [x] `ratelimit_policy/headers` — `X-RateLimit-*` and `Retry-After` header construction
- [x] `ratelimit_policy/response` — JSON, HTML, and plain text error body renderers
- [x] `rate_limited_with_headers` and `rate_limited_custom_error` handlers

### Phase 3 — composition through existing modules (future)

- [ ] Entry point handlers compose `ratelimit_policy/metrics` for decision emission
- [ ] Entry point handlers compose `workflow` for subrequest-based fallback
- [ ] Dynamic remaining/reset calculation from native module context

### Phase 4 — advanced policy (future)

- [ ] Per-key quota tracking via `mlcache`
- [ ] Rate limit policy rules: different limits for different paths/claims

## TDD plan

- [x] unit-test `parse_result` for all variants
- [x] unit-test `context` construction from raw strings
- [x] unit-test header rendering (denied, allowed, empty)
- [x] unit-test error body rendering (JSON, HTML, text)
- [x] `tests/basic/` — 7 integration scenarios with simulated variables

## Verification checklist

- [x] `bun scripts/test.js ratelimit_policy` — unit tests pass
- [x] `bun test modules/ratelimit_policy/tests/basic/do.test.js` — integration tests pass
- [ ] `make NGINZ_MODULES="ratelimit" && bun run test:native` — native integration (requires native module)

## Limitations

- **Header values are static.** `X-RateLimit-Limit` and `X-RateLimit-Remaining` use placeholder values (100, 99). Dynamic calculation requires the native module to expose remaining quota as a variable.
- **Fallback is static.** `rate_limited_with_fallback` returns a static degraded body. Full subrequest-based fallback requires composition through `workflow`.
- **No per-path policy.** All locations share the same rate limit policy. Per-path or per-claim differentiated limits are a Phase 4 item.

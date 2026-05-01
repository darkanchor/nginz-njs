# nginz_njs_ratelimit_policy

Scripted rate-limit response shaping, header injection, metrics, and policy composition for the native `ratelimit` module. Reads the native module's nginx variables and applies policy logic in Gleam.

## Roadmap position

Sprint 4 in Milestone 2 of `ROADMAP.md`. Depends on the native nginz `ratelimit` module which provides the counter logic and `$ratelimit_*` variables. This module provides the scripted policy layer on top.

## Design goals

- Read `$ratelimit_result`, `$ratelimit_key`, `$ratelimit_source`, `$ratelimit_cost` from the native ratelimit module
- Inject standard rate limit headers (`X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`, `Retry-After`) on every response
- Render custom JSON/HTML/plain-text error bodies for 429 responses
- Emit rate limit decision metrics via the `metrics` module
- Provide workflow integration: degraded-mode fallback when rate-limited
- Keep the policy layer pure and testable — the native module owns counters, this module owns response shaping

## Native dependency

Requires the nginz native `ratelimit` module (`make NGINZ_MODULES="ratelimit"`). The native module:

- Runs in ACCESS phase and sets `$ratelimit_result`, `$ratelimit_key`, `$ratelimit_source`, `$ratelimit_cost`
- Manages shared-memory counters in `ratelimit_zone`
- Handles the hot-path rate limit decision

This module runs in a later phase (CONTENT/LOG) and reads those variables to apply scripted policy.

For integration tests without the native module, variables can be simulated with `set $ratelimit_result "allowed"` directives (see `tests/basic/nginx.conf`).

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.rate_limited` | `js_content` | Basic: 204 on allow, 429 on deny; logs context |
| `main.rate_limited_with_headers` | `js_content` | Injects `X-RateLimit-*` and `Retry-After` headers |
| `main.rate_limited_custom_error` | `js_content` | Deny returns JSON error body with `retry_after` field |
| `main.rate_limited_with_fallback` | `js_content` | Deny serves degraded response from `$ratelimit_fallback_path` |

## nginx configuration

### Basic rate-limited endpoint

```nginx
http {
    js_engine qjs;
    js_path "njs/";
    js_import main from app.js;

    # Shared memory for native ratelimit counters
    js_shared_dict_zone zone=ratelimit_zone:1m timeout=1h;

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

### With workflow fallback

```nginx
location /api/ {
    ratelimit_rate "100r/s";
    ratelimit_key "$remote_addr";
    set $ratelimit_fallback_path "/internal/degraded";
    js_content main.rate_limited_with_fallback;
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
| `ratelimit_policy/metrics` | `decision_counter`, `denied_counter` — emits rate limit metrics to the `metrics` module |
| `ratelimit_policy/workflow` | `with_rate_limit_fallback` — wraps a workflow step to serve degraded response on 429 |

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

**`ratelimit_policy/metrics.gleam`**
- `decision_counter(ctx, route)` — counter for allowed/denied decisions
- `denied_counter(ctx, route)` — counter for denied requests only

**`ratelimit_policy/workflow.gleam`**
- `with_rate_limit_fallback(step, fallback_body)` — replaces 429 upstream responses with fallback body

**`nginz_njs_ratelimit_policy.gleam`** (njs entry point)
- 4 handler exports covering basic, headers, custom error, and fallback patterns

**Integration tests**
- `tests/basic/` — 7 scenarios: allowed, denied, unknown, headers on allow/deny, custom error, fallback

## Cross-module composition

### metrics — decision emission

The `ratelimit_policy/metrics` module emits counters to `metrics` for every rate limit decision. Compose in a log-phase handler:

```gleam
import ratelimit_policy/metrics as rl_metrics
import metrics/line

let m = rl_metrics.decision_counter(ctx, "/api")
line.render_statsd(m)
// → "nginz.ratelimit_decision_total:1|c|#result:denied,source:ip,route:/api"
```

### workflow — degraded-mode fallback

Wrap a workflow step so rate-limited requests get a cached or degraded response:

```gleam
import ratelimit_policy/workflow as rl_workflow

let safe_step = rl_workflow.with_rate_limit_fallback(upstream_step, cached_body)
```

### authz — rate limit by identity

When combined with the JWT module, rate limit by `$jwt_claim_sub` instead of IP:

```nginx
ratelimit_key "$jwt_sub";
```

The scripted layer doesn't need to change — the native module handles key resolution.

## Phased implementation plan

### Phase 1 — read native variables and apply basic policy ✓

- [x] `ratelimit_policy/model` — parse `$ratelimit_result` into typed `RateLimitResult`
- [x] `ratelimit_policy/context` — build `RateLimitContext` from nginx variables
- [x] Basic handler: 204 on allow, 429 on deny

### Phase 2 — header injection and error bodies ✓

- [x] `ratelimit_policy/headers` — `X-RateLimit-*` and `Retry-After` header construction
- [x] `ratelimit_policy/response` — JSON, HTML, and plain text error body renderers
- [x] `rate_limited_with_headers` and `rate_limited_custom_error` handlers

### Phase 3 — metrics and workflow integration ✓

- [x] `ratelimit_policy/metrics` — decision and denied counters
- [x] `ratelimit_policy/workflow` — `with_rate_limit_fallback` wrapper
- [x] `rate_limited_with_fallback` handler

### Phase 4 — advanced composition (future)

- [ ] Dynamic remaining/reset calculation from native module context
- [ ] Per-key quota tracking via `mlcache`
- [ ] Rate limit policy rules: different limits for different paths/claims
- [ ] Workflow step that checks rate limit before dispatching

## TDD plan

- [x] unit-test `parse_result` for all variants
- [x] unit-test `context` construction from raw strings
- [x] unit-test header rendering (denied, allowed, empty)
- [x] unit-test error body rendering (JSON, HTML, text)
- [x] unit-test metrics counter formatting
- [x] `tests/basic/` — 7 integration scenarios with simulated variables

## Verification checklist

- [x] `bun scripts/test.js ratelimit_policy` — unit tests pass
- [x] `bun test modules/ratelimit_policy/tests/basic/do.test.js` — integration tests pass
- [ ] `make NGINZ_MODULES="ratelimit" && bun run test:native` — native integration (requires native module)

## Limitations

- **Header values are static.** `X-RateLimit-Limit` and `X-RateLimit-Remaining` use placeholder values (100, 99). Dynamic calculation requires the native module to expose remaining quota as a variable, which it does not yet do.
- **Fallback is simulated.** `rate_limited_with_fallback` currently returns a static degraded body. Full subrequest-based fallback (`workflow/pipeline.fetch_step`) requires the native ratelimit module to run before the content phase handler.
- **No per-path policy.** All locations share the same rate limit policy. Per-path or per-claim differentiated limits are a Phase 4 item.

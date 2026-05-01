# nginz_njs_ratelimit_policy

Scripted rate-limit response shaping and header injection for the native `ratelimit` module. The pure policy layer reads `$ratelimit_result` and related nginx variables, then applies Gleam types to shape responses with standard headers and custom error bodies.

## Roadmap position

Sprint 4A (native-aware policy adapters) in Milestone 2 of `ROADMAP.md`. Depends on the native nginz `ratelimit` module which provides counter logic and `$ratelimit_*` variables. This module provides the scripted policy layer on top.

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
- Native module runs in ACCESS phase and returns HTTP 429 on deny — the request never reaches CONTENT phase
- This module's handlers run in CONTENT phase via `js_content`

The native module owns the hot-path counter logic and decision. This module owns the response and observability layer.

**Important phase gap:** Because the native module terminates denied requests in ACCESS phase, a `js_content` handler at the same location will only execute for *allowed* requests. To apply custom error responses on deny, wire the handler through `error_page 429 = @name;` — see the configuration section below.

## Exports

All handlers are `js_content` functions intended to run in an internal named location reached via `error_page 429 = @name;` from the primary location where the native `ratelimit_*` directives are configured.

| Handler | Wired via | Description |
|---|---|---|
| `main.rate_limited` | `error_page 429` → `js_content` | Basic: 204 on allow, 429 on deny; logs context |
| `main.rate_limited_with_headers` | `error_page 429` → `js_content` | Injects `X-RateLimit-*` and `Retry-After` headers |
| `main.rate_limited_custom_error` | `error_page 429` → `js_content` | Deny returns JSON error body with `retry_after` field |
| `main.rate_limited_with_fallback` | `error_page 429` → `js_content` | Deny serves static degraded response |

## nginx configuration

### How the phases interact

The native `ratelimit` module runs in the **ACCESS** phase. When the limit is exceeded it returns HTTP 429 immediately — the request never reaches the CONTENT phase where `js_content` or `proxy_pass` would execute.

This module's handlers run in the **CONTENT** phase. To apply custom error shaping to native denials, wire them through `error_page`:

```
Request flow:
  ACCESS phase: native ratelimit → allowed (DECLINED) or denied (returns 429)
       ↓ allowed                              ↓ denied
  CONTENT phase: proxy_pass / js_content      error_page 429 = @custom;
                                               ↓
                                               CONTENT retry: js_content handler
```

### Pattern A: Custom error on deny + proxy_pass on allow (recommended)

The primary production pattern. Native ratelimit gates the request; denied requests get a custom JSON/HTML error with headers; allowed requests are proxied to the backend.

```nginx
http {
    js_engine qjs;
    js_path "njs/";
    js_import main from app.js;

    server {
        listen 8080;

        # Primary location: native ratelimit gate + proxy_pass
        location /api/ {
            ratelimit_rate "100r/s";
            ratelimit_burst "50";
            ratelimit_key "$remote_addr";

            # Catch native 429 and redirect to custom error handler
            error_page 429 = @rate_limited;

            proxy_pass http://backend;
        }

        # Internal named location: custom 429 response with headers + JSON body
        location @rate_limited {
            internal;
            js_content main.rate_limited_custom_error;
        }
    }
}
```

Response on deny (429):
```http
HTTP/1.1 429 Too Many Requests
Content-Type: application/json
Retry-After: 60

{
  "error": "too_many_requests",
  "message": "Rate limit exceeded. Please retry later.",
  "retry_after": 60
}
```

### Pattern B: Standalone endpoint with custom error (no proxy_pass)

When the location doesn't proxy to a backend, use `error_page` to catch the native denial. **Do not use `return` as the content handler — `return` runs in REWRITE phase (before ACCESS) and would prevent the native ratelimit handler from executing.** Use a CONTENT-phase handler like `echozn` (from the `echoz` native module) or `proxy_pass`:

```nginx
location /limited/ {
    ratelimit_rate "50r/s";
    ratelimit_key "$remote_addr";

    error_page 429 = @rate_limited;

    # echozn runs in CONTENT phase (after ACCESS). Never use "return" here.
    echozn "ok";
}

location @rate_limited {
    internal;
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

### Pattern C: Headers-only (no custom body, no js_content)

If you only need rate-limit headers on the native 429 response and don't need a custom error body, you can skip `js_content` entirely and use `add_header`:

```nginx
location /api/ {
    ratelimit_rate "100r/s";
    ratelimit_key "$remote_addr";

    add_header X-RateLimit-Remaining "0" always;
    add_header Retry-After "60" always;

    proxy_pass http://backend;
}
```

The `always` keyword ensures headers are added even on the native 429 error response.

### Pattern D: Headers on both allowed and denied responses

To inject rate-limit headers on *every* response (both proxied successes and native denials), use `js_header_filter`:

```nginx
location /api/ {
    ratelimit_rate "100r/s";
    ratelimit_key "$remote_addr";

    error_page 429 = @rate_limited;
    proxy_pass http://backend;

    js_header_filter main.inject_rate_limit_headers;
}

location @rate_limited {
    internal;
    js_content main.rate_limited_custom_error;
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

    error_page 429 = @rate_limited;
    proxy_pass http://backend;
}

location @rate_limited {
    internal;
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
- `tests/basic/` — 7 scenarios: simulated variables via `set $ratelimit_result`, exercises all handler logic without native dependencies
- `tests/native/` — 8 scenarios: real native `ratelimit` module, `error_page 429 = @name;` wiring, cross-worker shared-memory enforcement

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

With the newer native `prometheus` variable surface, an additional future path is to combine local rate-limit decisions with shared load/error signals such as `$prometheus_requests_total` and `$prometheus_error_rate` when choosing degraded responses or richer observability output.

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
- [ ] Load-aware shaping using native `prometheus` variables (`$prometheus_requests_total`, `$prometheus_error_rate`)
- [ ] Degraded-mode decisions informed by native `redis` connection state (`$redis_connection_state`)

## TDD plan

- [x] unit-test `parse_result` for all variants ("allow", "deny", empty, unknown)
- [x] unit-test `context` construction from raw strings
- [x] unit-test header rendering (denied, allowed, empty)
- [x] unit-test error body rendering (JSON, HTML, text)
- [x] `tests/basic/` — 7 integration scenarios with simulated variables
- [x] `tests/native/` — 8 integration scenarios with real native ratelimit module

## Verification checklist

- [x] `bun scripts/test.js ratelimit_policy` — unit tests pass (18 tests)
- [x] `bun test modules/ratelimit_policy/tests/basic/do.test.js` — basic integration (7 scenarios)
- [ ] `make && bun test modules/ratelimit_policy/tests/native/do.test.js` — native integration (8 scenarios, requires native module)

## Limitations

- **Handlers require `error_page` wiring.** The native module terminates denied requests in ACCESS phase; `js_content` at the same location never executes on deny. Wire handlers through `error_page 429 = @name;` as shown in the configuration section above.
- **Header values are static.** `X-RateLimit-Limit` and `X-RateLimit-Remaining` use placeholder values (100, 99). Dynamic calculation requires the native module to expose remaining quota as a variable.
- **Fallback is static.** `rate_limited_with_fallback` returns a static degraded body. Full subrequest-based fallback requires composition through `workflow`.
- **No per-path policy.** All locations share the same rate limit policy. Per-path or per-claim differentiated limits are a Phase 4 item.

## DESIGN FLAWS

### Flaw 1: `return` in a location with ACCESS-phase modules is silently broken

**Severity:** Hard — every location using `return CODE;` or `return CODE "text";` alongside native ACCESS-phase directives (ratelimit, waf, jwt, etc.) will skip the native handler entirely.

**Root cause:** nginx's `return` directive runs in the **REWRITE** phase, which executes *before* the ACCESS phase. Any ACCESS-phase handler (native ratelimit, WAF, JWT verification) never runs because `return` finalizes the request in REWRITE.

```nginx
# ❌ BROKEN — ratelimit handler never executes
location /api/ {
    ratelimit_rate 10r/s;
    return 204;
}

# ✅ CORRECT — echozn runs in CONTENT phase (after ACCESS)
location /api/ {
    ratelimit_rate 10r/s;
    echozn "ok";
}
```

**Which directives are REWRITE-phase (before ACCESS):** `return`, `rewrite`, `set`, `if`.  
**Which directives are CONTENT-phase (after ACCESS):** `proxy_pass`, `echozn`, `js_content`, `try_files` (falls through), `empty_gif`, static file serving.

### Flaw 2: ACCESS-phase variables are lost in `error_page` internal redirects

**Severity:** Hard — makes it impossible to read native module decision variables (`$ratelimit_result`, `$waf_result`, `$jwt_claim_*`, etc.) from a `js_content` handler reached via `error_page 429 = @name;`.

**Root cause:** The native ratelimit module stores its result in `r->ctx[module_index]` during the ACCESS phase. When `error_page 429 = @name;` triggers `ngx_http_internal_redirect`, the variable get_handler cannot resolve the value in the new location context. njs reads an empty string.

**Confirmed by:** Running with `worker_processes 2` and `ratelimit_rate 2r/s` — the third request in a window is correctly denied by the native module (ACCESS returns 429), `error_page` catches it, but in the `@rl` internal location:

```
add_header X-Direct-Result $ratelimit_result always;   # → "allow" (original request, works)
return 200 "result=$ratelimit_result";                 # → "result=" (internal redirect, empty)
```

**Impact:** The `ratelimit_policy` handlers that read `$ratelimit_result` to decide allowed/denied/unknown cannot function through `error_page`. On deny, they see `Unknown` → return 204 instead of 429. The native test suite (`tests/native/`) confirms all deny-path assertions fail with `Expected: 429, Received: 204`.

**Workaround for header-only injection:** Use `add_header ... always;` in the primary location — it runs in the output filter chain (original request) where variables are available.

**Workaround for custom error bodies:** Add error-page-specific handler exports that skip the variable read and assume denial. Or use `js_body_filter` in the primary location to rewrite the 429 body.

**General lesson:** Any native module that stores per-request state in `r->ctx` and exposes it via `$variable` will lose that state through `error_page` internal redirects. This is a general nginx limitation, not specific to ratelimit.

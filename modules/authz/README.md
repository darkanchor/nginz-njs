# nginz_njs_authz

Policy-based authorization for nginx written in Gleam. Rules are pure functions; policies are compositions of rules. No hidden state, fully unit-testable without nginx.

## Design goals

- A single `Decision` type (`Allow` | `Deny(status: Int, reason: String)`) flows through every rule — no exceptions, no side channels
- Rules are first-class values: `Rule = fn(Context) -> Decision`
- Combinators (`all_of`, `any_of`, `not_`) let you build arbitrary policy trees from atomic rules
- The native jwt module (optional) handles cryptographic verification; this module reads the resulting nginx variables and applies claim-based policy in Gleam
- Deny reasons are always explicit strings — operators can log them; callers can inspect them in tests

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.check` | `js_content` | Method whitelist; returns 204 or the `Deny` status |
| `main.jwt_check` | `js_content` | Reads `$jwt_claim_*` vars and checks role claim |
| `main.remote_check` | `js_content` | POSTs to OPA-compatible endpoint; returns 204 or the `Deny` status |
| `main.cached_remote_check` | `js_content` | `remote_check` with `ngx.shared` cache keyed by Bearer token SHA-256 |
| `main.enriched_check` | `js_content` | `check` + sets `X-Authz-Status` response header |
| `main.enriched_jwt_check` | `js_content` | `jwt_check` + sets `X-Authz-Status` and `X-Authz-<Claim>` headers |
| `main.enriched_remote_check` | `js_content` | `remote_check` + sets `X-Authz-Status` response header |
| `main.session_gate` | `js_content` | Verifies a session cookie via the shared session store; returns 204 + `X-Session-Subject` or 401 |

## nginx configuration

### Basic method check

```nginx
http {
    js_engine qjs;
    js_path "njs/";
    js_import main from app.js;
    server {
        listen 8888;
        location /api/ { js_content main.check; }
        location /admin/ {
            jwt_secret "your-secret";
            jwt_claim $jwt_claim_role role;
            js_content main.jwt_check;
        }
    }
}
```

### Remote OPA decision point

```nginx
location /api/ {
    set $authz_opa_url http://opa.internal:8181/v1/data/authz/allow;
    js_content main.remote_check;
}
```

Sends `{"input":{"method":"…","path":"…","remote_addr":"…"}}`, expects `{"result":{"allow":true|false}}`.

### Cached remote check

```nginx
js_shared_dict_zone zone=authz_cache:10m timeout=1h;
…
location /api/ {
    set $authz_opa_url  http://opa.internal:8181/v1/data/authz/allow;
    set $authz_cache_ttl 300;   # seconds; default 300 if unset
    js_content main.cached_remote_check;
}
```

`timeout=` on `js_shared_dict_zone` is required for per-key TTL.

### Downstream header injection with auth_request

```nginx
location /protected/ {
    auth_request     /auth;
    auth_request_set $authz_status $upstream_http_x_authz_status;
    auth_request_set $authz_role   $upstream_http_x_authz_role;
    proxy_set_header X-User-Role   $authz_role;
    proxy_pass       http://backend;
}
location = /auth {
    internal;
    set $authz_opa_url http://opa.internal:8181/v1/data/authz/allow;
    js_content main.enriched_remote_check;
}
```

## Policy model

Rules are functions `fn(Context) -> Decision`. Combine with `all_of`, `any_of`, `not_`:

```gleam
import authz/policy.{all_of, any_of, claim_contains_one_of, method_in, path_prefix, query_param_one_of}

let api_policy = all_of([
  method_in(["GET", "POST"]),
  path_prefix("/api"),
  any_of([claim_contains_one_of("role", ["admin", "user"])]),
  query_param_one_of("version", ["v1", "v2"]),
])
```

`evaluate(ctx, rules)` short-circuits on the first `Deny`.

### Rule combinators

| Function | Description |
|---|---|
| `method_in(methods)` | Allow if request method is in the list |
| `path_prefix(prefix)` | Allow if request path starts with prefix |
| `require_header(name, value)` | Allow if header equals value exactly |
| `header_one_of(name, values)` | Allow if header is one of the values |
| `has_claim(key, value)` | Allow if claim equals value exactly |
| `claim_one_of(key, values)` | Allow if claim is one of the values |
| `claim_contains(key, value)` | Allow if comma-separated claim contains value as a segment |
| `claim_contains_one_of(key, values)` | Allow if comma-separated claim contains any value from the list |
| `query_param(key, value)` | Allow if query parameter equals value exactly |
| `query_param_one_of(key, values)` | Allow if query parameter is one of the values |
| `remote_addr_in(cidrs)` | Allow if remote address falls within any CIDR (`"10.0.0.0/8"` or plain IP) |
| `all_of(rules)` | Allow only if every rule allows (AND) |
| `any_of(rules)` | Allow if at least one rule allows (OR) |
| `not_(rule)` | Invert a rule |
| `deny_401(reason)` | Pure constructor — `Deny(401, reason)` |
| `deny_403(reason)` | Pure constructor — `Deny(403, reason)` |

### Async rules

```gleam
import authz/policy.{AsyncRule, async_evaluate, to_async}

// Lift sync rules and mix with async ones
let rules: List(AsyncRule) = [
  to_async(method_in(["GET"])),
  to_async(path_prefix("/api")),
  remote.opa_allow(_, endpoint, 2000),  // already AsyncRule
]
async_evaluate(ctx, rules)  // Promise(Decision), short-circuits on Deny
```

### Library modules

| Module | Purpose |
|---|---|
| `authz/policy` | Core types (`Context`, `Decision`, `Rule`, `AsyncRule`), all combinators, `deny_401`/`deny_403` |
| `authz/claims` | `from_vars(vars, names)` — extracts `$jwt_claim_<name>` nginx vars into claims dict |
| `authz/query` | `from_vars(vars, names)` — extracts `$arg_<name>` nginx vars into query dict |
| `authz/remote` | `opa_allow(ctx, endpoint, timeout_ms)` — async OPA-compatible remote check via `http_client` |
| `authz/cache` | `lookup/store` — `ngx.shared`-backed decision cache keyed by Bearer token SHA-256 |
| `authz/enrich` | `inject_status/inject_claims` — sets `X-Authz-*` response headers |
| `authz/subrequest` | `auth_request_step(r, path)` — AsyncRule backed by nginx subrequest |

## What is implemented

**`authz/policy.gleam`**
- `Context` — method, path, remote_addr, headers, claims, query
- `Decision` — `Allow` | `Deny(status: Int, reason: String)`
- `Rule = fn(Context) -> Decision` and `AsyncRule = fn(Context) -> Promise(Decision)`
- `evaluate` — short-circuits on first `Deny`
- `async_evaluate` — async short-circuit evaluation; `to_async` lifts a sync Rule
- Atomic rules: `method_in`, `path_prefix`, `require_header`, `header_one_of`, `has_claim`, `claim_one_of`, `claim_contains`, `claim_contains_one_of`, `query_param`, `query_param_one_of`, `remote_addr_in`
- Combinators: `all_of`, `any_of`, `not_`
- Helpers: `deny_401(reason)`, `deny_403(reason)`

**`authz/claims.gleam`** — `from_vars` reads any list of `jwt_claim_*` nginx variables

**`authz/query.gleam`** — `from_vars` reads any list of `arg_*` nginx variables

**`authz/remote.gleam`** — `opa_allow` POSTs context to an OPA-compatible endpoint via `http_client`

**`authz/cache.gleam`** — `lookup`/`store` backed by `mlcache/shared` with per-key TTL, keyed by SHA-256 of the Bearer token

**`authz/enrich.gleam`** — `inject_status` and `inject_claims` set `X-Authz-*` response headers

**`authz/subrequest.gleam`** — `auth_request_step(r, path)` builds an AsyncRule backed by `http.subrequest`; 2xx → Allow, anything else → Deny(403)

**`nginz_njs_authz.gleam`** (njs entry point) — 7 handler exports covering all combinations; handlers forward the HTTP status from `Deny`

**Integration tests**
- `tests/basic/` — method allowlist, no native deps
- `tests/opa/` — remote OPA check, no native deps
- `tests/cache/` — shared-dict cache, no native deps
- `tests/enrich/` — header injection, no native deps
- `tests/session/` — cross-module `session_gate` flow backed by the session bundle, no native deps
- `tests/jwt/` — full JWT flow: native module verifies HS256, njs checks role (`make` required)

## Limitations

- **No runtime policy reload.** Policy rules are compiled into the njs bundle. A policy change requires rebuilding and `nginx -s reload`. Hot-patching is not supported by the njs module system.
- `jwt_check` / `enriched_jwt_check` depend on `$jwt_claim_*` variables set by the nginz native JWT module. Signature verification is the native layer's job.

## Open upstream enabler: njs PR #1044

There is an open upstream njs PR (`nginx/njs#1044`) proposing `js_access` plus request-body readers such as `readRequestText()`, `readRequestJSON()`, and `readRequestForm()`.

If that PR lands substantially as proposed, it would be a **credible future enabler** for `authz`:

- optional access-phase adapters instead of only `js_content`-phase adapters
- pre-content body-aware authorization rules for JSON requests
- pre-content form-aware gates for classic login / CSRF-style flows
- fewer nginx workarounds when the policy decision really belongs before proxying

Important guardrails:

- this is **not available in this repo today**
- the PR is still open and may change before merge
- unresolved upstream review items around multipart parsing, docs, and tests mean we should not design current handlers around it yet
- it does **not** erase the `ratelimit_policy` lesson about native ACCESS-phase deny-path state and `error_page` redirects; `js_access` would strengthen scripted policy, not magically fix native context loss

## Phased implementation plan

### Phase 1 — strengthen the pure policy language ✓

- [x] `claim_one_of(key, values)` and `header_one_of(key, values)`
- [x] `claim_contains(key, value)` and `claim_contains_one_of(key, values)` — multi-value comma-separated claims
- [x] `query_param(key, value)` and `query_param_one_of(key, values)` — query string rules
- [x] `Context.query` field populated from `$arg_*` nginx variables via `authz/query.from_vars`
- [x] `remote_addr_in(cidrs)` — IPv4 allowlist/denylist with CIDR notation (`"10.0.0.0/8"`, `"1.2.3.4"`)
- [ ] `path_matches(pattern)` — regex/glob path matching (needs JS regex FFI)
- [ ] focused examples showing nested `all_of` / `any_of` policy trees

### Phase 2 — make decisions richer without losing purity ✓

- [x] `X-Authz-Status` and `X-Authz-<Claim>` response headers via `authz/enrich`
- [x] `apply_decision(r, decision, log_prefix)` nginx adapter in the entry point
- [x] `Deny` carries HTTP status code — `Deny(status: Int, reason: String)`
- [x] `deny_401(reason)` and `deny_403(reason)` pure constructor helpers
- [x] nginx handlers use the status from `Deny` (401 vs 403 semantics end-to-end)

### Phase 3 — async policy adapters ✓

- [x] `AsyncRule = fn(Context) -> Promise(Decision)` type alias in `policy.gleam`
- [x] `async_evaluate(ctx, rules)` — async short-circuit evaluation
- [x] `to_async(rule)` — lifts a sync `Rule` into an `AsyncRule`
- [x] `authz/remote.opa_allow` — async OPA-compatible external check via `http_client`
- [x] integration test coverage for external auth service (`tests/opa/`, `tests/cache/`)
- [x] `authz/subrequest.auth_request_step(r, path)` — AsyncRule backed by nginx subrequest; 2xx → Allow

### Phase 4 — compose policy outputs in nginx ✓

- [x] `X-Authz-Status` / `X-Authz-<Claim>` headers for `auth_request` enrichment flows
- [x] `ngx.shared` decision cache (`authz/cache`) for introspection result reuse
- [x] `cached_remote_check` handler wiring cache + OPA + Bearer token extraction
- [ ] reusable RBAC recipe documentation (path+method+role policy tree)
- [ ] document optional jwt module wiring end-to-end

### Phase 5 — optional access-phase adapters (future, upstream-dependent)

Goal: if upstream njs lands `js_access` and request-body readers, add access-phase adapters without changing the core policy DSL.

- [ ] optional `js_access` adapters for pre-content authz decisions
- [ ] body-aware policy adapters for JSON payloads when access-phase body reads are available upstream
- [ ] form-aware policy adapters for login / CSRF gates when upstream `readRequestForm()` stabilizes
- [ ] native integration coverage proving phase behavior before claiming these paths as supported

## TDD plan

- [x] unit-test each atomic rule in isolation
- [x] unit-test combinator nesting and short-circuit behavior
- [x] unit-test `async_evaluate` / `to_async` with sync rules
- [x] unit-test `query_param` and `query_param_one_of`
- [x] unit-test decision helper semantics when `Deny` carries HTTP status (`deny_401`, `deny_403`, status propagation)
- [ ] `tests/basic/` scenario for request-to-context extraction correctness
- [x] native JWT scenario as optional proof of composition with nginz (`tests/jwt/`)

## Verification checklist

- [x] `bun scripts/test.js authz` — 52 unit tests pass
- [x] `bun test modules/authz/tests/basic/do.test.js` — method allowlist passes
- [x] `bun test modules/authz/tests/opa/do.test.js` — remote OPA check passes
- [x] `bun test modules/authz/tests/cache/do.test.js` — shared-dict cache passes
- [x] `bun test modules/authz/tests/enrich/do.test.js` — header injection passes
- [x] `bun test modules/authz/tests/session/do.test.js` — session-backed `session_gate` passes
- [x] `bun test modules/authz/tests/jwt/do.test.js` — JWT integration passes (`make` required)
- [ ] Manual: configure a real RBAC policy, hit with admin/user/guest tokens, verify log output
- [ ] Load test: 10k req/s baseline through the `check` handler to measure njs overhead

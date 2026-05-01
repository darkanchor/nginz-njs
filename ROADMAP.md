# ROADMAP

## Direction

`nginz-njs` is the scripted composition layer on top of the native nginx platform built by `nginz`. The intended model is:

- **native Zig modules** (in `nginz`) provide primitives: JWT verification, rate-limit counters, shared-memory state, WAF engines, upstream balancers
- **scripted Gleam modules** (here) provide orchestration, policy logic, product customization, and protocol glue
- **njs built-ins** (`ngx.shared`, `ngx.fetch`, Web Crypto, timers) are available to all scripted modules without any native dependency

This is the right analogue to the OpenResty ecosystem — not "replace the server with scripts," but "use scripts as the composition and customization layer on top of strong native primitives."

## Native vs scripted decision framework

A simple checklist for any candidate module:

| Question | Native (nginz) | Scripted (here) |
|---|---|---|
| Hot path? | yes — per-request, CPU-sensitive | no — low frequency or async |
| Needs shared memory? | yes — counters, rings, maps | no — or shared dict is enough |
| Deep C API? | yes — BPF, QUIC, parser engines | no — HTTP objects are sufficient |
| Policy / branching logic? | no | yes — claim rules, routing trees, flag eval |
| Rapid iteration likely? | no | yes — webhook signatures, OAuth flows |
| Data structure is the module? | yes — trie, ring, LRU | no — logic around plain HTTP state |

When both columns apply: build a native primitive and expose it through njs. That is the hybrid model.

## Module roadmap

### Tier 1 — highest immediate value, no native dependency

#### `http_client` — `ngx.fetch()` wrapper

**Status:** complete  
**Lua analog:** `lua-resty-http`  
**Blockers:** none

The njs surface already has `ngx.fetch()`. The module now provides a typed Gleam wrapper with request building, validation, emitted timeout/error variants, response parsing helpers, immediate retry policy, middleware composition, and auth header injection as first-class types.

Why first:
- No native dependency — ships immediately
- Highest leverage: every module that calls upstream services needs this
- Multiplies the value of `workflow` and all enrichment pipelines
- `ngx.fetch()` is already in the njs surface; this is purely a composability layer

#### `nginz_njs_workflow` — subrequest orchestration

**Status:** complete  
**Lua analog:** `ngx.location.capture()` patterns  
**Blockers:** none

Parallel and sequential subrequest pipelines. `run_parallel` / `run_sequential`, `and_then` chaining, `with_timeout` / `with_retry` / `recover` wrappers, `fail_on_status` for HTTP-level error detection, `map_step` / `map_body` / `map_error` combinators, `first_ok` / `all_success` / `partition` collectors, and `merge_bodies` / `merge_with` / `require_all` / `select_first_ok` merge strategies. Backends: `subrequest_step` (nginx internal locations) and `fetch_step` (via `http_client`).

Roadmap integration:
- Pairs with `requestid` and `jwt` native modules for auth + enrichment flows
- Can use njs built-in `ngx.shared` for result caching

#### `nginz_njs_feature_flags` — stable bucketing

**Status:** complete  
**Lua analog:** various custom solutions backed by `lua-resty-mlcache`  
**Blockers:** none

Flag evaluation with FNV-1a stable bucketing. Today it reads flag state from nginx variables; later it can use the built-in `ngx.shared` dict for runtime-togglable flags without config reload.

Roadmap integration:
- Flags can later be toggled at runtime via the njs built-in `ngx.shared`
- Bucketing logic stays scripted; state storage uses the njs shared dict

#### `nginz_njs_authz` — policy / authorization engine

**Status:** complete  
**Lua analog:** `lua-resty-casbin`  
**Blockers:** `enriched_jwt_check` / `jwt_check` require the native `jwt` module (included in default `NGINZ_MODULES`); all other handlers work with standard nginx

FP-composable access control. Method, path, header, and JWT claim rules combined with `all_of` / `any_of` / `not_`. Remote OPA/Cedar decision via `http_client`. Result cache in `ngx.shared` by Bearer token hash. Downstream header injection for `auth_request` enrichment flows.

Why scripted:
- Policy rules change frequently — version-controlled scripts are the right artifact, not recompiled binaries
- Heavy on branching and business logic; complements native auth primitives rather than replacing them
- A natural "programmable gateway" use case

Shipped:
- Multi-value claim rules: `claim_contains`, `claim_contains_one_of`
- `authz/claims.from_vars` — reads any list of `jwt_claim_*` nginx vars into a claims dict
- `authz/remote.opa_allow` — async OPA-compatible remote decision via `http_client`
- `authz/cache` — `ngx.shared`-backed decision cache keyed by SHA-256 of the Bearer token
- `authz/enrich` — `X-Authz-Status` / `X-Authz-<Claim>` header injection for `auth_request` flows
- 7 njs handler exports covering all combinations of the above
- Remaining open: no runtime policy reload (requires nginx reload; inherent to njs bundle model)

### Tier 2 — depends on or pairs with native work

#### `session` — session state

**Status:** complete  
**Lua analog:** `lua-resty-session`  
**Blockers:** none

Session token issuance, validation, and TTL management. Cookie modeling, lifecycle policy, and an `ngx.shared`-backed store adapter backed by `mlcache`. The scripted layer owns session semantics; the store is an interchangeable adapter.

Shipped:
- `session/model` — `CookieConfig` (name, http_only, secure, path, same_site), `SessionDescriptor` (cookie, backend, ttl, rotate_after), `validate`, `summary`
- `session/cookie` — `set_header`, `clear_header`, `read_id` for cookie header construction and parsing
- `session/store` — `load`/`save`/`delete` backed by `mlcache/shared`
- `start` (async) — SHA-256 session ID from timestamp + remote addr, sets Set-Cookie, stores subject
- `verify` (sync) — reads cookie, returns 204 + X-Session-Subject or 401; for `auth_request`
- `end_session` (sync) — deletes session, clears cookie
- `authz.session_gate` — thin `auth_request` adapter in the `authz` module consuming `session/store`
- `feature_flags` `"session"` key type — resolves session subject → `ByUserId` for per-user bucketing

#### `mlcache` — two-level LRU + shared dict cache

**Status:** complete  
**Lua analog:** `lua-resty-mlcache`  
**Blockers:** none

njs manages LRU policy per-worker via `ngx.shared`. Stampede-collapse via atomic `add` (set-if-not-exists). High leverage for caching fetch results, session data, and flag state.

Shipped:
- `mlcache/model` — `CacheConfig`, `LookupResult`, `ConfigError`, `validate`, `summary`
- `mlcache/lookup` — `should_fetch`, `should_refresh`, `can_serve`, `get_value`
- `mlcache/shared` — `get`/`put`/`delete`/`try_lock`/`release_lock` backed by njs `ngx.shared`
- Stale detection via embedded `fresh_expiry_ms` prefix; dict TTL = `ttl + stale_ttl`
- Consumed by `authz/cache`, `feature_flags/state`, and `session/store`

#### `response_transform` — body shaping

**Status:** complete  
**Blockers:** none

Plan-based JSON field masking, dropping, renaming, and conditional shaping. Pure evaluation layer (`eval`) + `js_body_filter` adapter. No native dependency.

Shipped:
- `response_transform/plan` — `Operation` (MaskField, DropField, RenameField, SetField, WhenStatus), `Plan`, `PlanError`, `validate`, `compose`, `summary`
- `response_transform/eval` — `apply` / `apply_at_status` on `Dict(String, String)` field maps
- `response_transform/body` — `js_body_filter` adapter with JSON parse/encode; pass-through on non-string-value bodies
- `clear_content_length` header filter to enable chunked transfer after body mutation
- `transform` and `transform_with_status` body filter handlers; status read from nginx `$status`

#### `webhook` — request signing, delivery composition, and callback verification

**Status:** complete  
**Blockers:** none (HMAC verification delegates to njs Web Crypto)

Outbound request signing (HMAC-SHA256) and inbound callback verification. Lightweight protocol adaptation glue for third-party integrations.

Why scripted:
- Webhook integrations are awkward, fast-changing, and script-friendly
- The HMAC verification primitive is in njs Web Crypto; the vendor-specific glue is scripted

#### `metrics` — reusable metrics modeling and line rendering

**Status:** complete  
**Blockers:** none

Reusable scripted metric model plus StatsD/DogStatsD line rendering for downstream modules like `authz`, `http_client`, `feature_flags`, `session`, `mlcache`, and `response_transform`. Transport/sink delivery remains a separate concern.

Why scripted:
- Log-phase string formatting; no performance constraint
- Protocol serialization is pure string work

## Hybrid patterns (native primitive + njs policy)

Some problems need both layers. The correct pattern: native Zig provides the performance primitive or C-API integration; njs provides the policy shell.

### Phantom token / OAuth introspection

- **Native** (`jwt` module): HTTP subrequest to introspection endpoint; cache result in shared dict by token hash
- **Scripted** (here): claim-to-role mapping, downstream header injection, error response shaping
- **Path**: extend JWT module with `jwt_introspect_endpoint` directive (native), expose result variables to njs for policy evaluation

### Geo / IP intelligence

- **Native** (`nginz`): MaxMind MMDB lookup (binary trie in shared memory; C binding to `libmaxminddb`); exposes `$geoip2_country`, `$geoip2_asn`
- **Scripted** (here): policy on top — block, redirect, tag, or rate-limit by country/ASN via variables

### Worker-level event bus

- **Native** (`nginz`): shared-memory signal ring with atomic ops; requires native because of cross-worker coordination
- **Scripted** (here): subscribe in log-phase or timer handler; act on cache invalidation, session revocation, config reload signals

## Sprint sequence (scripted layer)

Sequencing is driven by the `nginz` native roadmap. Scripted modules unblock progressively as native primitives land.

### Sprint 1 — foundation (no native dependencies, complete)

1. ~~`http_client` — `ngx.fetch()` wrapper; enables all composition patterns~~ ✓ done
2. ~~`nginz_njs_workflow` — complete the scaffold; subrequest pipeline with `http_client`~~ ✓ done
3. ~~`nginz_njs_feature_flags` — complete the scaffold; stable bucketing + nginx var integration~~ ✓ done

### Sprint 2 — state (njs built-in shared dict, complete)

4. ~~`session` — cookie + lifecycle + a real `ngx.shared` store adapter~~ ✓ done
5. ~~`mlcache` — per-worker LRU + a real `ngx.shared` adapter; unlocks high-performance scripted caching~~ ✓ done
6. ~~`nginz_njs_feature_flags` — wire flag state to `ngx.shared` for runtime toggling without reload~~ ✓ done

### Sprint 3 — policy and enrichment (complete)

7. ~~`nginz_njs_authz` — complete JWT claim integration; add introspection cache path~~ ✓ done
8. ~~`response_transform` — plan-based body filter with mask/drop/rename/conditional ops~~ ✓ done
9. ~~`webhook` — HMAC signing and callback verification~~ ✓ done

All modules originally scheduled in Sprints 1–3 are now complete. Remaining roadmap items below are deferred extensions and hybrid/native follow-ons rather than incomplete scripted sprint modules.

### Deferred

- Phantom token — extend JWT module when OAuth introspection use case is concrete
- Worker event bus — can use njs `ngx.shared` as signal channel; native atomic ops lead for cross-worker coordination
- Geo/IP policy — depends on native geo module landing in `nginz`

## What belongs here vs what does not

### Correct candidates for scripted modules

These belong here even though C/Lua equivalents exist:

| Lua module | Why scripted here | njs approach |
|---|---|---|
| `lua-resty-http` | `ngx.fetch()` already exists | Gleam wrapper with typed request/response |
| `lua-resty-casbin` | Policy rules change constantly; scripting is right artifact | FP rule composition on `$jwt_claim_*` variables |
| `lua-resty-template` | String rendering; no performance constraint | njs body filter |
| `lua-resty-statsd` | Log-phase string formatting | njs log handler |
| `lua-resty-radixtree` | Routing logic, not parser engine | njs radix library |
| `lua-resty-validation` | Input schema logic | njs + JSON Schema |

### What must stay native (even though Lua patterns exist)

| Module type | Why native is required |
|---|---|
| WAF detection engine | Regex NFA traversal and scoring at line rate; njs cannot run this without degrading throughput |
| JWT / JWS signature verification | Cryptographic primitives on the hot path; must be auditable native code |
| Rate limit counters | Requires shared-memory atomic increments |
| Circuit breaker state machine | Cross-worker shared-memory state transitions require native locking |
| brotli / zstd compression | CPU-bound filter; JS cannot compress at acceptable throughput |
| TLS / ACME certificate management | Deep C API (OpenSSL), timer interaction |
| Request body parsing (JSON Schema) | Per-request JSON parse is the hot path; native cJSON is the right choice |

### What to avoid

- Do **not** build scripted wrappers that duplicate native module behavior (JWT verification, WAF scoring)
- Do **not** build modules that require shared-memory atomics or cross-worker locking beyond njs `ngx.shared`
- Do **not** add a parallel scripting language runtime — njs/QuickJS is the committed path

## Distribution

All modules are independent Gleam packages with the `nginz_njs_` name prefix for Hex.pm uniqueness. Versioning and dependency metadata live in `gleam.toml`.

Distribution deliverable:

```
dist/<name>/
  njs/app.js    ← bundled njs script; load with js_import in nginx
  nginx.conf    ← example configuration
```

Recommended order for a stable distribution story:
1. Ship a few production-quality modules (Sprint 1 above)
2. Solidify file layout and packaging conventions
3. Define `gleam add nginz_njs_<name>` import conventions
4. Only then consider a registry / installer workflow

The platform value comes from having good reusable modules first, not from building a package manager before there is an ecosystem worth packaging.

---

## Milestone 2 — hybrid native+scripted sprints

Milestone 1 (Sprints 1–3) built the scripted foundation with no native dependencies. Milestone 2 shifts to **maximizing the hybrid native+scripted value** — every module reads from native module variables or subrequest endpoints and provides scripted policy, orchestration, and composition on top.

### Native module surface available to njs

These are the nginx variables native modules expose that njs scripts read via `r.variables.<name>`:

| Variable | Native Module | What njs Reads |
|---|---|---|
| `$jwt_claims` | jwt | Full JWT payload as JSON string |
| `$jwt_nowtime` | jwt | Current Unix epoch timestamp |
| `$jwt_claim_<X>` | jwt | Individual JWT claim value (registered via `jwt_claim` directive) |
| `$jwt_header_<X>` | jwt | Individual JOSE header field (registered via `jwt_header` directive) |
| `$ratelimit_result` | ratelimit | Rate limit decision ("allowed" / "denied") |
| `$ratelimit_key` | ratelimit | The resolved rate limit key value |
| `$ratelimit_source` | ratelimit | Source identifier ("ip" or "variable") |
| `$ratelimit_cost` | ratelimit | Per-request cost (decimal string) |
| `$ngz_canary` | canary | "1" if canary request, "0" otherwise |
| `$ngz_circuit_state` | circuit-breaker | "closed", "open", or "half_open" |
| `$ngz_request_id` | requestid | UUIDv4 string per request |
| `$oidc_claim_sub` | oidc | OIDC subject claim |
| `$oidc_claim_email` | oidc | OIDC email claim |
| `$oidc_claim_name` | oidc | OIDC name claim |
| `$nftset_result` | nftset | nftset lookup result ("matched", "not_found", "denied") |
| `$nftset_matched_set` | nftset | Name of the matched nftables set |
| `$echoz_request_body` | echoz | Raw request body string |

Native modules with no variables expose data via subrequest JSON endpoints instead:

| Module | njs Access Pattern | Response Format |
|---|---|---|
| redis | subrequest to `redis_pass` location | `{"value":"..."}` or `{"values":[...]}` |
| consul | subrequest to `consul_services`/`consul_kv`/`consul_catalog` location | `{"services":[...]}`, `{"value":"..."}` |
| healthcheck | subrequest to `health_status`/`health_liveness`/`health_readiness` locations | Full JSON status, `{"status":"alive"}`, `{"status":"ready"}` |
| prometheus | subrequest to `prometheus_metrics` location | Prometheus text format |
| cache-tags | subrequest to `cache_tags_purge` location | `{"tag":"..","purged":N}` or `{"tags":[...]}` |
| waf | no njs-facing surface (purely internal access-phase gatekeeper) | — |

### Sprint 4 — native-aware policy (reads native variables)

#### 10. `ratelimit_policy` — scripted rate-limit response shaping and composition

**Reads from:** `$ratelimit_result`, `$ratelimit_key`, `$ratelimit_source`, `$ratelimit_cost` (native ratelimit module)

**Why scripted:**
- Custom error responses (JSON, HTML) and retry-after header injection are policy logic, not counter logic
- Per-key rate limit metrics via `metrics` module are log-phase string work
- Composition with `authz` — rate limit by JWT claim (e.g. `$jwt_claim_sub` as ratelimit key)
- Workflow integration: degraded-mode fallback when rate-limited

**Planned surface:**
- `ratelimit_policy/model` — `RateLimitContext` (result, key, source, cost), `PolicyDecision`, `PolicyConfig`
- `ratelimit_policy/headers` — `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` injection
- `ratelimit_policy/response` — custom JSON/HTML error body rendering for 429 responses
- `ratelimit_policy/metrics` — emit rate limit decisions to `metrics` module (allowed/denied counts by key)
- `ratelimit_policy/workflow` — `recover` wrapper that serves degraded response when rate-limited

**Composes with:** `authz`, `metrics`, `session`, `workflow`, `http_client`

#### 11. `canary_policy` — scripted canary routing policy

**Reads from:** `$ngz_canary` (native canary module)

**Why scripted:**
- Canary-aware header injection and response tagging are policy logic
- Feature flag integration: canary users get different flag evaluations
- Session-aware canary: sticky canary assignment via `session` cookie
- Metrics: track canary vs production request rates

**Planned surface:**
- `canary_policy/model` — `CanaryContext` (is_canary, headers), `PolicyDecision`
- `canary_policy/headers` — inject `X-Canary: true`, custom routing headers
- `canary_policy/feature_flags` — canary-aware flag evaluation: canary requests → different bucket
- `canary_policy/session` — sticky canary assignment: once canary, always canary (via session store)
- `canary_policy/metrics` — emit canary vs production request counts
- `canary_policy/transform` — apply `response_transform` plans differently for canary responses

**Composes with:** `feature_flags`, `session`, `metrics`, `response_transform`

#### 12. `circuit_breaker_policy` — scripted circuit-breaker fallback and observability

**Reads from:** `$ngz_circuit_state` (native circuit-breaker module)

**Why scripted:**
- Custom fallback responses per circuit state are policy logic
- Workflow `recover` patterns that respect circuit state
- Metrics emission on state transitions
- Composition with `http_client` retry — suppress retries when circuit is open

**Planned surface:**
- `circuit_breaker_policy/model` — `CircuitState` (Closed | Open | HalfOpen), `CircuitContext`, `FallbackConfig`
- `circuit_breaker_policy/fallback` — serve cached/degraded response when circuit is open
- `circuit_breaker_policy/workflow` — `recover` wrapper: if circuit open, skip upstream and serve fallback
- `circuit_breaker_policy/http_client` — retry policy modifier: no retries when circuit is open
- `circuit_breaker_policy/metrics` — emit circuit state and fallback counts

**Composes with:** `workflow`, `http_client`, `metrics`, `mlcache`

### Sprint 5 — native-aware observability and tracing

#### 13. `request_tracing` — distributed tracing glue

**Reads from:** `$ngz_request_id` (native requestid module)

**Why scripted:**
- Request ID propagation to upstreams via `http_client` and `workflow` subrequests
- Structured trace data emission (request ID, latency, status, upstream) in log phase
- Session correlation: links request ID to session subject for debugging

**Planned surface:**
- `request_tracing/model` — `TraceContext` (request_id, start_time, spans), `Span` (name, duration, status)
- `request_tracing/propagate` — inject `X-Request-ID` / `X-Trace-ID` into upstream requests and subrequests
- `request_tracing/record` — accumulate spans through workflow steps
- `request_tracing/emit` — log-phase structured trace output (JSON or logfmt)
- `request_tracing/metrics` — per-request-ID latency and status via `metrics` module

**Composes with:** `workflow`, `http_client`, `metrics`, `session`

#### 14. `health_gateway` — scripted health aggregation and readiness policy

**Reads from:** native healthcheck module's `/health_status` JSON endpoint (via subrequest)

**Why scripted:**
- Aggregate health across multiple backends via `http_client`
- Readiness gate: `workflow` steps that check backend health before dispatching
- Custom health response shaping (combine native health + session status + feature flag state)
- Health-aware routing: skip unhealthy backends in workflow `first_ok`

**Planned surface:**
- `health_gateway/model` — `BackendHealth` (name, status, success_rate, probe_healthy), `AggregateHealth`
- `health_gateway/aggregate` — fetch health from multiple backends, compute overall status
- `health_gateway/gate` — `workflow` step wrapper: skip step if backend unhealthy
- `health_gateway/response` — combine native health + scripted signals into custom health response
- `health_gateway/cache` — cache backend health via `mlcache` to avoid probing on every request

**Composes with:** `workflow`, `http_client`, `mlcache`, `session`, `feature_flags`

### Sprint 6 — security composition

#### 15. `security_gateway` — unified security policy composition

**Reads from:** `$jwt_claims`, `$oidc_claim_*`, `$nftset_result`, `$ratelimit_result` (multiple native modules)

**Why scripted:**
- Composing multiple security signals (IP reputation + JWT claims + rate limit) into a unified allow/deny/challenge decision is pure policy branching
- CAPTCHA/challenge page injection for borderline requests
- WAF response shaping: custom error pages for WAF detections
- Security decision metrics breakdown

**Planned surface:**
- `security_gateway/model` — `SecuritySignal` (JwtClaims | IpReputation | RateLimit | WafDetection), `SecurityDecision` (Allow | Deny | Challenge)
- `security_gateway/evaluate` — compose signals into a single decision using `all_of` / `any_of` / `not_` patterns (same FP model as `authz`)
- `security_gateway/challenge` — render CAPTCHA or challenge page for borderline requests
- `security_gateway/response` — custom error pages per denial reason (401, 403, 429)
- `security_gateway/metrics` — security decision breakdown (auth failures, rate limits, IP blocks, WAF hits)

**Composes with:** `authz`, `session`, `feature_flags`, `http_client`, `metrics`, `response_transform`

#### 16. `oidc_bridge` — OIDC-to-session and OIDC-to-policy bridge

**Reads from:** `$oidc_claim_sub`, `$oidc_claim_email`, `$oidc_claim_name` (native oidc module)

**Why scripted:**
- Binding OIDC identity to session state is orchestration logic
- Mapping OIDC claims to `authz` policy context is claim-to-role policy
- Token refresh orchestration via `http_client`
- Feature flag integration: OIDC user → `ByUserId` bucketing

**Planned surface:**
- `oidc_bridge/model` — `OidcIdentity` (sub, email, name, raw_claims), `SessionBinding`
- `oidc_bridge/session` — create/update session on OIDC callback; bind OIDC claims to session subject
- `oidc_bridge/claims` — map OIDC claims to `authz` claims dict (same shape as `authz/claims.from_vars`)
- `oidc_bridge/refresh` — token refresh orchestration via `http_client` when access token expires
- `oidc_bridge/feature_flags` — resolve OIDC subject → `ByUserId` for per-user flag bucketing

**Composes with:** `authz`, `session`, `feature_flags`, `http_client`

### What is deferred and why

| Item | Why Deferred |
|---|---|
| Phantom token / OAuth introspection | RFC 9068 JWTs making it less urgent; extend JWT module when use case is concrete |
| Worker event bus | Depends on native shared-memory signal ring landing in `nginz` first |
| Geo/IP policy | Depends on native geo module (`libmaxminddb` binding) landing in `nginz` |
| REST runtime API | Better as capstone once dynamic upstreams exist; no Zig work needed |
| Cache policy / cache-purge | Depends on native selective-cache-purge module landing in `nginz` |

### Sequencing rationale

| Sprint | Theme | Native Modules Consumed | Scripted Modules Composed |
|---|---|---|---|
| 4 | Native-aware policy | ratelimit, canary, circuit-breaker | authz, metrics, session, feature_flags, workflow, http_client |
| 5 | Observability + tracing | requestid, healthcheck | workflow, http_client, metrics, session |
| 6 | Security composition | jwt, oidc, nftset, ratelimit, waf | authz, session, feature_flags, http_client, metrics |

Each sprint produces modules that **read native variables and compose scripted policy on top** — the hybrid model where native Zig provides performance primitives and njs provides the policy shell. Every module in this batch would be impossible without the native layer, and equally impossible without the scripted composition layer.

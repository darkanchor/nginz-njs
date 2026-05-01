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

Milestone 1 (Sprints 1–3) built the scripted foundation with no native dependencies. Milestone 2 keeps the same seven planned modules, but the execution model is now tighter: **keep the milestone, re-sequence the work, and use the broader native surface that already exists** rather than inventing a new milestone just because more variables landed.

The design rule stays the same as the rest of the repo: the reusable library surface is the product; the nginx `exports()` adapter is just the deployment boundary. For this milestone, that means documenting and building typed policy, bridge, fallback, and aggregation libraries first, then composing them into handlers against the native surfaces that are now available.

### Native module surface available to njs

These are the current native surfaces that scripted modules can consume through nginx variables, subrequests, or both.

| Native module | Request-local variables available to njs | Subrequest / other njs-facing surface | Immediate scripted leverage |
|---|---|---|---|
| `jwt` | `$jwt_claims`, `$jwt_nowtime`, `$jwt_claim_<X>`, `$jwt_header_<X>` | — | Claim-aware policy and downstream auth context |
| `ratelimit` | `$ratelimit_result`, `$ratelimit_key`, `$ratelimit_source`, `$ratelimit_cost` | — | Rate-limit response shaping and composed security policy |
| `canary` | `$ngz_canary` | — | Canary tagging and rollout-aware policy |
| `circuit-breaker` | `$ngz_circuit_state` | — | State-aware fallback and degraded-mode behavior |
| `requestid` | `$ngz_request_id` | — | Trace propagation and request correlation |
| `oidc` | `$oidc_claim_sub`, `$oidc_claim_email`, `$oidc_claim_name` | — | Identity mapping and per-user downstream bridging |
| `nftset` | `$nftset_result`, `$nftset_matched_set` | — | IP-reputation and set-membership signals in security policy |
| `echoz` | `$echoz_request_body` | — | Request-body exposure for scripted glue and testing |
| `healthcheck` | `$health_readiness`, `$health_liveness`, `$health_backend_healthy_count`, `$health_backend_total_count`, `$health_backend_failure_count` | `/health_status`, `/health_liveness`, `/health_readiness` | Unblocks a real `health_gateway` baseline while keeping richer topology via subrequest JSON |
| `waf` | `$waf_result`, `$waf_rule_id`, `$waf_score`, `$waf_category` | — | Unblocks `security_gateway` composition and observability without bypassing native enforcement |
| `redis` | `$redis_last_value`, `$redis_last_exists`, `$redis_last_error`, `$redis_connection_state` | `redis_pass` JSON responses | Future sticky-session, cache-adjunct, and degraded-mode bridges |
| `consul` | `$consul_kv_value`, `$consul_kv_found`, `$consul_service_healthy_count`, `$consul_lookup_error` | `consul_services`, `consul_kv`, `consul_catalog` JSON responses | Future config, routing, and health-aware bridges |
| `prometheus` | `$prometheus_requests_total`, `$prometheus_error_rate` | `prometheus_metrics` text endpoint | Future adaptive policy and load-aware shaping |
| `cache-tags` | `$cache_tags_last_purged`, `$cache_tags_last_tag`, `$cache_tags_last_error` | `cache_tags_purge` JSON responses | Future purge workflow orchestration and audit hooks |

### Current hybrid surface rule

The hybrid rule is unchanged:

- use **variables** for cheap request-local facts that scripted policy wants to branch on
- use **subrequest endpoints** for bulk data, mutation flows, and richer operational payloads

The important change for this milestone is practical, not philosophical: `healthcheck` and `waf` are no longer hypothetical hybrid surfaces. They now expose the exact facts `health_gateway` and `security_gateway` were waiting on. By contrast, the new `redis`, `consul`, `prometheus`, and `cache-tags` variables are best treated as **future enablers**, not as a reason to bloat Milestone 2.

### Milestone 2 sub-sprints

Milestone 2 should be communicated as four dependency-driven sub-sprints rather than the older broad Sprint 4/5/6 buckets.

| Sub-sprint | Modules | Theme | Native surfaces consumed |
|---|---|---|---|
| `4A` | `ratelimit_policy`, `canary_policy`, `circuit_breaker_policy` | Single-signal policy adapters | `ratelimit`, `canary`, `circuit-breaker` |
| `4B` | `request_tracing`, `oidc_bridge` | Cross-cutting propagation and identity bridges | `requestid`, `oidc` |
| `5A` | `security_gateway` | Multi-signal security composition | `jwt`, `oidc`, `ratelimit`, `waf`, optional `nftset` |
| `5B` | `health_gateway` | Health aggregation and readiness policy | `healthcheck`, later `workflow` / `http_client` / `mlcache` composition |

### Sprint 4A — native-aware policy adapters

#### 10. `ratelimit_policy` — scripted rate-limit response shaping and composition

**Reads from:** `$ratelimit_result`, `$ratelimit_key`, `$ratelimit_source`, `$ratelimit_cost` (native ratelimit module)

**Why scripted:**
- Custom error responses (JSON, HTML) and retry-after header injection are policy logic, not counter logic
- Composition with `authz` — rate limit by JWT claim (e.g. `$jwt_claim_sub` as ratelimit key)
- Future composition with `metrics` and `workflow` belongs in scripted land rather than in the native counter module

**Current reusable surface:**
- `ratelimit_policy/model` — `RateLimitResult`, `RateLimitContext`, `PolicyDecision`, `RateLimitHeaders`
- `ratelimit_policy/headers` — `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` injection
- `ratelimit_policy/response` — custom JSON/HTML error body rendering for 429 responses

**Current adapter scope:**
- read native `$ratelimit_*` variables in the nginx handler
- inject static placeholder rate-limit headers
- render custom 429 bodies and a static degraded fallback response

**Future composition:**
- `ratelimit_policy/metrics` — decision counters via `metrics`
- `ratelimit_policy/workflow` — degraded-mode fallback composed through `workflow`
- optional load-aware shaping when a concrete use case exists for `$prometheus_*` or `$redis_connection_state`

**Composes with:** `authz`, `metrics`, `session`, `workflow`, `http_client`

#### 11. `canary_policy` — scripted canary routing policy

**Reads from:** `$ngz_canary` (native canary module)

**Why scripted:**
- Canary-aware header injection and response tagging are policy logic
- Feature-flag, session-sticky, and metrics composition should stay in scripted land rather than in the native routing primitive

**Current reusable surface:**
- `canary_policy/model` — `CanaryDecision`, `CanaryContext`, `PolicyAction`, header helpers
- `canary_policy/feature_flags` — canary-aware flag override helpers
- `canary_policy/session` — sticky-assignment serialization and resolution helpers
- `canary_policy/metrics` — decision counters

**Current adapter scope:**
- read `$ngz_canary` in the nginx handler
- inject `X-Canary` request/response visibility headers
- log canary vs stable decision

**Future composition:**
- compose `feature_flags` for canary-aware rollouts
- compose `session` for sticky assignment
- optionally use `$redis_last_*` for native-backed sticky reads and `$prometheus_*` for rollout observability
- compose `metrics` and `response_transform` for observability and canary-specific shaping

**Composes with:** `feature_flags`, `session`, `metrics`, `response_transform`

#### 12. `circuit_breaker_policy` — scripted circuit-breaker fallback and observability

**Reads from:** `$ngz_circuit_state` (native circuit-breaker module)

**Why scripted:**
- Custom fallback responses per circuit state are policy logic
- Workflow, metrics, cache, and retry composition should live in scripted libraries rather than in the native state machine

**Current reusable surface:**
- `circuit_breaker_policy/model` — `CircuitState` (Closed | Open | HalfOpen), `CircuitContext`, `FallbackConfig`
- `circuit_breaker_policy/fallback` — JSON/HTML/text fallback body rendering
- `circuit_breaker_policy/workflow` — wrappers for circuit-aware workflow composition
- `circuit_breaker_policy/metrics` — state/fallback counters

**Current adapter scope:**
- read `$ngz_circuit_state` in the nginx handler
- return 204/503 or state-aware static fallback bodies

**Future composition:**
- `workflow` wrappers for step-level recovery
- `mlcache`-backed cached fallback
- optional degraded-mode enrichment from `$redis_*`, `$consul_*`, and `$prometheus_*` when there is a concrete upstream-health use case
- `http_client` retry suppression when the circuit is open

**Composes with:** `workflow`, `http_client`, `metrics`, `mlcache`

### Sprint 4B — tracing and identity bridges

#### 13. `request_tracing` — distributed tracing glue

**Reads from:** `$ngz_request_id` (native requestid module)

**Why scripted:**
- Request ID propagation to upstreams via `http_client` and `workflow` subrequests
- Structured trace rendering and future session correlation are orchestration concerns, not native request-ID generation

**Current reusable surface:**
- `request_tracing/model` — `TraceContext` (request_id, start_time, spans), `Span` (name, duration, status)
- `request_tracing/propagate` — inject `X-Request-ID` / `X-Trace-ID` into upstream requests and subrequests
- `request_tracing/record` — span-accumulation helpers for future workflow composition
- `request_tracing/emit` — structured trace rendering (JSON or logfmt)
- `request_tracing/metrics` — trace metrics helpers

**Current adapter scope:**
- read `$ngz_request_id` in the nginx handler
- inject propagation headers
- emit structured trace lines in content-phase logging

**Future composition:**
- workflow span recording
- `http_client` middleware propagation
- optional sampling / emission policy informed by `$prometheus_*` when adaptive tracing becomes a real need
- `metrics` emission and eventual `js_log`-phase integration

**Composes with:** `workflow`, `http_client`, `metrics`, `session`

#### 14. `oidc_bridge` — OIDC identity mapping and downstream bridge

**Reads from:** `$oidc_claim_sub`, `$oidc_claim_email`, `$oidc_claim_name` (native oidc module)

**Why scripted:**
- Mapping OIDC claims to `authz` policy context is claim-to-role policy
- Feature flag integration: OIDC user → `ByUserId` bucketing
- Future session persistence and token refresh orchestration belong in scripted composition layers, not in the native OIDC flow primitive

**Current reusable surface:**
- `oidc_bridge/model` — `OidcIdentity` (sub, email, name, raw_claims), `SessionBinding`
- `oidc_bridge/session` — inline binding creation and subject extraction
- `oidc_bridge/claims` — map OIDC claims to `authz` claims dict (same shape as `authz/claims.from_vars`)
- `oidc_bridge/refresh` — interface for future token-refresh orchestration
- `oidc_bridge/feature_flags` — resolve OIDC subject → `ByUserId` for per-user flag bucketing

**Current adapter scope:**
- read `$oidc_claim_sub`, `$oidc_claim_email`, `$oidc_claim_name` in the handler
- map claims for authz consumption
- derive per-user feature-flag keys
- generate inline session-binding metadata without persisting it

**Future composition:**
- persist bindings via `session/store`
- refresh access tokens through `http_client`
- optionally consume `$redis_*` and `$consul_kv_*` for session-binding and provider-lookup adjuncts when a concrete use case exists

**Composes with:** `authz`, `session`, `feature_flags`, `http_client`

### Sprint 5A — security composition

#### 15. `security_gateway` — unified security policy composition

**Reads from:** `$jwt_claim_*`, `$oidc_claim_*`, `$ratelimit_result`, `$waf_result`, `$waf_rule_id`, `$waf_score`, `$waf_category`; optional `$nftset_result`

**Why scripted:**
- Composing multiple security signals into a unified allow/deny/challenge decision is pure policy branching
- CAPTCHA/challenge page injection for borderline requests
- Future metrics, WAF shaping, and IP-reputation composition belong in scripted policy rather than native primitives

**Current reusable surface:**
- `security_gateway/model` — `SecuritySignal`, `SecurityDecision`
- `security_gateway/evaluate` — compose signals into a single decision using `all_of` / `any_of` / `not_` patterns (same FP model as `authz`)
- `security_gateway/challenge` — challenge page renderers
- `security_gateway/response` — custom error pages per denial reason (401, 403, 429)
- `security_gateway/metrics` — decision counters and breakdown helpers

**Current adapter scope:**
- read JWT, OIDC, ratelimit, and WAF variables in the nginx handler
- apply a default hardcoded policy (`deny_if_rate_limited`, then `require_any_auth`, then optional WAF escalation)
- return allow/deny/challenge responses

**Future composition:**
- metrics emission through `metrics`
- IP reputation via nftset when the native surface is packageable for the chosen deployment
- response shaping through `response_transform`

**Composes with:** `authz`, `session`, `feature_flags`, `http_client`, `metrics`, `response_transform`

### Sprint 5B — health aggregation and readiness

#### 16. `health_gateway` — scripted health aggregation and readiness policy

**Reads from:** `$health_readiness`, `$health_liveness`, `$health_backend_healthy_count`, `$health_backend_total_count`, `$health_backend_failure_count`; later, native healthcheck JSON subrequests for richer detail

**Why scripted:**
- Aggregation and readiness policy are reusable pure logic
- Future health fetching, caching, and routing composition should happen through existing scripted modules (`http_client`, `workflow`, `mlcache`)

**Current reusable surface:**
- `health_gateway/model` — `BackendHealth`, `AggregateStatus`, `GateDecision`
- `health_gateway/response` — aggregate and readiness JSON renderers
- `health_gateway/gate` — helpers for health-aware dispatch decisions
- `health_gateway/aggregate` — interface for future `http_client`-based fetching
- `health_gateway/cache` — interface for future `mlcache`-backed lookup

**Current adapter scope:**
- shift the baseline adapter to direct `$health_*` reads instead of simulated backend-variable parsing
- build readiness / liveness / aggregate responses from the native scalar facts already present
- keep richer backend-topology rendering as an explicit later subrequest path, not as a fake first-pass requirement

**Future composition:**
- fetch native healthcheck JSON through `http_client` when richer backend detail is actually needed
- add `mlcache`-backed stale/hit/miss caching
- compose `workflow` for health-aware routing and `session`/`feature_flags` for richer custom health surfaces

**Composes with:** `workflow`, `http_client`, `mlcache`, `session`, `feature_flags`

### Deferred hybrid adapters and follow-ons

| Item | Why Deferred |
|---|---|
| Redis-backed cache / sticky-session adjuncts | `$redis_*` is now available, but Milestone 2 modules only need hooks for future composition, not a dedicated adapter family yet |
| Consul-backed config / routing bridges | `$consul_*` is useful, but dynamic config and service-routing modules should wait for a concrete consumer rather than inflate the current milestone |
| Prometheus-aware adaptive policy | `$prometheus_*` can enrich rate-limit, tracing, or circuit policy later, but `metrics` already covers scripted emission and the read-side use case is still optional |
| Cache-tag workflow orchestration | `$cache_tags_*` and purge endpoints are valuable once selective purge becomes a central scripted workflow, not before |
| Phantom token / OAuth introspection | RFC 9068 JWTs making it less urgent; extend JWT module when use case is concrete |
| Worker event bus | Depends on native shared-memory signal ring landing in `nginz` first |
| Geo/IP policy | Depends on native geo module (`libmaxminddb` binding) landing in `nginz` |
| REST runtime API | Better as capstone once dynamic upstreams exist; no Zig work needed |
| Cache policy / cache-purge | Depends on native selective-cache-purge module landing in `nginz` |

### Sequencing rationale

| Sub-sprint | Theme | Native surfaces consumed | Why this order |
|---|---|---|---|
| `4A` | Single-signal policy adapters | `ratelimit`, `canary`, `circuit-breaker` | Establish the baseline hybrid pattern: native fact → typed Gleam context → policy response |
| `4B` | Cross-cutting bridges | `requestid`, `oidc` | Land tracing and identity building blocks before higher-order composition needs to consume them |
| `5A` | Security composition | `jwt`, `oidc`, `ratelimit`, `waf`, optional `nftset` | `security_gateway` now has the native WAF facts it was waiting on and can compose earlier modules cleanly |
| `5B` | Health aggregation | `healthcheck` plus later scripted fetch/cache composition | `health_gateway` is now unblocked by `$health_*`, but it remains the more orchestration-heavy capstone |

Each sub-sprint produces modules that **read native facts and compose scripted policy on top** — the hybrid model where native Zig provides performance primitives and njs provides the policy shell. Every module in this batch depends on the native layer, but the reusable Gleam library surface remains the real design target.

### Recommended implementation sequence inside Milestone 2

The sub-sprint labels above are roadmap communication. The actual implementation order should still be **dependency-first** so we grow canonical building blocks and avoid returning later just to rewire early modules.

Principle: build the smallest reusable library surfaces first, then layer broader composition on top of them.

#### 1. `ratelimit_policy`

Start here because it is the cleanest single-signal hybrid module:

- one native surface (`$ratelimit_*`)
- one narrow scripted concern (typed decision context → headers / error bodies)
- immediate value without waiting on deeper cross-module wiring

This sets the baseline Milestone 2 pattern: **native variable → typed Gleam context → policy decision → adapter response**.

#### 2. `canary_policy`

Second, build another narrow single-signal module with a different output shape:

- one native surface (`$ngz_canary`)
- simple scripted output (`X-Canary` headers, tagging, logging)
- future composition hooks into `feature_flags`, `session`, and `metrics`

Doing this early validates the same hybrid pattern without yet forcing us to wire session persistence or feature-flag orchestration into first-pass handlers.

#### 3. `circuit_breaker_policy`

Third, add the state-aware fallback layer:

- one native surface (`$ngz_circuit_state`)
- richer fallback policy than the first two modules
- natural future composition with `workflow`, `mlcache`, and `http_client`

By doing it after `ratelimit_policy`, we reuse the response-shaping mindset before introducing broader recovery composition.

#### 4. `request_tracing`

Fourth, establish the cross-cutting propagation primitive before higher-order composition modules depend on it:

- one native surface (`$ngz_request_id`)
- reusable trace context and propagation headers
- future composition point for `workflow`, `http_client`, and `metrics`

This should land before larger orchestration-heavy modules so later milestone work can adopt one tracing model rather than retrofit it afterward.

#### 5. `oidc_bridge`

Fifth, build the identity-mapping bridge before the unified security layer:

- one native surface (`$oidc_claim_*`)
- reusable `OidcIdentity` mapping into authz claims and feature-flag keys
- future persistence and refresh through `session/store` and `http_client`

This lets `security_gateway` consume a stable OIDC-side building block instead of forcing OIDC mapping logic directly into the top-level security module.

#### 6. `security_gateway`

Sixth, build the multi-signal composition layer only after the narrower bridges exist:

- consumes JWT, OIDC, ratelimit, and WAF signals together
- benefits from the earlier pattern work in `ratelimit_policy` and `oidc_bridge`
- is the first true Milestone 2 “policy shell over multiple primitives” module

This is where we intentionally start composing prior building blocks instead of inventing fresh adapter-local logic.

#### 7. `health_gateway`

Implement last.

This is still the least canonical early module because its best version wants several pieces at once:

- direct scalar health facts from `$health_*`
- optional richer health data fetching through `http_client`
- routing/gating through `workflow`
- caching through `mlcache`
- possibly richer custom health shaping with `session` / `feature_flags`

Placing it last avoids building a fake first pass and then circling back to rewire richer health topology fetching, cache semantics, and routing integration.

### Why this order minimizes rewiring

This sequence intentionally moves from:

1. **single native variable → local policy**
2. **single native variable → reusable bridge**
3. **multiple native signals → composed policy**
4. **fetch/cache/routing-heavy capstone composition**

That gives us a canonical growth path:

- first prove the typed hybrid adapter pattern
- then prove reusable bridge modules
- then compose multiple signals
- only then build the orchestration-heavy health gateway

If we start with `health_gateway`, we will almost certainly come back later to re-thread richer topology fetches, caching, or workflow semantics. `security_gateway` moved forward specifically because the native WAF facts now exist, making it a better earlier composition target than it was before.

### Practical rollout order

If we want one concrete checklist for implementation work, use this exact order:

1. `ratelimit_policy`
2. `canary_policy`
3. `circuit_breaker_policy`
4. `request_tracing`
5. `oidc_bridge`
6. `security_gateway`
7. `health_gateway`

The sprint labels remain useful for roadmap communication, but engineering execution should prefer this dependency-first order.

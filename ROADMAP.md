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

Milestone 1 (Sprints 1–3) built the scripted foundation with no native dependencies. Milestone 2 shifts to **maximizing the hybrid native+scripted value** — native modules provide the hot-path primitive or endpoint surface, while scripted modules provide reusable Gleam-side policy, mapping, and response-shaping layers on top.

The design rule stays the same as the rest of the repo: the reusable library surface is the product; the nginx `exports()` adapter is just the deployment boundary. For this milestone, that means documenting and building typed policy/mapping/fallback libraries first, then composing them into handlers as native surfaces stabilize.

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

### Native variable expansion as an ecosystem tool

The table above is the **current** native surface, not a hard ceiling.

Some native modules expose rich nginx variables already (`jwt`, `ratelimit`, `canary`, `circuit-breaker`, `requestid`, `oidc`, `nftset`). Others currently expose subrequest JSON endpoints only, or no njs-facing surface at all. That is often the right initial design. But if we want to maximize the hybrid ecosystem, **selective variable exports are a power-enabler**.

The rule is simple:

- use **variables** for cheap, request-local facts that scripted modules want to branch on
- use **subrequest endpoints** for bulk data, mutations, complex payloads, and operational APIs

Variables matter because they let `nginz-njs` modules compose multiple native signals in one typed Gleam context without paying extra subrequest/JSON-parsing cost for every boolean or scalar decision.

#### When exposing a variable is worth it

Expose an nginx variable when the native module has a fact that is:

- read frequently by scripted policy
- scalar or short-string shaped
- useful for routing, fallback, gating, challenge, or observability decisions
- stable enough to document as part of the module surface

Do **not** force everything into variables. Large structured responses, mutation flows, and operational control paths should stay as subrequest endpoints.

#### Desired variable expansions by native module

These are not required for Milestone 2, but they are high-leverage candidates if we want to deepen the hybrid model.

##### `healthcheck`

**Current surface:** subrequest JSON endpoints only (`/health_status`, `/health_liveness`, `/health_readiness`)

**Desired variables:**

| Variable | Why it matters | Likely scripted consumers |
|---|---|---|
| `$health_readiness` | Cheap readiness gate without subrequest | `health_gateway`, `workflow` |
| `$health_liveness` | Fast liveness signal for custom health surfaces | `health_gateway` |
| `$health_backend_healthy_count` | Aggregate routing/gating decisions | `health_gateway`, `workflow` |
| `$health_backend_total_count` | Distinguish degraded vs total failure without parsing JSON | `health_gateway` |
| `$health_backend_failure_count` | Failure-aware fallback and circuit-style policy | `health_gateway`, `circuit_breaker_policy` |

These would let `health_gateway` evolve from “parse a simulated nginx variable” into a real hybrid module without making every check a JSON subrequest round-trip.

##### `waf`

**Current surface:** no njs-facing surface

**Desired variables:**

| Variable | Why it matters | Likely scripted consumers |
|---|---|---|
| `$waf_result` | Unified security composition: allow / deny / dryrun / error | `security_gateway` |
| `$waf_rule_id` | Explain or shape downstream denial/challenge responses | `security_gateway`, `metrics` |
| `$waf_score` | Escalation/challenge thresholds in scripted policy | `security_gateway` |
| `$waf_category` | Branch on SQLi/XSS/reputation class without parsing logs | `security_gateway` |

Important boundary: these variables should expose **facts for composition and observability**, not create a scripted bypass around the native access-phase block.

##### `redis`

**Current surface:** subrequest JSON endpoints only

**Desired variables:**

| Variable | Why it matters | Likely scripted consumers |
|---|---|---|
| `$redis_last_value` | Cheap policy/cache read for simple string lookups | `feature_flags`, `session` |
| `$redis_last_exists` | Branch on presence/absence without JSON parsing | `feature_flags`, `workflow` |
| `$redis_last_error` | Retry/fallback policy in scripted layers | `workflow`, `circuit_breaker_policy` |
| `$redis_connection_state` | Health-aware routing and degraded-mode decisions | `health_gateway`, `workflow` |

This is most valuable for simple read-through/cache-adapter patterns. Complex Redis operations should stay as subrequests.

##### `consul`

**Current surface:** subrequest JSON endpoints only

**Desired variables:**

| Variable | Why it matters | Likely scripted consumers |
|---|---|---|
| `$consul_kv_value` | Dynamic config lookup for policy/routing | `workflow`, `feature_flags` |
| `$consul_kv_found` | Branch on presence/absence without parsing JSON | `workflow` |
| `$consul_service_healthy_count` | Service-level gating and routing | `health_gateway`, `workflow` |
| `$consul_lookup_error` | Fail-open/fail-closed policy in scripted adapters | `workflow`, `health_gateway` |

If implemented, these likely need directive-scoped variable binding rather than unbounded dynamic variable generation.

##### `prometheus`

**Current surface:** Prometheus text endpoint only

**Desired variables:**

| Variable | Why it matters | Likely scripted consumers |
|---|---|---|
| `$prometheus_requests_total` | Load-aware routing and response shaping | `metrics`, `workflow` |
| `$prometheus_error_rate` | Degraded-mode or challenge policy | `circuit_breaker_policy`, `security_gateway` |
| `$prometheus_active_connections` | Simple load-shedding signal | `ratelimit_policy`, `workflow` |

This is lower priority than `healthcheck` or `waf`, because Prometheus already has a strong scrape-oriented surface. But a few scalar variables could still be powerful.

##### `cache-tags`

**Current surface:** purge-oriented subrequest endpoint only

**Desired variables:**

| Variable | Why it matters | Likely scripted consumers |
|---|---|---|
| `$cache_tags_last_purged` | Observability and scripted follow-up behavior | `metrics`, `workflow` |
| `$cache_tags_last_tag` | Structured logging / audit | `metrics` |
| `$cache_tags_last_error` | Recovery policy after purge attempts | `workflow` |

This is a lower-leverage candidate unless selective purge becomes a more central scripted orchestration flow.

##### Already strong variable surfaces

These native modules already follow the right hybrid pattern and are the reference model for future native surfaces:

- `jwt` — claims, headers, current time
- `ratelimit` — decision, key, source, cost
- `canary` — canary/stable decision
- `circuit-breaker` — circuit state
- `requestid` — request ID
- `oidc` — core identity claims
- `nftset` — result and matched set
- `echoz` — request body exposure

For these modules, future work is more likely to be **adding one or two high-value facts** rather than inventing a new surface class.

#### Priority order for variable-surface expansion

If we decide to invest in native-variable expansion as a roadmap theme, the highest-value order is:

1. `healthcheck` — directly unlocks a real `health_gateway`
2. `waf` — directly unlocks stronger `security_gateway` composition
3. `redis` — directly improves session/flag/cache adapters
4. `consul` — strong for dynamic routing/config, but less central than the three above
5. `prometheus` / `cache-tags` — useful, but more optional

The reason for this order is ecosystem leverage: each of the top three removes a major reason for scripted modules to fall back to ad-hoc subrequest parsing when all they really need is a typed fact.

### Sprint 4 — native-aware policy (reads native variables)

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
- `http_client` retry suppression when the circuit is open

**Composes with:** `workflow`, `http_client`, `metrics`, `mlcache`

### Sprint 5 — native-aware observability and tracing

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
- `metrics` emission and eventual `js_log`-phase integration

**Composes with:** `workflow`, `http_client`, `metrics`, `session`

#### 14. `health_gateway` — scripted health aggregation and readiness policy

**Reads from:** backend health inputs today; later, native healthcheck module `/health_status` JSON via subrequest

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
- read `$health_backends` from nginx variables in the handler
- parse it into backend health records
- apply aggregate and readiness logic to build JSON responses

**Future composition:**
- fetch native healthcheck JSON through `http_client`
- add `mlcache`-backed stale/hit/miss caching
- compose `workflow` for health-aware routing and `session`/`feature_flags` for richer custom health surfaces

**Composes with:** `workflow`, `http_client`, `mlcache`, `session`, `feature_flags`

### Sprint 6 — security composition

#### 15. `security_gateway` — unified security policy composition

**Reads from:** `$jwt_claim_*`, `$oidc_claim_*`, `$ratelimit_result` today; `$nftset_result` / WAF-facing signals later

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
- read JWT, OIDC, and ratelimit variables in the nginx handler
- apply a default hardcoded policy (`deny_if_rate_limited`, then `require_any_auth`)
- return allow/deny/challenge responses

**Future composition:**
- metrics emission through `metrics`
- IP reputation via nftset when the native surface is packageable
- WAF-facing signal integration when an njs surface exists
- response shaping through `response_transform`

**Composes with:** `authz`, `session`, `feature_flags`, `http_client`, `metrics`, `response_transform`

#### 16. `oidc_bridge` — OIDC identity mapping and downstream bridge

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
- support additional mapped claims when native OIDC variables expand

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

### Recommended implementation sequence inside Milestone 2

The sprint groupings above are thematic. The actual implementation order should be **dependency-first** so we grow canonical building blocks and avoid returning later just to rewire early modules.

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

- consumes JWT, OIDC, and ratelimit signals together
- benefits from the earlier pattern work in `ratelimit_policy` and `oidc_bridge`
- is the first true Milestone 2 “policy shell over multiple primitives” module

This is where we intentionally start composing prior building blocks instead of inventing fresh adapter-local logic.

#### 7. `health_gateway`

Implement last.

This is the least canonical early module because its best version wants several pieces at once:

- health data fetching through `http_client`
- routing/gating through `workflow`
- caching through `mlcache`
- possibly richer custom health shaping with `session` / `feature_flags`

Placing it last avoids building a fake first pass and then circling back to rewire subrequest fetching, cache semantics, and routing integration.

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

If we start with `health_gateway` or `security_gateway`, we will almost certainly come back later to re-thread tracing, identity mapping, caching, or workflow semantics. This order tries to avoid that first-milestone-style return trip.

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

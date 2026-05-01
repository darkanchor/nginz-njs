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

**Status:** scaffold  
**Lua analog:** `ngx.location.capture()` patterns  
**Blockers:** none; `http_client` improves ergonomics

Parallel and sequential subrequest pipelines. Fan-out to multiple internal locations, combine results, drive enrichment flows.

Roadmap integration:
- Pairs with `requestid` and `jwt` native modules for auth + enrichment flows
- Can use njs built-in `ngx.shared` for result caching

#### `nginz_njs_feature_flags` — stable bucketing

**Status:** scaffold  
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

#### `webhook` — request signing and callback verification

**Status:** scaffold  
**Blockers:** none (HMAC verification delegates to njs Web Crypto)

Outbound request signing (HMAC-SHA256) and inbound callback verification. Lightweight protocol adaptation glue for third-party integrations.

Why scripted:
- Webhook integrations are awkward, fast-changing, and script-friendly
- The HMAC verification primitive is in njs Web Crypto; the vendor-specific glue is scripted

#### `metrics` — push-based metrics forwarding

**Status:** scaffold  
**Blockers:** none

Log-phase njs script emitting per-request metrics to DogStatsD / StatsD. Complements the native `prometheus` (pull-based) module.

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

### Sprint 1 — foundation (no native dependencies)

1. `http_client` — `ngx.fetch()` wrapper; enables all composition patterns
2. `nginz_njs_workflow` — complete the scaffold; subrequest pipeline with `http_client`
3. `nginz_njs_feature_flags` — complete the scaffold; stable bucketing + nginx var integration

### Sprint 2 — state (njs built-in shared dict)

4. ~~`session` — cookie + lifecycle + a real `ngx.shared` store adapter~~ ✓ done
5. ~~`mlcache` — per-worker LRU + a real `ngx.shared` adapter; unlocks high-performance scripted caching~~ ✓ done
6. ~~`nginz_njs_feature_flags` — wire flag state to `ngx.shared` for runtime toggling without reload~~ ✓ done

### Sprint 3 — policy and enrichment

7. ~~`nginz_njs_authz` — complete JWT claim integration; add introspection cache path~~ ✓ done
8. ~~`response_transform` — plan-based body filter with mask/drop/rename/conditional ops~~ ✓ done
9. `webhook` — HMAC signing and callback verification

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

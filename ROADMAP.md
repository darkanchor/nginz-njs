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

## Milestone 2 — phase-valid hybrid consolidation

Milestone 1 (Sprints 1–3) built the scripted foundation. Milestone 2 started as a plan for seven new hybrid packages, but the `ratelimit_policy` review taught a harder lesson: **“native module exposes one variable” is not enough to justify a standalone scripted package.**

The repo rule still stands: the reusable Gleam library surface is the product; nginx handler wiring is the deployment boundary. After the phase-validity review, Milestone 2 becomes a consolidation milestone: keep only the modules with real reusable library value, merge thin wrappers into existing foundations, and defer speculative wrappers until they have a concrete multi-module consumer.

### Hard constraints learned from `ratelimit_policy`

These are milestone-shaping constraints, not just local bugs:

1. **REWRITE-phase directives can bypass native ACCESS handlers entirely.** `return`, `rewrite`, and similar directives run before ACCESS.
2. **Native ACCESS-phase state does not automatically survive `error_page` internal redirects.** A variable backed by request context (`r->ctx`) may become unreadable in the redirected location.
3. **Therefore, deny-path response shaping cannot be the default package story.** Any design that depends on reading native deny decisions from `js_content` after `error_page` is suspect until proven with native integration tests.
4. **A standalone package must justify its library surface separately from its handler demo.** If the reusable value really belongs in `authz`, `workflow`, `feature_flags`, or `session`, that is where it should live.

### Native surfaces that still matter — and their best scripted homes

| Native surface | Facts/scripts read | Best scripted home after review |
|---|---|---|
| `jwt` | `$jwt_claim_*`, `$jwt_header_*`, `$jwt_claims`, `$jwt_nowtime` | `authz` |
| `oidc` | `$oidc_claim_sub`, `$oidc_claim_email`, `$oidc_claim_name` | `authz`, `feature_flags`, `session` |
| `waf` | `$waf_result`, `$waf_rule_id`, `$waf_score`, `$waf_category` | `authz` (phase-safe allow/dry-run composition only) |
| `nftset` | `$nftset_result`, `$nftset_matched_set` | `authz` |
| `ratelimit` | `$ratelimit_*` | direct nginx config first; tiny local helpers only where proven phase-safe |
| `canary` | `$ngz_canary` | `feature_flags` + `session` |
| `circuit-breaker` | `$ngz_circuit_state` | `workflow` |
| `requestid` | `$ngz_request_id` | `request_tracing` |
| `healthcheck` | `$health_*`, health JSON endpoints | deferred `health_gateway` only if native surfaces stop being enough |
| `redis`, `consul`, `prometheus`, `cache-tags` | scalar variables + operational endpoints | future follow-on integrations, not new standalone Milestone 2 packages |

### Milestone 2 module triage

| Module | Decision | Why |
|---|---|---|
| `ratelimit_policy` | **Abort as standalone package** | The deny-path package story is phase-invalid. The surviving value is too small to justify a top-level module. |
| `canary_policy` | **Merge** into `feature_flags` + `session` | The real value is sticky assignment and rollout-aware evaluation, not `X-Canary` tagging by itself. |
| `circuit_breaker_policy` | **Merge** into `workflow` | The valuable part is resilience composition (`skip_when_open`, fallback wrappers), not static 503 pages around one variable. |
| `request_tracing` | **Keep standalone** | Propagation, span recording, and emitters are genuine reusable libraries with cross-module consumers. |
| `health_gateway` | **Defer** | Native `healthcheck` already covers the baseline. A standalone scripted package only makes sense once there is a real multi-source aggregation need. |
| `security_gateway` | **Merge** into `authz` | It duplicates `authz`’s policy engine and inherits the same phase risks when it tries to compose native deny-path signals. |
| `oidc_bridge` | **Merge** into `authz` + `feature_flags` + `session` | Claim mapping and per-user identity plumbing already belong beside their existing consumers. |

### Resulting milestone shape

Milestone 2 is no longer “seven sibling packages.” It is four stronger tracks.

#### Track A — extend `authz` into the broader security/identity policy engine

Absorb the real value from `security_gateway` and `oidc_bridge` into `authz`:

- OIDC claim-to-policy adapters
- richer security-signal modeling for WAF and nftset facts
- response/challenge helpers only where they fit the existing `Decision` model
- explicit refusal to promise generic deny-path shaping for native ratelimit/WAF failures via `error_page`

The principle is simple: keep one policy DSL (`all_of` / `any_of` / `not_`), not two.

**Open upstream enabler:** nginx/njs PR #1044 (`js_access` + request body/form readers) is a credible future uplift for this track if it lands substantially as proposed. It would let `authz` add optional pre-content adapters for access-phase policy, body-aware checks, and form-aware gates without routing everything through `js_content` or `auth_request` workarounds.

This is **not current capability** and it does **not** reopen the package decisions above. Even if PR #1044 lands, it does not by itself reverse the `ratelimit_policy` abort, the merge of `security_gateway` / `oidc_bridge` into `authz`, or the `health_gateway` deferral. It is an enabler for existing foundations, not a reason to recreate the old seven-package Milestone 2 split.

#### Track B — extend `workflow` with resilience primitives

Absorb the real value from `circuit_breaker_policy`:

- circuit-aware step wrappers
- cached fallback and recovery primitives
- retry suppression / degraded-mode orchestration
- optional response-shaping hooks through `response_transform` or shared response helpers

This keeps resilience where orchestration already lives instead of creating a separate package around one native state variable.

#### Track C — extend `feature_flags` + `session` with experimentation identity

Absorb the real value from `canary_policy`:

- sticky canary assignment
- canary-aware flag overrides and bucketing
- rollout identity persistence where it belongs
- optional thin adapter examples for `X-Canary` tagging, but not as a top-level product

The useful abstraction is experimentation identity, not a dedicated header-tagging module.

#### Track D — keep `request_tracing` as the only standalone Milestone 2 package

`request_tracing` survives because its library surface stands on its own:

- trace context propagation
- span recording helpers
- structured emitters
- future workflow / `http_client` composition

It is cross-cutting infrastructure, not a one-variable wrapper.

### What is explicitly not in Milestone 2 anymore

- `ratelimit_policy` as a standalone package
- `security_gateway` as a second policy engine beside `authz`
- `oidc_bridge` as a separate identity-mapping package
- `canary_policy` as a separate top-level rollout package
- `circuit_breaker_policy` as a separate top-level fallback package
- `health_gateway` as a near-term scripted wrapper over native health facts

### Deferred hybrid adapters and follow-ons

| Item | Why Deferred |
|---|---|
| `health_gateway` | Native `healthcheck` already exposes readiness/liveness/counts. Revisit only when we need multi-source aggregation, cache semantics, or policy that the native surface cannot express directly. |
| Redis-backed cache / sticky-session adjuncts | `$redis_*` is useful, but it should first sharpen existing foundations (`session`, `feature_flags`, `workflow`) rather than spawn a new package family. |
| Consul-backed config / routing bridges | `$consul_*` is promising, but still needs a concrete consumer before it becomes a standalone scripted product. |
| Prometheus-aware adaptive policy | `$prometheus_*` can enrich tracing, authz, or resilience later; `metrics` already covers the write-side today. |
| Cache-tag workflow orchestration | `$cache_tags_*` and purge endpoints matter once selective purge becomes a real scripted orchestration flow. |
| Phantom token / OAuth introspection | Extend JWT/authz path only when the use case becomes concrete. |
| Worker event bus | Depends on native shared-memory signal ring landing in `nginz`. |
| Geo/IP policy | Depends on native geo module (`libmaxminddb` binding) landing in `nginz`. |
| REST runtime API | Better as a capstone once dynamic upstreams and control-plane needs are concrete. |

### Recommended implementation order inside the revised milestone

1. **Extend `authz`** — absorb `oidc_bridge` and the real, phase-safe parts of `security_gateway`
2. **Extend `workflow`** — absorb `circuit_breaker_policy` and any resilience helpers that survive the phase review
3. **Extend `feature_flags` + `session`** — absorb `canary_policy` as experimentation identity and sticky rollout composition
4. **Ship `request_tracing`** — the only new standalone Milestone 2 package
5. **Revisit `health_gateway` only if** a concrete multi-source aggregation requirement appears that native `healthcheck` does not already solve

### Why this order is better

- it removes invalid package boundaries first instead of polishing them
- it extends proven foundation modules instead of creating sibling DSLs and adapters
- it keeps only one genuinely new standalone package in the milestone
- it follows the repo’s actual product rule: reusable Gleam building blocks first, nginx handlers second

# nginz_njs_oidc_bridge

OIDC-to-policy bridge for the native `oidc` module. The pure mapping layer reads `$oidc_claim_sub`, `$oidc_claim_email`, `$oidc_claim_name` and maps claims to authz policies and feature flag keys in Gleam.

## Roadmap position

Sprint 4B (tracing and identity bridges) in Milestone 2 of `ROADMAP.md`. Depends on the native nginz `oidc` module. Composes with `authz`, `session`, `feature_flags`, and `http_client`.

## Design goals

- Read `$oidc_claim_sub`, `$oidc_claim_email`, `$oidc_claim_name` from the native oidc module
- Map OIDC claims to `authz`-compatible claims dict for policy evaluation
- Resolve OIDC subject to `ByUserId` key for per-user feature flag bucketing
- Keep the bridge layer pure and testable — the native module owns OIDC flows, this module owns identity mapping

## Core abstractions

- `OidcIdentity` — sub, email, name, raw_claims: the typed identity extracted from native module variables
- `SessionBinding` — session_id, identity, created_at: the binding between session and OIDC identity
- `to_authz_claims` — `OidcIdentity` → `List(#(String, String))`: claim mapping for authz policy evaluation
- `to_flag_key` — `OidcIdentity` → `"ByUserId:<sub>"`: key resolution for per-user feature flag bucketing

The mapper is side-effect free: it transforms native module variables into typed identity, identity into claims/flag keys, and bindings into session metadata. OIDC flow handling and session persistence belong at the nginx adapter boundary or in dedicated modules (`session/store`).

## Scripted core vs optional native integration

### Scripted core

- Identity mapping: OIDC claims → `OidcIdentity` → authz claims / feature flag keys
- Session binding: inline session ID generation with identity binding
- Token refresh interface: orchestration hook for http_client-based refresh
- Reusable library surface: `model`, `session`, `claims`, `feature_flags`, `refresh` modules

### Optional native integration

- Native `oidc` module: handles OIDC authorization code flow, token exchange, sets `$oidc_claim_*` variables

Native module runs in ACCESS phase; this module runs in CONTENT phase.

The native module owns OIDC flow handling and token storage. This module owns identity mapping and cross-module integration (authz claims, feature flag keys).

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.bind_session` | `js_content` | Generates session ID inline, returns session binding as JSON |
| `main.map_claims` | `js_content` | Maps OIDC claims to authz-compatible claims dict |
| `main.resolve_flag_key` | `js_content` | Resolves OIDC subject to feature flag key |

## nginx configuration

```nginx
http {
    js_engine qjs;
    js_path "njs/";
    js_import main from app.js;

    server {
        listen 8888;

        location /oidc/bind     { js_content main.bind_session; }
        location /oidc/claims   { js_content main.map_claims; }
        location /oidc/flag-key { js_content main.resolve_flag_key; }
    }
}
```

Response for bind_session:
```json
{
  "session_id": "oidc:user-42:1700000000",
  "subject": "user-42",
  "email": "alice@example.test",
  "name": "Alice"
}
```

## Library modules

| Module | Purpose |
|---|---|
| `oidc_bridge/model` | `OidcIdentity`, `SessionBinding`, `identity`, `bind`, `identity_summary` |
| `oidc_bridge/session` | `create_binding`, `session_subject`, `binding_summary` — session ID generation |
| `oidc_bridge/claims` | `to_authz_claims`, `has_claim`, `get_claim` — claim mapping |
| `oidc_bridge/refresh` | `refresh` — token refresh orchestration interface |
| `oidc_bridge/feature_flags` | `to_flag_key`, `to_flag_key_pair` — feature flag integration |

## What is implemented

**`oidc_bridge/model.gleam`**
- `OidcIdentity` — sub, email, name, raw_claims
- `SessionBinding` — session_id, identity, created_at
- `identity(sub, email, name, raw_claims)` — constructor
- `bind(session_id, identity, created_at)` — binding constructor
- `identity_summary(id)` — logging string

**`oidc_bridge/session.gleam`**
- `create_binding(identity, now)` — generates session ID inline and binds
- `session_subject(identity)` — extracts sub for authz policy
- `binding_summary(binding)` — logging string

**`oidc_bridge/claims.gleam`**
- `to_authz_claims(identity)` — maps to authz-compatible `List(#(String, String))`
- `has_claim(identity, claim)` — claim presence check
- `get_claim(identity, claim)` — typed claim retrieval with `Option`

**`oidc_bridge/refresh.gleam`**
- `refresh(identity, refresh_token)` — token refresh interface (returns identity unchanged; http_client integration deferred)

**`oidc_bridge/feature_flags.gleam`**
- `to_flag_key(identity)` — resolves sub to `"ByUserId:<sub>"` for per-user bucketing
- `to_flag_key_pair(identity)` — returns `("session", "ByUserId:<sub>")` for flag evaluation

**`nginz_njs_oidc_bridge.gleam`** (njs entry point)
- 3 handlers: `bind_session`, `map_claims`, `resolve_flag_key`
- Reads `$oidc_claim_sub`, `$oidc_claim_email`, `$oidc_claim_name` variables
- Uses `ngx.now()` via the `ngs` package for session timestamp
- Session IDs are generated inline, not persisted via `session/store`

**Integration tests**
- `tests/basic/` — 5 scenarios: full identity, minimal identity, claim mapping, flag key, missing claims

## Cross-module composition

### authz — claim mapping

Map OIDC claims for authz policy evaluation:

```gleam
import oidc_bridge/claims
import authz/policy

let identity = model.identity(sub, email, name, [#("role", "admin")])
let authz_claims = claims.to_authz_claims(identity)
// Use authz_claims with authz/policy rules
```

### feature_flags — per-user bucketing

Resolve OIDC subject to a feature flag key for per-user experimentation:

```gleam
import oidc_bridge/feature_flags

let flag_key = feature_flags.to_flag_key(identity)
// → "ByUserId:user-42"
// Pass to feature_flags/evaluation for per-user bucketing
```

### session — identity binding (future)

The `oidc_bridge/session` module generates session IDs inline. Future work could persist bindings via `session/store`:

```gleam
import oidc_bridge/session
import oidc_bridge/model
import session/store

let identity = model.identity(sub, email, name, [])
let binding = session.create_binding(identity, ngx.now())
// Future: store.save(dict_name, binding.session_id, binding.identity.sub, ttl)
```

The newer native `redis` variables (`$redis_last_value`, `$redis_last_exists`, `$redis_last_error`, `$redis_connection_state`) make that persistence story more concrete if we want a native-backed read-through session-binding layer rather than only njs shared-state wiring.

### http_client — token refresh (interface available)

The `oidc_bridge/refresh` module provides the interface for http_client-based token refresh against the OIDC provider. Implementation is deferred to a future phase:

```gleam
import oidc_bridge/refresh
import http_client/client

// Future: refresh(identity, refresh_token) will use http_client
// to call the token endpoint and return an updated identity
```

Native `consul` variables (`$consul_kv_value`, `$consul_kv_found`, `$consul_lookup_error`) also make it more realistic to treat OIDC provider metadata or rollout-specific config as dynamic scripted inputs instead of compile-time-only settings.

## Completion scope

`oidc_bridge` is complete for its core contract as an OIDC identity mapping layer:

- Pure identity model: native claims → `OidcIdentity` → authz claims / feature flag keys
- Session binding: inline session ID generation with identity binding
- nginx handlers: bind_session, map_claims, resolve_flag_key variants
- Integration test coverage for all handler variants

The `refresh` module provides an interface for future `http_client` integration. Current entry point handlers do not persist session bindings via `session/store`.

## Phased implementation plan

### Phase 1 — identity model and claim mapping ✓

- [x] `oidc_bridge/model` — OidcIdentity, SessionBinding, constructors
- [x] `oidc_bridge/claims` — to_authz_claims, has_claim, get_claim
- [x] Basic handlers: bind_session, map_claims

### Phase 2 — feature flags and session ID generation ✓

- [x] `oidc_bridge/session` — create_binding, session_subject
- [x] `oidc_bridge/feature_flags` — to_flag_key, to_flag_key_pair
- [x] `resolve_flag_key` handler
- [x] Integration test scenarios

### Phase 3 — token refresh and session persistence (future)

- [x] `oidc_bridge/refresh` — token refresh interface
- [ ] Full http_client-based token refresh against OIDC provider
- [ ] Session store integration (persist bindings via `session/store`)
- [ ] Automatic refresh on 401 responses from upstream
- [ ] Custom claim variable registration for additional OIDC claims
- [ ] Redis-backed session-binding persistence informed by `$redis_last_*` variables
- [ ] Consul-backed provider/config lookup informed by `$consul_kv_*` variables

## TDD plan

- [x] unit-test OidcIdentity construction and identity_summary
- [x] unit-test SessionBinding construction
- [x] unit-test create_binding and session_subject
- [x] unit-test to_authz_claims, has_claim, get_claim
- [x] unit-test to_flag_key and to_flag_key_pair
- [x] `tests/basic/` — 5 integration scenarios with simulated variables

## Verification checklist

- [x] `bun scripts/test.js oidc_bridge` — 10 unit tests pass
- [x] `bun test modules/oidc_bridge/tests/basic/do.test.js` — 5 integration tests pass
- [ ] `make NGINZ_MODULES="oidc" && bun run test:native` — native integration

## Limitations

- **Token refresh not implemented.** The `refresh.gleam` module provides the interface but http_client-based refresh is deferred.
- **Session binding not persisted.** Session IDs are generated inline. Full mlcache-backed session persistence via `session/store` is deferred.
- **Only three core claims.** The entry point reads `sub`, `email`, and `name`. Additional claims require custom variable registration in the native oidc module.
- **No session lifecycle.** Session expiration, rotation, and logout are not implemented. The bridge focuses on initial binding only.

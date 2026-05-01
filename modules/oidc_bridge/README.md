# nginz_njs_oidc_bridge

OIDC-to-session and OIDC-to-policy bridge for the native `oidc` module. Reads `$oidc_claim_sub`, `$oidc_claim_email`, `$oidc_claim_name` and binds identity to session state, maps claims to authz policies, and integrates with feature flags in Gleam.

## Roadmap position

Sprint 6 (security composition) in Milestone 2 of `ROADMAP.md`. Depends on the native nginz `oidc` module. Composes with `authz`, `session`, `feature_flags`, and `http_client`.

## Design goals

- read `$oidc_claim_sub`, `$oidc_claim_email`, `$oidc_claim_name` from the native oidc module
- bind OIDC identity to session state on OIDC callback
- map OIDC claims to `authz`-compatible claims dict for policy evaluation
- resolve OIDC subject to `ByUserId` key for per-user feature flag bucketing
- orchestrate token refresh via `http_client` (stub)
- keep the bridge layer pure and testable — the native module owns OIDC flows, this module owns identity binding and mapping

## Native dependency

Requires the nginz native `oidc` module (`make NGINZ_MODULES="oidc"`). The native module:

- Handles OIDC authorization code flow and token exchange
- Sets `$oidc_claim_sub`, `$oidc_claim_email`, `$oidc_claim_name` variables
- Manages token storage and session state

This module runs in a later phase and reads those variables to apply scripted identity binding.

For integration tests without the native module, variables can be simulated with `set` directives (see `tests/basic/nginx.conf`).

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.bind_session` | `js_content` | Binds OIDC identity to session, returns session binding as JSON |
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
| `oidc_bridge/session` | `create_binding`, `session_subject`, `binding_summary` — session lifecycle |
| `oidc_bridge/claims` | `to_authz_claims`, `has_claim`, `get_claim` — claim mapping |
| `oidc_bridge/refresh` | `refresh` — token refresh orchestration (stub) |
| `oidc_bridge/feature_flags` | `to_flag_key`, `to_flag_key_pair` — feature flag integration |

## What is implemented

**`oidc_bridge/model.gleam`**
- `OidcIdentity` — sub, email, name, raw_claims
- `SessionBinding` — session_id, identity, created_at
- `identity(sub, email, name, raw_claims)` — constructor
- `bind(session_id, identity, created_at)` — binding constructor
- `identity_summary(id)` — logging string

**`oidc_bridge/session.gleam`**
- `create_binding(identity, now)` — generates session ID and binds
- `session_subject(identity)` — extracts sub for authz policy
- `binding_summary(binding)` — logging string

**`oidc_bridge/claims.gleam`**
- `to_authz_claims(identity)` — maps to authz-compatible `List(#(String, String))`
- `has_claim(identity, claim)` — claim presence check
- `get_claim(identity, claim)` — typed claim retrieval with `Option`

**`oidc_bridge/refresh.gleam`** (stub)
- `refresh(identity, refresh_token)` — returns identity unchanged; full http_client-based refresh deferred

**`oidc_bridge/feature_flags.gleam`**
- `to_flag_key(identity)` — resolves sub to `"ByUserId:<sub>"` for per-user bucketing
- `to_flag_key_pair(identity)` — returns `("session", "ByUserId:<sub>")` for flag evaluation

**`nginz_njs_oidc_bridge.gleam`** (njs entry point)
- 3 handlers: `bind_session`, `map_claims`, `resolve_flag_key`
- Reads `$oidc_claim_sub`, `$oidc_claim_email`, `$oidc_claim_name` variables
- Uses `ngx.now()` via the `ngs` package for session timestamp

**Integration tests**
- `tests/basic/` — 5 scenarios: full identity, minimal identity, claim mapping, flag key, missing claims

## Cross-module composition

### session — identity binding

Create a session binding from OIDC identity on callback:

```gleam
import oidc_bridge/session
import oidc_bridge/model

let identity = model.identity(sub, email, name, [])
let binding = session.create_binding(identity, ngx.now())
```

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

### http_client — token refresh

When access tokens expire, refresh via the OIDC provider's token endpoint:

```gleam
import oidc_bridge/refresh
import http_client/client

// Future: refresh(identity, refresh_token) will use http_client
// to call the token endpoint and return an updated identity
```

## Phased implementation plan

### Phase 1 — identity model and claim mapping ✓

- [x] `oidc_bridge/model` — OidcIdentity, SessionBinding, constructors
- [x] `oidc_bridge/claims` — to_authz_claims, has_claim, get_claim
- [x] Basic handlers: bind_session, map_claims

### Phase 2 — feature flags and session ✓

- [x] `oidc_bridge/session` — create_binding, session_subject
- [x] `oidc_bridge/feature_flags` — to_flag_key, to_flag_key_pair
- [x] `resolve_flag_key` handler
- [x] Integration test scenarios

### Phase 3 — token refresh and advanced integration (future)

- [x] `oidc_bridge/refresh` — stub for token refresh orchestration
- [ ] Full http_client-based token refresh against OIDC provider
- [ ] Automatic refresh on 401 responses from upstream
- [ ] Session store integration (mlcache-backed session persistence)
- [ ] Custom claim variable registration for additional OIDC claims

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

- **Token refresh is a stub.** The `refresh.gleam` module returns the identity unchanged. Full http_client-based token refresh against the OIDC provider is deferred to Phase 3.
- **Session store is simulated.** Session IDs are generated inline rather than persisted via `session/store`. Full mlcache-backed session persistence requires session module integration.
- **Only three core claims.** The entry point reads `sub`, `email`, and `name`. Additional claims require custom variable registration in the native oidc module.
- **No session lifecycle.** Session expiration, rotation, and logout are not implemented. The bridge focuses on initial binding only.

# nginz_njs_session

Session-state library for nginx written in Gleam. Cookie modeling, session lifecycle policy, and an `ngx.shared`-backed store adapter that other modules can compose for identity and targeting, without embedding session issuance logic in each consumer.

## Roadmap position

`session` is a Tier-2 module in `ROADMAP.md`. The core store adapter uses the njs built-in `ngx.shared` dict via `mlcache/shared`. The optional `start_oidc` handler additionally depends on the native `oidc` module and prefers a bridged `$session_oidc_sub` value, while falling back to the native `$oidc_claim_sub` in OIDC-gated content handlers.

## Design goals

- model session shape, cookie semantics, and backend choice as pure values
- separate session policy from runtime storage details
- let `authz` and `feature_flags` consume session-derived identity rather than duplicating session logic

## What is implemented

**`session/model.gleam`**
- `CookieConfig` — name, http_only, secure, path, same_site
- `StoreBackend` — `SharedDict` or `RedisFallback`
- `SessionDescriptor` — cookie, backend, ttl_seconds, rotate_after_seconds
- `DescriptorError` — `TtlNotPositive`, `RotateNegative`
- `default_descriptor`, `validate`, `summary`

**`session/cookie.gleam`**
- `set_header(config, session_id, ttl_s)` — builds a Set-Cookie header value
- `clear_header(config)` — builds a Max-Age=0 Set-Cookie to expire the client cookie
- `read_id(cookie_header, name)` — extracts the named session ID from a Cookie request header

**`session/store.gleam`**
- `load(dict_name, session_id)` — returns the subject for a live session or Error(Nil)
- `save(dict_name, session_id, subject, ttl_s)` — persists session ID → subject with TTL
- `delete(dict_name, session_id)` — invalidates a session; silent no-op on miss

**`session/assignment.gleam`**
- `CanaryAssignment` — `Assigned(Bool)` | `Unassigned`
- `canary_to_string(Bool) -> String` — serializes True→"1", False→"0"
- `canary_from_string(String) -> CanaryAssignment` — parses "1"→Assigned(True), "0"→Assigned(False), else Unassigned
- `load_canary(dict, sid) -> CanaryAssignment` — reads sticky canary from `{sid}:canary` key
- `save_canary(dict, sid, Bool, ttl_s)` — persists sticky assignment alongside the session
- `delete_canary(dict, sid)` — removes canary key on session end

**`session/identity.gleam`**
- `from_oidc_sub(sub) -> Result(String, Nil)` — normalizes OIDC subject as `"oidc:{sub}"`; Error on empty
- `to_oidc_sub(subject) -> Result(String, Nil)` — strips prefix; Error when not OIDC-prefixed

**`nginz_njs_session.gleam`** additions
- `get_canary` — reads sticky canary assignment from session cookie; 200+"1"/"0" or 404 when unset
- `set_canary` — stores assignment from `$session_canary` (must be `"1"` or `"0"`) for the current session; invalid input returns 400
- `start_oidc` (async) — reads `$session_oidc_sub` when present, otherwise falls back to native `$oidc_claim_sub`; normalizes to `"oidc:{sub}"`, issues session; 204+Set-Cookie or 401 on empty subject
- `end_session` now also deletes the `{sid}:canary` key on logout

**`session/metrics.gleam`**
- `start()` — reusable lifecycle counter for successful session creation
- `verify(success)` — reusable lifecycle counter for verification success/failure
- `end_session()` — reusable lifecycle counter for session invalidation

**`nginz_njs_session.gleam`**
- `describe` — returns a stable summary of the default session descriptor
- `start` (async) — random UUID-backed SHA-256 session ID; stores subject; sets Set-Cookie; returns 204
- `verify` (sync) — reads session cookie, returns 204 + X-Session-Subject or 401; designed for `auth_request`
- `end_session` (sync) — deletes session, clears client cookie; always returns 204

**Integration tests**
- `tests/basic/` — verifies the describe path with stock nginx
- `tests/store/` — verifies start/verify/end lifecycle against a live `ngx.shared` dict
- `tests/rollout/` — verifies sticky canary assignment: set/get/persist/clear on end_session
- `tests/oidc/` — verifies OIDC-backed session start: `start_oidc` issues `sid` with `oidc:{sub}` subject; requires native oidc module

## API reference

### `session/model`

| Function | Description |
|---|---|
| `default_descriptor()` | `SharedDict`, ttl=3600s, rotate=0, cookie name "sid", SameSite=Lax, HttpOnly |
| `validate(descriptor)` | `Ok(descriptor)` or `Error(DescriptorError)` |
| `summary(descriptor)` | Human-readable string: `"sid backend=shared_dict ttl=3600 rotate=0 same_site=Lax"` |

**`CookieConfig` fields**

| Field | Type | Description |
|---|---|---|
| `name` | `String` | Cookie name (e.g. `"sid"`) |
| `http_only` | `Bool` | Set HttpOnly attribute |
| `secure` | `Bool` | Set Secure attribute |
| `path` | `String` | Cookie path scope (e.g. `"/"`) |
| `same_site` | `String` | SameSite value: `"Lax"`, `"Strict"`, `"None"` |

**`SessionDescriptor` fields**

| Field | Type | Description |
|---|---|---|
| `cookie` | `CookieConfig` | Cookie configuration |
| `backend` | `StoreBackend` | `SharedDict` or `RedisFallback` |
| `ttl_seconds` | `Int` | Session lifetime; must be > 0 |
| `rotate_after_seconds` | `Int` | Rotation window; must be ≥ 0; 0 = no rotation |

**`DescriptorError` variants**

| Error | Condition |
|---|---|
| `TtlNotPositive` | `ttl_seconds ≤ 0` |
| `RotateNegative` | `rotate_after_seconds < 0` |

### `session/cookie`

| Function | Signature | Description |
|---|---|---|
| `set_header` | `CookieConfig, String, Int -> String` | Build a Set-Cookie header value |
| `clear_header` | `CookieConfig -> String` | Build a Max-Age=0 expiry header |
| `read_id` | `String, String -> Result(String, Nil)` | Parse session ID from Cookie header |

### `session/store`

| Function | Description |
|---|---|
| `load(dict_name, session_id)` | Returns subject string or Error(Nil) on miss/expired |
| `save(dict_name, session_id, subject, ttl_s)` | Persist session with TTL |
| `delete(dict_name, session_id)` | Invalidate session; silent no-op |

## Typical nginx usage

```nginx
js_shared_dict_zone zone=sessions:4m timeout=1h;

server {
    set $session_dict sessions;
    set $session_ttl 3600;

    # After login — called with $session_subject set to the authenticated user
    location /session/start {
        set $session_subject $authenticated_user;
        js_content main.start;
    }

    # Protect resources — use with auth_request
    location /session/verify {
        internal;
        js_content main.verify;
    }

    location /logout {
        js_content main.end_session;
    }
}
```

## Cross-module composition

### authz — `session_gate`

`authz` exports a `session_gate` handler built on `session/store` and `session/cookie`. It is an `auth_request`-compatible endpoint: 204 + X-Session-Subject on a live session, 401 otherwise.

This module's own integration coverage proves the underlying start / verify / end lifecycle, and `authz/tests/session/` now exercises `session_gate` as a cross-module consumer of the same cookie + store building blocks.

```nginx
location /auth {
    internal;
    set $session_dict sessions;
    js_content main.session_gate;  # from authz bundle
}

location /api/ {
    auth_request /auth;
    auth_request_set $session_subject $upstream_http_x_session_subject;
    proxy_pass http://backend;
}
```

### feature_flags — `"session"` key type

When `$ff_key_type = session`, `feature_flags` reads the session cookie → loads the subject → uses `ByUserId(subject)` for stable per-user bucketing. Requires `$session_dict`.

If `$session_dict` is unset, the cookie is missing or invalid, or the session lookup misses, `feature_flags` falls back to its normal request-key path instead of failing the request. `feature_flags/tests/session/` covers both the successful session-subject path and the fallback behavior.

```nginx
set $ff_key_type session;
set $session_dict sessions;
js_content main.evaluate;
```

## Core abstractions

- `CookieConfig` — cookie boundary configuration as a pure value
- `SessionDescriptor` — the session contract other modules consume without duplicating issuance logic
- `StoreBackend` — runtime storage strategy as a value, not hidden mutable state

The architectural rule: session lifecycle and policy belong in this reusable library; `authz` and `feature_flags` consume session-derived facts, not session mechanics.

## Phased implementation plan

### Phase 1 — stabilize the session descriptor model ✓

- [x] expand descriptor types with TTL, rotation, and cookie fields
- [x] keep cookie configuration pure and testable
- [x] add validation for insecure or conflicting settings

### Phase 2 — add pure session value helpers ✓

- [x] `session/cookie` — set_header, clear_header, read_id
- [x] `session/store` — load/save/delete backed by `mlcache/shared`
- [x] document how `authz` and `feature_flags` consume session facts

### Phase 3 — add backing-store adapters and lifecycle handlers ✓

- [x] `start` handler — SHA-256 session ID, stores subject, sets Set-Cookie
- [x] `verify` handler — session lookup, 204 + X-Session-Subject or 401
- [x] `end_session` handler — delete + clear cookie
- [x] `tests/store/` integration test — start/verify/end lifecycle
- [x] wire into `authz` (session_gate) and `feature_flags` (session key type)

### Phase 4 — absorb rollout identity and OIDC session bindings ✓

Goal: keep identity persistence here so `feature_flags` and `authz` can consume sticky rollout or OIDC-derived session facts without duplicating storage policy.

- [x] session helpers for sticky canary assignment persistence and lookup (`session/assignment.gleam`, `get_canary`/`set_canary` handlers)
- [x] OIDC-oriented session-binding helpers for carrying normalized subject identity into the existing session store (`session/identity.gleam`, `from_oidc_sub`/`to_oidc_sub`)
- [x] shared session value shape that exposes both auth subject and rollout assignment — separate keys (`{sid}` + `{sid}:canary`) give independent TTL control and backward-compatible evolution
- [x] docs/examples: `set $session_subject $ff_oidc_sub; js_content main.start;` binds OIDC → session; `get_canary`/`set_canary` expose sticky rollout assignment; downstream consumers (`feature_flags`, `authz`) read session facts without owning storage
- [x] `start_oidc` handler — prefers `$session_oidc_sub`, falls back to native `$oidc_claim_sub`, normalizes to `"oidc:{sub}"`, and issues session; native OIDC integration test in `tests/oidc/`

## TDD plan

- [x] unit-test descriptor defaults and summaries
- [x] unit-test cookie header construction and parsing
- [x] unit-test validation edge cases
- [x] integration-test lifecycle (start/verify/end) via `tests/store/`
- [x] unit-test sticky canary assignment serialization helpers
- [x] unit-test OIDC session-binding helpers
- [x] integration-test session-backed rollout identity shared with `feature_flags`
- [x] integration-test OIDC-backed session start via native oidc module (`tests/oidc/`)

## Verification checklist

- [x] `bun scripts/test.js session` — 29 unit tests pass
- [x] `bun test modules/session/tests/basic/do.test.js` — basic integration passes
- [x] `bun test modules/session/tests/store/do.test.js` — store lifecycle passes
- [x] `bun run test:int` — all 36 basic integration tests pass (includes authz + feature_flags)
- [x] `bun test modules/session/tests/rollout/do.test.js` — sticky rollout/session binding passes
- [x] `bun test modules/session/tests/oidc/do.test.js` — OIDC-backed session start passes (native oidc module required)

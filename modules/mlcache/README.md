# nginz_njs_mlcache

Two-level cache for nginx written in Gleam. Reusable cache semantics and a `ngx.shared`-backed adapter that other modules can compose for runtime lookups, keeping domain-specific key and invalidation policy outside the cache primitive.

## Roadmap position

`mlcache` is a Tier-2 module in `ROADMAP.md`. The cross-request backing target is the njs built-in `ngx.shared` — no native nginz dependency required.

## Design goals

- model cache semantics as reusable values first
- separate cache policy from consumer-domain concerns
- let `authz`, `feature_flags`, `webhook`, and `session` compose cache behavior rather than embedding bespoke caching

## What is implemented

**`mlcache/model.gleam`**
- `Backend`, `RefreshPolicy`, `CacheConfig`, `LookupResult`, `ConfigError`
- `default_config`, `validate`, `summary`

**`mlcache/lookup.gleam`**
- `should_fetch(result)` — True only for Miss
- `should_refresh(result)` — True for Miss and Stale
- `can_serve(result, policy)` — True for Hit; True for Stale only under RefreshStale
- `get_value(result)` — extracts cached value or Error(Nil)

**`mlcache/shared.gleam`**
- `get(dict_name, key, config)` — reads from `ngx.shared`, classifies as Hit/Stale/Miss using embedded timestamp
- `put(dict_name, key, value, config)` — writes with dict TTL = ttl + stale_ttl; embeds fresh expiry in the stored string

**`nginz_njs_mlcache.gleam`**
- `describe` — returns a stable summary of the default cache config

**Integration tests**
- `tests/basic/` — verifies the descriptive path with stock nginx only

## API reference

### `mlcache/model`

| Function | Description |
|---|---|
| `default_config()` | `SharedDict`, `RefreshOnMiss`, ttl=60s, stale=0s |
| `validate(config)` | `Ok(config)` or `Error(ConfigError)` |
| `summary(config)` | Human-readable string: `"shared_dict policy=refresh_on_miss ttl=60 stale=0"` |

**`CacheConfig` fields**

| Field | Type | Description |
|---|---|---|
| `backend` | `Backend` | `SharedDict` or `PerWorkerOnly` |
| `refresh_policy` | `RefreshPolicy` | `RefreshOnMiss` or `RefreshStale` |
| `ttl_seconds` | `Int` | Fresh lifetime; must be > 0 |
| `stale_ttl_seconds` | `Int` | Stale window beyond TTL; must be ≥ 0; required > 0 when policy is `RefreshStale` |

**`ConfigError` variants**

| Error | Condition |
|---|---|
| `TtlNotPositive` | `ttl_seconds ≤ 0` |
| `StaleTtlNegative` | `stale_ttl_seconds < 0` |
| `StaleWithNoWindow` | `refresh_policy = RefreshStale` but `stale_ttl_seconds = 0` |

### `mlcache/lookup`

| Function | Signature | Description |
|---|---|---|
| `should_fetch` | `LookupResult -> Bool` | True for Miss only |
| `should_refresh` | `LookupResult -> Bool` | True for Miss and Stale |
| `can_serve` | `LookupResult, RefreshPolicy -> Bool` | True for Hit; True for Stale only with RefreshStale |
| `get_value` | `LookupResult -> Result(String, Nil)` | Extracts value from Hit or Stale |

### `mlcache/shared`

| Function | Description |
|---|---|
| `get(dict_name, key, stale_ttl_seconds)` | Read from named shared dict; returns Hit/Stale/Miss |
| `put(dict_name, key, value, config)` | Write to named shared dict with TTL |
| `delete(dict_name, key)` | Remove a key; silent no-op when unavailable |
| `try_lock(dict_name, key, lock_ttl_ms)` | Acquire a per-key write lock; True if acquired |
| `release_lock(dict_name, key)` | Release a previously acquired lock |

**Stale detection**: `put` embeds `fresh_expiry_ms` as `"<ts>:<value>"`. `get` reads the timestamp: if `now < ts` → Hit, if `now ≥ ts` and `stale_ttl_seconds > 0` → Stale, else → Miss. The dict TTL (`ttl + stale_ttl`) ensures the entry is removed after the stale window.

**Stampede-collapse**: `try_lock` / `release_lock` use `ngx.shared`'s atomic `add` (set-if-not-exists) to serialise origin fetches. Degrade gracefully — returns True when the dict is unavailable so the caller still proceeds.

## Typical usage

```gleam
import mlcache/lookup
import mlcache/model
import mlcache/shared

let cfg = model.CacheConfig(
  backend: model.SharedDict,
  refresh_policy: model.RefreshStale,
  ttl_seconds: 300,
  stale_ttl_seconds: 60,
)

// On each request:
let result = shared.get("my_cache", key, cfg.stale_ttl_seconds)
case lookup.can_serve(result, cfg.refresh_policy) {
  True -> {
    let assert Ok(value) = lookup.get_value(result)
    // serve value; also kick off background refresh if should_refresh
  }
  False -> {
    let fresh = fetch_from_origin(key)
    shared.put("my_cache", key, fresh, cfg)
    // serve fresh
  }
}
```

Consumer modules own key construction and what to fetch — mlcache owns the cache mechanics.

## Core abstractions

- `CacheConfig` — reusable cache configuration contract
- `Backend` — backing strategy as a value, not hidden mutable state
- `RefreshPolicy` — refresh semantics owned by the cache primitive rather than by consumers individually

The architectural rule: `mlcache` exposes reusable cache semantics; consumers continue to own domain-specific keying and invalidation meaning.

## Cross-module composition boundary

All three downstream modules now consume mlcache directly — see the consumers table below.

- `webhook` may later use `mlcache` for replay/idempotency support

## Phased implementation plan

### Phase 1 — stabilize the cache semantics model ✓

- [x] expand config with TTL, stale, and refresh controls
- [x] keep summary and debug semantics deterministic and testable
- [x] add validation for conflicting cache settings

### Phase 2 — add pure fetch-on-miss helpers ✓

- [x] define lookup result transitions and refresh flow helpers (`mlcache/lookup`)
- [ ] document how consumer modules should own keys and invalidation semantics
- [x] keep cache policy reusable and domain-agnostic

### Phase 3 — add backing-store adapters ✓

- [x] add the first `ngx.shared`-backed adapter (`mlcache/shared`)
- [x] add stampede-collapse behavior on top of the shared dict contract (`try_lock`/`release_lock`)
- [x] keep backing-store failure separate from cache semantics (silent Miss on unavailable dict)

## TDD plan

- [x] unit-test config summaries first
- [x] add pure tests for refresh-policy helpers before runtime store work
- [x] backing-store behavior integration-tested via `authz/tests/cache/` and `feature_flags/tests/state/`

## Cross-module consumers

| Module | Usage |
|---|---|
| `authz/cache.gleam` | `shared.get`/`put` for OPA decision caching keyed by token SHA-256; `lookup.get_value` for result classification |
| `feature_flags/state.gleam` | `shared.get`/`put` and `lookup.get_value` for runtime-toggleable flag config stored in `ngx.shared` |
| `session/store.gleam` | `shared.get`/`put`/`delete` for session ID → subject mapping with TTL |

## Verification checklist

- [x] `bun scripts/test.js mlcache` — 23 unit tests pass
- [x] `bun test modules/mlcache/tests/basic/do.test.js` — basic integration passes
- [x] `bun test modules/authz/tests/cache/do.test.js` — authz cache backed by mlcache passes
- [x] `bun test modules/feature_flags/tests/state/do.test.js` — feature_flags dict-backed state passes
- [x] `bun test modules/session/tests/store/do.test.js` — session store backed by mlcache passes

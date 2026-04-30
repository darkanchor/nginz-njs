# nginz_njs_mlcache

Two-level cache scaffold for nginx written in Gleam. The long-term goal is a reusable cache capability that other modules can compose for runtime lookups, while keeping domain-specific key and invalidation policy outside the cache primitive itself.

## Roadmap position

`mlcache` is a Tier-2 module in `ROADMAP.md`. It uses the njs built-in `ngx.shared` for cross-request backing — no native nginz dependency required.

## Design goals

- model cache semantics as reusable values first
- separate cache policy from consumer-domain concerns
- let `authz`, `feature_flags`, `webhook`, and `session` compose cache behavior rather than embedding bespoke caching

## What is implemented

**`mlcache/model.gleam`**
- `Backend`, `RefreshPolicy`, `CacheConfig`, and `LookupResult`
- `default_config`, `summary`

**`nginz_njs_mlcache.gleam`**
- `describe` — returns a stable summary of the scaffold cache config

**Integration tests**
- `tests/basic/` — verifies the descriptive scaffold path with stock nginx only

## Core abstractions

- `CacheConfig` — reusable cache configuration contract
- `Backend` — backing strategy as a value, not hidden mutable state
- `RefreshPolicy` — refresh semantics owned by the cache primitive rather than by consumers individually

The architectural rule for this module is: `mlcache` should expose reusable cache semantics, while consumers continue to own domain-specific keying and invalidation meaning.

## Cross-module composition boundary

- `authz` should later compose `mlcache` for remote-decision or introspection caching
- `feature_flags` should later compose `mlcache` for runtime-backed flag state lookup
- `webhook` may later use `mlcache` for replay/idempotency support
- `session` may later use `mlcache`-like lookup semantics, but should continue owning session policy rather than becoming a general cache façade

## Scripted core vs optional native integration

### Scripted core

- cache config and refresh semantics
- fetch-on-miss modeling
- reusable cache-policy helpers
- njs built-in `ngx.shared` for cross-request backing

### Optional native integration

- none required; njs built-in `ngx.shared` provides shared state out of the box

## Phased implementation plan

### Phase 1 — stabilize the cache semantics model

Goal: define reusable cache contracts before runtime backing exists.

- [ ] expand config with TTL, stale, and refresh controls
- [ ] keep summary and debug semantics deterministic and testable
- [ ] add validation for conflicting cache settings

### Phase 2 — add pure fetch-on-miss helpers

Goal: support future consumers without coupling to a runtime store yet.

- [ ] define lookup result transitions and refresh flow helpers
- [ ] document how consumer modules should own keys and invalidation semantics
- [ ] keep cache policy reusable and domain-agnostic

### Phase 3 — add backing-store adapters

Goal: connect the reusable cache model to runtime state.

- [ ] add the first `ngx.shared`-backed adapter
- [ ] add stampede-collapse behavior on top of the shared dict contract
- [ ] keep backing-store failure separate from cache semantics

## TDD plan

- [ ] unit-test config summaries first
- [ ] add pure tests for refresh-policy helpers before runtime store work
- [ ] keep backing-store behavior behind later targeted integration tests

## Atomic commit strategy

- [ ] `mlcache: add pure cache model scaffold`
- [ ] `mlcache: add fetch-on-miss semantics helpers`
- [ ] `mlcache: add ngx.shared-backed adapter`
- [ ] `docs: document authz feature_flags webhook and session composition with mlcache`

## Verification checklist

- [ ] `bun scripts/test.js mlcache` — unit tests pass
- [ ] `bun test modules/mlcache/tests/basic/do.test.js` — basic integration passes
